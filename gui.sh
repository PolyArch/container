#!/usr/bin/env bash
set -euo pipefail

ACTION=""
RAW_NAME=""
RESOLUTION=""
DISPLAY_NUMBER=""
DESKTOP="xfce"
REQUESTED_ENGINE=""
POSITIONALS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_CONTAINERFILE="$SCRIPT_DIR/images/gui.containerfile"
IMAGE_PREFIX="${CONTAINER_GUI_IMAGE_PREFIX:-ucla.edu/polyarch/container}"
MANAGED_LABEL="ucla.polyarch.container.gui"
DEFAULT_RESOLUTION="1920x1080"
HASH_LENGTH=12

usage() {
  cat <<'EOF'
container gui - run an EL9 Xvnc container as a local X11 display.

Usage:
  container gui help
  container gui start [CONTAINER_NAME] [--resolution WIDTHxHEIGHT]
                                      [--port N] [--desktop xfce|openbox]
                                      [--engine docker|podman]
  container gui stop|remove|restart|enable|status|check CONTAINER_NAME
  container gui list

Actions:
  start    create and start an Xvnc-backed X11 container
  stop     stop a named managed container
  remove   remove a named managed container
  restart  restart a named managed container
  enable   set restart policy for a named managed container
  status   show state and connection details for a named managed container
  check    alias for status
  list     list managed containers
  help     show this help

Options:
  --resolution WxH       Xvnc desktop size. If omitted, use the current
                         physical display size when detectable, otherwise
                         1920x1080. Explicit values larger than the detected
                         physical display fail.
  --port N               X display number. X11 listens on 6000+N and VNC on
                         5900+N. If omitted for start, the first free display
                         number from 2 upward is used.
  --desktop xfce|openbox Desktop environment for the VNC session.
                         Default: xfce. Openbox is kept as a lightweight
                         fallback.
  --engine docker|podman Container engine to use. Default: podman when
                         available, otherwise docker.
  -h, --help             show this help.

Examples:
  container gui start eda --resolution 2560x1440 --port 2
  container gui status eda
  DISPLAY=127.0.0.1:2 rtl_shell -gui
  Connect a VNC viewer to vnc://127.0.0.1:5902
EOF
}

