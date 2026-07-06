#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path


class CuaError(Exception):
    pass


MISSING_VNCDOTOOL_MESSAGE = (
    "missing Python dependency: vncdotool\n"
    "install it with: python3 -m pip install --user vncdotool"
)

BUTTONS = {
    "left": 1,
    "middle": 2,
    "right": 3,
}

KEY_ALIASES = {
    "enter": "enter",
    "return": "enter",
    "escape": "escape",
    "esc": "escape",
    "tab": "tab",
    "backspace": "backspace",
    "delete": "delete",
    "del": "delete",
    "up": "up",
    "down": "down",
    "left": "left",
    "right": "right",
    "home": "home",
    "end": "end",
    "pageup": "pageup",
    "pagedown": "pagedown",
    "insert": "insert",
    "space": "space",
}

KEY_MODIFIERS = {"ctrl", "alt", "shift"}


class ManagedVncClient:
    def __init__(self, proxy, shutdown_func):
        self.proxy = proxy
        self.shutdown_func = shutdown_func

    def __enter__(self):
        self.proxy.__enter__()
        return self

    def __exit__(self, exc_type, exc, traceback):
        try:
            return self.proxy.__exit__(exc_type, exc, traceback)
        finally:
            self.shutdown_func()

    def __getattr__(self, name):
        return getattr(self.proxy, name)


def die(message, stderr):
    print(f"container gui: {message}", file=stderr)
    return 1


def parse_global_args(argv):
    vnc = None
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--vnc":
            if index + 1 >= len(argv):
                raise CuaError("--vnc needs HOST:PORT")
            vnc = argv[index + 1]
            index += 2
            continue
        if arg in ("-h", "--help", "help"):
            return vnc, ["help"]
        break

    if vnc is None:
        raise CuaError("--vnc is required")
    if index >= len(argv):
        raise CuaError("CUA action is required")
    return vnc, argv[index:]


def parse_option_pairs(action, args):
    options = {}
    index = 0
    while index < len(args):
        arg = args[index]
        if not arg.startswith("--"):
            raise CuaError(f"{action}: unexpected argument: {arg}")
        if index + 1 >= len(args):
            raise CuaError(f"{action}: {arg} needs a value")
        key = arg[2:].replace("-", "_")
        if key in options:
            raise CuaError(f"{action}: duplicate option: {arg}")
        options[key] = args[index + 1]
        index += 2
    return options


def require_option(action, options, key):
    value = options.get(key)
    if value is None or value == "":
        raise CuaError(f"{action}: {key} is required")
    return value


def reject_unknown_options(action, options, allowed):
    for key in options:
        if key not in allowed:
            raise CuaError(f"{action}: unknown option: --{key.replace('_', '-')}")


def parse_int(action, value, key, *, minimum=0):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise CuaError(f"{action}: {key} must be an integer")
    if parsed < minimum:
        raise CuaError(f"{action}: {key} must be at least {minimum}")
    return parsed


def parse_float(action, value, key, *, minimum=0.0):
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        raise CuaError(f"{action}: {key} must be a number")
    if parsed < minimum:
        raise CuaError(f"{action}: {key} must be at least {minimum}")
    return parsed


def parse_button(action, value):
    if value not in BUTTONS:
        raise CuaError(f"{action}: button must be one of left, middle, right")
    return value


def normalize_key_name(action, value):
    if not isinstance(value, str) or value == "":
        raise CuaError(f"{action}: key is required")
    parts = value.split("-")
    if any(part == "" for part in parts):
        raise CuaError(f"{action}: unsupported key: {value}")
    normalized_parts = []
    for part in parts[:-1]:
        modifier = part.lower()
        if modifier not in KEY_MODIFIERS:
            raise CuaError(f"{action}: unsupported key: {value}")
        normalized_parts.append(modifier)

    key = parts[-1]
    key_lower = key.lower()
    if len(key) == 1 and key.isprintable() and not key.isspace():
        normalized_parts.append(key_lower)
    elif key_lower in KEY_ALIASES:
        normalized_parts.append(KEY_ALIASES[key_lower])
    elif key_lower.startswith("f") and key_lower[1:].isdigit() and 1 <= int(key_lower[1:]) <= 24:
        normalized_parts.append(key_lower)
    else:
        raise CuaError(f"{action}: unsupported key: {value}")

    return "-".join(normalized_parts)


