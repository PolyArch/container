#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/container.sh"
SETUP="$REPO_ROOT/setup.sh"

FAILURES=0

fail() {
  printf 'not ok - %s\n' "$*" >&2
  return 1
}

containerfile_hash() {
  sha256sum "$REPO_ROOT/images/$1.containerfile" | awk '{print substr($1, 1, 12)}'
}

gui_image_name() {
  printf 'ucla.edu/polyarch/container-gui-%s:latest' "$(containerfile_hash gui)"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "missing expected text: $needle"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "unexpected text present: $needle"
}

with_fake_path() {
  local docker_mode="${1:-present}"
  local podman_mode="${2:-present}"
  local tmp bin_dir
  tmp="$(mktemp -d)"
  bin_dir="$tmp/bin"
  mkdir -p "$bin_dir"
  : >"$tmp/commands"

  cat >"$bin_dir/date" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  +%Y%m%d-%H%M%S)
    printf '20260701-123456\n'
    ;;
  *)
    command date "$@"
    ;;
esac
EOF
  chmod +x "$bin_dir/date"

  cat >"$bin_dir/xrandr" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Screen 0: minimum 16 x 16, current 3840 x 2160, maximum 32767 x 32767
DP-1 connected primary 3840x2160+0+0
   3840x2160     60.00*+
OUT
EOF
  chmod +x "$bin_dir/xrandr"

  cat >"$bin_dir/xdpyinfo" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
screen #0:
  dimensions:    3840x2160 pixels
OUT
EOF
  chmod +x "$bin_dir/xdpyinfo"

  cat >"$bin_dir/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$bin_dir/ss"

  make_fake_runtime "$bin_dir" docker "$docker_mode"
  make_fake_runtime "$bin_dir" podman "$podman_mode"

  cat >"$tmp/cua-helper" <<'EOF'
#!/usr/bin/env bash
printf 'cua-helper' >>"$CONTAINER_GUI_TEST_STATE/commands"
for arg in "$@"; do
  printf ' %s' "$arg" >>"$CONTAINER_GUI_TEST_STATE/commands"
done
printf '\n' >>"$CONTAINER_GUI_TEST_STATE/commands"
if [[ "${1:-}" == --check-dependency ]]; then
  if [[ "${CONTAINER_GUI_TEST_CUA_DEPENDENCY:-present}" == missing ]]; then
    printf 'container gui: missing Python dependency: vncdotool\n' >&2
    printf 'install it with: python3 -m pip install --user vncdotool\n' >&2
    exit 1
  fi
  exit 0
fi
printf 'helper ok\n'
EOF
  chmod +x "$tmp/cua-helper"

  CONTAINER_GUI_TEST_TMP="$tmp"
  CONTAINER_GUI_TEST_BIN="$bin_dir"
}

make_fake_runtime() {
  local bin_dir="$1" runtime="$2" mode="$3"
  if [[ "$mode" != present ]]; then
    cat >"$bin_dir/$runtime" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$bin_dir/$runtime"
    return 0
  fi

  cat >"$bin_dir/$runtime" <<'EOF'
#!/usr/bin/env bash
runtime="$(basename "$0")"
cmd="${1:-}"
printf '%s %s' "$runtime" "$1" >>"$CONTAINER_GUI_TEST_STATE/commands"
shift || true
for arg in "$@"; do
  printf ' %s' "$arg" >>"$CONTAINER_GUI_TEST_STATE/commands"
done
printf '\n' >>"$CONTAINER_GUI_TEST_STATE/commands"

case "$cmd" in
  version)
    exit 0
    ;;
  image)
    if [[ "${1:-}" == inspect ]]; then
      exit "${CONTAINER_GUI_TEST_IMAGE_EXISTS:-1}"
    fi
    ;;
  build)
    containerfile=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f)
          containerfile="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -n "$containerfile" && -f "$containerfile" ]]; then
      cp "$containerfile" "$CONTAINER_GUI_TEST_STATE/${runtime}-Containerfile"
    fi
    exit 0
    ;;
  run)
    printf 'fake-container-id\n'
    exit 0
    ;;
  ps)
    printf 'container-gui-demo running 127.0.0.1:5902->5902/tcp\n'
    exit 0
    ;;
  inspect)
    format=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --format)
          format="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    case "$format" in
      *State.Status*)
        printf 'running\n'
        ;;
      *HostConfig.RestartPolicy.Name*)
        printf 'unless-stopped\n'
        ;;
      *Config.Image*)
        printf '%s\n' "$CONTAINER_GUI_TEST_IMAGE"
        ;;
      *ucla.polyarch.container.gui.display*)
        printf '%s\n' "${CONTAINER_GUI_TEST_DISPLAY-7}"
        ;;
      *ucla.polyarch.container.gui.resolution*)
        printf '1600x900\n'
        ;;
      *ucla.polyarch.container.gui.desktop*)
        printf 'xfce\n'
        ;;
      *ucla.polyarch.container.gui*)
        printf '%s\n' "${CONTAINER_GUI_TEST_MANAGED:-true}"
        ;;
    esac
    exit 0
    ;;
  stop|rm|restart|update)
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "$bin_dir/$runtime"
}

