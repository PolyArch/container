# Container Tooling

This directory contains a self-contained container CLI for tool runtime images,
image maintenance, and local GUI display containers. The current image set is
optimized for EDA tools, but the entrypoint is intentionally generic:

```bash
container [run|image|gui]
```

Run `./setup.sh` to expose this repository's `container.sh` as
`~/.local/bin/container`, or run `./container.sh` directly from this checkout.

## Run Containers

```bash
container run --os almalinux8
container run --os almalinux9
container run --engine docker --os rockylinux9
container run --os almalinux9 --workdir /path/to/project -- vivado -mode gui
container run --os almalinux9 --env ./tool.env --network no -- vcs -full64 top.v
container run --os list
```

Run options:

| Option | Description |
| --- | --- |
| `--env INHERIT` | Pass host environment variables into the container. This is the default. |
| `--env <file>` | Load variables from an environment file instead of inheriting the host environment. |
| `--workdir <dir>` | Mount `<dir>` as `~/work` inside the container. |
| `--os <type>` | Required. Select the container OS. Use `--os list` to show supported values. |
| `--engine docker|podman` | Select the container engine when both are installed. Defaults to Podman when available. |
| `--network yes` | Use host networking. This is the default. |
| `--network no` | Use the restricted `container-restricted` network. |
| `--` | Separate `container run` options from the command to run in the container. |

If `--workdir` is omitted, `container run` creates a `container-work_*`
directory under the caller directory and mounts it as `~/work`.

If the current image for the selected OS is missing, `container run` builds it
from the matching `images/*.containerfile` before launching the container.

Host environment variables whose names start with `SNPS_CONTAINER` are not
passed into the container. The command wrapper also unsets any
`SNPS_CONTAINER*` variables already present inside the image before launching
the requested command.

## Manage Images

```bash
container image list
container image list --os all
container image --os all
container image create --os all
container image create --engine docker --os centos7,rockylinux8
container image update --os oraclelinux7,almalinux8
container image clean --os almalinux9
container image clean --os all --force
```

Help is available at each level:

```bash
container help
container run -h
container run --help
container image -h
container image --help
container gui -h
container gui --help
```

Image actions:

| Action | Description |
| --- | --- |
| `list` | Show image status for each selected OS. Defaults to `--os all`. |
| `create` | Build the current image for each selected OS if it does not already exist, then preflight container startup. |
| `update` | Build missing or stale current images, then preflight container startup. Current images skip rebuild but still run preflight. |
| `clean` | Remove selected OS images. Images used by containers are skipped unless `--force` is used. |

Image options:

| Option | Description |
| --- | --- |
| `--os all` | Select every supported runtime OS image plus the GUI image. Required for every action except `list`. |
| `--os <type>[,<type>...]` | Select one or more image types, such as `almalinux9` or `gui`. |
| `--engine all` | Select every installed container engine. This is the default. |
| `--engine <engine>[,<engine>...]` | Select one or more installed container engines. |
| `--force` | Remove containers that use target images, after a `[y/N]` confirmation. |

`images/*.containerfile` files are the source of truth. The eight runtime OS
images support tool execution, and `images/gui.containerfile` defines the
dedicated Xvnc desktop image used by `container gui`. Image names include the
containerfile hash:

```text
ucla.edu/polyarch/container-<OS>-<containerfile-hash>:latest
ucla.edu/polyarch/container-gui-<containerfile-hash>:latest
```

When Docker is selected, `container image create` and `container image update`
build from a temporary file named `Dockerfile` whose contents are copied from
the selected `*.containerfile`. The hash still comes from the `*.containerfile`.

After `create` or `update`, `container` starts a short-lived container for each
target image. For Podman this uses `--userns=keep-id`, so rootless ID-mapped
rootfs setup happens during image maintenance instead of the first interactive
`container run`.

Supported OS values are:

```text
oraclelinux7
centos7
almalinux8
rockylinux8
almalinux9
rockylinux9
almalinux10
rockylinux10
```

`container image list` reports one status table with the selected OS, current
container engine, containerfile hash, local image hash, image ID, image size,
creation age, container use count, and image name. Multiple rows for the same
engine and OS represent multiple local image versions. Missing images are shown
as `missing`.

It prints colored tables by default. Set `CONTAINER_COLOR=never` to disable
color. Set `CONTAINER_PROGRESS=plain` to disable TTY progress redraw.

Image action stdout and stderr are written separately under:

