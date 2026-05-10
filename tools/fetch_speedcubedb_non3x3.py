#!/usr/bin/env python3

import html
import json
import os
import re
import subprocess
import time
import urllib.parse
from dataclasses import dataclass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "CubeFlow", "Resources", "Algs")


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


CASE_RE = re.compile(
    r"<div class=\"row singlealgorithm[^>]*data-subgroup=\"([^\"]*)\"[^>]*data-alg=\"([^\"]*)\"[^>]*>"
    r"(.*?)<li class='text-center'><button class='btn underline-link more-algs no-print' "
    r"data-category='([^']+)' data-d='([^']+)' data-algname='([^']+)'[^>]*>",
    re.S,
)
FORMATTED_ALG_RE = re.compile(r"<div class=\"formatted-alg\">(.*?)</div>", re.S)
SUBCATEGORY_CARD_RE = re.compile(
    r"(<a[^>]*class='search-category'[^>]*>).*?<div class=\"card-body mt-2\">(.*?)</div>",
    re.S,
)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value or "")).strip()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return slug or "case"


def fetch_url(url: str, retries: int = 4, timeout_seconds: int = 35) -> str:
    for attempt in range(retries):
        try:
            return subprocess.check_output(
                ["curl", "-L", "-sS", "--max-time", str(timeout_seconds), url],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            if attempt == retries - 1:
                raise
            time.sleep(1.0 * (attempt + 1))
    raise RuntimeError("unreachable")


def parse_case_rows(page_html: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for subgroup, display_name, body, category, direction, algname in CASE_RE.findall(page_html):
        primary_match = FORMATTED_ALG_RE.search(body)
        primary_algorithm = normalize_text(primary_match.group(1) if primary_match else "")
        rows.append(
            {
                "subgroup": normalize_text(subgroup),
                "display_name": normalize_text(display_name),
                "category": normalize_text(category),
                "direction": normalize_text(direction),
                "algname": normalize_text(algname),
                "primary": primary_algorithm,
            }
        )
    return rows


def parse_more_algorithms(more_html: str) -> list[str]:
    algorithms = [normalize_text(item) for item in FORMATTED_ALG_RE.findall(more_html)]
    return [algorithm for algorithm in algorithms if algorithm]


def parse_subcategories(parent_html: str, puzzle: str) -> list[tuple[str, str]]:
    subcategories: list[tuple[str, str]] = []
    seen: set[str] = set()
    for anchor_tag, title in SUBCATEGORY_CARD_RE.findall(parent_html):
        data_search_match = re.search(r"data-search='([^']+)'", anchor_tag)
        href_match = re.search(r"href='([^']+)'", anchor_tag)
        if not data_search_match or not href_match:
            continue

        href = href_match.group(1)
        normalized_href = href.lstrip("/")
        expected_prefix = f"a/{puzzle}/"
        if not normalized_href.startswith(expected_prefix):
            continue

        set_id = normalize_text(data_search_match.group(1))
        if not set_id or set_id in seen:
            continue

        seen.add(set_id)
        subcategories.append((set_id, normalize_text(title)))
    return subcategories


def fetch_more_algorithms(row: dict[str, str], cache: dict[tuple[str, str, str], list[str]]) -> list[str]:
    key = (row["category"], row["direction"], row["algname"])
    if key in cache:
        return cache[key]

    url = (
        "https://speedcubedb.com/category.algs.php?algname="
        + urllib.parse.quote(row["algname"])
        + "&d="
        + urllib.parse.quote(row["direction"])
        + "&cat="
        + urllib.parse.quote(row["category"])
    )
    html_text = fetch_url(url, timeout_seconds=30)
    algorithms = parse_more_algorithms(html_text)
    cache[key] = algorithms
    return algorithms


def build_case_entry(
    *,
    row: dict[str, str],
    set_id: str,
    used_case_ids: set[str],
    more_cache: dict[tuple[str, str, str], list[str]],
    subgroup_override: str | None = None,
    group_override: str | None = None,
) -> dict | None:
    display_name = row["display_name"] or row["algname"]
    if not display_name:
        return None

    case_slug = slugify(display_name)
    case_id = case_slug
    suffix = 2
    while case_id in used_case_ids:
        case_id = f"{case_slug}_{suffix}"
        suffix += 1
    used_case_ids.add(case_id)

    algorithms: list[str] = []
    if row["primary"]:
        algorithms.append(row["primary"])
    for algorithm in fetch_more_algorithms(row, more_cache):
        if algorithm not in algorithms:
            algorithms.append(algorithm)

    if not algorithms:
        return None

    algorithm_objects = [
        {
            "id": f"{case_id}-{index + 1}",
            "notation": notation,
            "isPrimary": index == 0,
            "source": "SpeedCubeDB",
            "tags": [],
        }
        for index, notation in enumerate(algorithms)
    ]

    subgroup = subgroup_override if subgroup_override is not None else row["subgroup"]
    subgroup = subgroup or ""

    case_entry: dict = {
        "id": case_id,
        "displayName": display_name,
        "name": display_name,
        "subgroup": subgroup,
        "imageKey": f"{set_id.lower()}_{case_id}",
        "recognition": "",
        "notes": "",
        "setup": "",
        "algorithms": algorithm_objects,
    }
    if group_override is not None:
        case_entry["group"] = group_override
    return case_entry


def build_direct_payload(target: TargetSet, more_cache: dict[tuple[str, str, str], list[str]]) -> dict:
    url = f"https://speedcubedb.com/a/{target.puzzle}/{target.set_id}"
    page_html = fetch_url(url)
    rows = parse_case_rows(page_html)

    used_case_ids: set[str] = set()
    cases: list[dict] = []
    for row in rows:
        case_entry = build_case_entry(
            row=row,
            set_id=target.set_id,
            used_case_ids=used_case_ids,
            more_cache=more_cache,
        )
        if case_entry is not None:
            cases.append(case_entry)

    return {
        "puzzle": target.puzzle,
        "set": target.set_id,
        "version": 1,
        "source": "SpeedCubeDB",
        "cases": cases,
    }


def build_aggregate_payload(target: TargetSet, more_cache: dict[tuple[str, str, str], list[str]]) -> dict:
    parent_url = f"https://speedcubedb.com/a/{target.puzzle}/{target.set_id}"
    parent_html = fetch_url(parent_url)
    subcategories = parse_subcategories(parent_html, target.puzzle)

    used_case_ids: set[str] = set()
    cases: list[dict] = []
    for sub_set_id, sub_title in subcategories:
        page_html = fetch_url(f"https://speedcubedb.com/a/{target.puzzle}/{sub_set_id}")
        rows = parse_case_rows(page_html)
        for row in rows:
            case_entry = build_case_entry(
                row=row,
                set_id=target.set_id,
                used_case_ids=used_case_ids,
                more_cache=more_cache,
                subgroup_override=sub_title,
                group_override=sub_title,
            )
            if case_entry is not None:
                cases.append(case_entry)

    return {
        "puzzle": target.puzzle,
        "set": target.set_id,
        "version": 1,
        "source": "SpeedCubeDB",
        "cases": cases,
    }


def write_payload(payload: dict, set_id: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    output_path = os.path.join(OUT_DIR, f"{set_id.lower()}.json")
    with open(output_path, "w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")


def main() -> int:
    more_cache: dict[tuple[str, str, str], list[str]] = {}
    counts: dict[str, int] = {}
    sq1cs_cases: set[str] = set()
    sq1cs_subgroups: set[str] = set()

    print("Fetching non-3x3 sets from SpeedCubeDB...", flush=True)
    for index, target in enumerate(TARGETS, start=1):
        print(
            f"[{index}/{len(TARGETS)}] {target.puzzle}/{target.set_id} (aggregate={target.aggregate})",
            flush=True,
        )
        if target.aggregate:
            payload = build_aggregate_payload(target, more_cache)
        else:
            payload = build_direct_payload(target, more_cache)

        write_payload(payload, target.set_id)
        case_count = len(payload["cases"])
        counts[target.set_id] = case_count
        print(f"  -> {case_count} cases", flush=True)

        if target.set_id == "SQ1CS":
            sq1cs_cases = {case["displayName"] for case in payload["cases"]}
            sq1cs_subgroups = {case["subgroup"] for case in payload["cases"] if case["subgroup"]}

    print("COUNTS_JSON", json.dumps(counts, ensure_ascii=False, sort_keys=True), flush=True)
    print("SQ1CS_CASES_BEGIN", flush=True)
    for name in sorted(sq1cs_cases):
        print(name, flush=True)
    print("SQ1CS_CASES_END", flush=True)
    print("SQ1CS_SUBGROUPS_BEGIN", flush=True)
    for name in sorted(sq1cs_subgroups):
        print(name, flush=True)
    print("SQ1CS_SUBGROUPS_END", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