cleanup_fake_path() {
  rm -rf "${CONTAINER_GUI_TEST_TMP:-}"
  unset CONTAINER_GUI_TEST_TMP CONTAINER_GUI_TEST_BIN
}

run_script() {
  PATH="$CONTAINER_GUI_TEST_BIN:$PATH" \
    CONTAINER_GUI_TEST_STATE="$CONTAINER_GUI_TEST_TMP" \
    CONTAINER_GUI_TEST_IMAGE="$(gui_image_name)" \
    CONTAINER_GUI_CUA_HELPER="$CONTAINER_GUI_TEST_TMP/cua-helper" \
    bash "$SCRIPT" gui "$@"
}

commands_log() {
  cat "$CONTAINER_GUI_TEST_TMP/commands" 2>/dev/null || true
}

test_start_prefers_podman_and_prints_connection_details() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start demo --resolution 1600x900 --port 7)"
  commands="$(commands_log)"

  assert_contains "$output" 'Container: container-gui-demo' || return 1
  assert_contains "$output" 'Desktop: xfce' || return 1
  assert_contains "$output" 'DISPLAY=127.0.0.1:7' || return 1
  assert_contains "$output" 'VNC: vnc://127.0.0.1:5907' || return 1
  assert_contains "$output" 'Runtime: podman' || return 1
  assert_contains "$commands" "podman image inspect $(gui_image_name)" || return 1
  assert_contains "$commands" 'podman build' || return 1
  assert_contains "$commands" "podman build -t $(gui_image_name) -f" || return 1
  assert_contains "$commands" 'podman run' || return 1
  assert_contains "$commands" '--name container-gui-demo' || return 1
  assert_contains "$commands" '--label ucla.polyarch.container.gui.desktop=xfce' || return 1
  assert_contains "$commands" '-p 127.0.0.1:5907:5907' || return 1
  assert_contains "$commands" '-p 127.0.0.1:6007:6007' || return 1
  assert_contains "$commands" 'Xvnc :7' || return 1
  assert_contains "$commands" 'dbus-run-session startxfce4' || return 1
  assert_not_contains "$commands" 'xfce4-terminal --geometry' || return 1
  assert_not_contains "$commands" 'docker ' || return 1

  local containerfile
  containerfile="$(cat "$CONTAINER_GUI_TEST_TMP/podman-Containerfile")"
  assert_contains "$containerfile" 'xfce4-settings' || return 1
  assert_contains "$containerfile" 'xfdesktop' || return 1
  assert_contains "$containerfile" '/etc/xdg/autostart/xfce-polkit.desktop' || return 1
  assert_contains "$containerfile" '/etc/xdg/autostart/geoclue-demo-agent.desktop' || return 1
  assert_contains "$containerfile" 'useradd --create-home --shell /bin/bash x11user' || return 1
  assert_contains "$containerfile" 'USER x11user' || return 1
}

test_start_falls_back_to_docker() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start demo --resolution 1600x900 --port 8)"
  commands="$(commands_log)"

  assert_contains "$output" 'Runtime: docker' || return 1
  assert_contains "$commands" "docker image inspect $(gui_image_name)" || return 1
  assert_contains "$commands" 'docker run' || return 1
}

test_start_uses_requested_docker_engine() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start demo --engine docker --resolution 1600x900 --port 8)"
  commands="$(commands_log)"

  assert_contains "$output" 'Runtime: docker' || return 1
  assert_contains "$commands" "docker image inspect $(gui_image_name)" || return 1
  assert_contains "$commands" 'docker run' || return 1
  assert_not_contains "$commands" 'podman ' || return 1
}

