#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "artifacts/validation/public-pages.json"
BASE_URL = "https://adibirzu.github.io/OCI-Wazuh"

PAGES = {
    "/": ["OCI Wazuh Detection Lab documentation"],
    "/docs/wiki/": ["Wazuh + OCI Log Analytics Course", "Product Capability Tracks"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_CAPABILITIES.md": ["Capability Map", "Product Maturity Model"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_PRODUCT_ROADMAP.md": ["Capability Backlog", "Product Metrics"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_ADOPTION_GUIDE.md": ["Adoption Stages", "Production Exit Criteria"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_LEARNING_CURVE.md": ["Skill Ladder", "Role-Based Paths"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_LEARNER_WORKBOOK.md": ["Exercise 1: Source Inventory", "Final Assessment"],
    "/docs/wiki/WAZUH_LOG_ANALYTICS_GLOSSARY_FAQ.md": ["Glossary", "Troubleshooting Questions"],
    "/lessons/0001-siem-correlation-loop.html": ["Correlation Loop", "Module 1"],
    "/assets/teach.css": ["body", ".module"],
}


def fetch(url):
    request = Request(url, headers={"User-Agent": "oci-wazuh-page-validator/1.0"})
    with urlopen(request, timeout=20) as response:
        body = response.read().decode("utf-8", errors="replace")
        return response.status, body


def main():
    base = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else BASE_URL
    results = []
    failed = False

    for path, required_terms in PAGES.items():
        url = f"{base}{path}"
        try:
            status, body = fetch(url)
            missing = [term for term in required_terms if term not in body]
            ok = status == 200 and not missing
            failed = failed or not ok
            results.append({
                "url": url,
                "status": status,
                "required_terms": required_terms,
                "missing_terms": missing,
                "ok": ok,
            })
        except (HTTPError, URLError, TimeoutError) as exc:
            failed = True
            results.append({
                "url": url,
                "status": "error",
                "error": str(exc),
                "required_terms": required_terms,
                "missing_terms": required_terms,
                "ok": False,
            })

    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps({"base_url": base, "pages": results}, indent=2), encoding="utf-8")

    for result in results:
        print(f"page={result['url']} ok={str(result['ok']).lower()}")
        if result.get("missing_terms"):
            print(f"missing_terms={','.join(result['missing_terms'])}")

    if failed:
        return 1
    print(f"public_pages=ready artifact={ARTIFACT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