die() {
  printf 'container gui: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --action)
      [[ $# -ge 2 ]] || die "--action needs a value"
      ACTION="$2"
      shift 2
      ;;
    --container-name)
      [[ $# -ge 2 ]] || die "--container-name needs a value"
      RAW_NAME="$2"
      shift 2
      ;;
    --resolution)
      [[ $# -ge 2 ]] || die "--resolution needs a value"
      RESOLUTION="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port needs a value"
      DISPLAY_NUMBER="$2"
      shift 2
      ;;
    --desktop)
      [[ $# -ge 2 ]] || die "--desktop needs a value"
      DESKTOP="$2"
      shift 2
      ;;
    --engine)
      [[ $# -ge 2 ]] || die "--engine needs docker or podman"
      REQUESTED_ENGINE="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONALS+=("$1")
        shift
      done
      ;;
    -*)
      die "unknown argument: $1 (try --help)"
      ;;
    *)
      POSITIONALS+=("$1")
      shift
      ;;
  esac
done

positional_index=0
if [[ -z "$ACTION" ]]; then
  if (( ${#POSITIONALS[@]} == 0 )); then
    usage
    exit 0
  fi
  ACTION="${POSITIONALS[0]}"
  positional_index=1
fi

if [[ "$ACTION" == help ]]; then
  usage
  exit 0
fi

if [[ "$ACTION" == check ]]; then
  ACTION="status"
fi

if [[ -z "$RAW_NAME" && ${#POSITIONALS[@]} -gt $positional_index ]]; then
  RAW_NAME="${POSITIONALS[$positional_index]}"
  positional_index=$((positional_index + 1))
fi

if (( ${#POSITIONALS[@]} > positional_index )); then
  die "unexpected positional argument: ${POSITIONALS[$positional_index]}"
fi

case "$ACTION" in
  start|stop|remove|restart|enable|status|list) ;;
  *) die "action must be one of start, stop, remove, restart, enable, status, check, list, help" ;;
esac

case "$DESKTOP" in
  xfce|openbox) ;;
  *) die "--desktop must be one of xfce, openbox" ;;
esac

engine_is_supported() {
  case "$1" in
    podman|docker)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

engine_is_available() {
  local engine="$1"
  command -v "$engine" >/dev/null 2>&1 || return 1
  "$engine" --version >/dev/null 2>&1 || return 1
}

select_runtime() {
  local requested="$1" candidate
  if [[ -n "$requested" ]]; then
    engine_is_supported "$requested" || die "unsupported container engine: $requested"
    engine_is_available "$requested" || die "container engine is not available: $requested"
    printf '%s\n' "$requested"
    return 0
  fi

  for candidate in podman docker; do
    if engine_is_available "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  die "install docker or podman before running GUI containers"
}

validate_raw_name() {
  local name="$1"
  [[ -n "$name" ]] || die "--container-name must not be empty"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
    || die "--container-name may contain only letters, numbers, dot, dash, and underscore"
}

container_name_from_raw() {
  local name="$1"
  validate_raw_name "$name"
  if [[ "$name" == container-gui-* ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  printf 'container-gui-%s\n' "$name"
}

validate_resolution() {
  local value="$1"
  [[ "$value" =~ ^([1-9][0-9]*)x([1-9][0-9]*)$ ]] \
    || die "--resolution must look like WIDTHxHEIGHT (got '$value')"
}

resolution_width() {
  printf '%s\n' "${1%x*}"
}

resolution_height() {
  printf '%s\n' "${1#*x}"
}

detect_physical_resolution() {
  local value
  if command -v xrandr >/dev/null 2>&1; then
    value="$(xrandr 2>/dev/null | awk '
      /current [0-9]+ x [0-9]+/ {
        for (i = 1; i <= NF; i++) {
          if ($i == "current") {
            w = $(i + 1)
            h = $(i + 3)
            gsub(/,/, "", w)
            gsub(/,/, "", h)
            print w "x" h
            exit
          }
        }
      }
      /^[[:space:]]*[0-9]+x[0-9]+[[:space:]]/ && /\*/ {
        print $1
        exit
      }')"
    if [[ "$value" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  if command -v xdpyinfo >/dev/null 2>&1; then
    value="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ { print $2; exit }')"
    if [[ "$value" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  return 1
}

choose_resolution() {
  local physical="${1:-}" requested="${2:-}"
  if [[ -n "$requested" ]]; then
    validate_resolution "$requested"
    if [[ -n "$physical" ]]; then
      local req_w req_h phys_w phys_h
      req_w="$(resolution_width "$requested")"
      req_h="$(resolution_height "$requested")"
      phys_w="$(resolution_width "$physical")"
      phys_h="$(resolution_height "$physical")"
      if (( req_w > phys_w || req_h > phys_h )); then
        die "resolution exceeds detected physical display (${physical}): ${requested}"
      fi
    fi
    printf '%s\n' "$requested"
    return 0
  fi

  if [[ -n "$physical" ]]; then
    printf '%s\n' "$physical"
    return 0
  fi

  printf '%s\n' "$DEFAULT_RESOLUTION"
}

validate_display_number() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "--port must be a non-negative integer display number"
  (( value <= 99 )) || die "--port must be between 0 and 99"
}

tcp_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{ print $4 }' | grep -Eq "[:.]${port}$"
    return $?
  fi
  return 1
}

display_number_is_free() {
  local display="$1" x11_port vnc_port
  x11_port=$((6000 + display))
  vnc_port=$((5900 + display))
  ! tcp_port_in_use "$x11_port" && ! tcp_port_in_use "$vnc_port"
}

choose_display_number() {
  local requested="${1:-}" n
  if [[ -n "$requested" ]]; then
    validate_display_number "$requested"
    display_number_is_free "$requested" \
      || die "display :${requested} is not free on TCP ports $((6000 + requested)) and $((5900 + requested))"
    printf '%s\n' "$requested"
    return 0
  fi

  for n in {2..99}; do
    if display_number_is_free "$n"; then
      printf '%s\n' "$n"
      return 0
    fi
  done

  die "no free display number found in range 2..99"
}

containerfile_hash() {
  local path="$1"
  sha256sum "$path" | awk -v n="$HASH_LENGTH" '{print substr($1, 1, n)}'
}

image_for_desktop() {
  if [[ -n "${CONTAINER_GUI_IMAGE:-}" ]]; then
    printf '%s\n' "$CONTAINER_GUI_IMAGE"
    return 0
  fi
  [[ -f "$GUI_CONTAINERFILE" ]] || die "missing GUI containerfile: $GUI_CONTAINERFILE"
  printf '%s-gui-%s:latest\n' "$IMAGE_PREFIX" "$(containerfile_hash "$GUI_CONTAINERFILE")"
}

ensure_image() {
  local runtime="$1" image="$2" build_file build_file_dir rc
  if "$runtime" image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi

  build_file_dir="$(mktemp -d)"
  if [[ "$runtime" == docker ]]; then
    build_file="$build_file_dir/Dockerfile"
    cp "$GUI_CONTAINERFILE" "$build_file"
  else
    build_file="$GUI_CONTAINERFILE"
  fi
  set +e
  "$runtime" build -t "$image" -f "$build_file" "$SCRIPT_DIR"
  rc=$?
  set -e
  rm -rf "$build_file_dir"
  return "$rc"
}

print_connection_info() {
  local runtime="$1" container="$2" resolution="$3" display="$4" desktop="$5"

  printf 'Container: %s\n' "$container"
  printf 'Runtime: %s\n' "$runtime"
  printf 'Desktop: %s\n' "$desktop"
  printf 'Resolution: %s\n' "$resolution"
  print_connection_guide "$display"
}

print_connection_guide() {
  local display="$1"
  local x11_port vnc_port
  x11_port=$((6000 + display))
  vnc_port=$((5900 + display))

  printf 'DISPLAY=127.0.0.1:%s\n' "$display"
  printf 'X11 TCP: 127.0.0.1:%s\n' "$x11_port"
  printf 'VNC: vnc://127.0.0.1:%s\n' "$vnc_port"
  printf '\n'
  printf 'Run local X11 tools with:\n'
  printf '  DISPLAY=127.0.0.1:%s <tool-command>\n' "$display"
  printf '\n'
  printf 'For a remote SSH host, open a reverse tunnel from this machine:\n'
  printf '  ssh -R 127.0.0.1:%s:127.0.0.1:%s <user>@<remote-host>\n' "$x11_port" "$x11_port"
  printf 'Then on the remote host:\n'
  printf '  export DISPLAY=127.0.0.1:%s\n' "$display"
}

inspect_value() {
  local runtime="$1" container="$2" format="$3" value
  value="$("$runtime" inspect --format "$format" "$container" 2>/dev/null || true)"
  if [[ "$value" == "<no value>" ]]; then
    value=""
  fi
  printf '%s\n' "$value"
}

status_container() {
  local runtime="$1" container="$2"
  local managed state runtime_status image restart display resolution desktop

  "$runtime" inspect "$container" >/dev/null 2>&1 \
    || die "container not found: ${container}"

  managed="$(inspect_value "$runtime" "$container" '{{ index .Config.Labels "ucla.polyarch.container.gui" }}')"
  [[ "$managed" == true ]] \
    || die "container is not managed by container gui: ${container}"

  state="$(inspect_value "$runtime" "$container" '{{ .State.Status }}')"
  image="$(inspect_value "$runtime" "$container" '{{ .Config.Image }}')"
  restart="$(inspect_value "$runtime" "$container" '{{ .HostConfig.RestartPolicy.Name }}')"
  display="$(inspect_value "$runtime" "$container" '{{ index .Config.Labels "ucla.polyarch.container.gui.display" }}')"
  resolution="$(inspect_value "$runtime" "$container" '{{ index .Config.Labels "ucla.polyarch.container.gui.resolution" }}')"
  desktop="$(inspect_value "$runtime" "$container" '{{ index .Config.Labels "ucla.polyarch.container.gui.desktop" }}')"
  runtime_status="$("$runtime" ps -a --filter "name=^${container}$" \
    --format '{{.Names}} {{.Status}} {{.Ports}}' | head -n 1 || true)"

  printf 'Container: %s\n' "$container"
  printf 'Runtime: %s\n' "$runtime"
  printf 'State: %s\n' "${state:-unknown}"
  printf 'Runtime status: %s\n' "${runtime_status:-unknown}"
  printf 'Image: %s\n' "${image:-unknown}"
  printf 'Restart policy: %s\n' "${restart:-unknown}"
  printf 'Desktop: %s\n' "${desktop:-unknown}"
  printf 'Resolution: %s\n' "${resolution:-unknown}"

  if [[ "$display" =~ ^[0-9]+$ ]]; then
    print_connection_guide "$display"
  else
    printf 'Connection details unavailable: missing managed display label\n'
  fi
}

start_container() {
  local runtime="$1" container="$2" resolution="$3" display="$4" desktop="$5"
  local image x11_port vnc_port command
  image="$(image_for_desktop "$desktop")"
  x11_port=$((6000 + display))
  vnc_port=$((5900 + display))

  ensure_image "$runtime" "$image"

  if [[ "$desktop" == openbox ]]; then
    command="set -eu; Xvnc :${display} -geometry ${resolution} -depth 24 -rfbport ${vnc_port} -SecurityTypes None -localhost no -AlwaysShared -listen tcp -ac 2>&1 & xvnc_pid=\$!; sleep 2; DISPLAY=:${display} openbox >/tmp/openbox.log 2>&1 & DISPLAY=:${display} xterm -geometry 100x30+40+40 >/tmp/xterm.log 2>&1 & wait \"\$xvnc_pid\""
  else
    command="set -eu; export DISPLAY=:${display}; Xvnc :${display} -geometry ${resolution} -depth 24 -rfbport ${vnc_port} -SecurityTypes None -localhost no -AlwaysShared -listen tcp -ac 2>&1 & xvnc_pid=\$!; sleep 2; dbus-run-session startxfce4 >/tmp/xfce.log 2>&1 & wait \"\$xvnc_pid\""
  fi

  "$runtime" run -d \
    --name "$container" \
    --label "${MANAGED_LABEL}=true" \
    --label "${MANAGED_LABEL}.display=${display}" \
    --label "${MANAGED_LABEL}.resolution=${resolution}" \
    --label "${MANAGED_LABEL}.desktop=${desktop}" \
    -p "127.0.0.1:${vnc_port}:${vnc_port}" \
    -p "127.0.0.1:${x11_port}:${x11_port}" \
    "$image" \
    bash -lc "$command" >/dev/null

  print_connection_info "$runtime" "$container" "$resolution" "$display" "$desktop"
}

runtime="$(select_runtime "$REQUESTED_ENGINE")"

if [[ "$ACTION" == list ]]; then
  "$runtime" ps -a --filter "label=${MANAGED_LABEL}=true" \
    --format '{{.Names}} {{.Status}} {{.Ports}}'
  exit 0
fi

if [[ "$ACTION" != start && "$ACTION" != list && -z "$RAW_NAME" ]]; then
  die "container name is required for action ${ACTION}"
fi

if [[ "$ACTION" == start ]]; then
  if [[ -z "$RAW_NAME" ]]; then
    RAW_NAME="$(date '+%Y%m%d-%H%M%S')"
  fi
  container="$(container_name_from_raw "$RAW_NAME")"
  physical_resolution="$(detect_physical_resolution || true)"
  final_resolution="$(choose_resolution "$physical_resolution" "$RESOLUTION")"
  final_display="$(choose_display_number "$DISPLAY_NUMBER")"
  start_container "$runtime" "$container" "$final_resolution" "$final_display" "$DESKTOP"
  exit 0
fi

container="$(container_name_from_raw "$RAW_NAME")"

case "$ACTION" in
  status)
    status_container "$runtime" "$container"
    ;;
  stop)
    "$runtime" stop "$container"
    printf 'Stopped: %s\n' "$container"
    ;;
  remove)
    "$runtime" rm -f "$container"
    printf 'Removed: %s\n' "$container"
    ;;
  restart)
    "$runtime" restart "$container"
    printf 'Restarted: %s\n' "$container"
    ;;
  enable)
    "$runtime" update --restart=unless-stopped "$container"
    printf 'Enabled runtime restart policy for: %s\n' "$container"
    ;;
esac
