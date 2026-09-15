#!/usr/bin/env python3
"""Bounded test orchestration for the native Strikers build surface.

One place decides what a suite is, so `scripts/native/test.sh` stays a thin
contract wrapper and the row set stays reviewable.  The runner never invents a
pass: a check that cannot run is reported as IN_PROGRESS with the reason, and
suite_report.py turns any non-PASS row into a non-zero exit status.

Rows are emitted one per line as ID<TAB>STATUS<TAB>NOTE<TAB>EVIDENCE and piped
into suite_report.py, which owns the machine-readable result and the verdict.

Suites:

  unit        the port's data-independent tests, run from the macOS build
  smoke       the N2 gate: platform metadata, no host linkage, and the probe
              app bringing up a real drawable in the Simulator
  acceptance  the doc 34 functional matrix, driven through driver.py, plus the
              build/provenance rows that are not gameplay checks
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
NATIVE = os.path.dirname(HERE)                      # scripts/native
ROOT = os.path.dirname(os.path.dirname(NATIVE))     # repository root

DRIVER = os.path.join(HERE, "driver.py")
SUITE_REPORT = os.path.join(HERE, "suite_report.py")
SCENARIO_ROOT = os.path.join(ROOT, "tests", "native", "scenarios")

APP_BUNDLE_ID = "com.ballpad.strikers"
PROBE_BUNDLE_ID = "com.ballpad.strikers.probe"

# Aurora's own gtests, as installed by the macOS engine build.  They are data
# independent, which is what lets B01 run without the disc image.
AURORA_TEST_BINARIES = [
    "gfx_recording_tests",
    "gx_fifo_tests",
    "gx_texture_cache_tests",
    "io_tests",
    "os_alloc_tests",
    "os_time_tests",
    "render_worker_tests",
    "texture_replacement_streaming_tests",
    "time_tests",
]

# Pure-Python tool tests, declared as ctest entries by the port's tests/CMakeLists.txt.
PORT_TOOL_TESTS = [
    ("tool-genstubs", "tools/test_genstubs.py"),
    ("tool-extract-disc", "tools/test_extract_disc.py"),
]


def utc_now():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def sanitize(value):
    """Rows are a tab-separated protocol, so separators cannot survive into a field."""
    text = "" if value is None else str(value)
    text = text.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    return text.strip()


def rel(path):
    """Proof references are recorded relative to the repository root and never absolute."""
    if not path:
        return ""
    try:
        return os.path.relpath(path, ROOT)
    except ValueError:
        return path


class Runner(object):
    def __init__(self, args):
        self.args = args
        self.rows = []
        self.notes = []
        self.started = time.time()
        self.log_dir = os.path.join(args.proof_dir, "logs")
        self.scenario_root = args.scenario_root or SCENARIO_ROOT
        os.makedirs(self.log_dir, exist_ok=True)

    # ------------------------------------------------------------------ shell

    def run(self, argv, timeout, log_name):
        """Run a command with a hard deadline; the combined output is kept either way."""
        log_path = os.path.join(self.log_dir, log_name + ".log")
        started = time.time()
        with open(log_path, "wb") as handle:
            try:
                proc = subprocess.run(argv, stdout=handle, stderr=subprocess.STDOUT,
                                      stdin=subprocess.DEVNULL, timeout=timeout, cwd=ROOT)
                status = proc.returncode
                timed_out = False
            except subprocess.TimeoutExpired:
                status = None
                timed_out = True
            except OSError as problem:
                status = None
                timed_out = False
                with open(log_path, "ab") as err:
                    err.write(("runner: " + str(problem) + "\n").encode())
        return {
            "status": status,
            "timed_out": timed_out,
            "seconds": round(time.time() - started, 3),
            "log": log_path,
            "argv": argv,
        }

    def read_log(self, path, limit=400000):
        try:
            with open(path, "r", errors="replace") as handle:
                return handle.read(limit)
        except OSError:
            return ""

    # ------------------------------------------------------------------- rows

    def row(self, row_id, status, note, evidence):
        self.rows.append((sanitize(row_id), sanitize(status), sanitize(note), sanitize(evidence)))
        # Progress goes to stderr so the suite's own report on stdout stays the single
        # authoritative table; both are captured, so a long run is still watchable.
        sys.stderr.write("[test] {:<28} {}  {}\n".format(row_id, status, note))
        sys.stderr.flush()

    def budgets_exhausted(self):
        return self.args.budget > 0 and (time.time() - self.started) > self.args.budget

    def skip_for_budget(self, row_id, what):
        self.row(row_id, "IN_PROGRESS",
                 "suite budget of {}s exhausted before {}".format(self.args.budget, what), "")

    # ------------------------------------------------------------------- unit

    def unit_rows(self):
        """doc 34 B01: the macOS engine and its data-independent tests."""
        build = self.args.build_dir
        engine = os.path.join(build, "strikers")
        failures = 0

        if not os.path.exists(engine):
            self.row("B01", "IN_PROGRESS",
                     "no macOS engine at {}; run scripts/native/build.sh --platform macos".format(rel(engine)), "")
            return

        result = self.run(["otool", "-l", engine], 60, "unit-otool-engine")
        text = self.read_log(result["log"])
        platform_value = None
        match = re.search(r"LC_BUILD_VERSION.*?platform (\d+)", text, re.S)
        if match:
            platform_value = match.group(1)
        if platform_value == "1":
            self.row("U.engine-platform", "PASS", "macOS engine is arm64 macOS (LC_BUILD_VERSION platform 1)",
                     rel(result["log"]))
        else:
            failures += 1
            self.row("U.engine-platform", "FAIL",
                     "engine Mach-O platform is {}".format(platform_value or "unknown"), rel(result["log"]))

        tests = []
        for name in AURORA_TEST_BINARIES:
            tests.append(("U.aurora." + name,
                          [os.path.join(build, "extern", "aurora", "tests", name)],
                          "aurora"))
        tests.append(("U.chunk-bounds", [os.path.join(build, "tests", "chunk_bounds_test")], "port"))
        for name, script in PORT_TOOL_TESTS:
            tests.append(("U." + name,
                          ["python3", os.path.join(self.args.port_dir, script)],
                          "port"))

        for row_id, argv, group in tests:
            if self.budgets_exhausted():
                failures += 1
                self.skip_for_budget(row_id, "running the test suite")
                continue
            if not os.path.exists(argv[-1] if len(argv) == 1 else argv[1]):
                failures += 1
                self.row(row_id, "IN_PROGRESS", "test target was not built", "")
                continue
            result = self.run(argv, self.args.step_timeout, row_id.replace(".", "-"))
            output = self.read_log(result["log"])
            note = self.describe_test(group, output, result)
            if result["status"] == 0 and not result["timed_out"]:
                self.row(row_id, "PASS", note, rel(result["log"]))
            else:
                failures += 1
                self.row(row_id, "FAIL", note, rel(result["log"]))

        if failures:
            self.row("B01", "FAIL",
                     "{} of {} macOS engine/unit checks failed".format(failures, len(tests) + 1), rel(self.log_dir))
        else:
            self.row("B01", "PASS",
                     "macOS engine reproduces and all {} data-independent checks pass".format(len(tests)),
                     rel(self.log_dir))

    @staticmethod
    def describe_test(group, output, result):
        if result["timed_out"]:
            return "timed out after {:.0f}s".format(result["seconds"])
        if result["status"] not in (0, None):
            tail = output.strip().splitlines()[-1:] or [""]
            return "exit status {}; {}".format(result["status"], tail[0][:120])
        if group == "aurora":
            match = re.search(r"\[(\s*\d+)\s+tests? from .*?\]\[\s*PASSED\s*\]\s*(\d+) tests?", output)
            if match:
                return "{} gtests passed in {:.1f}s".format(match.group(2), result["seconds"])
            match = re.search(r"\[  PASSED  \] (\d+) test", output)
            if match:
                return "{} gtests passed in {:.1f}s".format(match.group(1), result["seconds"])
            return "gtest binary exited 0 in {:.1f}s".format(result["seconds"])
        tail = [line for line in output.strip().splitlines() if line.strip()][-1:]
        return "exit 0 in {:.1f}s; {}".format(result["seconds"], tail[0][:120] if tail else "no output")

    # --------------------------------------------------------------------- iOS

    def simctl(self, argv, timeout, log_name):
        return self.run(["xcrun", "simctl"] + argv, timeout, log_name)

    def app_path(self, name):
        """Resolve a bundle the way scripts/native/build.sh does.

        The app target comes from the port's add_subdirectory(), so its bundle lands in the
        port's binary directory instead of at the top of the build tree.  mobile/CMakeLists.txt
        publishes both paths at configure time; the plain location and a one-level search are
        fallbacks for a build directory that predates that file.  Resolving to a path that does
        not exist is reported as IN_PROGRESS rather than silently passing, so getting this right
        is what lets the platform and linkage rows mean anything.
        """
        direct = os.path.join(self.args.sim_build_dir, name + ".app")
        wanted = "probe" if name == self.args.probe_name else "strikers"
        published = os.path.join(self.args.sim_build_dir, "ballpad-bundles.txt")
        if os.path.isfile(published):
            try:
                with open(published) as handle:
                    for line in handle:
                        field, _, value = line.strip().partition("=")
                        if field == wanted and value and os.path.isdir(value):
                            return value
            except OSError:
                pass
        if os.path.isdir(direct):
            return direct
        if os.path.isdir(self.args.sim_build_dir):
            for entry in sorted(os.listdir(self.args.sim_build_dir)):
                candidate = os.path.join(self.args.sim_build_dir, entry, name + ".app")
                if os.path.isdir(candidate):
                    return candidate
        return direct

    def app_binary(self, app):
        name = os.path.basename(app)[:-4]
        candidate = os.path.join(app, name)
        if os.path.exists(candidate):
            return candidate
        return None

    def macho_platform(self, binary):
        result = self.run(["otool", "-l", binary], 60, "macho-" + os.path.basename(binary))
        text = self.read_log(result["log"])
        match = re.search(r"LC_BUILD_VERSION.*?platform (\d+)", text, re.S)
        return (match.group(1) if match else None), result["log"]

    def linked_libraries(self, binary):
        result = self.run(["otool", "-L", binary], 60, "otoolL-" + os.path.basename(binary))
        text = self.read_log(result["log"])
        libs = []
        for line in text.splitlines()[1:]:
            entry = line.strip().split(" (")[0]
            if entry:
                libs.append(entry)
        return libs, result["log"]

    def platform_rows(self, prefix):
        """doc 34 B02: platform metadata, not just an arm64 label."""
        want = "7" if self.args.platform == "simulator" else "2"
        want_name = "iOS Simulator" if want == "7" else "iOS device"
        ok = True
        for bundle, bundle_id in ((self.app_path(self.args.app_name), APP_BUNDLE_ID),
                                  (self.app_path(self.args.probe_name), PROBE_BUNDLE_ID)):
            binary = self.app_binary(bundle)
            label = os.path.basename(bundle)
            if binary is None:
                ok = False
                self.row(prefix + ".platform." + label, "IN_PROGRESS",
                         "not built at {}; run scripts/native/build.sh --platform {}".format(
                             rel(bundle), self.args.platform), "")
                continue
            value, log = self.macho_platform(binary)
            if value == want:
                self.row(prefix + ".platform." + label, "PASS",
                         "{} is {} (LC_BUILD_VERSION platform {})".format(label, want_name, value), rel(log))
            else:
                ok = False
                self.row(prefix + ".platform." + label, "FAIL",
                         "{} Mach-O platform is {} (expected {})".format(label, value or "unknown", want_name),
                         rel(log))
        return ok

    def leakage_rows(self, prefix):
        """Homebrew and other host libraries must not reach a mobile link."""
        poison = ("/opt/homebrew/", "/usr/local/", "/opt/local/")
        ok = True
        for bundle in (self.app_path(self.args.app_name), self.app_path(self.args.probe_name)):
            binary = self.app_binary(bundle)
            label = os.path.basename(bundle)
            if binary is None:
                continue
            libs, log = self.linked_libraries(binary)
            bad = [entry for entry in libs if entry.startswith(poison)]
            if bad:
                ok = False
                self.row(prefix + ".linkage." + label, "FAIL",
                         "host library in link line: " + ", ".join(bad[:4]), rel(log))
            else:
                self.row(prefix + ".linkage." + label, "PASS",
                         "{} host links: {} SDK/system libraries, no Homebrew or /usr/local path".format(
                             label, len(libs)), rel(log))
        return ok

    def boot_device(self):
        # Booting is a precondition for the probe, not a measurement, so the budget here is a
        # wait rather than a threshold. It was 300 s until a shared host under heavy load sat in
        # "Waiting on BackBoard" past that and the run reported the environment's stall as a probe
        # failure, one row away from the check that actually matters. The device did then finish
        # booting on its own, which is what makes a budget increase the right fix: the row this
        # feeds still fails when the device never comes up, so nothing real is hidden by it.
        result = self.simctl(["bootstatus", self.args.device, "-b"], 900, "simctl-bootstatus")
        return result["status"] == 0

    def install(self, bundle, bundle_id):
        result = self.simctl(["install", self.args.device, bundle], 240,
                             "simctl-install-" + bundle_id)
        return result["status"] == 0, result["log"]

    def sim_launch(self, bundle_id, env, timeout, log_name):
        sim_env = dict(os.environ)
        for key, value in env.items():
            sim_env["SIMCTL_CHILD_" + key] = str(value)
        # --console-pty streams the app's stderr so the probe's own report is the evidence;
        # simctl does not hand back the guest process' exit status, which is why the probe
        # prints an explicit verdict line instead of relying on it.
        command = ["xcrun", "simctl", "launch", "--console-pty",
                   "--terminate-running-process", self.args.device, bundle_id]
        log_path = os.path.join(self.log_dir, log_name + ".log")
        started = time.time()
        timed_out = False
        status = None
        with open(log_path, "wb") as handle:
            try:
                proc = subprocess.run(command, env=sim_env, stdout=handle, stderr=subprocess.STDOUT,
                                      stdin=subprocess.DEVNULL, timeout=timeout, cwd=ROOT)
                status = proc.returncode
            except subprocess.TimeoutExpired:
                timed_out = True
        return {"status": status, "timed_out": timed_out, "seconds": round(time.time() - started, 3),
                "log": log_path}

    def terminate(self, bundle_id):
        self.simctl(["terminate", self.args.device, bundle_id], 60, "simctl-terminate")

    def probe_rows(self, prefix):
        """doc 33 N2 gate: the minimal app brings up a drawable and exits cleanly."""
        bundle = self.app_path(self.args.probe_name)
        if self.app_binary(bundle) is None:
            self.row(prefix + ".probe", "IN_PROGRESS", "BallpadProbe.app was not built", "")
            return False
        installed, log = self.install(bundle, PROBE_BUNDLE_ID)
        if not installed:
            self.row(prefix + ".probe", "FAIL", "simctl install failed for BallpadProbe.app", rel(log))
            return False

        frames = self.args.probe_frames
        result = self.sim_launch(PROBE_BUNDLE_ID,
                                 {"STRIKERS_PROBE_FRAMES": frames,
                                  "STRIKERS_BACKEND": self.args.probe_backend,
                                  "STRIKERS_BACKEND_FORCE": self.args.probe_backend},
                                 self.args.probe_timeout, "probe")
        output = self.read_log(result["log"])
        match = re.search(r"\[probe\] (ok|fail) frames=(\d+) presented=(\d+) skipped=(\d+) exits=(\d+) backend=(\S+)",
                          output)
        if result["timed_out"]:
            self.terminate(PROBE_BUNDLE_ID)
            self.row(prefix + ".probe", "FAIL",
                     "probe did not finish within {:.0f}s".format(self.args.probe_timeout), rel(result["log"]))
            return False
        if not match:
            tail = [line for line in output.strip().splitlines() if line.strip()][-1:]
            self.row(prefix + ".probe", "FAIL",
                     "probe printed no verdict; last line: " + (tail[0][:120] if tail else "none"),
                     rel(result["log"]))
            return False
        verdict, wanted, presented, skipped, exits, backend = match.groups()
        if verdict == "ok" and int(presented) > 0:
            self.row(prefix + ".probe", "PASS",
                     "probe presented {}/{} frames on backend {} and exited cleanly".format(
                         presented, wanted, backend), rel(result["log"]))
            return True
        self.row(prefix + ".probe", "FAIL",
                 "probe verdict {}: presented={} skipped={} exits={} backend={}".format(
                     verdict, presented, skipped, exits, backend), rel(result["log"]))
        return False

    # ------------------------------------------------------------------- suites

    def suite_unit(self):
        self.unit_rows()
        return [row[0] for row in self.rows]

    def suite_smoke(self):
        if not self.args.device:
            self.row("W.device", "FAIL", "smoke needs --device <UDID> for the Simulator", "")
            return [row[0] for row in self.rows]
        self.platform_rows("W")
        self.leakage_rows("W")
        if not self.boot_device():
            self.row("W.probe", "FAIL", "Simulator {} did not reach booted state".format(self.args.device), "")
            return [row[0] for row in self.rows]
        self.probe_rows("W")
        return [row[0] for row in self.rows]

    # Map each doc 34 row to the check that produces it.  A row whose check is not
    # implemented yet is reported IN_PROGRESS, which suite_report turns into a
    # failing exit status: an unrun required row is never an acceptance pass.
    ACCEPTANCE_ROWS = [
        ("F01", "Files import UI"),
        ("F02", "invalid image handling"),
        ("F03", "cold boot to active play"),
        ("F04", "real touch navigation and simultaneous input"),
        ("F05", "full match, goal, replay, post-match, second match"),
        ("F06", "landscape layout, control editing and persistence"),
        ("F07", "pause/resume, menu cycles, background/foreground"),
        ("F08", "display settings at a frame boundary"),
        ("F09", "sustained native audio with queue diagnostics"),
        ("F10", "THP movie video and audio"),
        ("F11", "save persistence, export/import round trip"),
        ("F12", "controller merging at the bridge boundary"),
        ("F13", "About, links and bundled notices"),
        ("F14", "native engine identity and Metal presentation"),
        ("B01", "macOS engine and data-independent tests"),
        ("B02", "Simulator and device platform metadata"),
        ("B03", "bootstrap from clean checkout/output"),
        ("B04", "no generated data staged; inventory matches bundle"),
        ("B05", "truthful status, current digests, documented commands"),
    ]

    # Rows that a check in this repository can already decide today.  Everything
    # else is listed above and reported as IN_PROGRESS with its reason.
    ACCEPTANCE_IMPLEMENTED = set(["B01", "B02"])

    def suite_acceptance(self):
        if not self.args.device:
            self.row("A.device", "FAIL", "acceptance needs --device <UDID> for the Simulator", "")
            return [row[0] for row in self.rows]
        self.unit_rows()
        self.platform_rows("A")
        self.leakage_rows("A")
        for row_id, description in self.ACCEPTANCE_ROWS:
            if row_id in ("B01", "B02"):
                continue
            self.row(row_id, "IN_PROGRESS",
                     "no automated check yet for {} ({}); driven rows arrive with N3-N5".format(
                         row_id, description), "")
        return [row[0] for row in self.rows]

    def suite(self):
        if self.args.suite == "unit":
            return self.suite_unit()
        if self.args.suite == "smoke":
            return self.suite_smoke()
        return self.suite_acceptance()

    # ----------------------------------------------------------------- metadata

    def device_facts(self):
        if not self.args.device:
            return None
        result = self.simctl(["list", "devices", "-j"], 90, "simctl-list")
        try:
            with open(result["log"], "r") as handle:
                body = json.load(handle)
        except (OSError, ValueError):
            return None
        for runtime, devices in body.get("devices", {}).items():
            for device in devices:
                if device.get("udid") == self.args.device:
                    return {"name": device.get("name"), "runtime": runtime,
                            "state_before": device.get("state"), "udid": device.get("udid")}
        return None

    def metadata(self, expected):
        def command_output(argv):
            try:
                return subprocess.check_output(argv, stderr=subprocess.STDOUT).decode("utf-8", "replace").strip()
            except (OSError, subprocess.CalledProcessError):
                return None

        return {
            "run_id": self.args.run_id,
            "suite": self.args.suite,
            "platform": self.args.platform,
            "form_factor": self.args.form_factor,
            "configuration": self.args.configuration,
            "started_utc": utc_now(),
            "wall_seconds": round(time.time() - self.started, 3),
            "expected_rows": expected,
            "host": {
                "node": os.uname()[1],
                "machine": os.uname()[4],
                "macos": command_output(["sw_vers", "-productVersion"]),
                "xcode": command_output(["xcodebuild", "-version"]),
                "sdk": command_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
                "python": sys.version.split()[0],
            },
            "device": self.device_facts(),
            "proof_dir": rel(self.args.proof_dir),
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", required=True, choices=["unit", "smoke", "acceptance"])
    parser.add_argument("--platform", default="macos")
    parser.add_argument("--device", default="")
    parser.add_argument("--form-factor", default="")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--build-dir", default="")
    parser.add_argument("--sim-build-dir", default="")
    parser.add_argument("--port-dir", default="")
    parser.add_argument("--scenario-root", default="")
    parser.add_argument("--proof-dir", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--budget", type=float, default=1800.0)
    parser.add_argument("--step-timeout", type=float, default=180.0)
    parser.add_argument("--probe-timeout", type=float, default=180.0)
    parser.add_argument("--probe-frames", default="90")
    parser.add_argument("--probe-backend", default="metal")
    parser.add_argument("--app-name", default="BallpadStrikers")
    parser.add_argument("--probe-name", default="BallpadProbe")
    args = parser.parse_args()

    if not args.build_dir:
        args.build_dir = os.path.join(ROOT, "build", "native", "macos-release")
    if not args.sim_build_dir:
        args.sim_build_dir = os.path.join(ROOT, "build", "native", args.platform + "-release")
    if not args.port_dir:
        args.port_dir = os.path.join(ROOT, "work", "native", "strikers", "smstrikers-port")

    os.makedirs(args.proof_dir, exist_ok=True)
    runner = Runner(args)
    expected = runner.suite()

    rows_path = os.path.join(args.proof_dir, "rows.tsv")
    with open(rows_path, "w") as handle:
        for row in runner.rows:
            handle.write("\t".join(row) + "\n")

    with open(os.path.join(args.proof_dir, "suite-metadata.json"), "w") as handle:
        json.dump(runner.metadata(expected), handle, indent=2, sort_keys=True)
        handle.write("\n")

    with open(rows_path, "rb") as rows_handle:
        report = subprocess.run([sys.executable, SUITE_REPORT,
                                 "--suite", args.suite,
                                 "--platform", args.platform,
                                 "--device", args.device,
                                 "--run-id", args.run_id,
                                 "--configuration", args.configuration,
                                 "--proof-dir", args.proof_dir,
                                 "--expect", ",".join(expected)],
                                stdin=rows_handle)
    return report.returncode


if __name__ == "__main__":
    sys.exit(main())