test_start_uses_requested_podman_engine() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start demo --engine podman --resolution 1600x900 --port 8)"
  commands="$(commands_log)"

  assert_contains "$output" 'Runtime: podman' || return 1
  assert_contains "$commands" "podman image inspect $(gui_image_name)" || return 1
  assert_contains "$commands" 'podman run' || return 1
  assert_not_contains "$commands" 'docker ' || return 1
}

test_start_rejects_unavailable_requested_engine() {
  with_fake_path absent present
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script start demo --engine docker --resolution 1600x900 --port 8 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected unavailable engine to fail"; return 1; }
  assert_contains "$output" 'container engine is not available: docker' || return 1
}

test_start_rejects_unsupported_engine() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script start demo --engine nerdctl --resolution 1600x900 --port 8 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected unsupported engine to fail"; return 1; }
  assert_contains "$output" 'unsupported container engine: nerdctl' || return 1
}

test_start_errors_when_no_container_engine_is_available() {
  with_fake_path absent absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script start demo --resolution 1600x900 --port 8 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected missing engines to fail"; return 1; }
  assert_contains "$output" 'install docker or podman before running GUI containers' || return 1
}

test_start_defaults_name_resolution_display_number_and_xfce() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start)"
  commands="$(commands_log)"

  assert_contains "$output" 'Container: container-gui-20260701-123456' || return 1
  assert_contains "$output" 'Desktop: xfce' || return 1
  assert_contains "$output" 'Resolution: 3840x2160' || return 1
  assert_contains "$output" 'DISPLAY=127.0.0.1:2' || return 1
  assert_contains "$commands" '--name container-gui-20260701-123456' || return 1
  assert_contains "$commands" '-geometry 3840x2160' || return 1
}

test_create_is_start_alias() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script create demo --resolution 1600x900 --port 7)"
  commands="$(commands_log)"

  assert_contains "$output" 'Container: container-gui-demo' || return 1
  assert_contains "$commands" 'podman run' || return 1
  assert_contains "$commands" '--name container-gui-demo' || return 1
}

test_openbox_desktop_uses_openbox_image_and_start_command() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script start demo --desktop openbox --resolution 1600x900 --port 9)"
  commands="$(commands_log)"

  assert_contains "$output" 'Desktop: openbox' || return 1
  assert_contains "$commands" "docker image inspect $(gui_image_name)" || return 1
  assert_contains "$commands" '--label ucla.polyarch.container.gui.desktop=openbox' || return 1
  assert_contains "$commands" 'DISPLAY=:9 openbox' || return 1
  assert_not_contains "$commands" 'startxfce4' || return 1

  local containerfile
  containerfile="$(cat "$CONTAINER_GUI_TEST_TMP/docker-Containerfile")"
  assert_contains "$containerfile" 'useradd --create-home --shell /bin/bash x11user' || return 1
  assert_contains "$containerfile" 'USER x11user' || return 1
}

test_invalid_desktop_fails() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script start demo --desktop gnome 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected invalid desktop to fail"; return 1; }
  assert_contains "$output" '--desktop must be one of xfce, openbox' || return 1
}

test_resolution_larger_than_physical_fails() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script start demo --resolution 5000x1200 --port 9 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected oversized resolution to fail"; return 1; }
  assert_contains "$output" 'resolution exceeds detected physical display' || return 1
}

test_non_start_actions_require_container_name() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(run_script stop 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected missing name to fail"; return 1; }
  assert_contains "$output" 'container name is required for action stop' || return 1
}

test_lifecycle_actions_use_prefixed_container_name() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  run_script stop demo >/dev/null
  run_script remove demo >/dev/null
  run_script restart demo >/dev/null
  run_script enable demo >/dev/null

  local commands
  commands="$(commands_log)"
  assert_contains "$commands" 'docker stop container-gui-demo' || return 1
  assert_contains "$commands" 'docker rm -f container-gui-demo' || return 1
  assert_contains "$commands" 'docker restart container-gui-demo' || return 1
  assert_contains "$commands" 'docker update --restart=unless-stopped container-gui-demo' || return 1
}

test_delete_is_remove_alias() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script delete demo)"
  commands="$(commands_log)"

  assert_contains "$output" 'Removed: container-gui-demo' || return 1
  assert_contains "$commands" 'docker rm -f container-gui-demo' || return 1
}

