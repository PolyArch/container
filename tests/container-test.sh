#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILURES=0

fail() {
  printf 'not ok - %s\n' "$*" >&2
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "missing expected text: $needle"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "unexpected text present: $needle"
}

assert_status() {
  local actual="$1" expected="$2"
  [[ "$actual" -eq "$expected" ]] || fail "expected status $expected, got $actual"
}

first_container_log() {
  local pattern="$1"
  find "$EDA_TEST_HOME/.cache/container" -type f -name "$pattern" -print 2>/dev/null | sort | head -n1
}

first_container_err() {
  local pattern="$1"
  find "$EDA_TEST_HOME/.cache/container" -type f -name "$pattern" -print 2>/dev/null | sort | head -n1
}

assert_file_contains() {
  local file="$1" needle="$2"
  [[ -f "$file" ]] || fail "missing expected file: $file"
  grep -Fq -- "$needle" "$file" || fail "missing expected text in $file: $needle"
}

containerfile_hash() {
  sha256sum "$REPO_ROOT/images/$1.containerfile" | awk '{print substr($1, 1, 12)}'
}

image_name() {
  local os_type="$1"
  printf 'ucla.edu/polyarch/container-%s-%s:latest' "$os_type" "$(containerfile_hash "$os_type")"
}

setup_fake_podman() {
  setup_fake_engines podman
}

setup_fake_engines() {
  local tmp bin_dir
  tmp="$(mktemp -d)"
  bin_dir="$tmp/bin"
  mkdir -p "$bin_dir" "$tmp/home" "$tmp/caller" "$tmp/images" "$tmp/used"
  : >"$tmp/commands"
  : >"$tmp/images/podman"
  : >"$tmp/images/docker"
  : >"$tmp/used/podman"
  : >"$tmp/used/docker"
  : >"$tmp/host.xauth"

  cat >"$bin_dir/container-engine" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENGINE="$(basename "$0")"
IMAGES_FILE="$EDA_TEST_IMAGES_DIR/$ENGINE"
USED_FILE="$EDA_TEST_USED_DIR/$ENGINE"

if [[ "${1:-}" == "--version" ]]; then
  printf '%s fake engine\n' "$ENGINE"
  exit 0
fi

log_command() {
  printf '%s' "$ENGINE" >>"$EDA_TEST_COMMANDS"
  for arg in "$@"; do
    printf '[%s]' "$arg" >>"$EDA_TEST_COMMANDS"
  done
  printf '\n' >>"$EDA_TEST_COMMANDS"
}

image_is_present() {
  local image="$1"
  awk -F'|' -v image="$image" '$1 == image {found=1} END {exit found ? 0 : 1}' "$IMAGES_FILE"
}

containers_for_image() {
  local image="$1"
  awk -F'|' -v image="$image" '$1 == image {print $2}' "$USED_FILE" \
    | tr ' ' '\n' \
    | sed '/^$/d'
}

log_command "$@"

case "${1:-}" in
  image)
    if [[ "${2:-}" == exists ]]; then
      image_is_present "${3:-}" && exit 0
      exit 1
    fi
    if [[ "${2:-}" == inspect ]]; then
      image_is_present "${3:-}" && exit 0
      exit 1
    fi
    ;;
  images)
    cat "$IMAGES_FILE"
    exit 0
    ;;
  ps)
    ancestor=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --filter)
          case "${2:-}" in
            ancestor=*)
              ancestor="${2#ancestor=}"
              ;;
          esac
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "$ancestor" ]] && containers_for_image "$ancestor"
    exit 0
    ;;
  rmi)
    shift
    printf 'fake rmi %s\n' "$*"
    printf 'fake rmi err %s\n' "$*" >&2
    exit 0
    ;;
  rm)
    shift
    printf 'fake rm %s\n' "$*"
    exit 0
    ;;
  build)
    printf 'STEP 1/3: FROM fake\n'
    printf 'STEP 2/3: RUN fake\n'
    printf 'STEP 3/3: CMD fake\n'
    printf 'fake build log\n'
    printf 'fake build err\n' >&2
    exit 0
    ;;
  run)
    exit 0
    ;;
  network)
    case "${2:-}" in
      exists)
        exit 0
        ;;
      create|rm|ls)
        exit 0
        ;;
    esac
    ;;
