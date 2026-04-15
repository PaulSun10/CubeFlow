#!/usr/bin/env python3
import argparse
import json
import re
from urllib.parse import urljoin, quote
import sys
import ssl
from html import unescape
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

BASE_URL = "https://speedcubedb.com"
F2L_INDEX = BASE_URL + "/a/3x3/F2L/"

# Heuristic: algorithm tokens (single moves).
ALG_TOKEN_PATTERN = re.compile(r"(?:[URFDLBMESxyzrludfb])(?:w)?(?:2|'|)?")

SVG_PATTERN = re.compile(r"(<svg\b[^>]*>.*?</svg>)", re.DOTALL | re.IGNORECASE)
CASE_LINK_PATTERN = re.compile(r'href="([^"]+)"')
ALG_DIV_PATTERN = re.compile(r'<div class="formatted-alg">([^<]+)</div>', re.IGNORECASE)
SINGLE_ALG_PATTERN = re.compile(
    r'<div class="row singlealgorithm[^"]*"[^>]*data-subgroup="([^"]*)"[^>]*>.*?<div class="formatted-alg">([^<]+)</div>',
    re.IGNORECASE | re.DOTALL,
)

D_SUBGROUP = {
    0: "Front Right",
    1: "Front Left",
    2: "Back Left",
    3: "Back Right",
}


def fetch_url(url: str, insecure: bool, timeout: int) -> str:
    req = Request(url, headers={"User-Agent": "CubeFlow/1.0 (F2L fetch)"})
    context = ssl._create_unverified_context() if insecure else None
    with urlopen(req, timeout=timeout, context=context) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_case_links(index_html: str) -> list[str]:
    links = CASE_LINK_PATTERN.findall(index_html)
    # Keep only F2L case links (exclude category pages).
    candidates = []
    for link in links:
        if "F2L_" in link or "F2L%20" in link:
            candidates.append(link)

    # Normalize and dedupe.
    seen = set()
    result = []
    for link in candidates:
        abs_url = urljoin(BASE_URL + "/", link)
        if abs_url in seen:
            continue
        seen.add(abs_url)
        result.append(abs_url)
    return result


def extract_svg(html: str) -> str | None:
    match = SVG_PATTERN.search(html)
    if not match:
        return None
    return match.group(1)


