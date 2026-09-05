#!/usr/bin/env python3
"""Read-only tested stack diagnostic entry point."""
import argparse
import json
import sys

from stack_status import DEFAULT_MANIFEST, evaluate, load_json, probe_stack


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Emit deterministic JSON")
    parser.add_argument("--observed", help="Evaluate supplied observation JSON without any system probes")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="Manifest JSON to evaluate")
    args = parser.parse_args(argv)
    try:
        report = evaluate(load_json(args.manifest), load_json(args.observed) if args.observed else probe_stack())
    except (OSError, ValueError, TypeError, RecursionError):
        error = {"schemaVersion": 1, "error": {"code": "stack-input-invalid", "message": "Stack manifest or observations could not be validated."}}
        print(json.dumps(error, sort_keys=True) if args.json else error["error"]["message"])
        return 2
    if args.json:
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    else:
        print("Stack: " + report["status"])
        for name, component in report["components"].items():
            print(f"  {name}: {component['status']} ({component['reason']}; {component['value'] or 'unknown'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