esac

exit 0
EOF
  chmod +x "$bin_dir/container-engine"
  cat >"$bin_dir/unavailable-engine" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "$bin_dir/unavailable-engine"

  local engine have_docker=false have_podman=false
  for engine in "$@"; do
    ln -s "$bin_dir/container-engine" "$bin_dir/$engine"
    case "$engine" in
      docker)
        have_docker=true
        ;;
      podman)
        have_podman=true
        ;;
    esac
  done
  if [[ "$have_docker" != true ]]; then
    ln -s "$bin_dir/unavailable-engine" "$bin_dir/docker"
  fi
  if [[ "$have_podman" != true ]]; then
    ln -s "$bin_dir/unavailable-engine" "$bin_dir/podman"
  fi

  cat >"$bin_dir/lsmod" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
ip_tables 1
iptable_filter 1
nf_conntrack 1
OUT
EOF
  chmod +x "$bin_dir/lsmod"

  cat >"$bin_dir/timedatectl" <<'EOF'
#!/usr/bin/env bash
printf 'America/Los_Angeles\n'
EOF
  chmod +x "$bin_dir/timedatectl"

  cat >"$bin_dir/xauth" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  nlist)
    printf 'ffff 0000 fake-cookie\n'
    ;;
  -f)
    cat >/dev/null
    : >"${2:-/dev/null}"
    ;;
esac
EOF
  chmod +x "$bin_dir/xauth"

  EDA_TEST_TMP="$tmp"
  EDA_TEST_BIN="$bin_dir"
  EDA_TEST_COMMANDS="$tmp/commands"
  EDA_TEST_IMAGES_DIR="$tmp/images"
  EDA_TEST_USED_DIR="$tmp/used"
  EDA_TEST_IMAGES="$tmp/images/podman"
  EDA_TEST_DOCKER_IMAGES="$tmp/images/docker"
  EDA_TEST_USED="$tmp/used/podman"
  EDA_TEST_HOME="$tmp/home"
  EDA_TEST_CALLER="$tmp/caller"
  EDA_TEST_HOST_XAUTH="$tmp/host.xauth"
}

cleanup_fake_podman() {
  rm -rf "${EDA_TEST_TMP:-}"
  unset EDA_TEST_TMP EDA_TEST_BIN EDA_TEST_COMMANDS EDA_TEST_IMAGES_DIR EDA_TEST_USED_DIR
  unset EDA_TEST_IMAGES EDA_TEST_DOCKER_IMAGES EDA_TEST_USED
  unset EDA_TEST_HOME EDA_TEST_CALLER EDA_TEST_HOST_XAUTH
}

run_container_cli() {
  local output status
  set +e
  if [[ -n "${EDA_TEST_INPUT+x}" ]]; then
    output="$(
      printf '%s' "$EDA_TEST_INPUT" | \
      PATH="$EDA_TEST_BIN:$PATH" \
      HOME="$EDA_TEST_HOME" \
      USER="edauser" \
      CALLER_PWD="$EDA_TEST_CALLER" \
      DISPLAY=":0" \
      XAUTHORITY="$EDA_TEST_HOST_XAUTH" \
      CUSTOM_EDA_TEST_VAR="present" \
      MODULEPATH="/mnt/nas0/software/modulefiles" \
      SNPS_CONTAINER_TEST="drop" \
      EDA_TEST_COMMANDS="$EDA_TEST_COMMANDS" \
      EDA_TEST_IMAGES_DIR="$EDA_TEST_IMAGES_DIR" \
      EDA_TEST_USED_DIR="$EDA_TEST_USED_DIR" \
      bash "$REPO_ROOT/container.sh" "$@" 2>&1
    )"
  else
    output="$(
      PATH="$EDA_TEST_BIN:$PATH" \
      HOME="$EDA_TEST_HOME" \
      USER="edauser" \
      CALLER_PWD="$EDA_TEST_CALLER" \
      DISPLAY=":0" \
      XAUTHORITY="$EDA_TEST_HOST_XAUTH" \
      CUSTOM_EDA_TEST_VAR="present" \
      MODULEPATH="/mnt/nas0/software/modulefiles" \
      SNPS_CONTAINER_TEST="drop" \
      EDA_TEST_COMMANDS="$EDA_TEST_COMMANDS" \
      EDA_TEST_IMAGES_DIR="$EDA_TEST_IMAGES_DIR" \
      EDA_TEST_USED_DIR="$EDA_TEST_USED_DIR" \
      bash "$REPO_ROOT/container.sh" "$@" 2>&1
    )"
  fi
  status=$?
  set -e
  EDA_TEST_LAST_OUTPUT="$output"
  EDA_TEST_LAST_STATUS="$status"
  unset EDA_TEST_INPUT
}

