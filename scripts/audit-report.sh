#!/usr/bin/env python3

"""Audit log reporting utility.

Parses environment audit log entries written in the new key=value format
and renders filtered results as table, JSON, or CSV output. Optionally
produces summary statistics.
"""

import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
import re
import shlex


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
AUDIT_LOG = PROJECT_ROOT / "logs" / "environment-audit.log"

NEW_FORMAT_RE = re.compile(r"^\[(?P<timestamp>[^\]]+)\]\s+(?P<rest>.*)$")
OLD_FORMAT_RE = re.compile(
    r"^(?P<timestamp>[0-9]{4}-[0-9]{2}-[0-9]{2}[ _][0-9]{2}:[0-9]{2}:[0-9]{2})\s+\|\s+"
    r"(?P<user>[^@]+)@(?P<host>[^ ]+)\s+\|\s+(?P<status>[A-Z_]+)\s+\|\s+(?P<details>.*)$"
)

COLOR_CODES = {
    "green": "\033[0;32m",
    "red": "\033[0;31m",
    "yellow": "\033[1;33m",
    "blue": "\033[0;34m",
    "cyan": "\033[0;36m",
    "magenta": "\033[0;35m",
    "reset": "\033[0m",
}


def colorize(text: str, color: str, enable: bool) -> str:
    if not enable or color not in COLOR_CODES:
        return text
    return f"{COLOR_CODES[color]}{text}{COLOR_CODES['reset']}"


def parse_kv_pairs(rest: str) -> dict:
    data: dict[str, str] = {}
    for token in shlex.split(rest):
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        data[key.lower()] = value
    return data


def parse_line(line: str) -> dict | None:
    line = line.strip()
    if not line:
        return None

    match = NEW_FORMAT_RE.match(line)
    if match:
        timestamp = match.group("timestamp").replace("T", " ")
        pairs = parse_kv_pairs(match.group("rest"))
        record = {
            "timestamp": timestamp,
            "action": pairs.get("action", "unknown"),
            "user": pairs.get("user", "unknown"),
            "host": pairs.get("host", "unknown"),
            "status": pairs.get("status", pairs.get("result", "INFO")).upper(),
            "fields": pairs,
        }
        detail_items = [
            f"{k}={v}"
            for k, v in pairs.items()
            if k not in {"action", "user", "host", "status", "result"}
        ]
        record["details"] = " ".join(detail_items)
        return record

    match = OLD_FORMAT_RE.match(line)
    if match:
        timestamp = match.group("timestamp").replace("_", " ")
        details = match.group("details")
        record = {
            "timestamp": timestamp,
            "action": match.group("status").lower(),
            "user": match.group("user"),
            "host": match.group("host"),
            "status": match.group("status"),
            "fields": {},
            "details": details,
        }
        return record

    return None


def apply_filters(record: dict, args: argparse.Namespace) -> bool:
    if args.user and record["user"] != args.user:
        return False

    if args.status and record["status"] != args.status.upper():
        return False

    if args.operation:
        action = record.get("action", "").lower()
        if action != args.operation.lower():
            return False

    if args.env:
        fields = record.get("fields", {})
        env_matches = {
            fields.get("environment"),
            fields.get("env"),
            fields.get("to_env"),
            fields.get("target_env"),
            fields.get("from_env"),
        }
        if args.env.lower() not in {e.lower() for e in env_matches if e}:
            return False

    if args.since or args.until:
        try:
            timestamp = datetime.fromisoformat(record["timestamp"])  # type: ignore[arg-type]
        except ValueError:
            return False
        if args.since and timestamp.date() < args.since:
            return False
        if args.until and timestamp.date() > args.until:
            return False

    return True


def load_entries(args: argparse.Namespace) -> list[dict]:
    if not AUDIT_LOG.exists():
        if args.verbose:
            print(f"Audit log not found: {AUDIT_LOG}", file=sys.stderr)
        return []

    entries: list[dict] = []
    with AUDIT_LOG.open("r", encoding="utf-8", errors="ignore") as logfile:
        for line in logfile:
            record = parse_line(line)
            if not record:
                continue
            if apply_filters(record, args):
                entries.append(record)

    if not args.stats and args.last is not None and len(entries) > args.last:
        entries = entries[-args.last :]

    return entries


