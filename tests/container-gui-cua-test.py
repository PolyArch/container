#!/usr/bin/env python3
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
HELPER_PATH = REPO_ROOT / "scripts" / "container-gui-cua.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("container_gui_cua", HELPER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeClient:
    def __init__(self):
        self.calls = []
        self.fail_on = None

    def __enter__(self):
        self.calls.append(("enter",))
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.calls.append(("exit", exc_type is None))

    def mouseMove(self, x, y):
        self.calls.append(("mouseMove", x, y))

    def mousePress(self, button):
        if self.fail_on == "mousePress":
            raise RuntimeError("boom")
        self.calls.append(("mousePress", button))

    def mouseDown(self, button):
        self.calls.append(("mouseDown", button))

    def mouseUp(self, button):
        self.calls.append(("mouseUp", button))

    def keyPress(self, key):
        self.calls.append(("keyPress", key))

    def captureScreen(self, output):
        self.calls.append(("captureScreen", output))

    def captureRegion(self, output, x, y, width, height):
        self.calls.append(("captureRegion", output, x, y, width, height))


class FakeProxy:
    def __init__(self):
        self.calls = []

    def __enter__(self):
        self.calls.append(("enter",))
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.calls.append(("exit", exc_type is None))

    def keyPress(self, key):
        self.calls.append(("keyPress", key))