commands() {
  cat "$EDA_TEST_COMMANDS"
}

container_xauthority_from_commands() {
  sed -n 's/.*\[-e\]\[XAUTHORITY=\([^]]*\)\].*/\1/p' "$EDA_TEST_COMMANDS" | head -n1
}

test_container_cli_is_standalone() {
  local output
  output="$(bash "$REPO_ROOT/container.sh" help)"
  assert_contains "$output" "PolyArch container v0.1.0 (https://github.com/PolyArch/container)" || return 1
  assert_contains "$output" "container run" || return 1
  assert_contains "$output" "container image" || return 1
  assert_contains "$output" "container gui" || return 1
}

test_version_variants_are_exact_and_side_effect_free() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local expected="PolyArch container v0.1.0 (https://github.com/PolyArch/container)"

  run_container_cli --version
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  [[ "$EDA_TEST_LAST_OUTPUT" == "$expected" ]] \
    || { fail "unexpected --version output: $EDA_TEST_LAST_OUTPUT"; return 1; }

  run_container_cli -V
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  [[ "$EDA_TEST_LAST_OUTPUT" == "$expected" ]] \
    || { fail "unexpected -V output: $EDA_TEST_LAST_OUTPUT"; return 1; }

  [[ ! -s "$EDA_TEST_COMMANDS" ]] \
    || { fail "version output should not call podman"; return 1; }
}

test_run_defaults_to_inherit_env_and_host_network() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work"
  mkdir -p "$workdir"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli run --os almalinux8 --workdir "$workdir" -- echo hello

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[run]" || return 1
  assert_not_contains "$log" "[-it]" || return 1
  assert_contains "$log" "[--network=host]" || return 1
  assert_contains "$log" "[-v][$workdir:/home/edauser/work:rw]" || return 1
  assert_not_contains "$log" "[-v][$workdir:/home/edauser:rw]" || return 1
  [[ ! -e "$EDA_TEST_HOME/.achronix/.accept" ]] || {
    fail "run should not create an Achronix accept file"
    return 1
  }
  assert_not_contains "$log" ".achronix/.accept" || return 1
  assert_contains "$log" "[-e][DISPLAY=:0]" || return 1
  assert_not_contains "$log" "[-e][XAUTHORITY=$EDA_TEST_HOST_XAUTH]" || return 1
  local container_xauth
  container_xauth="$(container_xauthority_from_commands)"
  [[ "$container_xauth" == /tmp/.docker.xauth_edauser_* ]] || {
    fail "container XAUTHORITY should use generated xauth file, got: $container_xauth"
    return 1
  }
  assert_contains "$log" "[-v][$container_xauth:$container_xauth:rw]" || return 1
  assert_contains "$log" "[-e][CUSTOM_EDA_TEST_VAR=present]" || return 1
  assert_contains "$log" "[-e][MODULEPATH=/mnt/nas0/software/modulefiles]" || return 1
  assert_not_contains "$log" "[-e][SNPS_CONTAINER_TEST=drop]" || return 1
  assert_contains "$log" "[$(image_name almalinux8)]" || return 1
  assert_not_contains "$log" "[--build-only]" || return 1
}