def parse_region_value(value):
    parts = str(value).split(",")
    if len(parts) != 4:
        raise CuaError("screenshot: region must be X,Y,W,H")
    try:
        x, y, width, height = [int(part) for part in parts]
    except ValueError:
        raise CuaError("screenshot: region must be X,Y,W,H")
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        raise CuaError("screenshot: region must be X,Y,W,H with positive width and height")
    return [x, y, width, height]


def parse_region_list(value):
    if not isinstance(value, list) or len(value) != 4:
        raise CuaError("screenshot: region must be [x, y, width, height]")
    try:
        x, y, width, height = [int(part) for part in value]
    except (TypeError, ValueError):
        raise CuaError("screenshot: region must be [x, y, width, height]")
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        raise CuaError("screenshot: region must have positive width and height")
    return [x, y, width, height]


def normalize_cli_action(action, args):
    if action == "help":
        return {"action": "help"}
    if action == "screenshot":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"output", "region"})
        output = require_option(action, options, "output")
        if output == "-":
            raise CuaError("screenshot: --output - is not supported")
        result = {"action": action, "output": output}
        if "region" in options:
            result["region"] = parse_region_value(options["region"])
        return result
    if action in ("click", "double_click"):
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"x", "y", "button", "interval"})
        result = {
            "action": action,
            "x": parse_int(action, require_option(action, options, "x"), "x"),
            "y": parse_int(action, require_option(action, options, "y"), "y"),
            "button": parse_button(action, options.get("button", "left")),
        }
        if action == "double_click":
            result["interval"] = parse_float(action, options.get("interval", "100"), "interval")
        elif "interval" in options:
            raise CuaError("click: unknown option: --interval")
        return result
    if action == "move":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"x", "y"})
        return {
            "action": action,
            "x": parse_int(action, require_option(action, options, "x"), "x"),
            "y": parse_int(action, require_option(action, options, "y"), "y"),
        }
    if action == "drag":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"from_x", "from_y", "to_x", "to_y", "button", "duration"})
        return {
            "action": action,
            "from_x": parse_int(action, require_option(action, options, "from_x"), "from_x"),
            "from_y": parse_int(action, require_option(action, options, "from_y"), "from_y"),
            "to_x": parse_int(action, require_option(action, options, "to_x"), "to_x"),
            "to_y": parse_int(action, require_option(action, options, "to_y"), "to_y"),
            "button": parse_button(action, options.get("button", "left")),
            "duration": parse_float(action, options.get("duration", "250"), "duration"),
        }
    if action == "scroll":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"x", "y", "dy"})
        return {
            "action": action,
            "x": parse_int(action, require_option(action, options, "x"), "x"),
            "y": parse_int(action, require_option(action, options, "y"), "y"),
            "dy": parse_int(action, require_option(action, options, "dy"), "dy", minimum=-1000000),
        }
    if action == "type":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"text"})
        return {"action": action, "text": require_option(action, options, "text")}
    if action == "keypress":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"key"})
        return {"action": action, "key": normalize_key_name(action, require_option(action, options, "key"))}
    if action == "wait":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"seconds"})
        return {
            "action": action,
            "seconds": parse_float(action, require_option(action, options, "seconds"), "seconds"),
        }
    if action == "sequence":
        options = parse_option_pairs(action, args)
        reject_unknown_options(action, options, {"input"})
        return {"action": action, "input": require_option(action, options, "input")}
    raise CuaError(f"unknown CUA action: {action}")