test_prefixed_name_is_not_prefixed_twice() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  run_script stop container-gui-demo >/dev/null

  local commands
  commands="$(commands_log)"
  assert_contains "$commands" 'docker stop container-gui-demo' || return 1
  assert_not_contains "$commands" 'container-gui-container-gui-demo' || return 1
}

test_status_reports_state_and_connection_details() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script status demo)"
  commands="$(commands_log)"

  assert_contains "$output" 'Container: container-gui-demo' || return 1
  assert_contains "$output" 'Runtime: docker' || return 1
  assert_contains "$output" 'State: running' || return 1
  assert_contains "$output" 'Runtime status: container-gui-demo running 127.0.0.1:5902->5902/tcp' || return 1
  assert_contains "$output" "Image: $(gui_image_name)" || return 1
  assert_contains "$output" 'Restart policy: unless-stopped' || return 1
  assert_contains "$output" 'Desktop: xfce' || return 1
  assert_contains "$output" 'Resolution: 1600x900' || return 1
  assert_contains "$output" 'DISPLAY=127.0.0.1:7' || return 1
  assert_contains "$output" 'VNC: vnc://127.0.0.1:5907' || return 1
  assert_contains "$output" 'DISPLAY=127.0.0.1:7 <tool-command>' || return 1
  assert_contains "$commands" 'docker inspect container-gui-demo' || return 1
}

test_check_is_status_alias() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output
  output="$(run_script check demo)"

  assert_contains "$output" 'Container: container-gui-demo' || return 1
  assert_contains "$output" 'DISPLAY=127.0.0.1:7' || return 1
}

test_list_uses_managed_container_label() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script list)"
  commands="$(commands_log)"

  assert_contains "$output" 'container-gui-demo running' || return 1
  assert_contains "$commands" 'docker ps -a --filter label=ucla.polyarch.container.gui=true' || return 1
}

test_use_invokes_cua_helper_with_vnc_endpoint() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script use demo click --x 1 --y 2)"
  commands="$(commands_log)"

  assert_contains "$output" 'helper ok' || return 1
  assert_contains "$commands" 'cua-helper --check-dependency' || return 1
  assert_contains "$commands" 'docker inspect container-gui-demo' || return 1
  assert_contains "$commands" 'cua-helper --vnc 127.0.0.1:5907 click --x 1 --y 2' || return 1
}

test_use_missing_vncdotool_fails_before_container_inspect() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status commands
  set +e
  output="$(CONTAINER_GUI_TEST_CUA_DEPENDENCY=missing run_script use demo click --x 1 --y 2 2>&1)"
  status=$?
  set -e
  commands="$(commands_log)"

  [[ "$status" -ne 0 ]] || { fail "expected missing dependency to fail"; return 1; }
  assert_contains "$output" 'missing Python dependency: vncdotool' || return 1
  assert_contains "$output" 'python3 -m pip install --user vncdotool' || return 1
  assert_contains "$commands" 'cua-helper --check-dependency' || return 1
  assert_not_contains "$commands" 'docker inspect container-gui-demo' || return 1
}

test_use_respects_requested_engine() {
  with_fake_path present present
  trap cleanup_fake_path RETURN

  local output commands
  output="$(run_script use demo --engine docker screenshot --output /tmp/screen.png)"
  commands="$(commands_log)"

  assert_contains "$output" 'helper ok' || return 1
  assert_contains "$commands" 'docker inspect container-gui-demo' || return 1
  assert_not_contains "$commands" 'podman inspect container-gui-demo' || return 1
  assert_contains "$commands" 'cua-helper --vnc 127.0.0.1:5907 screenshot --output /tmp/screen.png' || return 1
}

test_use_rejects_unmanaged_container() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(CONTAINER_GUI_TEST_MANAGED=false run_script use demo click --x 1 --y 2 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected unmanaged container to fail"; return 1; }
  assert_contains "$output" 'container is not managed by container gui: container-gui-demo' || return 1
}

test_use_rejects_missing_display_label() {
  with_fake_path present absent
  trap cleanup_fake_path RETURN

  local output status
  set +e
  output="$(CONTAINER_GUI_TEST_DISPLAY='' run_script use demo click --x 1 --y 2 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || { fail "expected missing display label to fail"; return 1; }
  assert_contains "$output" 'managed display label is missing or invalid: container-gui-demo' || return 1
}