test_run_requires_os() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work"
  mkdir -p "$workdir"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli run --workdir "$workdir"

  [[ "$EDA_TEST_LAST_STATUS" -ne 0 ]] || { fail "run without --os should fail"; return 1; }
  assert_contains "$EDA_TEST_LAST_OUTPUT" "--os is required for container run" || return 1
  [[ ! -s "$EDA_TEST_COMMANDS" ]] || { fail "run without --os should not call container engine"; return 1; }
}

test_run_mounts_existing_achronix_accept_file_with_license_marker() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work" accept_file="$EDA_TEST_HOME/.achronix/.accept"
  mkdir -p "$workdir" "$(dirname "$accept_file")"
  printf 'Achronix_License=2099\ncustom-setting=yes\n' >"$accept_file"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli run --os almalinux8 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  [[ "$(<"$accept_file")" == $'Achronix_License=2099\ncustom-setting=yes' ]] || {
    fail "existing Achronix accept file was modified"
    return 1
  }
  assert_contains "$(commands)" "[-v][$accept_file:/home/edauser/.achronix/.accept:ro]" || return 1
}

test_run_skips_existing_achronix_file_without_license_marker() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work" accept_file="$EDA_TEST_HOME/.achronix/.accept"
  mkdir -p "$workdir" "$(dirname "$accept_file")"
  printf 'custom-setting=yes\n' >"$accept_file"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli run --os almalinux8 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  [[ "$(<"$accept_file")" == "custom-setting=yes" ]] || {
    fail "existing Achronix file was modified"
    return 1
  }
  assert_not_contains "$(commands)" ".achronix/.accept" || return 1
}

test_run_seeds_container_history_from_host_history_files() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work"
  mkdir -p "$workdir" "$EDA_TEST_HOME/.dirhistory"
  printf ': 1:0;echo host zsh\n' >"$EDA_TEST_HOME/.zsh_history"
  printf 'echo host bash\n' >"$EDA_TEST_HOME/.bash_history"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli run --os almalinux8 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "[-v][$EDA_TEST_HOME/.zsh_history:/tmp/container-host-history-.zsh_history:ro]" || return 1
  assert_contains "$log" "[-v][$EDA_TEST_HOME/.bash_history:/tmp/container-host-history-.bash_history:ro]" || return 1
  assert_not_contains "$log" "[-v][$EDA_TEST_HOME/.dirhistory:" || return 1
  assert_contains "$log" "[-e][CONTAINER_HOME=/home/edauser]" || return 1
  assert_contains "$log" "for src in /tmp/container-host-history-.*history; do" || return 1
  # shellcheck disable=SC2016
  assert_contains "$log" 'cp -f -- "$src" "$target_home/$name"' || return 1
}

test_run_default_workdir_mounts_under_container_work() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  printf '%s\n' "$(image_name almalinux9)" >"$EDA_TEST_IMAGES"

  run_container_cli run --os almalinux9

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Created work directory:" || return 1
  local created_workdir log
  created_workdir="${EDA_TEST_LAST_OUTPUT#*Created work directory: }"
  created_workdir="${created_workdir%%$'\n'*}"
  [[ -d "$created_workdir" ]] || { fail "missing created work directory"; return 1; }

  log="$(commands)"
  assert_contains "$log" "[-v][$created_workdir:/home/edauser/work:rw]" || return 1
  assert_not_contains "$log" "[-v][$created_workdir:/home/edauser:rw]" || return 1
  assert_not_contains "$log" "/tmp/container-zdotdir" || return 1
  assert_not_contains "$log" "[ZDOTDIR=/tmp/container-zdotdir]" || return 1
}

test_run_uses_env_file_and_restricted_network() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work" env_file
  mkdir -p "$workdir"
  env_file="$EDA_TEST_TMP/tool.env"
  printf 'CDS_LIC_FILE=27022@example.license.server\n' >"$env_file"
  printf 'SNPS_CONTAINER_FROM_FILE=drop\n' >>"$env_file"
  printf '%s\n' "$(image_name almalinux9)" >"$EDA_TEST_IMAGES"

  run_container_cli run --env "$env_file" --network no --os almalinux9 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "[-v][$workdir:/home/edauser/work:rw]" || return 1
  assert_contains "$log" "[--network=container-restricted]" || return 1
  assert_contains "$log" "[--entrypoint][/usr/local/bin/container-egress.sh]" || return 1
  assert_contains "$log" "[-e][CDS_LIC_FILE=27022@example.license.server]" || return 1
  assert_not_contains "$log" "[-e][CUSTOM_EDA_TEST_VAR=present]" || return 1
  assert_not_contains "$log" "[-e][SNPS_CONTAINER_FROM_FILE=drop]" || return 1
}

