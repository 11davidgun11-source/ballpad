#!/usr/bin/env python3
"""Turn one XCUITest result bundle into proof rows.

A UI test's verdict has to come from the result bundle the runner produced, not from
the build log. The log is scrubbed text and a scrape can silently disagree with what
XCTest recorded -- including the failure mode where the bundle loads and every test is
filtered out, which reads as a cheerful "Executed 0 tests" and no failure. So this
reads `xcrun xcresulttool get test-results tests`, the machine-readable form of the
same evidence, and emits one row per requested test method.

A requested method the bundle does not mention is emitted SKIP, which
lib/suite_report.py turns into a failing suite. That direction matters: an unrun UI
test must never read as a pass just because the bundle loaded.
"""

import argparse
import json
import subprocess
import sys


def test_report(bundle):
    output = subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "tests",
         "--path", bundle, "--compact"],
        stderr=subprocess.STDOUT)
    return json.loads(output.decode("utf-8", "replace"))


def collect(node, found):
    """Index every test case in the report tree by bare method name."""
    if node.get("nodeType") == "Test Case":
        name = (node.get("name") or "").rstrip("()")
        if name:
            found[name] = node
        return
    for child in node.get("children") or []:
        collect(child, found)


def describe(node):
    detail = (node.get("result") or "Unknown").lower()
    seconds = node.get("durationInSeconds")
    if seconds is not None:
        detail += " in {:.1f}s".format(float(seconds))
    messages = [child.get("name") for child in (node.get("children") or [])
                if child.get("nodeType") == "Failure Message"]
    if messages:
        detail += ": " + " / ".join(messages)
    return detail


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-bundle", required=True)
    parser.add_argument("--row", action="append", default=[],
                        help="ROWID=testMethodName, repeatable")
    args = parser.parse_args()

    try:
        report = test_report(args.result_bundle)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        sys.stderr.write("[ui] cannot read {}: {}\n".format(args.result_bundle, error))
        return 1

    found = {}
    for node in report.get("testNodes") or []:
        collect(node, found)

    for spec in args.row:
        row_id, _, method = spec.partition("=")
        node = found.get(method)
        if node is None:
            status = "SKIP"
            note = "{}: not in {}; the test did not run".format(method, args.result_bundle)
        elif node.get("result") == "Passed":
            status = "PASS"
            note = "{}: {}".format(method, describe(node))
        else:
            status = "FAIL"
            note = "{}: {}".format(method, describe(node))
        sys.stdout.write("{}\t{}\t{}\t{}\n".format(
            row_id, status, note.replace("\t", " "), args.result_bundle))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