test_use_help_works_without_runtime() {
  with_fake_path absent absent
  trap cleanup_fake_path RETURN

  local output_help output_short output_long commands
  output_help="$(run_script use help)"
  output_short="$(run_script use -h)"
  output_long="$(run_script use --help)"
  commands="$(commands_log)"

  assert_contains "$output_help" 'Usage:' || return 1
  assert_contains "$output_help" 'container gui use CONTAINER_NAME' || return 1
  assert_contains "$output_short" 'Usage:' || return 1
  assert_contains "$output_long" 'Usage:' || return 1
  [[ -z "$commands" ]] || { fail "use help should not call runtime, got: $commands"; return 1; }
}

test_help_is_default_and_aliases_work_without_runtime() {
  with_fake_path absent absent
  trap cleanup_fake_path RETURN

  local output_no_args output_help output_long output_short commands
  output_no_args="$(run_script)"
  output_help="$(run_script help)"
  output_long="$(run_script --help)"
  output_short="$(run_script -h)"
  commands="$(commands_log)"

  assert_contains "$output_no_args" 'Usage:' || return 1
  assert_contains "$output_no_args" 'container gui start|create [CONTAINER_NAME]' || return 1
  assert_contains "$output_no_args" '--desktop xfce|openbox' || return 1
  assert_contains "$output_no_args" '--engine docker|podman' || return 1
  assert_contains "$output_no_args" 'keep stdin open' || return 1
  assert_contains "$output_no_args" 'tail -f /dev/null | DISPLAY=127.0.0.1:N <gui-command>' || return 1
  assert_not_contains "$output_no_args" '--container-name' || return 1
  assert_contains "$output_help" 'Usage:' || return 1
  assert_contains "$output_long" 'Usage:' || return 1
  assert_contains "$output_short" 'Usage:' || return 1
  [[ -z "$commands" ]] || { fail "help should not call container runtime, got: $commands"; return 1; }
}

test_setup_installs_container_cli() {
  grep -q 'container.sh' "$SETUP" || fail "setup.sh does not install container CLI" || return 1
  grep -q 'container.sh' "$SETUP" || fail "setup.sh should install container.sh" || return 1
}

test_installed_symlink_resolves_repo_scripts() {
  with_fake_path absent absent
  trap cleanup_fake_path RETURN

  local link output
  link="$CONTAINER_GUI_TEST_TMP/container"
  ln -s "$SCRIPT" "$link"
  output="$(PATH="$CONTAINER_GUI_TEST_BIN:$PATH" "$link" gui help)"

  assert_contains "$output" 'container gui - run an EL9 Xvnc container' || return 1
}

run_test() {
  local name="$1"
  if "$name"; then
    printf 'ok - %s\n' "$name"
  else
    FAILURES=$((FAILURES + 1))
  fi
}

run_test test_start_prefers_podman_and_prints_connection_details
run_test test_start_falls_back_to_docker
run_test test_start_uses_requested_docker_engine
run_test test_start_uses_requested_podman_engine
run_test test_start_rejects_unavailable_requested_engine
run_test test_start_rejects_unsupported_engine
run_test test_start_errors_when_no_container_engine_is_available
run_test test_start_defaults_name_resolution_display_number_and_xfce
run_test test_create_is_start_alias
run_test test_openbox_desktop_uses_openbox_image_and_start_command
run_test test_invalid_desktop_fails
run_test test_resolution_larger_than_physical_fails
run_test test_non_start_actions_require_container_name
run_test test_lifecycle_actions_use_prefixed_container_name
run_test test_delete_is_remove_alias
run_test test_prefixed_name_is_not_prefixed_twice
run_test test_status_reports_state_and_connection_details
run_test test_check_is_status_alias
run_test test_list_uses_managed_container_label
run_test test_use_invokes_cua_helper_with_vnc_endpoint
run_test test_use_missing_vncdotool_fails_before_container_inspect
run_test test_use_respects_requested_engine
run_test test_use_rejects_unmanaged_container
run_test test_use_rejects_missing_display_label
run_test test_use_help_works_without_runtime
run_test test_help_is_default_and_aliases_work_without_runtime
run_test test_setup_installs_container_cli
run_test test_installed_symlink_resolves_repo_scripts

if (( FAILURES )); then
  printf 'not ok - container gui tests (%d failed)\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok - container gui tests\n'