test_run_selects_available_container_engine() {
  setup_fake_engines docker podman
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work"
  mkdir -p "$workdir"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"
  printf '%s\n' "$(image_name almalinux8)" >"$EDA_TEST_DOCKER_IMAGES"

  run_container_cli run --os almalinux8 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$(commands)" "podman[run]" || return 1
  assert_not_contains "$(commands)" "docker[run]" || return 1

  : >"$EDA_TEST_COMMANDS"
  run_container_cli run --engine docker --os almalinux8 --workdir "$workdir"

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "docker[image][inspect][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "docker[run]" || return 1
  assert_not_contains "$log" "podman[run]" || return 1
}

test_run_errors_when_no_container_engine_is_available() {
  setup_fake_engines
  trap cleanup_fake_podman RETURN
  local workdir="$EDA_TEST_TMP/work"
  mkdir -p "$workdir"

  run_container_cli run --os almalinux8 --workdir "$workdir"

  [[ "$EDA_TEST_LAST_STATUS" -ne 0 ]] || { fail "run without container engine should fail"; return 1; }
  assert_contains "$EDA_TEST_LAST_OUTPUT" "install docker or podman" || return 1
}

test_run_lists_os_types_and_rejects_build_only() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN

  run_container_cli run --os list
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "oraclelinux7" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "centos7" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux8" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux9" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux10" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "rockylinux8" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "rockylinux9" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "rockylinux10" || return 1
  [[ ! -s "$EDA_TEST_COMMANDS" ]] || { fail "OS listing should not call podman"; return 1; }

  run_container_cli run --build-only
  [[ "$EDA_TEST_LAST_STATUS" -ne 0 ]] || { fail "run --build-only should fail"; return 1; }
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image create" || return 1
}

test_help_variants_are_detailed_and_side_effect_free() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN

  run_container_cli help
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "PolyArch container v0.1.0 (https://github.com/PolyArch/container)" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Usage:" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container run" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image" || return 1
  [[ ! -s "$EDA_TEST_COMMANDS" ]] || { fail "top-level help should not call podman"; return 1; }

  run_container_cli run -h
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Usage:" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container run [OPTIONS]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "--env INHERIT|FILE" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "--network yes|no" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "Image actions:" || return 1

  run_container_cli run --help
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container run [OPTIONS]" || return 1

  run_container_cli run help
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container run [OPTIONS]" || return 1

  run_container_cli image -h
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Usage:" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image [create|update|list|clean]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Image actions:" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "--force" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "Run options:" || return 1

  run_container_cli image --help
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image [create|update|list|clean]" || return 1

  run_container_cli image help
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image [create|update|list|clean]" || return 1
}

