#!/usr/bin/env python3
"""Scenario driver for the native Strikers build surface.

Launches the engine -- the macOS binary directly, or the Simulator app through
simctl -- and drives it through the port's own control channel
(STRIKERS_CONTROL).  The engine acknowledges every script line it executes with
the frame it ran on, so the driver waits for its own acknowledgement instead of
sleeping and hoping.  State dumps the engine prints are recorded, and the run
ends in a machine-readable verdict.

The exit status is the only thing a caller should branch on: 0 means every
requirement in the scenario was observed, non-zero means one was not.  A
timeout, a crash and a missing expectation are all failures, and none of them is
converted into a pass.

Scenario directives (one per line; blank lines and # comments are ignored):

    env KEY=VALUE            set for the engine; only before the first step
    require-scene TEXT       wait until the heartbeat names a scene containing TEXT
    require-frame N          wait until the engine has rendered frame N
    wait-log TEXT [@SECONDS] wait for the next occurrence of TEXT in the engine log
    press BTN[+BTN...] [F]   hold buttons for F frames (default the port's own)
    stick X Y [F]            hold the main stick at -100..100 for F frames
    cmd SPEC                 queue a game debug command, OP[,a,b,c,f0..f3][=str]
    shot NAME                capture a frame to shots/NAME.ppm
    dump [LABEL]             record the engine's state dump
    expect TEXT              TEXT must appear in the engine output from now on
    quit                     ask the engine to shut down

A directive that becomes a control line is sent only after the previous line
has been acknowledged, so the engine executes the scenario in order even when a
scene load takes longer than usual.

wait-log exists for the states that have no scene of their own and no frame the
scenario can predict: a goal, an auto replay, a UI transition.  Each wait
consumes the text it matched, so repeating the same wait walks through the later
occurrences of a line the engine prints on a timer -- which is how a phase that
lasts many seconds gets sampled more than once.
"""

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

ACK_RE = re.compile(r"^\[control\] #(\d+) frame (\d+): (.*)$")
HEARTBEAT_RE = re.compile(r"^\[port\] frame (\d+) scene (.*)$")
# STRIKERS_LOG_SCENES=1 prints one of these on every front-end scene change,
# which is far finer than the ten-second heartbeat. It carries the screen's
# package name, so a scenario can wait for a screen by name even when the
# screen is over before the first heartbeat names it.
SCENE_ENTER_RE = re.compile(r"^\[port\] enter scene (\d+)(?:\s+(.*))?$")
CRASH_RE = re.compile(r"^\*\*\* .* (SIGSEGV|SIGBUS|SIGABRT|SIGILL|SIGFPE) ")