class CuaHelperTest(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()
        self.client = FakeClient()
        self.connected = []
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()

    def run_helper(self, args):
        return self.run_helper_with_stdin(args, None)

    def run_helper_with_stdin(self, args, stdin):
        def client_factory(vnc):
            self.connected.append(vnc)
            return self.client

        return self.helper.run(
            args,
            client_factory=client_factory,
            stdout=self.stdout,
            stderr=self.stderr,
            stdin=stdin,
        )

    def run_helper_with_dependency_checker(self, args, dependency_checker):
        return self.helper.run(
            args,
            client_factory=lambda vnc: self.client,
            stdout=self.stdout,
            stderr=self.stderr,
            dependency_checker=dependency_checker,
        )

    def test_click_moves_then_presses_left_button(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "click", "--x", "10", "--y", "20"])

        self.assertEqual(status, 0)
        self.assertEqual(self.connected, ["127.0.0.1:5907"])
        self.assertIn(("mouseMove", 10, 20), self.client.calls)
        self.assertIn(("mousePress", 1), self.client.calls)
        self.assertEqual(self.stdout.getvalue(), "click ok\n")

    def test_screenshot_region_uses_capture_region(self):
        status = self.run_helper(
            [
                "--vnc",
                "127.0.0.1:5907",
                "screenshot",
                "--output",
                "/tmp/region.png",
                "--region",
                "1,2,300,400",
            ]
        )

        self.assertEqual(status, 0)
        self.assertIn(("captureRegion", "/tmp/region.png", 1, 2, 300, 400), self.client.calls)
        self.assertEqual(self.stdout.getvalue(), "screenshot saved: /tmp/region.png\n")

    def test_double_click_moves_then_presses_twice(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "double_click", "--x", "10", "--y", "20"])

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 10, 20), self.client.calls)
        self.assertEqual(self.client.calls.count(("mousePress", 1)), 2)
        self.assertEqual(self.stdout.getvalue(), "double_click ok\n")

    def test_move_sends_pointer_move(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "move", "--x", "30", "--y", "40"])

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 30, 40), self.client.calls)
        self.assertEqual(self.stdout.getvalue(), "move ok\n")

    def test_drag_uses_button_down_move_and_button_up(self):
        status = self.run_helper(
            [
                "--vnc",
                "127.0.0.1:5907",
                "drag",
                "--from-x",
                "1",
                "--from-y",
                "2",
                "--to-x",
                "10",
                "--to-y",
                "20",
            ]
        )

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 1, 2), self.client.calls)
        self.assertIn(("mouseDown", 1), self.client.calls)
        self.assertIn(("mouseMove", 10, 20), self.client.calls)
        self.assertIn(("mouseUp", 1), self.client.calls)
        self.assertEqual(self.stdout.getvalue(), "drag ok\n")

    def test_scroll_moves_then_sends_wheel_events(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "scroll", "--x", "5", "--y", "6", "--dy", "-2"])

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 5, 6), self.client.calls)
        self.assertEqual(self.client.calls.count(("mousePress", 5)), 2)
        self.assertEqual(self.stdout.getvalue(), "scroll ok\n")

    def test_type_maps_newline_to_vnc_key_name(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "type", "--text", "a\n"])

        self.assertEqual(status, 0)
        self.assertEqual(
            [call for call in self.client.calls if call[0] == "keyPress"],
            [("keyPress", "a"), ("keyPress", "enter")],
        )
        self.assertEqual(self.stdout.getvalue(), "type ok\n")

    def test_sequence_array_runs_actions_in_order(self):
        actions = [
            {"action": "click", "x": 10, "y": 20},
            {"action": "wait", "seconds": 0.01},
            {"action": "type", "text": "a\n"},
            {"action": "keypress", "key": "Enter"},
            {"action": "screenshot", "output": "/tmp/screen.png"},
        ]
        with tempfile.NamedTemporaryFile("w", delete=False) as sequence_file:
            json.dump(actions, sequence_file)
            sequence_path = sequence_file.name

        status = self.run_helper(["--vnc", "127.0.0.1:5907", "sequence", "--input", sequence_path])

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 10, 20), self.client.calls)
        self.assertIn(("mousePress", 1), self.client.calls)
        self.assertIn(("keyPress", "a"), self.client.calls)
        self.assertIn(("keyPress", "enter"), self.client.calls)
        self.assertIn(("captureScreen", "/tmp/screen.png"), self.client.calls)
        self.assertIn("1 click ok", self.stdout.getvalue())
        self.assertIn("5 screenshot ok /tmp/screen.png", self.stdout.getvalue())

    def test_sequence_input_dash_reads_json_from_stdin(self):
        stdin = io.StringIO(json.dumps([{"action": "click", "x": 7, "y": 8}]))

        status = self.run_helper_with_stdin(["--vnc", "127.0.0.1:5907", "sequence", "--input", "-"], stdin)

        self.assertEqual(status, 0)
        self.assertIn(("mouseMove", 7, 8), self.client.calls)
        self.assertIn("1 click ok", self.stdout.getvalue())

    def test_sequence_object_rejects_stop_on_error_false(self):
        payload = {"actions": [{"action": "click", "x": 1, "y": 2}], "stop_on_error": False}
        with tempfile.NamedTemporaryFile("w", delete=False) as sequence_file:
            json.dump(payload, sequence_file)
            sequence_path = sequence_file.name

        status = self.run_helper(["--vnc", "127.0.0.1:5907", "sequence", "--input", sequence_path])

        self.assertNotEqual(status, 0)
        self.assertIn("stop_on_error=false is not supported", self.stderr.getvalue())

    def test_sequence_validation_error_reports_action_index(self):
        actions = [
            {"action": "wait", "seconds": 0.01},
            {"action": "click", "x": 1},
        ]
        with tempfile.NamedTemporaryFile("w", delete=False) as sequence_file:
            json.dump(actions, sequence_file)
            sequence_path = sequence_file.name

        status = self.run_helper(["--vnc", "127.0.0.1:5907", "sequence", "--input", sequence_path])

        self.assertNotEqual(status, 0)
        self.assertEqual(self.connected, [])
        self.assertIn("sequence action 2 click failed", self.stderr.getvalue())

    def test_sequence_runtime_error_reports_action_index(self):
        self.client.fail_on = "mousePress"
        actions = [
            {"action": "wait", "seconds": 0.01},
            {"action": "click", "x": 1, "y": 2},
        ]
        with tempfile.NamedTemporaryFile("w", delete=False) as sequence_file:
            json.dump(actions, sequence_file)
            sequence_path = sequence_file.name

        status = self.run_helper(["--vnc", "127.0.0.1:5907", "sequence", "--input", sequence_path])

        self.assertNotEqual(status, 0)
        self.assertIn("sequence action 2 click failed: boom", self.stderr.getvalue())

    def test_screenshot_rejects_stdout_output(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "screenshot", "--output", "-"])

        self.assertNotEqual(status, 0)
        self.assertEqual(self.connected, [])
        self.assertIn("screenshot: --output - is not supported", self.stderr.getvalue())

    def test_keypress_normalizes_common_key_names(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "keypress", "--key", "Ctrl-L"])

        self.assertEqual(status, 0)
        self.assertIn(("keyPress", "ctrl-l"), self.client.calls)
        self.assertEqual(self.stdout.getvalue(), "keypress ok\n")

    def test_keypress_rejects_invalid_key_name(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "keypress", "--key", "Ctrl-"])

        self.assertNotEqual(status, 0)
        self.assertEqual(self.connected, [])
        self.assertIn("keypress: unsupported key: Ctrl-", self.stderr.getvalue())

    def test_missing_required_coordinates_fail_before_connecting(self):
        status = self.run_helper(["--vnc", "127.0.0.1:5907", "click", "--x", "10"])

        self.assertNotEqual(status, 0)
        self.assertEqual(self.connected, [])
        self.assertIn("click: y is required", self.stderr.getvalue())

    def test_invalid_region_fails_before_connecting(self):
        status = self.run_helper(
            ["--vnc", "127.0.0.1:5907", "screenshot", "--output", "/tmp/a.png", "--region", "1,2,3"]
        )

        self.assertNotEqual(status, 0)
        self.assertEqual(self.connected, [])
        self.assertIn("region must be X,Y,W,H", self.stderr.getvalue())

    def test_vncdotool_server_uses_explicit_tcp_port(self):
        self.assertEqual(
            self.helper.vncdotool_server("127.0.0.1:5907"),
            "127.0.0.1::5907",
        )

    def test_check_dependency_reports_missing_vncdotool(self):
        status = self.run_helper_with_dependency_checker(
            ["--check-dependency"],
            lambda: "missing Python dependency: vncdotool\ninstall it with: python3 -m pip install --user vncdotool",
        )

        self.assertNotEqual(status, 0)
        self.assertIn("missing Python dependency: vncdotool", self.stderr.getvalue())
        self.assertIn("python3 -m pip install --user vncdotool", self.stderr.getvalue())

    def test_check_dependency_succeeds_without_vnc(self):
        status = self.run_helper_with_dependency_checker(["--check-dependency"], lambda: None)

        self.assertEqual(status, 0)
        self.assertEqual(self.stdout.getvalue(), "")

    def test_managed_vnc_client_shuts_down_after_context_exit(self):
        proxy = FakeProxy()
        calls = []

        with self.helper.ManagedVncClient(proxy, lambda: calls.append(("shutdown",))) as client:
            client.keyPress("enter")

        self.assertEqual(
            proxy.calls,
            [("enter",), ("keyPress", "enter"), ("exit", True)],
        )
        self.assertEqual(calls, [("shutdown",)])


if __name__ == "__main__":
    unittest.main()
