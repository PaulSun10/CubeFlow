#!/usr/bin/env python3

import argparse
import base64
import html
import os
import re
import time
import urllib.parse
import subprocess
from dataclasses import dataclass
from pathlib import Path

from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "CubeFlow" / "Resources" / "Algs"
BASE_URL = "https://speedcubedb.com"


@dataclass(frozen=True)
class TargetSet:
    puzzle: str
    set_id: str
    aggregate: bool = False


TARGETS: list[TargetSet] = [
    TargetSet("2x2", "OrtegaOLL"),
    TargetSet("2x2", "OrtegaPBL"),
    TargetSet("2x2", "CLL"),
    TargetSet("2x2", "EG1"),
    TargetSet("2x2", "EG2"),
    TargetSet("4x4", "OLLParity"),
    TargetSet("4x4", "PLLParity"),
    TargetSet("5x5", "L2E"),
    TargetSet("5x5", "L2C"),
    TargetSet("SQ1", "Lin", aggregate=True),
    TargetSet("SQ1", "SQ1CS"),
    TargetSet("SQ1", "SQ1CO"),
    TargetSet("SQ1", "SQ1EO"),
    TargetSet("SQ1", "SQ1CP"),
    TargetSet("SQ1", "SQ1Parity"),
    TargetSet("SQ1", "SQ1LinPLL"),
    TargetSet("SQ1", "SQ1LinParityPLL"),
    TargetSet("SQ1", "SQ1EP"),
    TargetSet("SQ1", "SQ1LinPLL1"),
    TargetSet("Megaminx", "MegaminxOLL", aggregate=True),
    TargetSet("Megaminx", "MegaminxPLL", aggregate=True),
    TargetSet("Megaminx", "MegaminxEO"),
    TargetSet("Megaminx", "MegaminxCO"),
    TargetSet("Megaminx", "MegaminxEP"),
    TargetSet("Megaminx", "MegaminxCP"),
    TargetSet("Pyraminx", "L3E"),
    TargetSet("Pyraminx", "L4E"),
    TargetSet("Skewb", "SarahsAdvanced"),
]

SUBCATEGORY_CARD_RE = re.compile(
    r"(<a[^>]*class='search-category'[^>]*>).*?<div class=\"card-body mt-2\">(.*?)</div>",
    re.S,
)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "case"


def folder_name(set_id: str) -> str:
    return f"{set_id.upper()}Images"


