#!/usr/bin/env python3
"""Assemble one suite's machine-readable result and decide its exit status.

The suite scripts collect evidence; this decides what that evidence means. It exists
as its own file because the rule that matters is a rule about absence:

    a required row that was not run is a failure, not a pass

A shell script that appends rows as it goes will happily report success when it
never reached half of them, so the required rows are declared up front with
--expect and every one of them has to come back with a passing status.

Rows arrive on stdin, one per line, tab separated:

    ID <TAB> STATUS <TAB> NOTE <TAB> EVIDENCE

STATUS is one of PASS, FAIL, SKIP, NOT_APPLICABLE, IN_PROGRESS. The overall verdict
is PASS only when every expected row is PASS, or NOT_APPLICABLE with a non-empty
reason. Anything else -- FAIL, SKIP, IN_PROGRESS, a status that is not recognised,
or a row that never arrived -- makes the suite non-passing and the exit status 1.
"""

import argparse
import json
import os
import platform
import subprocess
import sys
import time

PASSING = ("PASS", "NOT_APPLICABLE")
KNOWN = ("PASS", "FAIL", "SKIP", "NOT_APPLICABLE", "IN_PROGRESS")


def utc_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def read_rows(stream):
    rows = []
    for line in stream:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split("\t")
        while len(parts) < 4:
            parts.append("")
        row = {
            "id": parts[0].strip(),
            "status": parts[1].strip().upper(),
            "note": parts[2].strip(),
            "evidence": parts[3].strip(),
        }
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--device", default="")
    parser.add_argument("--bundle-id", default="")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--proof-dir", required=True)
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--expect", required=True,
                        help="comma separated ids that must all come back passing")
    parser.add_argument("--command", default="")
    parser.add_argument("--started-utc", default="")
    args = parser.parse_args()

    expected = [item.strip() for item in args.expect.split(",") if item.strip()]
    rows = read_rows(sys.stdin)
    by_id = {}
    for row in rows:
        by_id[row["id"]] = row

    missing = []
    for row_id in expected:
        if row_id not in by_id:
            missing.append(row_id)
            by_id[row_id] = {
                "id": row_id,
                "status": "SKIP",
                "note": "not run: the suite never reached this row",
                "evidence": "",
            }

    ordered = [by_id[row_id] for row_id in expected]
    # Rows the suite reported that were not declared are kept, so an unexpected
    # observation is visible rather than dropped, but they cannot rescue a verdict.
    extra = [row for row in rows if row["id"] not in expected]

    problems = []
    for row in ordered:
        status = row["status"]
        if status not in KNOWN:
            problems.append("{}: unrecognised status {}".format(row["id"], status or "(empty)"))
            row["status"] = "FAIL"
            continue
        if status == "NOT_APPLICABLE":
            if not row["note"]:
                problems.append("{}: NOT_APPLICABLE without a reason".format(row["id"]))
                row["status"] = "FAIL"
            continue
        if status != "PASS":
            problems.append("{}: {}".format(row["id"], status))

    verdict = "PASS" if not problems else "FAIL"

    os.makedirs(args.proof_dir, exist_ok=True)
    # A suite verdict is only meaningful against the SDK it ran on, so the toolchain
    # goes in beside the host block rather than being left to the caller to remember.
    xcode = []
    try:
        xcode = subprocess.check_output(["xcodebuild", "-version"]).decode("utf-8", "replace").splitlines()
    except (OSError, subprocess.CalledProcessError):
        pass

    result = {
        "suite": args.suite,
        "platform": args.platform,
        "configuration": args.configuration,
        "run_id": args.run_id,
        "proof_dir": os.path.abspath(args.proof_dir),
        "device_udid": args.device or None,
        "bundle_id": args.bundle_id or None,
        "started_utc": args.started_utc or utc_now(),
        "ended_utc": utc_now(),
        "command": args.command or " ".join(sys.argv),
        "host": {
            "node": platform.node(),
            "machine": platform.machine(),
            "macos": platform.mac_ver()[0],
            "python": platform.python_version(),
        },
        "xcode": [line.strip() for line in xcode],
        "expected_rows": expected,
        "rows": ordered,
        "unexpected_rows": extra,
        "verdict": verdict,
        "problems": problems,
    }

    path = os.path.join(args.proof_dir, "result.json")
    with open(path, "w") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")

    for row in ordered:
        sys.stdout.write("[test] {:4s} {:22s} {}\n".format(
            row["status"], row["id"], row["note"]))
    if extra:
        for row in extra:
            sys.stdout.write("[test] {:4s} {:22s} {} (not a required row)\n".format(
                row["status"], row["id"], row["note"]))
    sys.stdout.write("[test] {} {}: {}\n".format(args.suite, verdict, path))
    for problem in problems:
        sys.stdout.write("[test]   {}\n".format(problem))
    sys.stdout.flush()

    exit_code = 0
    if verdict != "PASS" or missing:
        exit_code = 1
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
