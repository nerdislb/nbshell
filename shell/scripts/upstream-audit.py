#!/usr/bin/env python3
"""Check upstream sources, display cached results, or record a review decision."""
import argparse
import json
import sys
import fork_updates as forks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notify', action='store_true')
    parser.add_argument('--json', action='store_true', help='Output the shared JSON snapshot')
    parser.add_argument('--cached', action='store_true', help='Read saved results without networking')
    parser.add_argument('--decision', choices=['approved', 'deferred', 'pending'], help='Record a decision; never installs')
    parser.add_argument('--source', help='Catalog source ID')
    parser.add_argument('--token', help='Exact revision token shown in the snapshot')
    args = parser.parse_args()
    try:
        if args.decision:
            if not args.source or not args.token or args.cached or args.notify:
                parser.error('--decision requires --source and --token, without --cached/--notify')
            data = forks.decide(args.source, args.token, args.decision)
        elif args.cached:
            data = forks.snapshot()
        else:
            data = forks.refresh(args.notify)
        if args.json:
            print(json.dumps(data, ensure_ascii=False))
        else:
            for row in data['sources']:
                print(f"{row['name']}: {row['status']} ({row['base'][:7]} → {row.get('head', '')[:7] or '?'}) · {row['decision']}" + (f" · {row['error']}" if row.get('error') else ''))
        return 0 if args.decision else int(any(r['status'] == 'error' for r in data['sources']))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        error = 'A refresh is already running' if isinstance(exc, BlockingIOError) else str(exc)
        print(json.dumps({'error': error}) if args.json else error)
        return 1


if __name__ == '__main__':
    sys.exit(main())