def utc_now():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def sha256_of(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                h.update(block)
        return h.hexdigest()
    except OSError:
        return None


def bundle_executable(app):
    """The file inside an .app bundle whose bytes are the engine.

    A Simulator run has no single executable to name -- --app is the bundle directory -- and
    hashing a directory fails, which is why earlier Simulator bundles recorded a null
    binary_sha256 and could not be tied to a build.  Naming the bundle's own executable gives
    the row the same identity a macOS run gets.
    """

    if os.path.isfile(app):
        return app
    if not os.path.isdir(app):
        return None
    candidate = os.path.join(app, os.path.basename(app)[:-4])
    return candidate if os.path.exists(candidate) else None


class Directive(object):
    def __init__(self, index, verb, argument, line):
        self.index = index
        self.verb = verb
        self.argument = argument
        self.line = line
        self.control_line = None
        self.ack_frame = None
        self.ok = True
        self.note = None


class Failure(Exception):
    pass


class Driver(object):
    def __init__(self, args):
        self.args = args
        self.env = {}
        self.directives = []
        self.steps = []
        self.scenes = []
        self.dumps = []
        self.shots = []
        self.crashes = []
        self.expectations = []
        self.proc = None
        self.log_path = None
        self.log_pos = 0
        self.log_pending = ""
        self.last_ack_seq = 0
        self.last_ack_frame = 0
        self.latest_frame = 0
        self.control_path = os.path.join(args.proof_dir, "control.txt")
        self.started_utc = utc_now()
        self.start_monotonic = time.time()
        self.log_scan_pos = 0
        self.pending_expect = []

    # ---------------------------------------------------------------- scenario

    def load_scenario(self, path):
        with open(path, "r") as handle:
            raw = handle.readlines()
        index = 0
        seen_step = False
        for line in raw:
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            parts = text.split(None, 1)
            verb = parts[0]
            argument = parts[1].strip() if len(parts) > 1 else ""
            if verb == "env":
                if seen_step:
                    raise Failure("line {}: env must come before the first step".format(index + 1))
                if "=" not in argument:
                    raise Failure("line {}: env needs KEY=VALUE".format(index + 1))
                key, value = argument.split("=", 1)
                self.env[key.strip()] = value
                continue
            known = ("require-scene", "require-frame", "wait-log", "press", "stick",
                     "cmd", "host", "shot", "dump", "expect", "quit")
            if verb not in known:
                raise Failure("line {}: unknown directive {}".format(index + 1, verb))
            seen_step = True
            index += 1
            self.directives.append(Directive(index, verb, argument, text))

    # ------------------------------------------------------------------- launch

    def control_for(self, directive):
        verb, argument = directive.verb, directive.argument
        if verb == "press":
            return "press " + argument
        if verb == "stick":
            return "stick " + argument
        if verb == "cmd":
            return "cmd " + argument
        if verb == "dump":
            return "dump"
        if verb == "shot":
            return "shot " + argument
        if verb == "quit":
            return "quit"
        return None

    def launch(self):
        os.makedirs(self.args.proof_dir, exist_ok=True)
        os.makedirs(os.path.join(self.args.proof_dir, "shots"), exist_ok=True)
        open(self.control_path, "w").close()

        env = dict(os.environ)
        env["STRIKERS_CONTROL"] = self.control_path
        env.setdefault("STRIKERS_SEED", "12345")
        # The engine resolves its disc image from STRIKERS_DATA; without it a run from the
        # proof directory would only find the data by accident.
        if self.args.asset:
            env["STRIKERS_DATA"] = self.args.asset
        # A run that writes into the player's user and cache directories is not
        # reproducible and would touch the owner's card, so both are pointed at
        # the proof bundle.
        env["STRIKERS_USER_DIR"] = os.path.join(self.args.proof_dir, "user")
        env["STRIKERS_CACHE_DIR"] = os.path.join(self.args.proof_dir, "cache")
        env.update(self.env)

        self.log_path = os.path.join(self.args.proof_dir, "app.log")
        self.stdout_path = os.path.join(self.args.proof_dir, "app.stdout.log")
        log = open(self.log_path, "w")
        out = open(self.stdout_path, "w")

        if self.args.platform == "simulator":
            command = ["xcrun", "simctl", "launch", "--console-pty",
                       "--terminate-running-process", self.args.device, self.args.bundle_id]
            sim = {}
            for key, value in env.items():
                sim["SIMCTL_CHILD_" + key] = value
            sim_env = dict(os.environ)
            sim_env.update(sim)
            self.proc = subprocess.Popen(command, env=sim_env, cwd=self.args.proof_dir,
                                         stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        else:
            if not os.path.exists(self.args.app):
                raise Failure("no engine binary at " + self.args.app)
            self.proc = subprocess.Popen([self.args.app], env=env, cwd=self.args.proof_dir,
                                         stdout=out, stderr=log, stdin=subprocess.DEVNULL)
        log.close()
        out.close()

    # --------------------------------------------------------------- log tailing

    def pump(self):
        """Read whatever the engine has written since the last call."""
        try:
            with open(self.log_path, "r", errors="replace") as handle:
                handle.seek(self.log_pos)
                data = handle.read()
                self.log_pos = handle.tell()
        except OSError:
            return []
        if not data:
            return []
        lines = (self.log_pending + data).split("\n")
        self.log_pending = lines.pop()
        for line in lines:
            self.observe(line)
        return lines

    def observe(self, line):
        match = ACK_RE.match(line)
        if match:
            self.last_ack_seq = int(match.group(1))
            self.last_ack_frame = int(match.group(2))
            self.latest_frame = max(self.latest_frame, self.last_ack_frame)
            return
        match = HEARTBEAT_RE.match(line)
        if match:
            self.latest_frame = max(self.latest_frame, int(match.group(1)))
            self.scenes.append({"frame": int(match.group(1)), "scene": match.group(2).strip()})
            return
        match = SCENE_ENTER_RE.match(line)
        if match:
            name = match.group(2)
            self.scenes.append({"frame": self.latest_frame,
                                "scene": match.group(1) + ("  " + name if name else "")})
            return
        if CRASH_RE.match(line):
            self.crashes.append(line.strip())

    def live_text(self):
        try:
            with open(self.log_path, "r", errors="replace") as handle:
                return handle.read()
        except OSError:
            return ""

    # ------------------------------------------------------------------ waiting

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def check_budget(self, what):
        if self.args.budget > 0 and (time.time() - self.start_monotonic) > self.args.budget:
            raise Failure("run budget of {}s exceeded while {}".format(self.args.budget, what))

    def wait_for(self, predicate, timeout, what):
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump()
            if predicate():
                return True
            if not self.alive() and self.args.platform != "simulator":
                self.pump()
                if predicate():
                    return True
                raise Failure("engine exited (status {}) while {}".format(
                    self.proc.returncode, what))
            self.check_budget(what)
            time.sleep(0.05)
        raise Failure("timeout after {:.0f}s while {}".format(timeout, what))

    def send(self, line):
        target = self.last_ack_seq + 1
        with open(self.control_path, "a") as handle:
            handle.write(line + "\n")
            handle.flush()
        self.wait_for(lambda: self.last_ack_seq >= target,
                      self.args.step_timeout,
                      "waiting for acknowledgement {} ({})".format(target, line))
        return self.last_ack_frame

    def wait_scene(self, needle):
        wanted = needle.lower()
        found = {"hit": False}

        def predicate():
            for entry in self.scenes:
                if wanted in entry["scene"].lower():
                    found["hit"] = True
                    return True
            return False

        self.wait_for(predicate, self.args.scene_timeout, "waiting for scene containing " + needle)
        return found["hit"]

    def wait_text(self, text, timeout):
        """Consume the next occurrence of TEXT in the engine log.

        The search resumes where the previous wait stopped, so two waits for the
        same periodic line land on two different lines rather than twice on one.

        A whole line is consumed, not just the match, so a needle that is a
        prefix of a longer line -- "state=0x10" against "state=0x100" -- cannot
        be matched twice off the same line.  Callers still have to keep the
        needle specific enough to name the line they mean.
        """

        def predicate():
            try:
                with open(self.log_path, "r", errors="replace") as handle:
                    handle.seek(self.log_scan_pos)
                    data = handle.read()
            except (OSError, AttributeError):
                return False
            index = data.find(text)
            if index < 0:
                return False
            newline = data.find("\n", index + len(text))
            self.log_scan_pos += newline + 1 if newline >= 0 else index + len(text)
            return True

        self.wait_for(predicate, timeout, "waiting for log text " + repr(text))

    def skip_prior_log(self):
        """Begin a wait from the current end of the engine log.

        A wait-log names a transition the driver has not caused yet, so text
        already in the file is history rather than evidence for this step.
        Without this, a wait would match the first goal of an earlier run and
        every later step would pass off stale lines.  wait_text keeps its own
        forward consumption so a repeated wait still lands on a new line.
        """

        try:
            self.log_scan_pos = max(self.log_scan_pos, os.path.getsize(self.log_path))
        except (OSError, TypeError):
            return

    # ------------------------------------------------------------- host actions

    def simctl(self, *arguments):
        result = subprocess.run(["xcrun", "simctl"] + list(arguments),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            raise Failure("simctl {}: {}".format(" ".join(arguments),
                                                 result.stdout.decode("utf-8", "replace").strip()))
        return result.stdout.decode("utf-8", "replace").strip()

    def host_action(self, argument):
        """A lifecycle transition the application cannot perform on itself.

        Backgrounding is what forces this hole in the directive set: doc 34 F07 asks
        for five background/foreground cycles and no in-process action can send an app
        to the background. Two named actions rather than a shell escape on purpose, so
        a scenario keeps describing the application rather than the host.

        Each action waits for the application's own log to report the transition, so a
        step succeeds because the app moved, not because a sleep elapsed.  Bringing
        another app to the front backgrounds this one; bringing this one back is a
        launch of an already-running process, which activates it rather than
        restarting it, and that is the difference between a resume and a relaunch.
        """

        if self.args.platform != "simulator":
            raise Failure("host actions are Simulator-only, not " + self.args.platform)

        # The log position is taken before the launch, not after it.  `simctl launch` returns
        # once the request is in, and the application can raise the notification the wait below
        # is looking for before that happens -- so skipping afterwards is a window in which the
        # one line this step exists to prove can already be in the file and still be missed.
        # Skipping first cannot match an earlier cycle either: those lines are behind the mark.
        if argument == "background":
            # Settings is present in every Simulator runtime, so no extra app has to be
            # installed for this and nothing here depends on a compiled helper.
            self.skip_prior_log()
            self.simctl("launch", self.args.device, "com.apple.Preferences")
            self.wait_text("host ui: background;", self.args.step_timeout)
            step_text = "backgrounded (touch input released)"
        elif argument == "foreground":
            self.skip_prior_log()
            self.simctl("launch", self.args.device, self.args.bundle_id)
            self.wait_text("host ui: active;", self.args.step_timeout)
            step_text = "foregrounded (frame loop resumed)"
        else:
            raise Failure("unknown host action: " + argument)

        print("[driver] host {}: {}".format(argument, step_text), flush=True)

    # ------------------------------------------------------------- dump parsing

    @staticmethod
    def parse_dump(block):
        session = {}
        match = {}
        for line in block:
            if "session task=" in line:
                body = line.split("session ", 1)[1]
                for key, value in re.findall(r"([a-z]+)=([^\s]+)", body):
                    if key in ("task", "pause"):
                        session[key] = int(value)
                    elif key in ("fe", "overlay"):
                        session[key] = [int(v) for v in value.split(",") if v]
            elif "match valid=" in line:
                body = line.split("match ", 1)[1]
                for key, value in re.findall(r"([a-z_]+)=([^\s]+)", body):
                    if key == "pads":
                        match[key] = [int(v) for v in value.split(",") if v]
                    elif key in ("pres", "pres_t"):
                        continue
                    else:
                        try:
                            match[key] = int(value)
                        except ValueError:
                            try:
                                match[key] = float(value)
                            except ValueError:
                                match[key] = value
        return session, match

    # -------------------------------------------------------------------- steps

    def run_steps(self):
        planned = list(self.directives)
        # The engine does not stop when control lines stop arriving, so every scenario
        # ends with an explicit shutdown unless it already asked for one.
        if not planned or planned[-1].verb != "quit":
            planned.append(Directive(len(planned) + 1, "quit", "", "quit (implicit)"))
        for directive in planned:
            step = {"n": directive.index, "directive": directive.line}
            try:
                self.execute(directive, step)
            except Failure as failure:
                step["ok"] = False
                step["failure"] = str(failure)
                self.steps.append(step)
                raise
            self.steps.append(step)
            print("[driver] step {}: {}  (frame {})".format(
                directive.index, directive.line, directive.ack_frame), flush=True)

    def execute(self, directive, step):
        verb, argument = directive.verb, directive.argument

        if self.pending_expect:
            for text in self.pending_expect:
                if text not in self.live_text():
                    raise Failure("expected text never appeared: " + text)
            self.pending_expect = []

        if verb == "expect":
            if argument not in self.live_text():
                self.pending_expect.append(argument)
            step["control_line"] = None
            return

        if verb == "require-scene":
            self.wait_scene(argument)
            step["control_line"] = None
            return

        if verb == "require-frame":
            target = int(argument)
            self.wait_for(lambda: self.latest_frame >= target,
                          self.args.scene_timeout,
                          "waiting for frame {}".format(target))
            step["control_line"] = None
            return

        if verb == "wait-log":
            head, _, seconds = argument.rpartition(" @")
            if head and seconds.isdigit():
                text, timeout = head, float(seconds)
            else:
                text, timeout = argument, self.args.scene_timeout
            self.skip_prior_log()
            self.wait_text(text, timeout)
            step["control_line"] = None
            return

        if verb == "host":
            self.host_action(argument)
            step["control_line"] = None
            return

        if verb == "shot":
            path = os.path.join(self.args.proof_dir, "shots", argument)
            if not path.endswith(".ppm"):
                path += ".ppm"
            line = "shot " + path
        else:
            line = self.control_for(directive)
            if line is None:
                step["control_line"] = None
                return

        directive.control_line = line
        step["control_line"] = line

        if verb == "dump":
            mark = self.log_pos
            directive.ack_frame = self.send(line)
            step["ack_frame"] = directive.ack_frame
            self.pump()
            with open(self.log_path, "r", errors="replace") as handle:
                handle.seek(mark)
                block = handle.read().split("\n")
            session, match = self.parse_dump(block)
            self.dumps.append({"label": argument or "dump-{}".format(directive.index),
                               "frame": directive.ack_frame,
                               "session": session, "match": match})
            return

        directive.ack_frame = self.send(line)
        step["ack_frame"] = directive.ack_frame

        if verb == "shot":
            self.shots.append(os.path.relpath(path, self.args.proof_dir))
            # The readback is recorded on the frame's own command encoder, so
            # the file lands a frame or two later.
            self.wait_for(lambda: os.path.exists(path) and os.path.getsize(path) > 0,
                          min(self.args.step_timeout, 30),
                          "waiting for the frame capture to be written")

        if verb == "quit":
            self.wait_for(lambda: not self.alive(), min(self.args.step_timeout, 60),
                          "waiting for a clean shutdown")

    # ------------------------------------------------------------------ metadata

    def metadata(self, result):
        """The host/toolchain/engine block doc 34 asks every proof bundle to carry."""
        return {
            "run_id": self.args.run_id,
            "host": {
                "node": platform.node(),
                "machine": platform.machine(),
                "system": platform.system(),
                "release": platform.release(),
                "macos": platform.mac_ver()[0],
                "python": platform.python_version(),
            },
            "platform": self.args.platform,
            "device_udid": self.args.device or None,
            "bundle_id": self.args.bundle_id or None,
            "app": self.args.app or None,
            "configuration": self.args.configuration,
            "engine_pin": self.args.engine_pin or None,
            "engine_head": self.args.engine_head or None,
            "patch_series_sha256": self.args.patch_series or None,
            "game_image": self.args.asset or None,
            "game_image_sha256": self.args.asset_sha or None,
            "seed": self.env.get("STRIKERS_SEED", "12345"),
            "scenario": os.path.basename(self.args.scenario_path),
            "verdict": result["verdict"],
            "wall_seconds": result["wall_seconds"],
            "started_utc": result["started_utc"],
            "ended_utc": result["ended_utc"],
            "shots": result["shots"],
        }

    # -------------------------------------------------------------------- teardown

    def teardown(self):
        if self.proc is None:
            return
        if self.alive():
            try:
                os.kill(self.proc.pid, signal.SIGTERM)
            except OSError:
                pass
            for _ in range(40):
                if not self.alive():
                    break
                time.sleep(0.1)
        if self.alive():
            try:
                os.kill(self.proc.pid, signal.SIGKILL)
            except OSError:
                pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass

    # --------------------------------------------------------------------- result

    def result(self, verdict, failure):
        status = self.proc.returncode if (self.proc and not self.alive()) else None
        return {
            "run_id": self.args.run_id,
            "suite": self.args.suite,
            "platform": self.args.platform,
            "scenario": self.args.scenario_path,
            "label": self.args.label,
            "started_utc": self.started_utc,
            "ended_utc": utc_now(),
            "wall_seconds": round(time.time() - self.start_monotonic, 3),
            "engine": {
                "pin": self.args.engine_pin,
                "head": self.args.engine_head,
                "binary": self.args.app,
                "binary_sha256": sha256_of(bundle_executable(self.args.app) or "") if self.args.app else None,
            },
            "game_image_sha256": self.args.asset_sha,
            "environment": self.env,
            "steps": self.steps,
            "scenes": self.scenes,
            "dumps": self.dumps,
            "shots": self.shots,
            "crashes": self.crashes,
            "engine_exit_status": status,
            "verdict": verdict,
            "failure": failure,
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--scenario-path", required=True)
    parser.add_argument("--proof-dir", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--app", default="")
    parser.add_argument("--device", default="")
    parser.add_argument("--bundle-id", default="")
    parser.add_argument("--label", default="")
    parser.add_argument("--asset-sha", default="")
    parser.add_argument("--asset", default="")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--patch-series", default="")
    parser.add_argument("--engine-pin", default="")
    parser.add_argument("--engine-head", default="")
    parser.add_argument("--budget", type=float, default=900.0)
    parser.add_argument("--step-timeout", type=float, default=60.0)
    parser.add_argument("--scene-timeout", type=float, default=180.0)
    args = parser.parse_args()

    # The guest runs with the proof directory as its working directory and is told where the
    # control file is, so a relative proof directory would send it looking for
    # <proof>/<proof>/control.txt and every script line would go unacknowledged.
    args.proof_dir = os.path.abspath(os.path.expanduser(args.proof_dir))
    args.scenario_path = os.path.abspath(os.path.expanduser(args.scenario_path))

    driver = Driver(args)
    verdict = "FAIL"
    failure = None
    exit_status = 1
    try:
        driver.load_scenario(args.scenario_path)
        driver.launch()
        driver.run_steps()
        verdict = "PASS"
        exit_status = 0
    except Failure as problem:
        failure = str(problem)
    except Exception as problem:  # noqa: BLE001 - reported, not swallowed
        failure = "{}: {}".format(type(problem).__name__, problem)
    finally:
        driver.teardown()

    if verdict == "PASS" and driver.crashes:
        verdict = "FAIL"
        failure = "engine crashed: " + driver.crashes[0]
        exit_status = 1
    if verdict == "PASS" and driver.args.platform != "simulator":
        status = driver.proc.returncode
        if status != 0:
            verdict = "FAIL"
            failure = "engine exited with status {}".format(status)
            exit_status = 1

    result = driver.result(verdict, failure)
    result_path = os.path.join(args.proof_dir, "result.json")
    with open(result_path, "w") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")

    metadata_path = os.path.join(args.proof_dir, "metadata.json")
    with open(metadata_path, "w") as handle:
        json.dump(driver.metadata(result), handle, indent=2, sort_keys=True)
        handle.write("\n")

    print("[driver] verdict {}  ({})".format(verdict, failure or "all requirements observed"))
    print("[driver] result {}".format(result_path))
    print("[driver] metadata {}".format(metadata_path))
    print("[driver] log    {}".format(driver.log_path))
    return exit_status


if __name__ == "__main__":
    sys.exit(main())
