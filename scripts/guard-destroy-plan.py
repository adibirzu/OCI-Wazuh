#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from m11.destroy_guard import evaluate_destroy_plan  # noqa: E402

ARTIFACT = ROOT / "artifacts/validation/destroy-guard.json"
def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: guard-destroy-plan.py <destroy-plan.json> <project_name>")

    plan_path = Path(sys.argv[1])
    project_name = sys.argv[2]
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    result = evaluate_destroy_plan(plan, project_name)
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    context_path = ARTIFACT.parent / "_run.json"
    context = json.loads(context_path.read_text(encoding="utf-8")) if context_path.is_file() else {
        "mode": "teardown",
        "run_id": "standalone-teardown",
        "timestamp": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    artifact = {
        "gate": "destroy-guard",
        "mode": context["mode"],
        "run_id": context["run_id"],
        "state": "green" if result["ok"] else "failed",
        "timestamp": context["timestamp"],
        **result,
    }
    ARTIFACT.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if result["blocked"]:
        print(f"destroy_guard=blocked artifact={ARTIFACT.relative_to(ROOT)}")
        for item in result["blocked"]:
            print(f"blocked_delete address={item['address']} type={item['type']}")
        return 1

    print(f"destroy_guard=ready delete_count={result['delete_count']} artifact={ARTIFACT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