test_image_create_builds_hashed_image() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN

  run_container_cli image create --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[image][exists][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "podman[build][-t][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "podman[run][--rm][--pull=never][--userns=keep-id]" || return 1
  assert_contains "$log" "[$(image_name almalinux8)][/usr/bin/true]" || return 1
  assert_contains "$log" "[-f][$REPO_ROOT/images/almalinux8.containerfile]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image create" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  image     [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  STEP      [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  preflight [" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" " | build [" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" " | preflight [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "3/3 steps" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "preflight [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 preflighted" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "$EDA_TEST_HOME/.cache/container/container-image-create-" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake build log" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake build err" || return 1
  local image_log
  image_log="$(first_container_log 'container-image-create-*.log')"
  [[ -n "$image_log" ]] || { fail "missing create log"; return 1; }
  assert_file_contains "$image_log" "Building $(image_name almalinux8)" || return 1
  assert_file_contains "$image_log" "Preflighting podman rootfs for $(image_name almalinux8)" || return 1
  assert_file_contains "$image_log" "STEP 1/3: FROM fake" || return 1
  assert_file_contains "$image_log" "fake build log" || return 1
  assert_not_contains "$(cat "$image_log")" "fake build err" || return 1
  local image_err
  image_err="$(first_container_err 'container-image-create-*.err')"
  [[ -n "$image_err" ]] || { fail "missing create err"; return 1; }
  assert_file_contains "$image_err" "fake build err" || return 1
  assert_not_contains "$(cat "$image_err")" "fake build log" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Container image action logs" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Engine/OS" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Logs" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Status" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "podman/almalinux8" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "${image_log%.log}.log/.err" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "done" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "done-with-stderr" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "stdout=" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "stderr=" || return 1
}

test_image_progress_spinner_uses_braille_frames() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local output status expected_spinner
  expected_spinner=$'\342\240\213'

  set +e
  # shellcheck disable=SC2016
  output="$(
    PATH="$EDA_TEST_BIN:$PATH" \
    HOME="$EDA_TEST_HOME" \
    TERM="xterm-256color" \
    USER="edauser" \
    CALLER_PWD="$EDA_TEST_CALLER" \
    CUSTOM_EDA_TEST_VAR="present" \
    EDA_TEST_COMMANDS="$EDA_TEST_COMMANDS" \
    EDA_TEST_IMAGES_DIR="$EDA_TEST_IMAGES_DIR" \
    EDA_TEST_USED_DIR="$EDA_TEST_USED_DIR" \
    script -qefc "bash '$REPO_ROOT/container.sh' image create --os almalinux8" /dev/null 2>&1
  )"
  status=$?
  set -e

  assert_status "$status" 0 || return 1
  assert_contains "$output" "$expected_spinner" || return 1
}

test_image_list_reports_image_status_by_os() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  {
    printf '%s|img-alma8|12 minutes ago|123.45 GB\n' "$(image_name almalinux8)"
    printf '%s|img-alma9-old|3 weeks ago|2.40 GB\n' "ucla.edu/polyarch/container-almalinux9-oldhash:latest"
  } >"$EDA_TEST_IMAGES"
  printf '%s|ctr-a ctr-b\n' "ucla.edu/polyarch/container-almalinux9-oldhash:latest" >"$EDA_TEST_USED"

  run_container_cli image list

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" $'\033[' || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Container image status" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "Container image versions" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "+----------+---------------+----------+--------------+--------------+---------------+" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "| Engine   | OS            | Status   | Current Hash | Image Hash   | Image ID" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "Image (All starts with \`ucla.edu/polyarch/container-\`)" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux8" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "current" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "$(containerfile_hash almalinux8)" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "123.45 GB" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "12 minutes ago" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux8-$(containerfile_hash almalinux8):latest" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux9" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "stale" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "oldhash" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "2.40 GB" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "3 weeks ago" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "123..." || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "12 minute..." || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "oraclelinux7" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "missing" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "oraclelinux7-$(containerfile_hash oraclelinux7):latest" || return 1

  run_container_cli image list --os all
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux10" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "gui" || return 1

  run_container_cli image --os all
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "almalinux10" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "gui" || return 1
}

test_image_list_and_create_cover_engine_matrix() {
  setup_fake_engines docker podman
  trap cleanup_fake_podman RETURN
  printf '%s|dockalma8|5 minutes ago|1.00 GB\n' "$(image_name almalinux8)" >"$EDA_TEST_DOCKER_IMAGES"
  printf '%s|podalma8|6 minutes ago|1.01 GB\n' "$(image_name almalinux8)" >"$EDA_TEST_IMAGES"

  run_container_cli image list --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "docker" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "podman" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "dockalma8" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "podalma8" || return 1

  : >"$EDA_TEST_COMMANDS"
  run_container_cli image create --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "docker[image][inspect][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "podman[image][exists][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "docker[run][--rm][--pull=never]" || return 1
  assert_not_contains "$log" "docker[run][--rm][--pull=never][--userns=keep-id]" || return 1
  assert_contains "$log" "podman[run][--rm][--pull=never][--userns=keep-id]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "2/2 done" || return 1

  : >"$EDA_TEST_COMMANDS"
  : >"$EDA_TEST_DOCKER_IMAGES"
  run_container_cli image create --engine docker --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  log="$(commands)"
  assert_contains "$log" "docker[build][-t][$(image_name almalinux8)]" || return 1
  assert_contains "$log" "docker[run][--rm][--pull=never]" || return 1
  assert_not_contains "$log" "podman[build]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
}

test_containerfiles_support_module_initialization() {
  local os_type containerfile
  while IFS= read -r os_type; do
    containerfile="$REPO_ROOT/images/$os_type.containerfile"
    grep -Eiq "environment[- ]modules|Lmod|modules_version" "$containerfile" \
      || fail "missing module system package in $containerfile" || return 1
    assert_file_contains "$containerfile" "/etc/profile.d/modules.sh" || return 1
  done < <("$REPO_ROOT/container.sh" run --os list)
}

test_image_requires_os_except_list() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN

  run_container_cli image clean

  [[ "$EDA_TEST_LAST_STATUS" -ne 0 ]] || { fail "image clean without --os should fail"; return 1; }
  assert_contains "$EDA_TEST_LAST_OUTPUT" "--os is required" || return 1
}

test_image_clean_skips_used_images_without_force() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local image
  image="$(image_name almalinux8)"
  printf '%s\n' "$image" >"$EDA_TEST_IMAGES"
  printf '%s|ctr-a ctr-b\n' "$image" >"$EDA_TEST_USED"

  run_container_cli image clean --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "Warning:" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image clean" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  image     [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "$EDA_TEST_HOME/.cache/container/container-image-clean-" || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[ps][-a][--filter][ancestor=$image]" || return 1
  assert_not_contains "$log" "podman[rmi]" || return 1
  local image_log
  image_log="$(first_container_log 'container-image-clean-*.log')"
  [[ -n "$image_log" ]] || { fail "missing clean log"; return 1; }
  assert_file_contains "$image_log" "podman/almalinux8: removed=0 skipped=1" || return 1
  assert_not_contains "$(cat "$image_log")" "Warning:" || return 1
  local image_err
  image_err="$(first_container_err 'container-image-clean-*.err')"
  [[ -n "$image_err" ]] || { fail "missing clean err"; return 1; }
  assert_file_contains "$image_err" "Warning:" || return 1
}

