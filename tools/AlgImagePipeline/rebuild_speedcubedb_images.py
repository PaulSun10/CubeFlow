#!/usr/bin/env python3
"""Rebuild non-3x3 algorithm case images with SpeedCubeDB's own renderers.

SpeedCubeDB stores each case diagram as lightweight HTML (`.icube`, `.sqcube`,
`.pcube`, `.scube`, or cached image markup). This script fetches the source
category pages, matches local cases by name, renders those diagram elements at
the app's existing PNG dimensions in headless Chrome, and crops the transparent
atlas back into individual PNG files.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import struct
import zlib
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
ALGS_DIR = ROOT / "CubeFlow" / "Resources" / "Algs"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
MAX_ATLAS_WIDTH = 4096

PUZZLE_PATH = {
    "2x2": "2x2",
    "4x4": "4x4",
    "5x5": "5x5",
    "SQ1": "SQ1",
    "Megaminx": "Megaminx",
    "Pyraminx": "Pyraminx",
    "Skewb": "Skewb",
}

# `lin.json` is an app-level grouping; SpeedCubeDB exposes the same cases on
# these three individual Square-1 pages.
SET_SOURCE_OVERRIDES = {
    "Lin": ["SQ1LinPLL", "SQ1LinParityPLL", "SQ1LinPLL1"],
    "MegaminxOLL": [f"MegaminxOLL{index}" for index in range(1, 38)],
    "MegaminxPLL": [f"MegaminxPLL{letter}" for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"],
}

RENDERER_CLASSES = ("icube", "jcube", "tdrcube", "sqcube", "pcube", "scube")


@dataclass(frozen=True)
class AlgCaseTarget:
    json_path: Path
    puzzle: str
    set_id: str
    case_id: str
    display_name: str
    name: str
    image_key: str
    setup: str
    output_path: Path
    width: int
    height: int


@dataclass(frozen=True)
class SourceDiagram:
    source_set: str
    name: str
    markup: str


@dataclass(frozen=True)
class AtlasEntry:
    target: AlgCaseTarget
    markup: str
    x: int
    y: int


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def normalize(value: str) -> str:
    value = html.unescape(value).lower().strip()
    value = value.replace("&amp;", "&")
    value = value.replace("+", " plus ")
    value = value.replace("-", " minus ")
    return re.sub(r"[^a-z0-9]+", "", value)


def image_folder_name(image_key: str) -> str:
    return f"{image_key.split('_', 1)[0].upper()}Images"


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def load_targets(only_sets: set[str] | None) -> list[AlgCaseTarget]:
    targets: list[AlgCaseTarget] = []
    for json_path in sorted(ALGS_DIR.glob("*.json")):
        data = json.loads(json_path.read_text(encoding="utf-8"))
        puzzle = data.get("puzzle", "")
        set_id = data.get("set", "")
        if puzzle == "3x3":
            continue
        if only_sets and set_id not in only_sets and json_path.stem not in only_sets:
            continue
        if puzzle not in PUZZLE_PATH:
            print(f"warning: skipping {json_path.name}; unknown puzzle {puzzle!r}")
            continue
        for case in data.get("cases", []):
            image_key = case.get("imageKey")
            if not image_key:
                continue
            output_path = ALGS_DIR / image_folder_name(image_key) / f"{image_key}.png"
            if not output_path.exists():
                print(f"warning: missing output PNG for {image_key}: {output_path}")
                continue
            width, height = png_size(output_path)
            targets.append(
                AlgCaseTarget(
                    json_path=json_path,
                    puzzle=puzzle,
                    set_id=set_id,
                    case_id=case.get("id", ""),
                    display_name=case.get("displayName", ""),
                    name=case.get("name", ""),
                    image_key=image_key,
                    setup=case.get("setup", ""),
                    output_path=output_path,
                    width=width,
                    height=height,
                )
            )
    return targets


def filter_targets(targets: list[AlgCaseTarget], only_image_keys: set[str] | None) -> list[AlgCaseTarget]:
    if not only_image_keys:
        return targets
    selected = [target for target in targets if target.image_key in only_image_keys]
    found = {target.image_key for target in selected}
    missing = sorted(only_image_keys - found)
    if missing:
        fail("unknown image keys: " + ", ".join(missing))
    return selected


def fetch_source_html(url: str) -> str:
    result = subprocess.run(
        ["curl", "-L", "-s", "--fail", "--connect-timeout", "20", "--max-time", "60", url],
        check=True,
        capture_output=True,
        timeout=75,
    )
    return result.stdout.decode("utf-8", errors="replace")


def fetch_rendered_source_html(url: str) -> str:
    result = subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--virtual-time-budget=8000",
            "--dump-dom",
            url,
        ],
        check=True,
        capture_output=True,
        timeout=120,
    )
    return result.stdout.decode("utf-8", errors="replace")


def extract_attr(tag: str, name: str) -> str | None:
    match = re.search(rf"\b{name}=([\"'])(.*?)\1", tag, flags=re.S)
    return html.unescape(match.group(2)) if match else None


def set_attr(tag: str, name: str, value: str) -> str:
    pattern = rf"\s{name}=([\"']).*?\1"
    if re.search(pattern, tag, flags=re.S):
        return re.sub(pattern, f' {name}="{html.escape(value, quote=True)}"', tag, count=1, flags=re.S)
    return tag[:-1] + f' {name}="{html.escape(value, quote=True)}">'


def absolutize_urls(markup: str) -> str:
    return re.sub(r"\b(src|href)=([\"'])/(.*?)\2", r"\1=\2https://www.speedcubedb.com/\3\2", markup)


def extract_case_blocks(source_html: str) -> list[str]:
    starts = [m.start() for m in re.finditer(r'<div\s+class="row\s+singlealgorithm\b', source_html)]
    blocks: list[str] = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(source_html)
        blocks.append(source_html[start:end])
    return blocks


def extract_diagram_markup(block: str) -> str | None:
    anchor_match = re.search(r'<!--\s*Image\s*-->\s*(<a\b.*?</a>)', block, flags=re.S)
    search_area = anchor_match.group(1) if anchor_match else block

    svg_match = re.search(r'(<svg\b.*?</svg>)', search_area, flags=re.S)
    if svg_match:
        return svg_match.group(1)

    class_pattern = "|".join(RENDERER_CLASSES)
    div_match = re.search(
        rf"(<div\b(?=[^>]*\bclass=([\"']).*?\b(?:{class_pattern})\b.*?\2)[^>]*>\s*</div>)",
        search_area,
        flags=re.S,
    )
    if div_match:
        return absolutize_urls(div_match.group(1))

    img_match = re.search(r'(<img\b[^>]*>)', search_area, flags=re.S)
    if img_match:
        return absolutize_urls(img_match.group(1))
    return None


def extract_source_diagrams(source_html: str, source_set: str) -> list[SourceDiagram]:
    diagrams: list[SourceDiagram] = []
    for block in extract_case_blocks(source_html):
        name_match = re.search(r"\bdata-alg-filter=([\"'])(.*?)\1", block, flags=re.S)
        name = html.unescape(name_match.group(2)) if name_match else ""
        if not name:
            row_tag = block.split(">", 1)[0]
            name = extract_attr(row_tag, "data-alg") or ""
        markup = extract_diagram_markup(block)
        if name and markup:
            diagrams.append(SourceDiagram(source_set=source_set, name=name, markup=markup))
    return diagrams


def source_sets_for(targets: Iterable[AlgCaseTarget]) -> dict[tuple[str, str], list[str]]:
    result: dict[tuple[str, str], list[str]] = {}
    for target in targets:
        key = (target.puzzle, target.set_id)
        result[key] = SET_SOURCE_OVERRIDES.get(target.set_id, [target.set_id])
    return result


def fetch_source_index(targets: list[AlgCaseTarget]) -> dict[tuple[str, str], dict[str, list[SourceDiagram]]]:
    index: dict[tuple[str, str], dict[str, list[SourceDiagram]]] = {}
    for (puzzle, local_set), source_sets in sorted(source_sets_for(targets).items()):
        by_name: dict[str, list[SourceDiagram]] = {}
        for source_set in source_sets:
            url = f"https://www.speedcubedb.com/a/{PUZZLE_PATH[puzzle]}/{source_set}"
            print(f"fetch {url}")
            source = fetch_source_html(url)
            diagrams = extract_source_diagrams(source, source_set)
            if not diagrams:
                print(f"warning: no source diagrams found for {url}")
            for diagram in diagrams:
                by_name.setdefault(normalize(diagram.name), []).append(diagram)
        index[(puzzle, local_set)] = by_name
        print(f"  {sum(len(v) for v in by_name.values())} source diagrams")
    return index


def match_source_diagram(target: AlgCaseTarget, source_index: dict[tuple[str, str], dict[str, list[SourceDiagram]]]) -> SourceDiagram | None:
    by_name = source_index.get((target.puzzle, target.set_id), {})
    keys: list[str] = []
    for raw in (target.display_name, target.name, target.case_id):
        key = normalize(raw)
        if key and key not in keys:
            keys.append(key)
    for key in keys:
        matches = by_name.get(key)
        if matches:
            return matches[0]
    return None


def rewrite_markup(target: AlgCaseTarget, markup: str) -> str:
    width = target.width
    height = target.height
    markup = markup.strip()
    if markup.startswith("<img"):
        padding = 6 if target.puzzle == "Megaminx" else 0
        image_width = max(1, width - padding * 2)
        image_height = max(1, height - padding * 2)
        markup = set_attr(markup, "width", str(image_width))
        markup = set_attr(markup, "height", str(image_height))
        markup = set_attr(
            markup,
            "style",
            (
                "display:block;"
                f"width:{image_width}px;height:{image_height}px;"
                f"margin:{padding}px;"
                "object-fit:contain;background:transparent"
            ),
        )
        return markup

    if markup.startswith("<svg"):
        svg_tag_match = re.match(r'<svg\b[^>]*>', markup, flags=re.S)
        if not svg_tag_match:
            return markup
        tag = svg_tag_match.group(0)
        original_width = extract_attr(tag, "width") or str(width)
        original_height = extract_attr(tag, "height") or str(height)
        tag = set_attr(tag, "width", str(width))
        tag = set_attr(tag, "height", str(height))
        tag = set_attr(tag, "viewBox", f"0 0 {original_width} {original_height}")
        tag = set_attr(tag, "style", f"display:block;width:{width}px;height:{height}px;background:transparent")
        return tag + markup[svg_tag_match.end():]

    tag_match = re.match(r'<div\b[^>]*>', markup, flags=re.S)
    if not tag_match:
        return markup
    tag = tag_match.group(0)
    class_value = extract_attr(tag, "class") or ""
    data_height = height
    class_names = class_value.split()
    if "sqcube" in class_names and extract_attr(tag, "data-display") == "2":
        data_height = max(1, height // 2)
    tag = set_attr(tag, "data-width", str(width))
    tag = set_attr(tag, "data-height", str(data_height))
    tag = set_attr(tag, "style", f"width:{width}px;height:{height}px;overflow:hidden;background:transparent")
    return tag + markup[tag_match.end():]



def read_png_pixels(path: Path) -> tuple[int, int, int, list[bytearray]]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    pos = 8
    width = height = color_type = None
    idat = bytearray()
    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        chunk_type = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])[:4]
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError(f"unsupported PNG format in {path}: bit_depth={bit_depth} color_type={color_type}")
        elif chunk_type == b"IDAT":
            idat.extend(chunk)
        elif chunk_type == b"IEND":
            break
    if width is None or height is None or color_type is None:
        raise ValueError(f"invalid PNG: {path}")
    channels = 4 if color_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    rows: list[bytearray] = []
    previous = bytearray(stride)
    index = 0

    def paeth(a: int, b: int, c: int) -> int:
        p = a + b - c
        pa = abs(p - a)
        pb = abs(p - b)
        pc = abs(p - c)
        if pa <= pb and pa <= pc:
            return a
        if pb <= pc:
            return b
        return c

    for _ in range(height):
        filter_type = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        if filter_type == 1:
            for i in range(stride):
                row[i] = (row[i] + (row[i - channels] if i >= channels else 0)) & 0xff
        elif filter_type == 2:
            for i in range(stride):
                row[i] = (row[i] + previous[i]) & 0xff
        elif filter_type == 3:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + ((left + previous[i]) // 2)) & 0xff
        elif filter_type == 4:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                up = previous[i]
                up_left = previous[i - channels] if i >= channels else 0
                row[i] = (row[i] + paeth(left, up, up_left)) & 0xff
        elif filter_type != 0:
            raise ValueError(f"unsupported PNG filter: {filter_type}")
        previous = row
        rows.append(row)
    return width, height, channels, rows


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    import binascii
    return len(payload).to_bytes(4, "big") + kind + payload + binascii.crc32(kind + payload).to_bytes(4, "big")


def write_png_rgba(path: Path, width: int, height: int, rows: list[bytes | bytearray]) -> None:
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), level=6))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(payload)

def crop_atlas_png(atlas_path: Path, entries: list[AtlasEntry]) -> None:
    atlas_width, atlas_height, channels, rows = read_png_pixels(atlas_path)
    for entry in entries:
        target = entry.target
        if entry.x + target.width > atlas_width or entry.y + target.height > atlas_height:
            raise ValueError(f"crop outside atlas for {target.image_key}")
        cropped: list[bytearray] = []
        for y in range(entry.y, entry.y + target.height):
            source_row = rows[y]
            if channels == 4:
                cropped.append(source_row[entry.x * 4:(entry.x + target.width) * 4])
            else:
                rgba = bytearray()
                for x in range(entry.x, entry.x + target.width):
                    start = x * 3
                    rgba.extend(source_row[start:start + 3])
                    rgba.append(255)
                cropped.append(rgba)
        target.output_path.parent.mkdir(parents=True, exist_ok=True)
        write_png_rgba(target.output_path, target.width, target.height, cropped)

def pack_entries(entries: list[tuple[AlgCaseTarget, str]]) -> tuple[list[AtlasEntry], int, int]:
    packed: list[AtlasEntry] = []
    atlas_width = max(MAX_ATLAS_WIDTH, max((target.width for target, _ in entries), default=1))
    atlas_width = min(atlas_width, MAX_ATLAS_WIDTH)
    x = y = row_height = 0
    for target, markup in entries:
        if x and x + target.width > atlas_width:
            x = 0
            y += row_height
            row_height = 0
        packed.append(AtlasEntry(target=target, markup=markup, x=x, y=y))
        x += target.width
        row_height = max(row_height, target.height)
    return packed, atlas_width, y + row_height


def render_atlas(entries: list[tuple[AlgCaseTarget, str]], workdir: Path, label: str) -> None:
    if not entries:
        return
    packed, width, height = pack_entries(entries)
    html_path = workdir / f"{label}.html"
    atlas_path = workdir / f"{label}.png"
    tiles = []
    for entry in packed:
        markup = rewrite_markup(entry.target, entry.markup)
        tiles.append(
            f'<div class="tile" style="left:{entry.x}px;top:{entry.y}px;width:{entry.target.width}px;height:{entry.target.height}px">{markup}</div>'
        )
    html_path.write_text(
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<style>html,body{{margin:0;width:{width}px;height:{height}px;background:transparent;overflow:hidden}}"
        ".tile{position:absolute;overflow:hidden;background:transparent}.tile>img,.tile>div{display:block}</style>"
        "<script src='https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js'></script>"
        "<script src='https://cdnjs.cloudflare.com/ajax/libs/svg.js/3.1.2/svg.min.js'></script>"
        "<script src='https://www.speedcubedb.com/includes/puzzleGen.min.js?d=12'></script>"
        "<script src='https://www.speedcubedb.com/includes/ijsm.js?d=2'></script>"
        "</head><body>" + "\n".join(tiles) + "</body></html>",
        encoding="utf-8",
    )
    command = [
        str(CHROME),
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--default-background-color=00000000",
        "--virtual-time-budget=8000",
        f"--window-size={width},{height}",
        f"--screenshot={atlas_path}",
        html_path.as_uri(),
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    crop_atlas_png(atlas_path, packed)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sets", nargs="*", help="Optional set IDs or JSON stems to rebuild, e.g. L3E sq1cs")
    parser.add_argument("--image-keys", nargs="*", help="Optional exact image keys to rebuild within the selected sets")
    parser.add_argument("--dry-run", action="store_true", help="Only fetch and match; do not write PNGs")
    args = parser.parse_args()

    if not CHROME.exists():
        fail(f"Google Chrome not found at {CHROME}")
    targets = load_targets(set(args.sets) if args.sets else None)
    targets = filter_targets(targets, set(args.image_keys) if args.image_keys else None)
    print(f"targets: {len(targets)} images")
    if not targets:
        return

    with tempfile.TemporaryDirectory(prefix="cubeflow-speedcubedb-images-") as temp_dir:
        workdir = Path(temp_dir)
        source_index = fetch_source_index(targets)
        entries_by_set: dict[tuple[str, str], list[tuple[AlgCaseTarget, str]]] = {}
        missing: list[AlgCaseTarget] = []
        for target in targets:
            diagram = match_source_diagram(target, source_index)
            if diagram:
                entries_by_set.setdefault((target.puzzle, target.set_id), []).append((target, diagram.markup))
                continue
            if target.puzzle == "Skewb" and target.setup:
                escaped_setup = html.escape(target.setup, quote=True)
                markup = f'<div class="scube" data-width="75" data-height="75" data-display="Pyra" data-alg="{escaped_setup}"></div>'
                entries_by_set.setdefault((target.puzzle, target.set_id), []).append((target, markup))
                continue
            missing.append(target)

        matched = sum(len(v) for v in entries_by_set.values())
        print(f"matched: {matched}; missing: {len(missing)}")
        if missing:
            for target in missing[:80]:
                print(f"missing: {target.set_id}/{target.display_name} ({target.image_key})")
            if len(missing) > 80:
                print(f"missing: ... {len(missing) - 80} more")
            fail("not all local cases matched SpeedCubeDB source diagrams")

        if args.dry_run:
            return

        for (puzzle, set_id), entries in sorted(entries_by_set.items()):
            label = re.sub(r"[^A-Za-z0-9_-]+", "_", f"{puzzle}_{set_id}")
            print(f"render {set_id}: {len(entries)} images")
            svg_entries = [(target, markup) for target, markup in entries if markup.strip().startswith("<svg")]
            non_svg_entries = [(target, markup) for target, markup in entries if not markup.strip().startswith("<svg")]
            if non_svg_entries:
                render_atlas(non_svg_entries, workdir, label)
            if svg_entries:
                # Chrome clips inline SVGs when they are positioned on later
                # atlas rows, so keep each SVG batch on a single row.
                max_per_row = max(1, MAX_ATLAS_WIDTH // max(target.width for target, _ in svg_entries))
                for index in range(0, len(svg_entries), max_per_row):
                    render_atlas(svg_entries[index:index + max_per_row], workdir, f"{label}_svg_{index // max_per_row}")

    print("done")


if __name__ == "__main__":
    main()