def render_table(entries: list[dict], color: bool) -> None:
    if not entries:
        print("No entries found.")
        return

    headers = ["Timestamp", "User", "Host", "Status", "Details"]
    widths = [len(h) for h in headers[:-1]]
    for entry in entries:
        widths[0] = max(widths[0], len(entry.get("timestamp", "")))
        widths[1] = max(widths[1], len(entry.get("user", "")))
        widths[2] = max(widths[2], len(entry.get("host", "")))
        widths[3] = max(widths[3], len(entry.get("status", "")))

    def format_status(status: str) -> str:
        mapping = {
            "SUCCESS": "green",
            "AUTHORIZED": "green",
            "PASS_WITH_WARNINGS": "yellow",
            "START": "blue",
            "ATTEMPT": "blue",
            "WARNING": "yellow",
            "FAILED": "red",
            "FAIL": "red",
            "CANCELLED": "yellow",
        }
        color_name = mapping.get(status.upper(), "cyan")
        return colorize(status, color_name, color)

    header_line = " │ ".join([
        headers[0].ljust(widths[0]),
        headers[1].ljust(widths[1]),
        headers[2].ljust(widths[2]),
        headers[3].ljust(widths[3]),
        headers[4],
    ])
    rule = "═" * len(header_line)

    print(colorize(rule, "blue", color))
    print(colorize(header_line, "blue", color))
    print(colorize(rule, "blue", color))

    for entry in entries:
        details = entry.get("details", "")
        row = " │ ".join([
            entry.get("timestamp", "").ljust(widths[0]),
            entry.get("user", "").ljust(widths[1]),
            entry.get("host", "").ljust(widths[2]),
            format_status(entry.get("status", "")).ljust(widths[3]),
            details,
        ])
        print(row)

    print(colorize(rule, "blue", color))
    print(f"Total entries: {len(entries)}")


def render_json(entries: list[dict]) -> None:
    serialisable = [
        {
            "timestamp": e["timestamp"],
            "user": e["user"],
            "host": e["host"],
            "status": e["status"],
            "action": e.get("action", ""),
            "details": e.get("details", ""),
            "fields": e.get("fields", {}),
        }
        for e in entries
    ]
    json.dump({"entries": serialisable}, sys.stdout, indent=2)
    print()


def render_csv(entries: list[dict]) -> None:
    writer = csv.writer(sys.stdout)
    writer.writerow(["timestamp", "user", "host", "status", "action", "details"])
    for e in entries:
        writer.writerow([
            e["timestamp"],
            e["user"],
            e["host"],
            e["status"],
            e.get("action", ""),
            e.get("details", ""),
        ])


def render_stats(entries: list[dict], color: bool) -> None:
    if not entries:
        print("No entries found for statistics.")
        return

    total = len(entries)
    def percent(count: int) -> str:
        return f"{(count * 100) / total:.1f}%"

    counters = {
        "Status": Counter(e["status"] for e in entries),
        "Action": Counter(e.get("action", "unknown") for e in entries),
        "User": Counter(e["user"] for e in entries),
        "Host": Counter(e["host"] for e in entries),
    }

    env_counter: Counter[str] = Counter()
    for e in entries:
        fields = e.get("fields", {})
        env = fields.get("environment") or fields.get("env") or fields.get("to_env")
        if env:
            env_counter[env] += 1
    if env_counter:
        counters["Environment"] = env_counter

    for title, counter in counters.items():
        print(colorize(title, "magenta", color))
        for key, count in counter.most_common():
            label = f"  {key}:".ljust(24)
            print(f"{label}{count:3d} ({percent(count)})")
        print()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit log reporting tool")
    parser.add_argument("--last", type=int, default=20, help="Number of entries to display")
    parser.add_argument("--user", help="Filter by user")
    parser.add_argument("--status", help="Filter by status")
    parser.add_argument("--env", help="Filter by environment")
    parser.add_argument("--operation", help="Filter by action/operation")
    parser.add_argument("--since", type=lambda s: datetime.fromisoformat(s).date(), help="Filter entries on or after date (YYYY-MM-DD)")
    parser.add_argument("--until", type=lambda s: datetime.fromisoformat(s).date(), help="Filter entries on or before date (YYYY-MM-DD)")
    parser.add_argument("--stats", action="store_true", help="Show summary statistics instead of entries")
    parser.add_argument("--format", choices=["table", "json", "csv"], default="table", help="Output format")
    parser.add_argument("--no-color", action="store_true", help="Disable ANSI colors in table output")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose logging")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    entries = load_entries(args)

    if args.stats:
        render_stats(entries, not args.no_color)
        return 0

    if args.format == "json":
        render_json(entries)
    elif args.format == "csv":
        render_csv(entries)
    else:
        render_table(entries, not args.no_color)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