test_image_clean_force_requires_confirmation_for_used_images() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local image
  image="$(image_name almalinux8)"
  printf '%s\n' "$image" >"$EDA_TEST_IMAGES"
  printf '%s|ctr-a\n' "$image" >"$EDA_TEST_USED"

  EDA_TEST_INPUT=$'n\n' run_container_cli image clean --os almalinux8 --force
  [[ "$EDA_TEST_LAST_STATUS" -ne 0 ]] || { fail "declined force clean should fail"; return 1; }
  assert_not_contains "$(commands)" "podman[rm][-f][ctr-a]" || return 1

  : >"$EDA_TEST_COMMANDS"
  EDA_TEST_INPUT=$'y\n' run_container_cli image clean --os almalinux8 --force
  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image clean" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  image     [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "$EDA_TEST_HOME/.cache/container/container-image-clean-" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake rm -f ctr-a" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake rmi -f $image" || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[rm][-f][ctr-a]" || return 1
  assert_contains "$log" "podman[rmi][-f][$image]" || return 1
  local image_log
  image_log="$(first_container_log 'container-image-clean-*.log')"
  [[ -n "$image_log" ]] || { fail "missing clean log"; return 1; }
  assert_file_contains "$image_log" "fake rm -f ctr-a" || return 1
  assert_file_contains "$image_log" "fake rmi -f $image" || return 1
  assert_not_contains "$(cat "$image_log")" "fake rmi err -f $image" || return 1
  local image_err
  image_err="$(first_container_err 'container-image-clean-*.err')"
  [[ -n "$image_err" ]] || { fail "missing clean err"; return 1; }
  assert_file_contains "$image_err" "fake rmi err -f $image" || return 1
}