def normalize_json_action(raw):
    if not isinstance(raw, dict):
        raise CuaError("sequence action must be an object")
    action = raw.get("action")
    if not isinstance(action, str) or not action:
        raise CuaError("sequence action is missing action")
    allowed = {
        "screenshot": {"action", "output", "region"},
        "click": {"action", "x", "y", "button"},
        "double_click": {"action", "x", "y", "button", "interval"},
        "move": {"action", "x", "y"},
        "drag": {"action", "from_x", "from_y", "to_x", "to_y", "button", "duration"},
        "scroll": {"action", "x", "y", "dy"},
        "type": {"action", "text"},
        "keypress": {"action", "key"},
        "wait": {"action", "seconds"},
    }
    if action not in allowed:
        raise CuaError(f"unknown CUA action: {action}")
    extra = sorted(set(raw) - allowed[action])
    if extra:
        raise CuaError(f"{action}: unknown JSON field: {extra[0]}")

    if action == "screenshot":
        output = raw.get("output")
        if not isinstance(output, str) or not output:
            raise CuaError("screenshot: output is required")
        if output == "-":
            raise CuaError("screenshot: output - is not supported")
        result = {"action": action, "output": output}
        if "region" in raw:
            result["region"] = parse_region_list(raw["region"])
        return result
    if action in ("click", "double_click"):
        result = {
            "action": action,
            "x": parse_int(action, raw.get("x"), "x"),
            "y": parse_int(action, raw.get("y"), "y"),
            "button": parse_button(action, raw.get("button", "left")),
        }
        if action == "double_click":
            result["interval"] = parse_float(action, raw.get("interval", 100), "interval")
        return result
    if action == "move":
        return {
            "action": action,
            "x": parse_int(action, raw.get("x"), "x"),
            "y": parse_int(action, raw.get("y"), "y"),
        }
    if action == "drag":
        return {
            "action": action,
            "from_x": parse_int(action, raw.get("from_x"), "from_x"),
            "from_y": parse_int(action, raw.get("from_y"), "from_y"),
            "to_x": parse_int(action, raw.get("to_x"), "to_x"),
            "to_y": parse_int(action, raw.get("to_y"), "to_y"),
            "button": parse_button(action, raw.get("button", "left")),
            "duration": parse_float(action, raw.get("duration", 250), "duration"),
        }
    if action == "scroll":
        return {
            "action": action,
            "x": parse_int(action, raw.get("x"), "x"),
            "y": parse_int(action, raw.get("y"), "y"),
            "dy": parse_int(action, raw.get("dy"), "dy", minimum=-1000000),
        }
    if action == "type":
        text = raw.get("text")
        if not isinstance(text, str) or text == "":
            raise CuaError("type: text is required")
        return {"action": action, "text": text}
    if action == "keypress":
        return {"action": action, "key": normalize_key_name(action, raw.get("key"))}
    if action == "wait":
        return {"action": action, "seconds": parse_float(action, raw.get("seconds"), "seconds")}
    raise CuaError(f"unknown CUA action: {action}")


def read_sequence(path, stdin):
    try:
        if path == "-":
            text = stdin.read()
        else:
            text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise CuaError(f"failed to read sequence JSON: {exc}")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise CuaError(f"failed to read sequence JSON: {exc}")

    if isinstance(payload, list):
        raw_actions = payload
    elif isinstance(payload, dict):
        unknown = sorted(set(payload) - {"actions", "stop_on_error"})
        if unknown:
            raise CuaError(f"sequence: unknown top-level field: {unknown[0]}")
        if payload.get("stop_on_error", True) is not True:
            raise CuaError("stop_on_error=false is not supported")
        raw_actions = payload.get("actions")
        if not isinstance(raw_actions, list):
            raise CuaError("sequence: actions must be an array")
    else:
        raise CuaError("sequence JSON must be an array or object")

    actions = []
    for index, raw in enumerate(raw_actions, start=1):
        try:
            actions.append(normalize_json_action(raw))
        except CuaError as exc:
            action_name = raw.get("action", "unknown") if isinstance(raw, dict) else "unknown"
            raise CuaError(f"sequence action {index} {action_name} failed: {exc}")
    return actions


def key_for_character(character):
    if character == "\n":
        return "enter"
    if character == "\t":
        return "tab"
    if character == "-":
        return "minus"
    return character