```text
$HOME/.cache/container/container-image-<ACTION>-<date-time>-<engine-image>.log
$HOME/.cache/container/container-image-<ACTION>-<date-time>-<engine-image>.err
```

## GUI Containers

`container gui` manages local Xvnc-backed GUI containers:

```bash
container gui start eda --resolution 2560x1440 --port 2
container gui create eda --resolution 2560x1440 --port 2
container gui start eda --engine podman --resolution 2560x1440 --port 2
container gui status eda
container gui check eda
container gui list
container gui stop eda
container gui restart eda
container gui remove eda
container gui delete eda
container gui use help
container gui use eda screenshot --output /tmp/eda.png
container gui use eda click --x 120 --y 240
container gui use eda sequence --input actions.json
```

The GUI image is built locally from `images/gui.containerfile` as
`ucla.edu/polyarch/container-gui-<containerfile-hash>:latest`. `xfce` is the
default desktop and `openbox` is a lightweight fallback inside the same GUI
image.
Use `--engine docker|podman` to select the GUI container engine. If omitted,
`container gui` defaults to Podman when available, then Docker.
Managed GUI container names always use the `container-gui-*` prefix. A command
such as `container gui start eda` creates `container-gui-eda`; omitting the name
creates `container-gui-YYYYMMDD-hhmmss`.
`container gui create` is an alias for `start`, and `container gui delete` is an
alias for `remove`.

`container gui use` sends Computer Use actions through the managed container's
VNC/RFB endpoint. It does not use the host X11 socket or run commands inside
the GUI container. Install the host-side VNC client dependency before using it:

```bash
python3 -m pip install --user vncdotool
```

`container gui use help`, `container gui use -h`, and `container gui use --help`
print the CUA help without requiring a container name. Other `container gui use`
commands check for `vncdotool` before inspecting the target container and report
the install command when the dependency is missing.

Single actions:

```bash
container gui use eda screenshot --output /tmp/screen.png
container gui use eda screenshot --output /tmp/region.png --region 0,0,800,600
container gui use eda click --x 120 --y 240
container gui use eda double_click --x 120 --y 240
container gui use eda move --x 120 --y 240
container gui use eda drag --from-x 100 --from-y 200 --to-x 400 --to-y 500
container gui use eda scroll --x 120 --y 240 --dy -5
container gui use eda type --text "hello"
container gui use eda keypress --key Enter
container gui use eda wait --seconds 0.5
```

Batch actions can be supplied as JSON:

```bash
container gui use eda sequence --input actions.json
container gui use eda sequence --input -
```

```json
[
  {"action": "screenshot", "output": "/tmp/before.png"},
  {"action": "click", "x": 120, "y": 240},
  {"action": "wait", "seconds": 0.5},
  {"action": "type", "text": "hello"},
  {"action": "keypress", "key": "Enter"},
  {"action": "screenshot", "output": "/tmp/after.png", "region": [0, 0, 800, 600]}
]
```

## Network Access

`container run` uses host networking by default:

```bash
container run --network yes
```

Restricted networking is available with:

```bash
container run --network no
```

Restricted networking allows DNS, loopback, the host gateway, and destinations
listed in `CONTAINER_NETWORK_ALLOWLIST`.

```bash
export CONTAINER_NETWORK_ALLOWLIST="license.example.com,192.168.1.100"
container run --network no
```

The restricted mode requires the `ip_tables`, `iptable_filter`, and
`nf_conntrack` kernel modules on the host.

## Mounts

| Host path | Container path | Purpose |
| --- | --- | --- |
| `/mnt/nas0` | `/mnt/nas0` read-only | Shared software, mounted when present. |
| `<workdir>` | `/home/<user>/work` read-write | Project work directory. |
| `$HOME/.Xilinx/license.lic` | `/home/<user>/.Xilinx/license.lic` read-only | Xilinx license file, mounted when present. |
| `$HOME/.achronix/.accept` | `/home/<user>/.achronix/.accept` read-only | Achronix acceptance file. Created with `Achronix_License=2023` when missing. |
| `/tmp/.X11-unix` | `/tmp/.X11-unix` | X11 socket, mounted when `DISPLAY` is set. |

## Files

| File | Description |
| --- | --- |
| `container.sh` | Unified `container run`, `container image`, and `container gui` dispatcher. |
| `gui.sh` | Xvnc-backed GUI container implementation. |
| `images/*.containerfile` | OS image definitions and hash source of truth. |
| `env.example` | Example environment file. |