def extract_algs(html: str) -> list[str]:
    # Strip tags to get text-ish content.
    text = re.sub(r"<script\b[^>]*>.*?</script>", " ", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<style\b[^>]*>.*?</style>", " ", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = unescape(text)

    # Split into lines and capture move-like sequences.
    lines = [line.strip() for line in text.splitlines()]
    algs = []
    for line in lines:
        if not line:
            continue
        # Require at least one space and at least 3 moves.
        tokens = [t for t in line.split() if ALG_TOKEN_PATTERN.fullmatch(t)]
        if len(tokens) >= 3 and " " in line:
            # Normalize spacing by extracting move tokens.
            moves = []
            for token in tokens:
                move = token.strip()
                if not move:
                    continue
                moves.append(move)
            if len(moves) >= 3:
                alg = " ".join(moves)
                algs.append(alg)

    # Deduplicate while preserving order
    seen = set()
    deduped = []
    for alg in algs:
        if alg in seen:
            continue
        seen.add(alg)
        deduped.append(alg)
    return deduped


def fetch_algs_from_category(case_id: str, insecure: bool, timeout: int) -> list[dict]:
    algname = case_id.replace("_", " ")
    algs: list[dict] = []
    for d in range(4):
        url = f"https://speedcubedb.com/category.algs.php?algname={quote(algname)}&d={d}&cat=F2L"
        html = fetch_url(url, insecure, timeout)
        matches = SINGLE_ALG_PATTERN.findall(html)
        if matches:
            for subgroup, alg_raw in matches:
                alg = unescape(alg_raw).strip()
                alg = " ".join(alg.split())
                if alg:
                    algs.append({"alg": alg, "subgroup": subgroup or D_SUBGROUP.get(d)})
        else:
            for match in ALG_DIV_PATTERN.findall(html):
                alg = unescape(match).strip()
                alg = " ".join(alg.split())
                if alg:
                    algs.append({"alg": alg, "subgroup": D_SUBGROUP.get(d)})
    # Dedup by (alg, subgroup)
    seen = set()
    deduped = []
    for item in algs:
        key = (item.get("alg"), item.get("subgroup"))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def extract_algs_from_list_items(items: list[str]) -> list[str]:
    algs = []
    for text in items:
        if not text:
            continue
        if not re.search(r"[URFDLB]", text):
            continue
        for marker in ["Community Votes", "Movecount", "ETM", "STM", "Face Moves", "GEN ("]:
            if marker in text:
                text = text.split(marker)[0].strip()
                break
        line = text.splitlines()[0].strip()
        tokens = [t for t in line.split() if ALG_TOKEN_PATTERN.fullmatch(t)]
        if len(tokens) >= 3:
            algs.append(" ".join(tokens))

    seen = set()
    deduped = []
    for alg in algs:
        if alg in seen:
            continue
        seen.add(alg)
        deduped.append(alg)
    return deduped


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch SpeedCubeDB F2L algs and SVGs")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of cases (0 = all)")
    parser.add_argument("--output", type=str, default="F2L_speedcubedb.json", help="Output JSON path")
    parser.add_argument("--insecure", action="store_true", help="Disable SSL verification")
    parser.add_argument("--timeout", type=int, default=15, help="Network timeout in seconds")
    parser.add_argument("--case", action="append", default=[], help="Case ID or full URL (can be repeated)")
    parser.add_argument("--render", action="store_true", help="Render pages with Playwright to capture inline SVGs")
    args = parser.parse_args()

    if args.case:
        case_links = []
        for case in args.case:
            if case.startswith("http"):
                case_links.append(case)
            else:
                case_links.append(urljoin(BASE_URL + "/", f"/a/3x3/F2L/{case}"))
    else:
        try:
            index_html = fetch_url(F2L_INDEX, args.insecure, args.timeout)
        except (URLError, HTTPError, TimeoutError) as exc:
            print(f"Failed to fetch index: {exc}", file=sys.stderr)
            return 1

        case_links = extract_case_links(index_html)
    if args.limit > 0:
        case_links = case_links[: args.limit]

    results = []
    if args.render:
        try:
            from playwright.sync_api import sync_playwright
        except Exception as exc:
            print(f"Playwright not available: {exc}", file=sys.stderr)
            return 1

        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            for url in case_links:
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=args.timeout * 1000)
                    page.wait_for_timeout(1000)
                except Exception as exc:
                    print(f"Failed to render {url}: {exc}", file=sys.stderr)
                    continue

                case_id = url.rstrip("/").split("/")[-1].replace("%20", "_")
                svg = page.evaluate(
                    """
                    () => {
                      const svgs = Array.from(document.querySelectorAll('svg'));
                      const target = svgs.find(s => {
                        const w = parseFloat(s.getAttribute('width') || '0');
                        const h = parseFloat(s.getAttribute('height') || '0');
                        return w >= 60 && h >= 60;
                      }) || svgs[0];
                      return target ? target.outerHTML : null;
                    }
                    """
                )
                try:
                    primary_algs = fetch_algs_from_category(case_id, args.insecure, args.timeout)
                except Exception:
                    primary_algs = []

                # Scrape rendered DOM blocks (often the "More Algorithms" list on the case page).
                raw = page.evaluate(
                    """
                    () => {
                      const blocks = Array.from(document.querySelectorAll('div.singlealgorithm'));
                      const results = [];
                      for (const b of blocks) {
                        const el = b.querySelector('.formatted-alg');
                        const subgroup = b.getAttribute('data-subgroup');
                        if (el && el.textContent) {
                          results.push({ alg: el.textContent.trim(), subgroup });
                        }
                      }
                      return results;
                    }
                    """
                )
                more_algs = raw or []

                if not primary_algs and not more_algs:
                    items = page.eval_on_selector_all("li.list-group-item", "els => els.map(e => e.innerText)")
                    more_algs = [{"alg": a, "subgroup": None} for a in extract_algs_from_list_items(items)]

                # Normalize + dedup each list
                def normalize(items):
                    normalized = []
                    seen = set()
                    for item in items:
                        alg = " ".join((item.get("alg") or "").split())
                        subgroup = item.get("subgroup")
                        key = (alg, subgroup)
                        if not alg or key in seen:
                            continue
                        seen.add(key)
                        normalized.append({"alg": alg, "subgroup": subgroup})
                    return normalized

                primary_algs = normalize(primary_algs)
                more_algs = normalize(more_algs)

                results.append(
                    {
                        "case": case_id,
                        "url": url,
                        "primary_algs": primary_algs,
                        "more_algs": more_algs,
                        "svg": svg,
                    }
                )
            browser.close()
    else:
        for url in case_links:
            try:
                html = fetch_url(url, args.insecure, args.timeout)
            except (URLError, HTTPError, TimeoutError) as exc:
                print(f"Failed to fetch {url}: {exc}", file=sys.stderr)
                continue

            case_id = url.rstrip("/").split("/")[-1].replace("%20", "_")
            svg = extract_svg(html)
            algs = extract_algs(html)

            results.append(
                {
                    "case": case_id,
                    "url": url,
                    "primary_algs": [{"alg": a, "subgroup": None} for a in algs],
                    "more_algs": [],
                    "svg": svg,
                }
            )

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"Wrote {len(results)} cases to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