def perform_action(client, action, sleep_func):
    name = action["action"]
    if name == "screenshot":
        if "region" in action:
            x, y, width, height = action["region"]
            client.captureRegion(action["output"], x, y, width, height)
        else:
            client.captureScreen(action["output"])
        return f"screenshot ok {action['output']}"
    if name == "click":
        client.mouseMove(action["x"], action["y"])
        client.mousePress(BUTTONS[action["button"]])
        return "click ok"
    if name == "double_click":
        client.mouseMove(action["x"], action["y"])
        button = BUTTONS[action["button"]]
        client.mousePress(button)
        sleep_func(action["interval"] / 1000.0)
        client.mousePress(button)
        return "double_click ok"
    if name == "move":
        client.mouseMove(action["x"], action["y"])
        return "move ok"
    if name == "drag":
        button = BUTTONS[action["button"]]
        client.mouseMove(action["from_x"], action["from_y"])
        client.mouseDown(button)
        sleep_func(action["duration"] / 1000.0)
        client.mouseMove(action["to_x"], action["to_y"])
        client.mouseUp(button)
        return "drag ok"
    if name == "scroll":
        client.mouseMove(action["x"], action["y"])
        wheel_button = 4 if action["dy"] > 0 else 5
        for _ in range(abs(action["dy"])):
            client.mousePress(wheel_button)
        return "scroll ok"
    if name == "type":
        for character in action["text"]:
            client.keyPress(key_for_character(character))
        return "type ok"
    if name == "keypress":
        client.keyPress(action["key"])
        return "keypress ok"
    if name == "wait":
        sleep_func(action["seconds"])
        return "wait ok"
    raise CuaError(f"unknown CUA action: {name}")


def default_client_factory(vnc):
    error = dependency_error()
    if error is not None:
        raise CuaError(error)
    from vncdotool import api

    return ManagedVncClient(api.connect(vncdotool_server(vnc)), api.shutdown)


def dependency_error(importer=None):
    importer = importer or __import__
    try:
        importer("vncdotool", fromlist=["api"])
    except ImportError:
        return MISSING_VNCDOTOOL_MESSAGE
    return None


def vncdotool_server(vnc):
    if vnc.count(":") == 1:
        host, port = vnc.rsplit(":", 1)
        if port.isdigit():
            return f"{host}::{port}"
    return vnc


def print_usage(stdout):
    stdout.write(
        "Usage:\n"
        "  container gui use CONTAINER_NAME screenshot --output PATH [--region X,Y,W,H]\n"
        "  container gui use CONTAINER_NAME click --x N --y N [--button left|middle|right]\n"
        "  container gui use CONTAINER_NAME double_click --x N --y N [--button left|middle|right] [--interval MS]\n"
        "  container gui use CONTAINER_NAME move --x N --y N\n"
        "  container gui use CONTAINER_NAME drag --from-x N --from-y N --to-x N --to-y N [--duration MS]\n"
        "  container gui use CONTAINER_NAME scroll --x N --y N --dy N\n"
        "  container gui use CONTAINER_NAME type --text TEXT\n"
        "  container gui use CONTAINER_NAME keypress --key KEY\n"
        "  container gui use CONTAINER_NAME wait --seconds N\n"
        "  container gui use CONTAINER_NAME sequence --input PATH|-\n"
    )


def run(
    argv,
    *,
    client_factory=None,
    stdout=None,
    stderr=None,
    stdin=None,
    sleep_func=None,
    dependency_checker=None,
):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    stdin = stdin or sys.stdin
    sleep_func = sleep_func or time.sleep
    client_factory = client_factory or default_client_factory
    dependency_checker = dependency_checker or dependency_error

    try:
        if argv and argv[0] == "--check-dependency":
            if len(argv) != 1:
                raise CuaError("--check-dependency does not accept arguments")
            error = dependency_checker()
            if error is not None:
                raise CuaError(error)
            return 0

        vnc, action_args = parse_global_args(argv)
        action = normalize_cli_action(action_args[0], action_args[1:])
        if action["action"] == "help":
            print_usage(stdout)
            return 0
        if action["action"] == "sequence":
            actions = read_sequence(action["input"], stdin)
            with client_factory(vnc) as client:
                for index, sequence_action in enumerate(actions, start=1):
                    try:
                        result = perform_action(client, sequence_action, sleep_func)
                    except Exception as exc:
                        raise CuaError(
                            f"sequence action {index} {sequence_action['action']} failed: {exc}"
                        )
                    stdout.write(f"{index} {result}\n")
            return 0

        with client_factory(vnc) as client:
            result = perform_action(client, action, sleep_func)
        if action["action"] == "screenshot":
            stdout.write(f"screenshot saved: {action['output']}\n")
        else:
            stdout.write(f"{result}\n")
        return 0
    except CuaError as exc:
        return die(str(exc), stderr)
    except Exception as exc:
        return die(f"VNC action failed: {exc}", stderr)


def main():
    raise SystemExit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