def fetch_url(url: str, retries: int = 4, timeout_seconds: int = 35) -> str:
    for attempt in range(retries):
        try:
            return subprocess.check_output(
                ["curl", "-k", "-L", "-sS", "--max-time", str(timeout_seconds), url],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            if attempt == retries - 1:
                raise
            time.sleep(1.0 * (attempt + 1))
    raise RuntimeError("unreachable")


def download_file(url: str, output_path: Path, retries: int = 4, timeout_seconds: int = 35) -> None:
    data_url_prefix = "data:image/png;base64,"
    if url.startswith(data_url_prefix):
        output_path.write_bytes(base64.b64decode(url[len(data_url_prefix):]))
        return

    for attempt in range(retries):
        try:
            subprocess.check_call(
                ["curl", "-k", "-L", "-sS", "--max-time", str(timeout_seconds), "-o", str(output_path), url],
                stderr=subprocess.DEVNULL,
            )
            return
        except subprocess.CalledProcessError:
            if attempt == retries - 1:
                raise
            time.sleep(1.0 * (attempt + 1))


def parse_subcategories(parent_html: str, puzzle: str) -> list[str]:
    subcategories: list[str] = []
    seen: set[str] = set()
    for anchor_tag, _title in SUBCATEGORY_CARD_RE.findall(parent_html):
        data_search_match = re.search(r"data-search='([^']+)'", anchor_tag)
        href_match = re.search(r"href='([^']+)'", anchor_tag)
        if not data_search_match or not href_match:
            continue

        href = href_match.group(1).lstrip("/")
        expected_prefix = f"a/{puzzle}/"
        if not href.startswith(expected_prefix):
            continue

        set_id = normalize_text(data_search_match.group(1))
        if set_id and set_id not in seen:
            seen.add(set_id)
            subcategories.append(set_id)
    return subcategories


def page_urls_for(target: TargetSet) -> list[str]:
    parent = f"{BASE_URL}/a/{target.puzzle}/{target.set_id}"
    if not target.aggregate:
        return [parent]

    parent_html = fetch_url(parent)
    return [f"{BASE_URL}/a/{target.puzzle}/{sub_set_id}" for sub_set_id in parse_subcategories(parent_html, target.puzzle)]


def rows_on_page(page) -> list[dict[str, str]]:
    return page.eval_on_selector_all(
        ".row.singlealgorithm",
        """
        rows => rows.map((row, index) => {
            const link = row.querySelector('[data-alg-filter], [data-title], [data-alg]');
            const title = link?.getAttribute('data-alg-filter')
                || row.getAttribute('data-alg')
                || link?.textContent
                || '';
            return { index, displayName: title.trim() };
        })
        """,
    )


def capture_svg_image(render_page, svg_html: str, output_path: Path) -> None:
    render_page.set_content(
        f"""
        <!doctype html>
        <html>
        <head>
            <style>
                html, body {{
                    margin: 0;
                    padding: 0;
                    background: white;
                }}
                #target {{
                    display: inline-block;
                    line-height: 0;
                }}
                svg {{
                    display: block;
                    overflow: visible;
                }}
            </style>
        </head>
        <body>
            <div id="target">{svg_html}</div>
        </body>
        </html>
        """,
        wait_until="load",
    )
    render_page.locator("#target").screenshot(path=str(output_path), omit_background=False)


def capture_img_image(render_page, image_url: str, output_path: Path) -> None:
    escaped_url = html.escape(image_url, quote=True)
    render_page.set_content(
        f"""
        <!doctype html>
        <html>
        <head>
            <style>
                html, body {{
                    margin: 0;
                    padding: 0;
                    background: white;
                }}
                #target {{
                    display: inline-block;
                    line-height: 0;
                    background: white;
                }}
                img {{
                    display: block;
                }}
            </style>
        </head>
        <body>
            <div id="target"><img id="image" src="{escaped_url}"></div>
        </body>
        </html>
        """,
        wait_until="load",
    )
    render_page.wait_for_function(
        "() => { const image = document.getElementById('image'); return image && image.complete && image.naturalWidth > 0; }",
        timeout=15_000,
    )
    render_page.locator("#target").screenshot(path=str(output_path), omit_background=False)


def capture_page_rows(page, url: str, set_id: str, output_dir: Path, used_case_ids: set[str], overwrite: bool) -> tuple[int, int]:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60_000)
    except PlaywrightTimeoutError:
        print(f"  ! load timeout, trying partial DOM: {url}", flush=True)
        try:
            page.evaluate("window.stop()")
        except Exception:
            pass
    try:
        page.wait_for_selector(".row.singlealgorithm", timeout=15_000)
    except PlaywrightTimeoutError:
        print(f"  ! no rows: {url}", flush=True)
        return (0, 0)

    # jcube draws itself after page scripts run; a short settle avoids blank captures.
    page.wait_for_timeout(750)
    rows = rows_on_page(page)
    saved = 0
    skipped = 0
    render_page = page.context.new_page()

    for row_info in rows:
        display_name = normalize_text(row_info.get("displayName", ""))
        if not display_name:
            skipped += 1
            continue

        case_slug = slugify(display_name)
        case_id = case_slug
        suffix = 2
        while case_id in used_case_ids:
            case_id = f"{case_slug}_{suffix}"
            suffix += 1
        used_case_ids.add(case_id)

        image_key = f"{set_id.lower()}_{case_id}"
        output_path = output_dir / f"{image_key}.png"
        if output_path.exists() and not overwrite:
            skipped += 1
            continue

        row = page.locator(".row.singlealgorithm").nth(int(row_info["index"]))
        if set_id.lower() == "sarahsadvanced":
            try:
                row.evaluate("row => row.querySelectorAll('.alg-details').forEach(el => { el.style.display = 'block'; el.style.visibility = 'visible'; })")
                page.wait_for_timeout(100)
            except Exception:
                pass
        svg = row.locator(".jcube svg, .sqcube svg, .icube svg, .pcube svg, .scube svg").first
        try:
            if svg.count() > 0 and svg.bounding_box() is not None:
                svg_html = svg.evaluate("element => element.outerHTML")
                capture_svg_image(render_page, svg_html, output_path)
                saved += 1
                continue
        except Exception as exc:
            print(f"  ! isolated svg failed {image_key}: {exc}", flush=True)

        image = row.locator(".search-category-image img, img").first
        try:
            if image.count() > 0:
                image_url = image.evaluate("element => element.src")
                if image_url:
                    capture_img_image(render_page, image_url, output_path)
                    saved += 1
                    continue
        except Exception as exc:
            print(f"  ! image download failed {image_key}: {exc}", flush=True)

        candidates = [
            row.locator(".jcube canvas").first,
            row.locator(".sqcube canvas").first,
            row.locator(".icube canvas").first,
            row.locator(".pcube canvas").first,
            row.locator(".scube canvas").first,
            row.locator(".cubedb-ftw- canvas").first,
            row.locator(".jcube svg").first,
            row.locator(".sqcube svg").first,
            row.locator(".icube svg").first,
            row.locator(".pcube svg").first,
            row.locator(".scube svg").first,
            row.locator(".cubedb-ftw- svg").first,
            row.locator(".jcube").first,
            row.locator(".sqcube").first,
            row.locator(".icube").first,
            row.locator(".pcube").first,
            row.locator(".scube").first,
            row.locator(".cubedb-ftw-").first,
        ]

        target = None
        for candidate in candidates:
            try:
                if candidate.count() > 0 and candidate.bounding_box() is not None:
                    target = candidate
                    break
            except Exception:
                continue

        if target is None:
            print(f"  ! no image element for {image_key} ({display_name})", flush=True)
            skipped += 1
            continue

        try:
            target.screenshot(path=str(output_path), omit_background=True)
            saved += 1
        except Exception as exc:
            print(f"  ! failed {image_key}: {exc}", flush=True)
            skipped += 1

    render_page.close()
    return (saved, skipped)


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture SpeedCubeDB non-3x3 case images")
    parser.add_argument("--set", action="append", dest="sets", help="Limit to one or more set IDs, e.g. SQ1CS")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--headful", action="store_true")
    args = parser.parse_args()

    wanted = {item.lower() for item in args.sets or []}
    targets = [target for target in TARGETS if not wanted or target.set_id.lower() in wanted]

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headful)
        context = browser.new_context(
            viewport={"width": 900, "height": 900},
            device_scale_factor=2,
            ignore_https_errors=True,
        )
        page = context.new_page()

        total_saved = 0
        total_skipped = 0
        for index, target in enumerate(targets, start=1):
            output_dir = OUT_DIR / folder_name(target.set_id)
            output_dir.mkdir(parents=True, exist_ok=True)
            used_case_ids: set[str] = set()
            urls = page_urls_for(target)
            print(f"[{index}/{len(targets)}] {target.puzzle}/{target.set_id}: {len(urls)} page(s)", flush=True)
            for url in urls:
                saved, skipped = capture_page_rows(page, url, target.set_id, output_dir, used_case_ids, args.overwrite)
                total_saved += saved
                total_skipped += skipped
                print(f"  {url} -> saved {saved}, skipped {skipped}", flush=True)

        browser.close()

    print(f"DONE saved={total_saved} skipped={total_skipped}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
