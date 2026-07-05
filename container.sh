#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/images"
IMAGE_PREFIX="ucla.edu/polyarch/container"
DEFAULT_ENGINE_TYPE="podman"
HASH_LENGTH=12

die() {
    printf 'container: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

COLOR_RESET=$'\033[0m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_RED=$'\033[31m'
COLOR_CYAN=$'\033[36m'
COLOR_DIM=$'\033[2m'

color_enabled() {
    [[ "${CONTAINER_COLOR:-always}" != never ]]
}

truncate_text() {
    local text="$1" width="$2"
    if (( ${#text} > width )); then
        if (( width > 3 )); then
            printf '%s\n' "${text:0:width-3}..."
        else
            printf '%s\n' "${text:0:width}"
        fi
    else
        printf '%s\n' "$text"
    fi
}

table_cell() {
    local text="$1" width="$2" color="${3:-}" value
    value="$(truncate_text "$text" "$width")"
    if [[ -n "$color" ]] && color_enabled; then
        printf '%b' "$color"
        printf '%-*s' "$width" "$value"
        printf '%b' "$COLOR_RESET"
    else
        printf '%-*s' "$width" "$value"
    fi
}

table_line() {
    local width
    printf '+'
    for width in "$@"; do
        printf '%*s' "$((width + 2))" '' | tr ' ' '-'
        printf '+'
    done
    printf '\n'
}

image_status_color() {
    case "$1" in
        current|yes)
            printf '%s\n' "$COLOR_GREEN"
            ;;
        stale|legacy|no)
            printf '%s\n' "$COLOR_YELLOW"
            ;;
        missing)
            printf '%s\n' "$COLOR_RED"
            ;;
        *)
            printf '%s\n' "$COLOR_DIM"
            ;;
    esac
}

display_image_name() {
    local image="$1" common_prefix="$2"
    if [[ -n "$common_prefix" && "$image" == "$common_prefix"* ]]; then
        printf '%s\n' "${image#"$common_prefix"}"
    else
        printf '%s\n' "$image"
    fi
}

common_image_prefix() {
    local prefix="" value count=0
    for value in "$@"; do
        [[ -n "$value" ]] || continue
        count=$((count + 1))
        if [[ -z "$prefix" ]]; then
            prefix="$value"
            continue
        fi
        while [[ -n "$prefix" && "${value:0:${#prefix}}" != "$prefix" ]]; do
            prefix="${prefix%?}"
        done
    done

    if (( count < 2 )); then
        printf '\n'
        return 0
    fi

    while [[ -n "$prefix" && "$prefix" != *[-_/:.] ]]; do
        prefix="${prefix%?}"
    done

    for value in "$@"; do
        [[ -n "$value" ]] || continue
        if [[ "$value" == "$prefix" || "$value" != "$prefix"* ]]; then
            printf '\n'
            return 0
        fi
    done

    printf '%s\n' "$prefix"
}

update_width() {
    local width_name="$1" value="$2"
    local -n width_ref="$width_name"
    if (( ${#value} > width_ref )); then
        width_ref="${#value}"
    fi
}

filename_safe() {
    local value="$1"
    value="${value//\//_}"
    value="${value//:/_}"
    value="${value//[^A-Za-z0-9._-]/_}"
    printf '%s\n' "$value"
}

image_action_log_dir() {
    local dir="${HOME:-$PWD}/.cache/container"
    mkdir -p "$dir" || die "cannot create log directory: $dir"
    printf '%s\n' "$dir"
}

achronix_accept_file() {
    local dir="${HOME:-$PWD}/.achronix"
    local accept_file="$dir/.accept"
    mkdir -p "$dir" || die "cannot create Achronix accept directory: $dir"
    if [[ ! -e "$accept_file" ]]; then
        printf 'Achronix_License=2023\n' >"$accept_file" \
            || die "cannot create Achronix accept file: $accept_file"
        chmod 644 "$accept_file" || die "cannot update Achronix accept file mode: $accept_file"
    fi
    [[ -f "$accept_file" ]] || die "Achronix accept path is not a file: $accept_file"
    printf '%s\n' "$accept_file"
}

add_host_history_mounts() {
    local history_file history_name
    [[ -n "${HOME:-}" && -d "$HOME" ]] || return 0
    for history_file in "$HOME"/.*history; do
        [[ -f "$history_file" && -r "$history_file" ]] || continue
        history_name="$(basename "$history_file")"
        PODMAN_ARGS+=("-v" "$history_file:/tmp/container-host-history-$history_name:ro")
    done
}

append_container_command() {
    local entry_script
    # shellcheck disable=SC2016
    entry_script='target_home="${CONTAINER_HOME:-$HOME}"
shopt -s nullglob
for src in /tmp/container-host-history-.*history; do
    name="${src#/tmp/container-host-history-}"
    cp -f -- "$src" "$target_home/$name"
done
while IFS= read -r name; do
    unset "$name"
done < <(env | sed -n "s/^\(SNPS_CONTAINER[A-Za-z0-9_]*\)=.*/\1/p")
if [ "$#" -eq 0 ]; then
    exec /usr/bin/zsh
else
    exec "$@"
fi'
    PODMAN_ARGS+=("/usr/bin/bash" "-lc" "$entry_script" "container-entry")
    PODMAN_ARGS+=("${cmd_args[@]}")
}

top_usage() {
    cat <<'USAGE'
Usage:
  container run [OPTIONS] [--] [COMMAND [ARGS...]]
  container image [create|update|list|clean] [OPTIONS]
  container gui [ACTION] [CONTAINER_NAME] [OPTIONS]

Commands:
  run      Start a tool container and optionally run a command inside it.
  image    List, build, update, or clean tool container images.
  gui      Manage a local Xvnc-backed GUI container.
  help     Show this help.

Help:
  container help
  container run help
  container image help
  container gui help
  container run -h
  container image --help
  container gui --help

Common examples:
  container run --os almalinux8
  container run --os almalinux9 --workdir "$PWD" -- vivado -mode gui
  container run --env ./tool.env --network no -- vcs -full64 top.v
  container image list
  container image create --os all
  container image update --os oraclelinux7,almalinux8
  container image clean --os all --force
  container gui start eda --resolution 2560x1440 --port 2
USAGE
}

run_usage() {
    cat <<'USAGE'
Usage:
  container run [OPTIONS] [--] [COMMAND [ARGS...]]

Run options:
  --env INHERIT|FILE       Inherit host environment or load variables from FILE.
                           Default: INHERIT.
  --workdir DIR            Mount DIR as ~/work inside the container.
  --os OS                  Required. Container OS type. Use "list" to show supported OS types.
USAGE
    if (( $(available_engine_count) > 1 )); then
        cat <<'USAGE'
  --engine docker|podman   Container engine to use. Default: podman.
USAGE
    fi
    cat <<'USAGE'
  --network yes|no         yes uses host network. no uses restricted network.
                           Default: yes.
  --                       Separate container options from the container command.

Behavior:
  If --workdir is omitted, container creates a container-work_* directory under the caller
  directory and mounts it as ~/work inside the container.
  If the selected OS image for the current containerfile hash does not exist,
  container builds it before starting the container.

Examples:
  container run --os list
  container run --os almalinux8
  container run --os almalinux8 --env INHERIT
  container run --os almalinux9 --env ./tool.env --network no
  container run --os almalinux9 --workdir "$PWD" -- vivado -mode gui
USAGE
}

image_usage() {
    cat <<'USAGE'
Usage:
  container image [create|update|list|clean] [OPTIONS]
  container image [OPTIONS]

Image options:
  --os all|OS[,OS...]      Target OS types. Required except for image list.
                           image list defaults to --os all.
USAGE
    if (( $(available_engine_count) > 1 )); then
        cat <<'USAGE'
  --engine all|ENGINE[,ENGINE...] Target container engines. Default: all installed.
USAGE
    fi
    cat <<'USAGE'
  --force                  Remove containers that use target images after confirmation.

Image actions:
  list                     Show per-OS image status. This is the default action.
  create                   Build current images for selected OS types.
  update                   Build missing or stale current images. Current images are skipped.
  clean                    Remove images for selected OS types.

Status fields:
  status                   current, stale, or missing for each OS image row.
  current-hash             Hash of the selected OS containerfile.
  image-hash               Hash represented by the local image row.
  image-id                 Local image ID.
  size                     Local image size.
  created                  Local image creation age.
  containers               Number of containers using the image.
  engine                   Container engine that owns the image row.

Safety:
  clean and update skip images used by containers unless --force is passed.
  With --force, container asks for [y/N] confirmation before removing containers.

Examples:
  container image list
  container image --os all
  container image create --os all
  container image create --engine docker --os almalinux8
  container image update --os oraclelinux7,almalinux8
  container image clean --os almalinux9
  container image clean --os all --force
USAGE
}

supported_os_types() {
    local preferred os path found
    local seen=()
    preferred=(oraclelinux7 centos7 almalinux8 rockylinux8 almalinux9 rockylinux9 almalinux10 rockylinux10)

    for os in "${preferred[@]}"; do
        if [[ -f "$IMAGE_DIR/$os.containerfile" ]]; then
            printf '%s\n' "$os"
            seen+=("$os")
        fi
    done

    for path in "$IMAGE_DIR"/*.containerfile; do
        [[ -e "$path" ]] || continue
        os="$(basename "$path" .containerfile)"
        found=false
        for known in "${seen[@]}"; do
            if [[ "$known" == "$os" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == true ]] || printf '%s\n' "$os"
    done
}

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

available_engine_types() {
    local engine
    for engine in "$DEFAULT_ENGINE_TYPE" docker; do
        if engine_is_available "$engine"; then
            printf '%s\n' "$engine"
        fi
    done
}

available_engine_count() {
    available_engine_types | wc -l | tr -d ' '
}

require_container_engine_available() {
    if [[ "$(available_engine_count)" -eq 0 ]]; then
        die "install docker or podman before running tool containers"
    fi
}

select_run_engine() {
    local requested="$1" engine
    require_container_engine_available

    if [[ -n "$requested" ]]; then
        engine_is_supported "$requested" || die "unsupported container engine: $requested"
        engine_is_available "$requested" || die "container engine is not available: $requested"
        printf '%s\n' "$requested"
        return 0
    fi

    if engine_is_available "$DEFAULT_ENGINE_TYPE"; then
        printf '%s\n' "$DEFAULT_ENGINE_TYPE"
        return 0
    fi

    while IFS= read -r engine; do
        printf '%s\n' "$engine"
        return 0
    done < <(available_engine_types)
}

parse_engine_list() {
    local spec="$1" engine
    if [[ -z "$spec" || "$spec" == all ]]; then
        require_container_engine_available
        available_engine_types
        return 0
    fi

    IFS=',' read -r -a engine_values <<<"$spec"
    for engine in "${engine_values[@]}"; do
        [[ -n "$engine" ]] || die "empty engine type in --engine"
        engine_is_supported "$engine" || die "unsupported container engine: $engine"
        engine_is_available "$engine" || die "container engine is not available: $engine"
        printf '%s\n' "$engine"
    done
}

print_supported_os_types() {
    supported_os_types
}

containerfile_for_os() {
    local os_type="$1"
    local containerfile="$IMAGE_DIR/$os_type.containerfile"
    [[ -f "$containerfile" ]] || die "unsupported OS type: $os_type"
    printf '%s\n' "$containerfile"
}

containerfile_hash_for_os() {
    local containerfile
    containerfile="$(containerfile_for_os "$1")"
    sha256sum "$containerfile" | awk -v n="$HASH_LENGTH" '{print substr($1, 1, n)}'
}

image_for_os() {
    local os_type="$1" hash
    hash="$(containerfile_hash_for_os "$os_type")"
    printf '%s-%s-%s:latest\n' "$IMAGE_PREFIX" "$os_type" "$hash"
}

image_matches_os() {
    local image="$1" os_type="$2"
    [[ "$image" == "$IMAGE_PREFIX-$os_type:"* ]] && return 0
    [[ "$image" == "$IMAGE_PREFIX-$os_type-"*":latest" ]] && return 0
    return 1
}

image_hash_from_name() {
    local image="$1" os_type="$2" prefix
    prefix="$IMAGE_PREFIX-$os_type-"
    if [[ "$image" == "$prefix"*":latest" ]]; then
        image="${image#"$prefix"}"
        printf '%s\n' "${image%:latest}"
    elif [[ "$image" == "$IMAGE_PREFIX-$os_type:latest" ]]; then
        printf 'legacy\n'
    else
        printf 'unknown\n'
    fi
}

parse_os_list() {
    local spec="$1"
    local os_type
    if [[ "$spec" == all ]]; then
        supported_os_types
        return 0
    fi

    IFS=',' read -r -a os_values <<<"$spec"
    for os_type in "${os_values[@]}"; do
        [[ -n "$os_type" ]] || die "empty OS type in --os"
        containerfile_for_os "$os_type" >/dev/null
        printf '%s\n' "$os_type"
    done
}

image_records_for_os() {
    local engine="$1" os_type="$2"
    local image image_id created size
    container_engine_image_records "$engine" | while IFS='|' read -r image image_id created size; do
        [[ -n "$image" ]] || continue
        if image_matches_os "$image" "$os_type"; then
            printf '%s|%s|%s|%s\n' "$image" "$image_id" "$created" "$size"
        fi
    done
}

containers_for_image() {
    local engine="$1" image="$2"
    "$engine" ps -a --filter "ancestor=$image" --format '{{.ID}}' 2>/dev/null | sed '/^$/d'
}

container_count_for_image() {
    containers_for_image "$1" "$2" | wc -l | tr -d ' '
}

host_timezone() {
    timedatectl show --property=Timezone --value 2>/dev/null || printf 'America/Los_Angeles\n'
}

container_engine_image_records() {
    local engine="$1"
    "$engine" images --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.CreatedSince}}|{{.Size}}' 2>/dev/null
}

container_engine_image_exists() {
    local engine="$1" image="$2"
    case "$engine" in
        podman)
            "$engine" image exists "$image"
            ;;
        docker)
            "$engine" image inspect "$image" >/dev/null 2>&1
            ;;
        *)
            die "unsupported container engine: $engine"
            ;;
    esac
}

dockerfile_for_engine() {
    local engine="$1" containerfile="$2" output_dir="$3"
    case "$engine" in
        docker)
            mkdir -p "$output_dir" || die "cannot create Dockerfile directory: $output_dir"
            cp "$containerfile" "$output_dir/Dockerfile" || die "cannot prepare Dockerfile from: $containerfile"
            printf '%s\n' "$output_dir/Dockerfile"
            ;;
        podman)
            printf '%s\n' "$containerfile"
            ;;
        *)
            die "unsupported container engine: $engine"
            ;;
    esac
}

build_image_for_os() {
    local engine="$1" os_type="$2" image containerfile build_file build_file_dir timezone container_user rc
    image="$(image_for_os "$os_type")"
    containerfile="$(containerfile_for_os "$os_type")"
    timezone="$(host_timezone)"
    container_user="${USER:-$(whoami)}"

    if container_engine_image_exists "$engine" "$image"; then
        printf '%s already exists in %s\n' "$image" "$engine"
        return 0
    fi

    build_file_dir="$(mktemp -d)"
    build_file="$(dockerfile_for_engine "$engine" "$containerfile" "$build_file_dir")"

    printf 'Building %s with %s from %s\n' "$image" "$engine" "$containerfile"
    set +e
    "$engine" build -t "$image" \
        --build-arg "user=$container_user" \
        --build-arg "uid=$(id -u)" \
        --build-arg "gid=$(id -g)" \
        --build-arg "timezone=$timezone" \
        -f "$build_file" "$SCRIPT_DIR"
    rc=$?
    set -e
    rm -rf "$build_file_dir"
    return "$rc"
}

current_image_exists_for_os() {
    container_engine_image_exists "$1" "$(image_for_os "$2")"
}

update_image_for_os() {
    local engine="$1" os_type="$2" force="$3"
    if current_image_exists_for_os "$engine" "$os_type"; then
        printf '%s/%s: current image exists; update skipped\n' "$engine" "$os_type"
        preflight_image_for_os "$engine" "$os_type"
        return 0
    fi
    clean_images_for_os "$engine" "$os_type" "$force"
    build_image_for_os "$engine" "$os_type"
    preflight_image_for_os "$engine" "$os_type"
}

preflight_image_for_os() {
    local engine="$1" os_type="$2" image
    image="$(image_for_os "$os_type")"
    printf 'Preflighting %s rootfs for %s\n' "$engine" "$image"
    case "$engine" in
        podman)
            "$engine" run --rm --pull=never --userns=keep-id --security-opt label=disable "$image" /usr/bin/true
            ;;
        docker)
            "$engine" run --rm --pull=never --security-opt label=disable "$image" /usr/bin/true
            ;;
        *)
            die "unsupported container engine: $engine"
            ;;
    esac
    printf 'Preflight complete for %s in %s\n' "$image" "$engine"
}

add_common_podman_args() {
    local engine="$1"
    case "$engine" in
        podman)
            PODMAN_ARGS+=(
                "run" "--rm" "--uts=host"
                "--name" "$CONTAINER_NAME"
                "--userns=keep-id"
                "--systemd=false"
                "--cgroups=disabled"
                "--sdnotify=ignore"
                "--security-opt" "label=disable"
            )
            ;;
        docker)
            PODMAN_ARGS+=(
                "run" "--rm" "--uts=host"
                "--name" "$CONTAINER_NAME"
                "--security-opt" "label=disable"
            )
            ;;
        *)
            die "unsupported container engine: $engine"
            ;;
    esac
    if [[ -t 0 && -t 1 ]]; then
        PODMAN_ARGS+=("-it")
    fi
}

setup_restricted_network() {
    local engine="$1" modules_output network_name user_subnet_octet
    modules_output="$(lsmod | grep -E 'ip_tables|iptable_filter|ip_conntrack|nf_conntrack' || true)"

    [[ "$modules_output" == *ip_tables* ]] \
        || die "kernel module ip_tables is not loaded; use --network yes or load the module"
    [[ "$modules_output" == *iptable_filter* ]] \
        || die "kernel module iptable_filter is not loaded; use --network yes or load the module"
    [[ "$modules_output" == *ip_conntrack* || "$modules_output" == *nf_conntrack* ]] \
        || die "connection tracking module is not loaded; use --network yes or load nf_conntrack"

    network_name="container-restricted"
    if ! container_engine_network_exists "$engine" "$network_name"; then
        user_subnet_octet=$((( $(id -u) % 200 ) + 50))
        "$engine" network create --subnet "10.200.${user_subnet_octet}.0/24" "$network_name" >/dev/null
    fi

    PODMAN_ARGS+=("--network=$network_name" "--cap-add=NET_ADMIN" "--cap-add=NET_RAW")
    if [[ "$engine" == docker ]]; then
        PODMAN_ARGS+=("--add-host" "host.containers.internal:host-gateway")
    fi

    TEMP_SCRIPT_DIR="/tmp/container-egress-${CONTAINER_TIMESTAMP}-${CONTAINER_HASH}"
    mkdir -p "$TEMP_SCRIPT_DIR"
    SETUP_SCRIPT="${TEMP_SCRIPT_DIR}/container-egress.sh"
    cat >"$SETUP_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export XTABLES_LOCKFILE=/tmp/xtables.lock
touch "$XTABLES_LOCKFILE"
iptables -P OUTPUT DROP
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
RESOLV="$(grep -Eo "nameserver[[:space:]]+[0-9.]+" /etc/resolv.conf | awk '{print $2}' | sort -u)"
for ip in ${RESOLV}; do
  iptables -A OUTPUT -d "$ip" -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -d "$ip" -p tcp --dport 53 -j ACCEPT
done
HOST_GW="$(getent hosts host.containers.internal 2>/dev/null | awk '{print $1}' | head -n1)"
if [ -z "$HOST_GW" ] && command -v ip >/dev/null 2>&1; then
  HOST_GW="$(ip route | awk '/default/ {print $3}' 2>/dev/null | head -n1)"
fi
if [ -z "$HOST_GW" ] && command -v route >/dev/null 2>&1; then
  HOST_GW="$(route -n | awk '/^0\.0\.0\.0/ {print $2}' 2>/dev/null | head -n1)"
fi
if [ -z "$HOST_GW" ] && [ -f /proc/net/route ]; then
  HEX_GW="$(awk '$2=="00000000" {print $3}' /proc/net/route 2>/dev/null | head -n1)"
  if [ -n "$HEX_GW" ]; then
    HOST_GW="$(printf "%d.%d.%d.%d" $((0x${HEX_GW:6:2})) $((0x${HEX_GW:4:2})) $((0x${HEX_GW:2:2})) $((0x${HEX_GW:0:2})))"
  fi
fi
if [ -n "$HOST_GW" ]; then
  iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j DNAT --to-destination "$HOST_GW"
  iptables -t nat -A POSTROUTING -d "$HOST_GW" -j MASQUERADE
  iptables -A OUTPUT -d "$HOST_GW" -j ACCEPT
fi
if [ -n "${CONTAINER_NETWORK_ALLOWLIST:-}" ]; then
  IFS=',' read -ra ALLOWED_DESTS <<<"${CONTAINER_NETWORK_ALLOWLIST}"
  for dest in "${ALLOWED_DESTS[@]}"; do
    dest="$(echo "$dest" | xargs)"
    [ -n "$dest" ] && iptables -A OUTPUT -d "$dest" -j ACCEPT
  done
fi
if [ "$#" -eq 0 ]; then
  exec /usr/bin/zsh
else
  exec "$@"
fi
EOS
    chmod 755 "$SETUP_SCRIPT"
    PODMAN_ARGS+=("-v" "$SETUP_SCRIPT:/usr/local/bin/container-egress.sh:ro")
    PODMAN_ARGS+=("--entrypoint" "/usr/local/bin/container-egress.sh")
}

container_engine_network_exists() {
    local engine="$1" network_name="$2"
    case "$engine" in
        podman)
            "$engine" network exists "$network_name"
            ;;
        docker)
            "$engine" network inspect "$network_name" >/dev/null 2>&1
            ;;
        *)
            die "unsupported container engine: $engine"
            ;;
    esac
}

add_environment_args() {
    local env_mode="$1" env_file="$2" gui_enabled="$3" name value upper_name env_name

    if [[ "$env_mode" == inherit ]]; then
        while IFS='=' read -r name value; do
            case "$name" in
                DISPLAY|XAUTHORITY|WAYLAND_DISPLAY|SNPS_CONTAINER*|PROMPT_COMMAND|PS1|BASH_FUNC_*|WINDOWID|VTE_VERSION|SSH_*|GPG_*|SUDO_*|XDG_*|COLORTERM|LS_COLORS|LSCOLORS|S_COLORS|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|SESSION_MANAGER|DESKTOP_SESSION|GDMSESSION|GDM_LANG|GNOME_TERMINAL_SCREEN|GNOME_TERMINAL_SERVICE|WINDOWPATH|MAIL|DBUS_SESSION_BUS_ADDRESS|*MODULES*|*LMFILES*|*TMUX*|*TERM_PROGRAM*|*GUESTFISH*|DEBUGINFOD_IMA_CERT_PATH|SHELL|ZSH*|ZDOTDIR|HISTCONTROL|HISTSIZE|which_declare|DISABLE_AUTO_UPDATE|JAVA_*|DOCKER_HOST|SYSTEMD_EXEC_PID)
                    ;;
                *)
                    PODMAN_ARGS+=("-e" "${name}=${value}")
                    ;;
            esac
        done < <(env)
    else
        [[ -f "$env_file" ]] || die "environment file does not exist: $env_file"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a

        [[ -n "${PATH:-}" ]] && PODMAN_ARGS+=("-e" "PATH=$PATH")
        [[ -n "${LD_LIBRARY_PATH:-}" ]] && PODMAN_ARGS+=("-e" "LD_LIBRARY_PATH=$LD_LIBRARY_PATH")
        [[ -n "${PYTHONPATH:-}" ]] && PODMAN_ARGS+=("-e" "PYTHONPATH=$PYTHONPATH")
        [[ -n "${HOME:-}" ]] && PODMAN_ARGS+=("-e" "HOST_HOME=$HOME")
        [[ -n "${USER:-}" ]] && PODMAN_ARGS+=("-e" "HOST_USER=$USER")

        while IFS= read -r env_name; do
            [[ -n "$env_name" ]] || continue
            [[ "$env_name" == SNPS_CONTAINER* ]] && continue
            PODMAN_ARGS+=("-e" "${env_name}=${!env_name:-}")
        done < <(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$env_file" | sort -u)

        while IFS='=' read -r name value; do
            [[ "$name" == SNPS_CONTAINER* ]] && continue
            upper_name="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
            if [[ $upper_name == *CDS* || $upper_name == *CADENCE* || $upper_name == *MMSIM* || $upper_name == *SPECTRE* || $upper_name == *SYNOPSYS* || $upper_name == *SNPS* || $upper_name == *VCS* || $upper_name == *VERDI* || $upper_name == *SPYGLASS* || $upper_name == *PRIME* || $upper_name == *XILINX* || $upper_name == *XLNX* || $upper_name == *VIVADO* || $upper_name == *VITIS* ]]; then
                PODMAN_ARGS+=("-e" "${name}=${value}")
            fi
        done < <(env)
    fi

    if [[ "$gui_enabled" == true ]]; then
        PODMAN_ARGS+=("-e" "DISPLAY=$DISPLAY")
        PODMAN_ARGS+=("-e" "XAUTHORITY=$XAUTH")
    fi
    PODMAN_ARGS+=("-e" "HOST_WORKDIR_PATH=$WORK_DIR")
    [[ -n "${CONTAINER_NETWORK_ALLOWLIST:-}" ]] && PODMAN_ARGS+=("-e" "CONTAINER_NETWORK_ALLOWLIST=$CONTAINER_NETWORK_ALLOWLIST")
    PODMAN_ARGS+=("-e" "LIBGL_ALWAYS_SOFTWARE=1")
}

cmd_run() {
    local env_mode="inherit" env_file="" os_type="" network="yes" requested_work_dir=""
    local requested_engine="" engine
    local caller_pwd="${CALLER_PWD:-$PWD}" gui_enabled=true tool_name timestamp random_hash image
    local container_user="${USER:-$(whoami)}"
    local achronix_file
    local cmd_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                [[ $# -ge 2 ]] || die "--env needs INHERIT or a file path"
                if [[ "$2" == INHERIT ]]; then
                    env_mode="inherit"
                    env_file=""
                else
                    env_mode="file"
                    env_file="$2"
                fi
                shift 2
                ;;
            --workdir)
                [[ $# -ge 2 ]] || die "--workdir needs a directory"
                requested_work_dir="$2"
                shift 2
                ;;
            --os)
                [[ $# -ge 2 ]] || die "--os needs an OS type"
                if [[ "$2" == list ]]; then
                    print_supported_os_types
                    return 0
                fi
                os_type="$2"
                shift 2
                ;;
            --engine)
                [[ $# -ge 2 ]] || die "--engine needs docker or podman"
                requested_engine="$2"
                shift 2
                ;;
            --network)
                [[ $# -ge 2 ]] || die "--network needs yes or no"
                case "$2" in
                    yes|no)
                        network="$2"
                        ;;
                    *)
                        die "--network must be yes or no"
                        ;;
                esac
                shift 2
                ;;
            --build-only)
                die "--build-only moved to: container image create --os <OS>"
                ;;
            help)
                run_usage
                return 0
                ;;
            -h|--help)
                run_usage
                return 0
                ;;
            --)
                shift
                cmd_args=("$@")
                break
                ;;
            -*)
                die "unknown run option: $1"
                ;;
            *)
                cmd_args=("$@")
                break
                ;;
        esac
    done

    [[ -n "$os_type" ]] || die "--os is required for container run"
    containerfile_for_os "$os_type" >/dev/null
    engine="$(select_run_engine "$requested_engine")"
    image="$(image_for_os "$os_type")"
    build_image_for_os "$engine" "$os_type"

    if [[ -n "$requested_work_dir" ]]; then
        [[ -d "$requested_work_dir" ]] || die "work directory does not exist: $requested_work_dir"
        [[ -w "$requested_work_dir" ]] || die "work directory is not writable: $requested_work_dir"
        WORK_DIR="$(cd "$requested_work_dir" && pwd)"
    else
        if [[ ${#cmd_args[@]} -gt 0 && -n "${cmd_args[0]}" ]]; then
            tool_name="$(basename "${cmd_args[0]}")"
        else
            tool_name="interactive"
        fi
        timestamp="$(date +%Y%m%d-%H%M%S)"
        random_hash="$(head -c 6 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 6)"
        WORK_DIR="${caller_pwd}/container-work_${timestamp}_${os_type}_${tool_name}_${random_hash}"
        mkdir -p "$WORK_DIR"
        printf 'Created work directory: %s\n' "$WORK_DIR"
    fi

    CONTAINER_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    CONTAINER_HASH="$(head -c 6 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 6)"
    CONTAINER_NAME="container-${engine}-${os_type}-${CONTAINER_TIMESTAMP}-${CONTAINER_HASH}"
    PODMAN_ARGS=()
    add_common_podman_args "$engine"

    if [[ -z "${DISPLAY:-}" ]]; then
        gui_enabled=false
        printf 'DISPLAY is not set; starting container in headless mode.\n'
    elif ! command -v xauth >/dev/null 2>&1; then
        die "xauth command not found; install xauth or unset DISPLAY"
    fi

    if [[ "$gui_enabled" == true ]]; then
        XSOCK=/tmp/.X11-unix
        XAUTH="/tmp/.docker.xauth_${USER}_$(date +%s)_$RANDOM"
        touch "$XAUTH"
        xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge -
    fi

    if [[ "$network" == yes ]]; then
        PODMAN_ARGS+=("--network=host")
    else
        setup_restricted_network "$engine"
    fi

    if [[ "$gui_enabled" == true ]]; then
        PODMAN_ARGS+=("-v" "$XSOCK:$XSOCK:rw" "-v" "$XAUTH:$XAUTH:rw")
    fi
    [[ -d /mnt/nas0 ]] && PODMAN_ARGS+=("-v" "/mnt/nas0:/mnt/nas0:ro")
    PODMAN_ARGS+=("-v" "$WORK_DIR:/home/$container_user/work:rw")
    achronix_file="$(achronix_accept_file)"
    PODMAN_ARGS+=("-v" "$achronix_file:/home/$container_user/.achronix/.accept:ro")
    add_host_history_mounts
    if [[ -f "$HOME/.Xilinx/license.lic" ]]; then
        PODMAN_ARGS+=("-v" "$HOME/.Xilinx/license.lic:/home/$container_user/.Xilinx/license.lic:ro")
    fi

    add_environment_args "$env_mode" "$env_file" "$gui_enabled"
    PODMAN_ARGS+=("-e" "CONTAINER_HOME=/home/$container_user")

    PODMAN_ARGS+=("$image")
    append_container_command
    exec "$engine" "${PODMAN_ARGS[@]}"
}

confirm_force_removal() {
    local engine_values_name="$1" os_values_name="$2"
    local -n engine_values_ref="$engine_values_name"
    local -n os_values_ref="$os_values_name"
    local engine os_type image containers used_count=0

    for engine in "${engine_values_ref[@]}"; do
        for os_type in "${os_values_ref[@]}"; do
            while IFS='|' read -r image _; do
                [[ -n "$image" ]] || continue
                containers="$(containers_for_image "$engine" "$image" | tr '\n' ' ')"
                if [[ -n "$containers" ]]; then
                    printf 'Force removal will delete %s containers using %s: %s\n' "$engine" "$image" "$containers" >&2
                    used_count=$((used_count + 1))
                fi
            done < <(image_records_for_os "$engine" "$os_type")
        done
    done

    [[ "$used_count" -eq 0 ]] && return 0

    printf 'Continue with forced container and image removal? [y/N] ' >&2
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            die "force removal cancelled"
            ;;
    esac
}

clean_images_for_os() {
    local engine="$1" os_type="$2" force="$3"
    local image containers container removed=0 skipped=0
    while IFS='|' read -r image _; do
        [[ -n "$image" ]] || continue
        mapfile -t containers < <(containers_for_image "$engine" "$image")
        if [[ ${#containers[@]} -gt 0 ]]; then
            if [[ "$force" != true ]]; then
                warn "$image is used by ${#containers[@]} container(s); use --force to remove them"
                skipped=$((skipped + 1))
                continue
            fi
            for container in "${containers[@]}"; do
                "$engine" rm -f "$container"
            done
            "$engine" rmi -f "$image"
        else
            "$engine" rmi "$image"
        fi
        removed=$((removed + 1))
    done < <(image_records_for_os "$engine" "$os_type")

    printf '%s/%s: removed=%d skipped=%d\n' "$engine" "$os_type" "$removed" "$skipped"
}

print_image_table_header() {
    local image_header="$1" size_width="$2" created_width="$3" image_width="$4"
    table_line 8 13 8 12 12 13 "$size_width" "$created_width" 10 "$image_width"
    printf '| '
    table_cell "Engine" 8
    printf ' | '
    table_cell "OS" 13
    printf ' | '
    table_cell "Status" 8
    printf ' | '
    table_cell "Current Hash" 12
    printf ' | '
    table_cell "Image Hash" 12
    printf ' | '
    table_cell "Image ID" 13
    printf ' | '
    table_cell "Size" "$size_width"
    printf ' | '
    table_cell "Created" "$created_width"
    printf ' | '
    table_cell "Containers" 10
    printf ' | '
    table_cell "$image_header" "$image_width"
    printf ' |\n'
    table_line 8 13 8 12 12 13 "$size_width" "$created_width" 10 "$image_width"
}

print_image_table_row() {
    local engine="$1" os_type="$2" status="$3" current_hash="$4" hash="$5" image_id="$6"
    local size="$7" created="$8" container_total="$9" display_image="${10}"
    local size_width="${11}" created_width="${12}" image_width="${13}"

    printf '| '
    table_cell "$engine" 8 "$COLOR_DIM"
    printf ' | '
    table_cell "$os_type" 13 "$COLOR_CYAN"
    printf ' | '
    table_cell "$status" 8 "$(image_status_color "$status")"
    printf ' | '
    table_cell "$current_hash" 12
    printf ' | '
    table_cell "$hash" 12 "$(image_status_color "$hash")"
    printf ' | '
    table_cell "$image_id" 13
    printf ' | '
    table_cell "$size" "$size_width"
    printf ' | '
    table_cell "$created" "$created_width"
    printf ' | '
    table_cell "$container_total" 10
    printf ' | '
    table_cell "$display_image" "$image_width" "$COLOR_DIM"
    printf ' |\n'
}

print_image_rows_for_os() {
    local engine="$1" os_type="$2" common_prefix="$3" size_width="$4" created_width="$5" image_width="$6"
    local current_hash current_image image image_id created size hash container_total status display_image rows=0
    current_hash="$(containerfile_hash_for_os "$os_type")"
    current_image="$(image_for_os "$os_type")"

    while IFS='|' read -r image image_id created size; do
        [[ -n "$image" ]] || continue
        rows=$((rows + 1))
        hash="$(image_hash_from_name "$image" "$os_type")"
        container_total="$(container_count_for_image "$engine" "$image")"
        display_image="$(display_image_name "$image" "$common_prefix")"
        if [[ "$image" == "$current_image" ]]; then
            status=current
        else
            status=stale
        fi

        print_image_table_row \
            "$engine" "$os_type" "$status" "$current_hash" "$hash" "${image_id:-unknown}" \
            "${size:-unknown}" "${created:-unknown}" "$container_total" "$display_image" \
            "$size_width" "$created_width" "$image_width"
    done < <(image_records_for_os "$engine" "$os_type")

    if (( rows == 0 )); then
        display_image="$(display_image_name "$current_image" "$common_prefix")"
        print_image_table_row \
            "$engine" "$os_type" "missing" "$current_hash" "-" "-" "-" "-" "0" "$display_image" \
            "$size_width" "$created_width" "$image_width"
    fi
}

list_images_table() {
    local engine_values_name="$1" os_values_name="$2"
    local -n engine_values_ref="$engine_values_name"
    local -n os_values_ref="$os_values_name"
    local engine os_type image image_id created size current_image common_prefix image_header
    local image_width=40 size_width=8 created_width=14
    local images=()

    for engine in "${engine_values_ref[@]}"; do
        for os_type in "${os_values_ref[@]}"; do
            current_image="$(image_for_os "$os_type")"
            images+=("$current_image")
            while IFS='|' read -r image image_id created size; do
                [[ -n "$image" ]] || continue
                images+=("$image")
                update_width size_width "${size:-unknown}"
                update_width created_width "${created:-unknown}"
            done < <(image_records_for_os "$engine" "$os_type")
        done
    done

    common_prefix="$(common_image_prefix "${images[@]}")"
    if [[ -n "$common_prefix" ]]; then
        image_header="Image (All starts with \`$common_prefix\`)"
    else
        image_header="Image"
    fi
    update_width image_width "$image_header"
    for image in "${images[@]}"; do
        update_width image_width "$(display_image_name "$image" "$common_prefix")"
    done

    printf 'Container image status\n'
    print_image_table_header "$image_header" "$size_width" "$created_width" "$image_width"
    for engine in "${engine_values_ref[@]}"; do
        for os_type in "${os_values_ref[@]}"; do
            print_image_rows_for_os "$engine" "$os_type" "$common_prefix" "$size_width" "$created_width" "$image_width"
        done
    done
    table_line 8 13 8 12 12 13 "$size_width" "$created_width" 10 "$image_width"
}

run_image_action_for_os() {
    local action="$1" force="$2" engine="$3" os_type="$4"
    case "$action" in
        create)
            build_image_for_os "$engine" "$os_type"
            preflight_image_for_os "$engine" "$os_type"
            ;;
        clean)
            clean_images_for_os "$engine" "$os_type" "$force"
            ;;
        update)
            update_image_for_os "$engine" "$os_type" "$force"
            ;;
        *)
            die "unknown image action: $action"
            ;;
    esac
}

progress_bar_text() {
    local completed="$1" total="$2" width=28 filled empty
    if (( total <= 0 )); then
        total=1
    fi
    filled=$((completed * width / total))
    empty=$((width - filled))
    printf '%*s' "$filled" '' | tr ' ' '#'
    printf '%*s' "$empty" '' | tr ' ' '-'
}

progress_label_text() {
    local label="$1" tty_mode="$2"
    if [[ "$tty_mode" == true ]] && color_enabled; then
        printf '%b%-9s%b' "$COLOR_CYAN" "$label" "$COLOR_RESET"
    else
        printf '%-9s' "$label"
    fi
}

build_step_state_for_log() {
    local log_file="$1" rc="${2:-}" latest current total completed
    latest="$(awk '/^STEP [0-9]+\/[0-9]+:/ {line=$0} END {print line}' "$log_file" 2>/dev/null)"
    if [[ "$latest" =~ ^STEP[[:space:]]+([0-9]+)/([0-9]+): ]]; then
        current="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
        if [[ "$rc" == 0 ]]; then
            completed="$total"
        elif (( current > 0 )); then
            completed=$((current - 1))
        else
            completed=0
        fi
        printf '%d %d\n' "$completed" "$total"
    else
        printf '0 0\n'
    fi
}

build_step_progress_totals() {
    local logs_name="$1" rcs_name="$2" completed_name="$3" total_name="$4"
    local -n logs_ref="$logs_name"
    local -n rcs_ref="$rcs_name"
    local -n completed_ref="$completed_name"
    local -n total_ref="$total_name"
    local i rc="" completed total

    completed_ref=0
    total_ref=0
    for i in "${!logs_ref[@]}"; do
        rc=""
        if [[ -n "${rcs_ref[$i]+set}" ]]; then
            rc="${rcs_ref[$i]}"
        fi
        read -r completed total < <(build_step_state_for_log "${logs_ref[$i]}" "$rc")
        completed_ref=$((completed_ref + completed))
        total_ref=$((total_ref + total))
    done
}

image_action_uses_preflight() {
    case "$1" in
        create|update)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

preflight_state_for_log() {
    local log_file="$1" rc="${2:-}" started=0 completed=0
    if [[ -f "$log_file" ]] && grep -q '^Preflighting ' "$log_file" 2>/dev/null; then
        started=1
    fi
    if [[ -f "$log_file" ]] && grep -q '^Preflight complete ' "$log_file" 2>/dev/null; then
        completed=1
    elif [[ "$rc" == 0 && "$started" -eq 1 ]]; then
        completed=1
    fi
    printf '%d %d\n' "$started" "$completed"
}

preflight_progress_totals() {
    local logs_name="$1" rcs_name="$2" started_name="$3" completed_name="$4"
    local -n logs_ref="$logs_name"
    local -n rcs_ref="$rcs_name"
    local -n started_ref="$started_name"
    local -n completed_ref="$completed_name"
    local i rc="" started completed

    started_ref=0
    completed_ref=0
    for i in "${!logs_ref[@]}"; do
        rc=""
        if [[ -n "${rcs_ref[$i]+set}" ]]; then
            rc="${rcs_ref[$i]}"
        fi
        read -r started completed < <(preflight_state_for_log "${logs_ref[$i]}" "$rc")
        started_ref=$((started_ref + started))
        completed_ref=$((completed_ref + completed))
    done
}

progress_spinner() {
    case "$(( $1 % 10 ))" in
        0)
            printf '\342\240\213'
            ;;
        1)
            printf '\342\240\231'
            ;;
        2)
            printf '\342\240\271'
            ;;
        3)
            printf '\342\240\270'
            ;;
        4)
            printf '\342\240\274'
            ;;
        5)
            printf '\342\240\264'
            ;;
        6)
            printf '\342\240\246'
            ;;
        7)
            printf '\342\240\247'
            ;;
        8)
            printf '\342\240\207'
            ;;
        *)
            printf '\342\240\217'
            ;;
    esac
}

progress_tty_enabled() {
    [[ -t 2 && "${TERM:-}" != dumb && "${CONTAINER_PROGRESS:-auto}" != plain ]]
}

render_image_progress() {
    local action="$1" completed="$2" total="$3" failures="$4" tick="$5" tty_mode="$6"
    local build_completed="${7:-0}" build_total="${8:-0}"
    local preflight_completed="${9:-0}" preflight_total="${10:-0}" preflight_running="${11:-0}"
    local running=$((total - completed)) bar line spinner build_bar preflight_bar line_count i
    local lines=()
    bar="$(progress_bar_text "$completed" "$total")"
    if [[ "$tty_mode" == true && $running -gt 0 ]]; then
        spinner="$(progress_spinner "$tick")"
        lines+=("container image $action $spinner")
    else
        lines+=("container image $action")
    fi

    line="$(printf '  %s [%s] %d/%d done, %d running' "$(progress_label_text image "$tty_mode")" "$bar" "$completed" "$total" "$running")"
    if (( failures > 0 )); then
        line="$line, $failures failed"
    fi
    lines+=("$line")

    if (( build_total > 0 )); then
        build_bar="$(progress_bar_text "$build_completed" "$build_total")"
    elif (( preflight_total > 0 )); then
        build_bar="$(progress_bar_text 0 1)"
    fi
    if (( build_total > 0 || preflight_total > 0 )); then
        lines+=("  $(progress_label_text STEP "$tty_mode") [$build_bar] $build_completed/$build_total steps")
    fi

    if (( preflight_total > 0 )); then
        preflight_bar="$(progress_bar_text "$preflight_completed" "$preflight_total")"
        lines+=("  $(progress_label_text preflight "$tty_mode") [$preflight_bar] $preflight_completed/$preflight_total preflighted, $preflight_running running")
    fi

    if [[ "$tty_mode" == true ]]; then
        if (( ${IMAGE_PROGRESS_RENDERED_LINES:-0} > 0 )); then
            printf '\033[%dA' "$IMAGE_PROGRESS_RENDERED_LINES" >&2
        fi
        line_count="${#lines[@]}"
        for ((i = 0; i < line_count; i++)); do
            printf '\r\033[K%s\n' "${lines[$i]}" >&2
        done
        IMAGE_PROGRESS_RENDERED_LINES="$line_count"
    else
        printf '%s\n' "${lines[@]}" >&2
    fi
}

stderr_table_line() {
    local width
    printf '+' >&2
    for width in "$@"; do
        printf '%*s' "$((width + 2))" '' | tr ' ' '-' >&2
        printf '+' >&2
    done
    printf '\n' >&2
}

stderr_table_cell() {
    local text="$1" width="$2"
    printf ' %-*s ' "$width" "$text" >&2
}

image_action_log_pair() {
    local log_file="$1" err_file="$2" log_base err_base
    log_base="${log_file%.log}"
    err_base="${err_file%.err}"
    if [[ "$log_base" == "$err_base" ]]; then
        printf '%s.log/.err\n' "$log_base"
    else
        printf '%s / %s\n' "$log_file" "$err_file"
    fi
}

print_image_action_log_table() {
    local engines_name="$1" os_names_name="$2" log_files_name="$3" err_files_name="$4" rc_values_name="$5"
    local -n engines_ref="$engines_name"
    local -n os_ref="$os_names_name"
    local -n logs_ref="$log_files_name"
    local -n errs_ref="$err_files_name"
    local -n rcs_ref="$rc_values_name"
    local target logs status i
    local target_width=9 logs_width=4 status_width=6
    local targets=() log_pairs=() statuses=()

    for i in "${!os_ref[@]}"; do
        target="${engines_ref[$i]}/${os_ref[$i]}"
        logs="$(image_action_log_pair "${logs_ref[$i]}" "${errs_ref[$i]}")"
        if [[ "${rcs_ref[$i]}" -eq 0 ]]; then
            status="done"
        else
            status="failed"
        fi
        targets+=("$target")
        log_pairs+=("$logs")
        statuses+=("$status")
        update_width target_width "$target"
        update_width logs_width "$logs"
        update_width status_width "$status"
    done

    printf 'Container image action logs\n' >&2
    stderr_table_line "$target_width" "$logs_width" "$status_width"
    printf '|' >&2
    stderr_table_cell "Engine/OS" "$target_width"
    printf '|' >&2
    stderr_table_cell "Logs" "$logs_width"
    printf '|' >&2
    stderr_table_cell "Status" "$status_width"
    printf '|\n' >&2
    stderr_table_line "$target_width" "$logs_width" "$status_width"
    for i in "${!targets[@]}"; do
        printf '|' >&2
        stderr_table_cell "${targets[$i]}" "$target_width"
        printf '|' >&2
        stderr_table_cell "${log_pairs[$i]}" "$logs_width"
        printf '|' >&2
        stderr_table_cell "${statuses[$i]}" "$status_width"
        printf '|\n' >&2
    done
    stderr_table_line "$target_width" "$logs_width" "$status_width"
}

run_os_action_parallel() {
    local action="$1" force="$2"
    shift 2
    local engine_values_name="$1" os_values_name="$2"
    local -n engine_values_ref="$engine_values_name"
    local -n os_values_ref="$os_values_name"
    local log_dir timestamp status_dir total completed=0 failures=0 tick=0 changed
    local build_completed=0 build_total=0
    local preflight_started=0 preflight_completed=0 preflight_total=0 preflight_running=0
    local engine os_type image safe_name log_file err_file status_file pid rc tty_mode=false
    local pids=() engine_names=() os_names=() log_files=() err_files=() status_files=() rc_values=()
    IMAGE_PROGRESS_RENDERED_LINES=0

    log_dir="$(image_action_log_dir)"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    status_dir="$(mktemp -d)"
    total=$(( ${#engine_values_ref[@]} * ${#os_values_ref[@]} ))
    if image_action_uses_preflight "$action"; then
        preflight_total="$total"
    fi

    if progress_tty_enabled; then
        tty_mode=true
    fi

    for engine in "${engine_values_ref[@]}"; do
        for os_type in "${os_values_ref[@]}"; do
            image="$(image_for_os "$os_type")"
            safe_name="$(filename_safe "$engine-$image")"
            log_file="$log_dir/container-image-$action-$timestamp-$safe_name.log"
            err_file="$log_dir/container-image-$action-$timestamp-$safe_name.err"
            status_file="$status_dir/$safe_name.status"
            : >"$log_file"
            : >"$err_file"
            (
                set +e
                run_image_action_for_os "$action" "$force" "$engine" "$os_type" >"$log_file" 2>"$err_file"
                rc=$?
                printf '%d\n' "$rc" >"$status_file"
                exit "$rc"
            ) &
            pid="$!"
            pids+=("$pid")
            engine_names+=("$engine")
            os_names+=("$os_type")
            log_files+=("$log_file")
            err_files+=("$err_file")
            status_files+=("$status_file")
        done
    done

    build_step_progress_totals log_files rc_values build_completed build_total
    preflight_progress_totals log_files rc_values preflight_started preflight_completed
    preflight_running=$((preflight_started - preflight_completed))
    render_image_progress "$action" "$completed" "$total" "$failures" "$tick" "$tty_mode" "$build_completed" "$build_total" "$preflight_completed" "$preflight_total" "$preflight_running"
    while (( completed < total )); do
        sleep 0.2
        tick=$((tick + 1))
        changed=false
        for i in "${!pids[@]}"; do
            if [[ -n "${rc_values[$i]+set}" ]]; then
                continue
            fi
            if [[ -f "${status_files[$i]}" ]]; then
                rc="$(<"${status_files[$i]}")"
                rc_values[i]="$rc"
                completed=$((completed + 1))
                changed=true
                if [[ "$rc" -ne 0 ]]; then
                    failures=$((failures + 1))
                fi
            elif ! kill -0 "${pids[$i]}" 2>/dev/null; then
                set +e
                wait "${pids[$i]}"
                rc=$?
                set -e
                printf '%d\n' "$rc" >"${status_files[$i]}"
                rc_values[i]="$rc"
                completed=$((completed + 1))
                changed=true
                if [[ "$rc" -ne 0 ]]; then
                    failures=$((failures + 1))
                fi
            fi
        done
        if [[ "$tty_mode" == true || "$changed" == true ]]; then
            build_step_progress_totals log_files rc_values build_completed build_total
            preflight_progress_totals log_files rc_values preflight_started preflight_completed
            preflight_running=$((preflight_started - preflight_completed))
            render_image_progress "$action" "$completed" "$total" "$failures" "$tick" "$tty_mode" "$build_completed" "$build_total" "$preflight_completed" "$preflight_total" "$preflight_running"
        fi
    done

    IMAGE_PROGRESS_RENDERED_LINES=0

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    print_image_action_log_table engine_names os_names log_files err_files rc_values

    rm -rf "$status_dir"
    [[ "$failures" -eq 0 ]]
}

cmd_image() {
    local action="list" os_spec="" engine_spec="" force=false os_values=() engine_values=()
    if [[ $# -gt 0 && "$1" != --* ]]; then
        action="$1"
        shift
    fi

    case "$action" in
        create|update|list|clean)
            ;;
        help|-h|--help)
            image_usage
            return 0
            ;;
        *)
            die "unknown image action: $action"
            ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os)
                [[ $# -ge 2 ]] || die "--os needs all or an OS list"
                os_spec="$2"
                shift 2
                ;;
            --engine)
                [[ $# -ge 2 ]] || die "--engine needs all or an engine list"
                engine_spec="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                image_usage
                return 0
                ;;
            *)
                die "unknown image option: $1"
                ;;
        esac
    done

    if [[ "$action" == list && -z "$os_spec" ]]; then
        os_spec=all
    fi
    if [[ "$action" != list && -z "$os_spec" ]]; then
        die "--os is required for container image $action"
    fi

    mapfile -t os_values < <(parse_os_list "$os_spec")
    [[ ${#os_values[@]} -gt 0 ]] || die "no OS types selected"
    mapfile -t engine_values < <(parse_engine_list "$engine_spec")
    [[ ${#engine_values[@]} -gt 0 ]] || die "no container engines selected"

    if [[ "$action" == list ]]; then
        list_images_table engine_values os_values
        return 0
    fi

    if [[ "$force" == true ]]; then
        confirm_force_removal engine_values os_values
    fi

    run_os_action_parallel "$action" "$force" engine_values os_values
}

main() {
    local command="${1:-}"
    case "$command" in
        run)
            shift
            cmd_run "$@"
            ;;
        image)
            shift
            cmd_image "$@"
            ;;
        gui)
            shift
            exec bash "$SCRIPT_DIR/gui.sh" "$@"
            ;;
        help|-h|--help|"")
            top_usage
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac
}

main "$@"