test_image_update_cleans_before_create() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local stale
  stale="ucla.edu/polyarch/container-almalinux8-oldhash:latest"
  printf '%s\n' "$stale" >"$EDA_TEST_IMAGES"

  run_container_cli image update --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[rmi][$stale]" || return 1
  assert_contains "$log" "podman[build][-t][$(image_name almalinux8)]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image update" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  image     [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  STEP      [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  preflight [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "3/3 steps" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "$EDA_TEST_HOME/.cache/container/container-image-update-" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake rmi $stale" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake rmi err $stale" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake build log" || return 1
  assert_not_contains "$EDA_TEST_LAST_OUTPUT" "fake build err" || return 1
  local image_log
  image_log="$(first_container_log 'container-image-update-*.log')"
  [[ -n "$image_log" ]] || { fail "missing update log"; return 1; }
  assert_file_contains "$image_log" "fake rmi $stale" || return 1
  assert_file_contains "$image_log" "STEP 1/3: FROM fake" || return 1
  assert_file_contains "$image_log" "fake build log" || return 1
  assert_not_contains "$(cat "$image_log")" "fake rmi err $stale" || return 1
  local image_err
  image_err="$(first_container_err 'container-image-update-*.err')"
  [[ -n "$image_err" ]] || { fail "missing update err"; return 1; }
  assert_file_contains "$image_err" "fake rmi err $stale" || return 1
  assert_file_contains "$image_err" "fake build err" || return 1
}

test_image_update_skips_current_images() {
  setup_fake_podman
  trap cleanup_fake_podman RETURN
  local image
  image="$(image_name almalinux8)"
  printf '%s\n' "$image" >"$EDA_TEST_IMAGES"

  run_container_cli image update --os almalinux8

  assert_status "$EDA_TEST_LAST_STATUS" 0 || return 1
  local log
  log="$(commands)"
  assert_contains "$log" "podman[image][exists][$image]" || return 1
  assert_not_contains "$log" "podman[rmi]" || return 1
  assert_not_contains "$log" "podman[build]" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "container image update" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  image     [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  STEP      [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "  preflight [" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 done" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "0/0 steps" || return 1
  assert_contains "$EDA_TEST_LAST_OUTPUT" "1/1 preflighted" || return 1
  local image_log
  image_log="$(first_container_log 'container-image-update-*.log')"
  [[ -n "$image_log" ]] || { fail "missing update log"; return 1; }
  assert_file_contains "$image_log" "podman/almalinux8: current image exists; update skipped" || return 1
}

run_test() {
  local name="$1"
  if "$name"; then
    printf 'ok - %s\n' "$name"
  else
    FAILURES=$((FAILURES + 1))
  fi
}

run_test test_container_cli_is_standalone
run_test test_version_variants_are_exact_and_side_effect_free
run_test test_run_defaults_to_inherit_env_and_host_network
run_test test_run_requires_os
run_test test_run_mounts_existing_achronix_accept_file_with_license_marker
run_test test_run_skips_existing_achronix_file_without_license_marker
run_test test_run_seeds_container_history_from_host_history_files
run_test test_run_default_workdir_mounts_under_container_work
run_test test_run_uses_env_file_and_restricted_network
run_test test_run_selects_available_container_engine
run_test test_run_errors_when_no_container_engine_is_available
run_test test_run_lists_os_types_and_rejects_build_only
run_test test_help_variants_are_detailed_and_side_effect_free
run_test test_image_create_builds_hashed_image
run_test test_image_progress_spinner_uses_braille_frames
run_test test_image_list_reports_image_status_by_os
run_test test_image_list_and_create_cover_engine_matrix
run_test test_containerfiles_support_module_initialization
run_test test_image_requires_os_except_list
run_test test_image_clean_skips_used_images_without_force
run_test test_image_clean_force_requires_confirmation_for_used_images
run_test test_image_update_cleans_before_create
run_test test_image_update_skips_current_images

if [[ "$FAILURES" -gt 0 ]]; then
  printf 'not ok - container tests (%d failed)\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok - container tests\n'
