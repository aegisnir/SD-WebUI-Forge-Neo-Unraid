# SD-WebUI-Forge-Neo-Unraid

**[Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo) by Haoming02, packaged for Unraid by Aegisnir.**

[![Cyan badge displaying latest GitHub release version for forge-neo-unraid, clickable to view release history](https://img.shields.io/github/v/release/aegisnir/sd-webui-forge-neo-unraid?include_prereleases&label=release&color=cyan)](https://github.com/aegisnir/sd-webui-forge-neo-unraid/releases)
[![Blue badge with Docker logo indicating container image hosted on GitHub Container Registry, clickable to view packages](https://img.shields.io/badge/image-ghcr.io-blue?logo=docker)](https://github.com/aegisnir/sd-webui-forge-neo-unraid/pkgs/container/sd-webui-forge-neo-unraid)
[![Orange badge identifying upstream source as Forge Neo, clickable to view repository](https://img.shields.io/badge/upstream-Forge%20Neo-orange)](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo)
[![Green badge indicating AGPL-3.0 License, clickable to view license file](https://img.shields.io/badge/license-AGPL--3.0-green)](LICENSE)
[![Yellow badge displaying pre-release status, clickable to view releases page](https://img.shields.io/badge/status-pre--release-yellow)](https://github.com/aegisnir/sd-webui-forge-neo-unraid/releases)
[![Orange badge with Unraid logo indicating platform compatibility, clickable to visit Unraid website](https://img.shields.io/badge/platform-Unraid-F15A2C?logo=unraid&logoColor=white)](https://unraid.net/)
[![Green badge with NVIDIA logo indicating GPU support functionality, clickable to view CUDA toolkit documentation](https://img.shields.io/badge/GPU-NVIDIA-76B900?logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-toolkit)
[![Green badge with NVIDIA logo displaying CUDA version 13.0.2 requirement, clickable to view CUDA toolkit archive](https://img.shields.io/badge/CUDA-13.0.2-76B900?logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-toolkit-archive)
[![Badge showing Continuous Integration workflow status passing, clickable to view CI actions page](https://github.com/aegisnir/sd-webui-forge-neo-unraid/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/aegisnir/sd-webui-forge-neo-unraid/actions/workflows/ci.yml)
[![Light blue badge indicating security hardening with best practices implemented, clickable to view security details](https://img.shields.io/badge/security-hardened-informational)](SECURITY.md)

Forge Neo is Haoming02's work, a maintained fork of the Stable Diffusion WebUI. This repository does not change the WebUI. It only packages it as a hardened Unraid container with NVIDIA GPU support in mind. Bugs in the WebUI itself belong [upstream](https://github.com/Haoming02/sd-webui-forge-classic/issues). The goal is to keep it practical, easy to use, and security-conscious.

I couldn't find a Forge Neo container built for Unraid, so I made one. I had been running Forge Neo from a generic Docker image I found online, but since it wasn't built for Unraid, I ran into issues with automatic updates and other quirks. I'm making this repo public in the hopes that it will be useful to others.

> [!NOTE]
> This project started as an AUTOMATIC1111 container. AUTOMATIC1111 stopped receiving updates in March 2026 and has unpatched security issues, so it was rebased on Forge Neo. If you are coming from the old A1111 image, see [Migration Notes](#migration-notes).

This is a personal hobby project and it is heavily AI-assisted. This is also a learning experience for me as I have never made my own container before or produced anything on this scale for others. I care a lot about security and I am trying to make thoughtful choices, but I am not a programmer or security expert, so mistakes and inaccuracies are likely. If you notice something I could do better, please let me know. I welcome constructive criticism and feedback, and I am willing to learn and correct my mistakes. Thank you for your interest and I hope you find this useful.

> [!CAUTION]
> Public internet exposure is **not** the intended use case.
> If you expose this beyond a trusted network, the risk profile changes significantly and you should make those decisions carefully for your own environment.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [First Launch: What to Expect](#first-launch-what-to-expect)
- [Getting Your First Model](#getting-your-first-model)
- [Directory Layout](#directory-layout)
- [Configuration](#configuration)
  - [Authentication](#authentication-defaults)
  - [COMMANDLINE_ARGS](#commandline_args)
  - [HTTPS / TLS](#https--tls-options)
  - [Data Directory](#--data-dir)
- [Storage and Permissions](#storage-and-permissions)
- [Security Hardening](#security-hardening-defaults)
- [Operational Notes](#operational-notes)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Quick Reference](#quick-reference)
- [Licensing and Third-Party Notices](#licensing-and-third-party-notices)

---

## Prerequisites

Before you start, make sure you have:

| Requirement | Details |
|---|---|
| **Unraid** | Version 6.12+ recommended |
| **NVIDIA GPU** | Turing architecture or newer (RTX 20-series, GTX 16-series, or later). Maxwell, Pascal, and Volta are no longer supported by CUDA 13. |
| **NVIDIA driver** | **≥ 580** on the host (CUDA 13.0 requirement). Install the [Nvidia-Driver plugin](https://forums.unraid.net/topic/98978-plugin-nvidia-driver/) from Community Applications if you have not already. |
| **Disk space** | The image itself is large (Python, PyTorch and CUDA libraries are built in), so leave room in your Docker storage. On the path you map to `/data`, plan for models: a single model can be 2–7 GB. SSD storage is strongly recommended. |
| **RAM** | 16 GB minimum for basic SD 1.5 workflows. 32 GB+ recommended for SDXL or heavy extension use. |
| **Internet** | Required to pull the image. The WebUI itself needs no downloads to start, but extensions may install their own packages. |

### GPU sanity check

**Optional:** Before installing the container, you can confirm your Unraid host can see the GPU through Docker. Open the Unraid terminal (or SSH in) and run:

```bash
docker run --rm --gpus all nvidia/cuda:13.0.2-runtime-ubuntu22.04 nvidia-smi
```

You should see your GPU name, driver version, and CUDA version in the output. If this fails, troubleshoot the host NVIDIA setup (driver install, plugin configuration) before proceeding. The container will not work without GPU access.

The included Unraid template sets `--runtime=nvidia` in Extra Parameters by default. This gives the container access to the NVIDIA runtime when the NVIDIA Container Toolkit / Unraid NVIDIA plugin is set up correctly.

---

## Quick Start

> [!NOTE]
> This project is not yet in the Unraid Community Applications store. Use the manual template import steps below.

1. **Confirm your GPU works.** Run the [GPU sanity check](#gpu-sanity-check) above if you have not already.

2. **Import the template into Unraid.** SSH into your Unraid host and run:
   ```bash
   wget -P /boot/config/plugins/dockerMan/templates-user/ \
     https://raw.githubusercontent.com/aegisnir/sd-webui-forge-neo-unraid/dev/template.xml
   ```
   Then go to the **Docker** tab → **Add Container** and select `SD-WebUI-Forge-Neo-Unraid` from the template list.

   Alternatively, open the template file from this repo in a text editor, copy the contents, and paste it directly using Unraid's **Edit Mode** in the Add Container dialog.

3. **Choose a network type.** In the Unraid Docker UI, set the **Network Type** for the container:

   | Network Type | What It Does | When to Use |
   |---|---|---|
   | **Bridge** (default) | The container gets its own internal IP. You map container ports to host ports (e.g., container `7860` → host `7860`). Other devices reach it via `http://<unraid-ip>:<host-port>`. | Most users. Simple, isolated, works out of the box. |
   | **Host** | The container shares the Unraid host's network directly. No port mapping needed. The WebUI is available on port 7860 at Unraid's IP automatically. | When you want the simplest network path or need the container to see all host network interfaces. Slightly less isolation. |
   | **Custom (br0, etc.)** | The container gets its own IP on your physical LAN, separate from Unraid's IP. You assign it a static or DHCP address. No port mapping needed. | When you want the container to appear as its own device on the network, or when you need it accessible at a dedicated IP. Common for services like Plex, Home Assistant, etc. |

   **If you choose Bridge** (recommended for most users), map container port `7860` to a host port of your choice (default: `7860`).

4. **Review the default login credentials.** The container seeds `admin` / `changeme` on first launch. Change this after your first login. See [Authentication](#authentication-defaults).

5. **Start the container.** Everything the WebUI needs is built into the image, so it usually starts in a minute or two. See [First Launch: What to Expect](#first-launch-what-to-expect) for what healthy logs look like.

6. **Access the WebUI** from a trusted device on your LAN:
   - Bridge: `http://<unraid-ip>:7860`
   - Host: `http://<unraid-ip>:7860`
   - Custom network: `http://<container-ip>:7860`

   Replace the IP and port with your actual values. Unraid's default hostname `tower.local` also works if mDNS is set up.

If you build your own image, the Dockerfile pins a Forge Neo release through `WEBUI_TAG` and `WEBUI_REF` (that release's commit). These are build-time settings for image builders, not runtime variables. See [Upstream version pinning](#upstream-version-pinning).

---

## First Launch: What to Expect

Python 3.13, PyTorch and every package Forge Neo needs are built into the image, so there is no long first-run install. The first start mainly sets up folders under `/data` and `/config`, then loads the WebUI.

### What healthy logs look like

The container prints a short summary, then the WebUI's own output:

```
Dependency sanity check: torch=2.14.0+cu130, torchvision=0.29.0+cu130
...
Python 3.13.x ...
Version: neo 2.31
Launching Web UI with arguments: --listen --port 7860 --data-dir /data --gradio-auth-path <redacted>
...
Running on local URL: http://0.0.0.0:7860
```

A `[READY]` box appears once the WebUI accepts connections. If the container finds no model, it says so before launch. That is **normal**. See [Getting Your First Model](#getting-your-first-model).

### What if something goes wrong?

- Extensions can install their own Python packages on start. Those go to `/data/python-user`, never into the image. If an extension breaks things (for example by installing a different PyTorch), delete that folder on the host and restart. The container checks the PyTorch version on every start and tells you when this happens.
- If the log says `config.json is from an older WebUI version`, the container stopped on purpose. Move `config.json` and `ui-config.json` out of the appdata `webui/` folder and restart. See [Migration Notes](#migration-notes).

---

## Getting Your First Model

After the container starts, you will see a login page. Log in with `admin` / `changeme` (the default credentials). If you have not added a model yet, the WebUI starts but cannot generate images. This is expected.

You need at least one model (checkpoint) to generate images. Models are `.safetensors` files, typically 2–7 GB each. Forge Neo also runs newer model families such as Flux, Qwen and Wan.

### Recommended: install a CivitAI browser extension

> [!NOTE]
> Managing extensions from the WebUI needs `--enable-insecure-extension-access` in `COMMANDLINE_ARGS`. It is off by default. See [Migration Notes](#extension-management-removed-from-defaults) for the trade-off. Also check that an extension supports Forge Neo before installing it: many A1111 extensions need a Neo-specific fork.

The easiest way to browse and download models is with a CivitAI browser extension, which lets you search and download models from [CivitAI](https://civitai.com/) directly inside the WebUI.

**Recommended:** [CivBrowser](https://github.com/SignalFlagZ/sd-webui-civbrowser) by SignalFlagZ. Actively maintained, supports searching and downloading models across multiple tabs.

**Alternative:** [CivitAI Browser+](https://github.com/BlafKing/sd-civitai-browser-plus) by BlafKing. Feature-rich (download, delete, scan for updates, tag management, multi-threaded downloads). Note: this repository is **archived** and no longer receiving updates, but the extension still works.

#### Installing from the Available tab (easiest)

1. In the WebUI, go to the **Extensions** tab.
2. Click the **Available** sub-tab.
3. Click **Load from:** to load the extension index.
4. Use the search box to filter by name (e.g. `CivBrowser` or `CivitAI Browser+`).
5. Click **Install** next to the extension you want.
6. Go to **Installed** → click **Apply and restart UI**.
7. A new tab will appear for the extension. Browse models and click download. They are saved directly to the right folder.

#### Alternative: Install from URL

If you prefer, you can paste a GitHub URL directly:

1. In the **Extensions** tab, click **Install from URL**.
2. Paste the repository URL (e.g., `https://github.com/SignalFlagZ/sd-webui-civbrowser.git`).
3. Click **Install**, then go to **Installed** → **Apply and restart UI**.

### Manual download

If you prefer to download models manually:

1. Download a `.safetensors` file from [CivitAI](https://civitai.com/), [Hugging Face](https://huggingface.co/), or another trusted source.
2. Place it in the models directory on your Unraid host:
   ```
   /mnt/user/ai/data/models/Stable-diffusion/
   ```
   You can copy files via SMB share, SCP, or the Unraid terminal:
   ```bash
   # Example: download a model via the Unraid terminal
   wget -P /mnt/user/ai/data/models/Stable-diffusion/ <model-download-url>
   ```
3. In the WebUI, click the **refresh** button next to the checkpoint dropdown (top left) to detect the new model, then select it.

### Model types you might encounter

| Type | Where it goes | Typical size |
|---|---|---|
| Checkpoint (SD 1.5) | `models/Stable-diffusion/` | 2–4 GB |
| Checkpoint (SDXL) | `models/Stable-diffusion/` | 6–7 GB |
| LoRA / LyCORIS | `models/Lora/` | 10–200 MB |
| VAE | `models/VAE/` | 300–800 MB |
| Textual Inversion / Embedding | `embeddings/` | 10–100 KB |

---

## Directory Layout

The container uses two main mount points. Here is where everything lives:

```
/config/                          (host: /mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/)
├── webui/                        WebUI config files
│   ├── config.json               UI settings
│   ├── ui-config.json            UI layout/defaults
│   ├── styles.csv                Prompt styles
│   └── config_states/            Extension state snapshots
└── auth/
    └── webui-auth.txt            Login credentials (chmod 600)

/data/                            (host: /mnt/user/ai/data/)
├── models/
│   ├── Stable-diffusion/         Model checkpoints (.safetensors, .ckpt)
│   ├── VAE/                      VAE models
│   └── Lora/                     LoRA/LyCORIS models
├── output/                       Generated images
├── extensions/                   Installed extensions
├── embeddings/                   Textual inversions
├── python-user/                  Packages installed by extensions (safe to delete)
├── pip-cache/                    Cached pip downloads for extensions
└── tmp/                          Temporary files (cleaned on start)
```

**Why two paths?** `/config` holds small configuration files that belong in your appdata backup. `/data` holds large, fast-growing content (models, outputs, extensions) that should live on a drive with plenty of space, preferably an SSD.

---

## Configuration

### Authentication defaults

This container enables the WebUI login page by default. The API is disabled by default unless you explicitly add `--api` to `COMMANDLINE_ARGS`.

**Default credentials (seeded on first launch):**

- Username: `admin`
- Password: `changeme`

Change this as soon as possible after first login.

**Auth file location:**

| | Path |
|---|---|
| Container | `/config/auth/webui-auth.txt` |
| Host (default) | `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/auth/webui-auth.txt` |
| Env override | `WEBUI_AUTH_FILE` |

**To change your password**, edit the auth file on the Unraid host:

```bash
nano /mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/auth/webui-auth.txt
```

Auth file format: one credential per line as `username:password`:

```text
admin:replace-with-strong-password
viewer:another-password
```

Lines starting with `#` are comments. Blank lines are ignored.

<details>
<summary><strong>Auth file details: permissions, SMB access, API mirroring</strong></summary>

#### File permissions

The auth file is created with `chmod 600` (owner read/write only). This prevents other processes and containers sharing the `/data` volume from reading your credentials.

**Unraid terminal (recommended):** The Unraid terminal runs as `root`, so root always has access regardless of permissions.

**SMB share:** Unraid serves SMB. If you access the share with your Unraid admin credentials, you can read and write `chmod 600` files normally. However, because the container runs as `nobody` (UID 99) and Unraid's Samba guest account is also `nobody` (UID 99), a **Public** or **Secure** share maps anonymous connections to the same UID that owns the auth file, meaning SMB guests can read it. Set the `appdata` share to **Private** if you want to restrict SMB access to this file.

**In summary:** Unraid terminal or SSH is the simplest and most reliable method. Authenticated SMB (Private share) works. The `chmod 600` permission does **not** protect the auth file from SMB access on a Public or Secure share. The Samba guest account maps to the file's owner UID.

#### API auth mirroring

If API is enabled (`--api`), the container mirrors auth-file credentials into `--api-auth` by default. You can control that with:

- `API_AUTH_FILE_MODE=mirror-webui-file`
- `API_AUTH_FILE_MODE=disabled`

> [!WARNING]
> **API auth exposure:** The WebUI's `--api-auth` flag accepts credentials as a plain string (not a file path). When mirroring is active, the container appends `--api-auth user:password` to the `COMMANDLINE_ARGS` environment variable. This means credentials are readable via `docker inspect` and `/proc/<pid>/environ` by any process or user that can inspect the container. This is a known upstream limitation of the WebUI's API auth mechanism (inherited from AUTOMATIC1111). There is no file-based equivalent for `--api-auth`. If this exposure is unacceptable for your environment, set `API_AUTH_FILE_MODE=disabled` and do not enable the API, or place the entire service behind a reverse proxy that handles API auth at the network layer.

> [!IMPORTANT]
> **Why `WEBUI_USERNAME` / `WEBUI_PASSWORD` were removed:** Passing credentials via template/env variables exposes them in the same way. Auth-file based login (`--gradio-auth-path`) is safer because the credential string never appears in env vars or command-line arguments.

#### Manual auth flags

If you want to manage authentication manually, you can still pass your own auth flags in `COMMANDLINE_ARGS`:

- `--gradio-auth username:password`
- `--gradio-auth-path /path/to/auth-file`
- `--api-auth username:password`

If you provide your own auth flags in `COMMANDLINE_ARGS`, the container will not add duplicate auth arguments.
If `--api-auth` is provided without `--api`, startup logs now warn that API auth flags are ignored until API is explicitly enabled.

</details>

### `COMMANDLINE_ARGS`

`COMMANDLINE_ARGS` is passed directly to `launch.py`.

> [!NOTE]
> **Log redaction:** Sensitive auth flags (`--gradio-auth`, `--gradio-auth-path`, `--api-auth`) have their values replaced with `<redacted>` in startup log output. The flag names remain visible so you can confirm they are active.

**Default** (from the Unraid template):

```
--listen --port 7860 --data-dir /data
```

> [!WARNING]
> Forge Neo stops at startup on any flag it does not know. Check [Neo's flag list](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo) before adding one. Three common A1111 flags that Neo removed (`--no-download-sd-model`, `--disable-safe-unpickle`, `--allow-code`) are dropped automatically with a log message.

> [!TIP]
> The container automatically appends `--gradio-auth-path <runtime-auth-file>` at launch (see [Authentication](#authentication-defaults)). You do not need to add auth flags yourself. They are injected by `start.sh` based on your `WEBUI_AUTH_FILE`.

API is intentionally not part of the default args. Add `--api` only when you explicitly need API access.

Use the defaults as a starting point, then tune for your own hardware, risk tolerance, and workflow.

For a complete list of supported arguments, run `python launch.py --help` inside the container or see the [Forge Neo README](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo).

<details>
<summary><strong>Flag details and security considerations</strong></summary>

- **Attention (`--xformers`, `--sage`, `--flash`)** (not set by default): The image ships without these packages, so Neo uses PyTorch's built-in attention, which Neo's README calls "usually as fast, and also more stable". These flags only *install* the package (into `/data/python-user`) on the next start. Once installed, Neo uses it automatically. Use `--disable-xformers` (and so on) to switch one off again.

- **`--enable-insecure-extension-access`** (not set by default): Allows installing/updating extensions from the WebUI. Risk: anyone who can log in can install an extension from any git URL, and its code runs inside the container on every start. Manage extensions on disk instead for a safer posture.

- **`--api`** (not set by default): Enables the REST API. Only add this when you explicitly need programmatic access.

If you change these arguments, keep in mind that some flags can weaken the container's security posture. Be especially careful with anything that increases network exposure.

</details>

### HTTPS / TLS options

By default, the WebUI serves over HTTP, not HTTPS. My recommended approach for most Unraid users:

1. Keep the container on a trusted local network.
2. Leave the container itself on HTTP internally.
3. Put HTTPS in front of it with a reverse proxy such as Nginx Proxy Manager, Traefik, Caddy, or another TLS-terminating proxy.
4. Restrict exposure with a VPN, access controls, or both if you need remote access.

<details>
<summary><strong>Direct TLS configuration</strong></summary>

The WebUI does support direct TLS flags:

- `--tls-certfile /path/to/cert.pem`
- `--tls-keyfile /path/to/key.pem`

You can mount certificate files into the container and add the TLS flags to `COMMANDLINE_ARGS`. I do not currently recommend making that the default because:

- You need to provide certificates and keys securely.
- Certificate renewal is easier to manage outside the app.
- Reverse proxies handle TLS, redirects, and hostname routing better than the WebUI itself.
- Certificate management is highly environment-specific and easy to get wrong.

</details>

<details>
<summary><strong>Auto TLS-HTTPS extension (zero-config option)</strong></summary>

The [Auto TLS-HTTPS](https://github.com/papuSpartan/stable-diffusion-webui-auto-tls-https) extension by papuSpartan can automatically generate a self-signed certificate and enable HTTPS with zero configuration. When installed, it:

1. Generates a key/certificate pair automatically.
2. Fuses the certificate with Python's trust store so internal WebUI requests succeed.
3. Starts serving over HTTPS without manual certificate management.

You can also bring your own certificate by passing `--tls-keyfile` and `--tls-certfile`. The extension will incorporate it into the trust bundle.

**Caveats:**
- On Forge Neo, this extension can crash startup on Python 3.13 (it pulls an old `trio` package). Prefer the direct TLS flags above, or a reverse proxy.
- Self-signed certificates will trigger browser warnings. You can add a browser exception or import the generated `webui.cert` into your OS trust store.
- The extension has not been updated in ~2 years (last commit May 2024), though it remains functional.
- A reverse proxy is still the more robust long-term solution, especially if you need certificate renewal, hostname routing, or multi-service TLS.

Install it from the **Extensions** → **Available** tab (search for `Auto TLS-HTTPS`) or via **Install from URL** with `https://github.com/papuSpartan/stable-diffusion-webui-auto-tls-https.git`.

</details>

### `--data-dir`

This container uses the WebUI's `--data-dir` so the large, fast-growing working set lives on a host path you choose.

| | Path |
|---|---|
| Container path | `/data` |
| Default host path | `/mnt/user/ai/data/` |

**Why not `/appdata`?** This directory can grow very large very quickly with models, outputs, extensions, and caches. If you store it in `appdata`, it may fill that area much faster than expected, especially if your Docker-related storage is limited. You can absolutely use `appdata` if that fits your setup, just be aware of the growth.

The Python environment is part of the image, not `/data`. Only packages that extensions install live in `/data/python-user`.

## Storage and Permissions

This image uses Unraid-friendly defaults:

- UID `99` (`nobody`)
- GID `100` (`users`)

Make sure your mapped host paths are writable by that UID/GID, or adjust the container settings to match your environment.

<details>
<summary><strong>File permissions and umask</strong></summary>

By default, this container does not set a restrictive `UMASK`, so files in `/data` remain easier to access from outside the container.

If you want stricter file permissions, set the template variable `UMASK` in Unraid (advanced view), for example:

- `UMASK=0027`

This results in files with permissions like `rw-r-----` and directories with `rwxr-x---`.

</details>

## Security Hardening Defaults

This container uses the following security options by default (set in the Unraid template Extra Parameters):

```bash
--read-only
--tmpfs /tmp:rw,noexec,nosuid,nodev,size=2g
--security-opt no-new-privileges:true
--cap-drop=ALL
--cap-add=CHOWN --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID
--pids-limit=2048
```

- The container will refuse to start as root (UID 0) for safety.
- All SUID/SGID bits are removed from binaries at build time.
- If you use `--read-only`, provide explicit writable mounts for anything that needs to persist. The template already maps `/data` and `/config` as writable volumes. If you add custom paths outside those mounts, you will need additional `-v` volume mounts or `--tmpfs` entries. For example, to add a writable scratch directory:
  ```
  -v /mnt/user/ai/scratch:/scratch:rw
  ```
  Without writable mounts, any write operation to the read-only filesystem will fail with `Read-only file system`.

For the full security baseline regression checklist, see `SECURITY.md`. To run the automated checks: `./scripts/security-check.sh`

<details>
<summary><strong>What each security flag does</strong></summary>

- **`--read-only`**: Reduces write access to the container filesystem, limiting persistence for attackers.
- **`--tmpfs /tmp:...`**: Provides a safe, writable /tmp for runtime needs.
- **`no-new-privileges:true`**: Prevents processes from gaining new privileges, reducing escalation risk.
- **`--cap-drop=ALL` + targeted `--cap-add`**: Keeps a least-privilege capability profile while preserving required startup operations:
	- `CHOWN`: required when `/data` ownership must be repaired
	- `FOWNER`: required to fix mode bits on host-mounted paths not owned by uid 0
	- `SETUID` / `SETGID`: required to drop from root to uid 99/gid 100 before launching WebUI
- **`--pids-limit=2048`**: Contains runaway process spawning without being overly restrictive.

To change the PID limit in Unraid:

1. Open the container in Unraid and switch to advanced view.
2. In Extra Parameters, change the `--pids-limit=<value>`.
3. Apply the update.

</details>

### Docker Healthcheck

The image includes a built-in `HEALTHCHECK` that probes whether the Gradio HTTP server is accepting TCP connections on port 7860:

| Setting | Value | Why |
|---|---|---|
| `--start-period` | 5 min | Covers extension installers and model loading on a first start |
| `--interval` | 2 min | Enough to catch crashes without spamming during model loads |
| `--timeout` | 30 s | Absorbs brief pauses during model swaps and extension installs |
| `--retries` | 5 | 5 failures x 2 min interval = 10 min of unresponsiveness before marking unhealthy |

> [!IMPORTANT]
> Unhealthy status is **informational only**. Docker/Unraid will not auto-restart the container. It just shows a red dot vs green dot. Normal heavy operations (model loading, ControlNet preprocessing, image browser scanning) do **not** cause false positives because Gradio handles HTTP requests in separate threads.

## Operational Notes

### Automatic restart

The container automatically restarts the WebUI process if it exits. You do not need to restart the container itself.

- **Restart button** (in the WebUI, or after installing an extension): the WebUI exits cleanly (code 0). The container waits `RESTART_DELAY` seconds (default 5 s) then relaunches it.
- **Settings need attention** (exit code 78, for example an old `config.json`): the container exits instead of restarting, and the log explains the fix.
- **Crash** (non-zero exit): exponential backoff starting at `RESTART_DELAY`, doubling each attempt up to `RESTART_DELAY_MAX` (default 60 s).
- **Docker stop / Unraid stop container**: sends SIGTERM, which exits the container cleanly without restarting.

| Variable | Default | Description |
|---|---|---|
| `RESTART_ON_EXIT` | `1` | Set to `0` to disable the restart loop |
| `RESTART_DELAY` | `5` | Seconds to wait before a clean-exit restart |
| `RESTART_DELAY_MAX` | `60` | Maximum backoff delay for crash restarts |
| `RESTART_MAX_ATTEMPTS` | `0` | Max restart attempts; `0` = unlimited |

### General notes

- Host networking, public exposure, and relaxed runtime settings all change the risk profile.
- Models, extensions, and other third-party content should be treated as untrusted inputs.
- Only install extensions and models from trusted sources. Third-party code can compromise the security of your system.
- A healthy container only means the service responded on the expected port. It does **not** prove the application is safe or fully working.

## Troubleshooting

### The WebUI does not load
- Check the container logs. The container prints a pre-launch summary and annotates known harmless warnings inline, so look past those to find real errors.
- Confirm the port mapping is correct (Bridge mode) or that you are using the right IP (custom network mode).
- Confirm the container is still running.
- If the container exited with a message about `config.json`, see [Migration Notes](#migration-notes).
- If the log mentions an unrecognized argument, remove that flag from `COMMANDLINE_ARGS`. Forge Neo stops on unknown flags.

### The WebUI loads but cannot generate
- You probably have no model yet. See [Getting Your First Model](#getting-your-first-model).

### The GPU is not being used
- Re-run the [GPU sanity check](#gpu-sanity-check).
- Confirm the container still has `--runtime=nvidia` in Extra Parameters.
- Confirm Unraid is providing GPU access to the container.
- Confirm the host NVIDIA driver/plugin is working.
- If the WebUI fails with a message like `PyTorch is not able to access any compute device (GPU)`, you can temporarily add `--skip-torch-cuda-test` to `COMMANDLINE_ARGS` for troubleshooting. I do not recommend making that your long-term default, because it can hide a real GPU passthrough problem.
- If the startup sanity check reports a torch version mismatch, an extension replaced PyTorch. Delete `/mnt/user/ai/data/python-user` (template default path) and restart.

### I am seeing permission errors
- Check that your mapped host folders are writable by the configured UID/GID.
- If `/data` ended up owned by root (e.g., after deleting and Docker recreating the host directory), the container self-heals this automatically. See below.
- If using `--read-only`, make sure required writable paths are explicitly mounted.

### Error: `Operation not permitted` in entrypoint (`chmod`, `runuser`, or `setpriv`)
- If logs show messages like `chmod: changing permissions of '/data': Operation not permitted`, `runuser: cannot set groups`, or `setpriv: setresuid failed`, the host/runtime is denying metadata or UID/GID transitions.
- The container prints a short runtime diagnostic line with `NoNewPrivs`, `Seccomp`, and `CapEff` values to help identify this class of restriction.
- Typical causes: rootless/user-namespace remap behavior, no-new-privileges hardening, NFS root-squash exports, or share ACL/mount policy restrictions.
- Fix on host first, then restart:

```bash
chown nobody:users /mnt/user/ai/data
chmod 775 /mnt/user/ai/data
```

### The container fails to start after deleting `/data`

If you delete the host data directory (default: `/mnt/user/ai/data/`), Docker may recreate it owned by `root` on next start.

**In most cases this is fully automatic.** The container entrypoint runs as root, detects the wrong ownership, corrects it, then drops to the unprivileged app user before startup continues. You should see a log line like:

```
[entrypoint] /data is owned by uid=0, expected uid=99.
[entrypoint] Correcting ownership to 99:100 (nobody:users) and setting mode 775...
[entrypoint] /data ownership corrected. Continuing startup.
```

**If the auto-fix fails** (NFS shares with root squash, unusual SELinux policies, or other host-side restrictions), correct ownership manually on the Unraid host and restart:

```bash
chown nobody:users /mnt/user/ai/data
chmod 775 /mnt/user/ai/data
```

### The container is unhealthy
- The healthcheck is deliberately generous. The container must be completely unresponsive for ~10 minutes (5 retries x 2 min interval) before Docker marks it unhealthy.
- Normal heavy operations (model loading, extension installs, image browser scanning) do **not** cause false positives.
- Unhealthy status is informational only. Docker/Unraid will **not** auto-restart the container.
- If you see unhealthy status, check the container logs for crash output.
- If you changed the port in `COMMANDLINE_ARGS`, the healthcheck still probes 7860. Either keep the default port or rebuild the image with a matching `HEALTHCHECK`.

## Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `COMMANDLINE_ARGS` | `--listen --port 7860 --data-dir /data` | Arguments passed directly to the WebUI launch command |
| `WEBUI_AUTH_FILE` | `/config/auth/webui-auth.txt` | Path to the managed authentication credentials file |
| `API_AUTH_FILE_MODE` | `disabled` | Set to `mirror-webui-file` to copy WebUI creds to `--api-auth` when `--api` is enabled |
| `RESTART_ON_EXIT` | `1` | `1` = restart WebUI after any exit; `0` = exit container on WebUI stop |
| `RESTART_DELAY` | `5` | Seconds to wait before restarting after a clean exit |
| `RESTART_DELAY_MAX` | `60` | Backoff ceiling (seconds) for crash restarts |
| `RESTART_MAX_ATTEMPTS` | `0` | `0` = retry indefinitely; N = stop after N consecutive crash restarts |
| `PYTHONUSERBASE` | `/data/python-user` | Where packages installed by extensions go |
| `WEBUI_HOST_IP` | `0.0.0.0` | IP address the WebUI binds to inside the container |
| `UMASK` | *(unset)* | Override default umask for all file creation (e.g., `022`) |
| `NO_COLOR` | *(unset)* | Set to `1` to suppress ANSI color codes in container logs |
| `TERM` | *(unset)* | Set to `dumb` to suppress ANSI color codes (alternative to `NO_COLOR`) |

## Migration Notes

### Coming from the old A1111 image

The image, template and repository were renamed: `ghcr.io/aegisnir/sd-webui-forge-neo-unraid`, template `SD-WebUI-Forge-Neo-Unraid`, repository `aegisnir/sd-webui-forge-neo-unraid`. Add the new template as a new container. Your models in `/data` work as they are.

- **Settings:** the container renames `/config/a1111` to `/config/webui` on first start. Forge Neo then stops with a message, because A1111 settings are not compatible. Move `config.json` and `ui-config.json` out of the appdata `webui/` folder and restart.
- **Outputs:** Neo saves to `/data/output` (A1111 used `/data/outputs`). Your old images stay where they are. To keep using the old folder, set it in **Settings → Paths for saving**.
- **Old Python files:** `/data/venv` and `/data/repositories` are no longer used. The container leaves them alone. Delete them to free space.
- **Extensions:** many A1111 extensions do not work on Neo. Check each one for a Neo version.
- **Flags:** `--xformers` is no longer a default (see [`COMMANDLINE_ARGS`](#commandline_args)). `--no-download-sd-model`, `--disable-safe-unpickle` and `--allow-code` are removed by Neo and dropped automatically.

### Coming from another Forge Neo container

Your `config.json` already has Neo's version marker, so settings carry over. The entrypoint changes `/data` ownership to `99:100` on first start. If the old container ran as another user, test with a **copy** of the data first, because the old container may not be able to write to it afterwards.

### Extension management removed from defaults

Previous versions included `--enable-insecure-extension-access` in the default `COMMANDLINE_ARGS`.  This flag bypasses the WebUI's built-in safety check that prevents installing extensions from the WebUI when the server is network-accessible.

**What changed:** The flag is no longer in the default template.  If you install extensions through the WebUI's ==Extensions== tab, they will stop working after updating to this version.

**How to restore it:** Add `--enable-insecure-extension-access` to your container's `COMMANDLINE_ARGS` environment variable (via Unraid template or Docker Compose).  This is an explicit opt-in to the security tradeoff.

**Why:** Extensions have full code execution within the container.  Allowing unauthenticated remote installation of arbitrary code is a significant risk when combined with network exposure.  Users who need this feature can still enable it, but it should be a conscious decision.

**Alternative:** Install extensions via the container's `/data/extensions/` directory by cloning them from the host or a startup script.  This does not require the flag.

## Advanced Topics

### Upstream version pinning

The image pins one Forge Neo release, set at build time by two build arguments in the `Dockerfile`:

- `WEBUI_TAG`: the release tag (for example `2.31`)
- `WEBUI_REF`: that release's commit SHA, so a moved tag cannot change what gets built

Only release tags are used, never the daily commits between releases. A scheduled GitHub Action checks for new Neo releases every day and opens a pull request that bumps both values. Merging it builds and publishes a new `:dev` image.

To build a different release yourself:

```bash
docker build --build-arg WEBUI_TAG=<tag> --build-arg WEBUI_REF=<commit-sha> -t sd-webui-forge-neo-unraid:local .
```

### Image tags

The included `template.xml` defaults to the published GHCR image:

- Repository: `ghcr.io/aegisnir/sd-webui-forge-neo-unraid:dev`

Images are built by GitHub Actions. Every build is pushed as `:sha-<commit>`, scanned with Trivy, and only then published under its channel tag (`:dev`, `:latest`, or `:vX.Y.Z`). The `:sha-` tags stay available as rollback points.

For local builds, change the repository to `sd-webui-forge-neo-unraid:local`. When a stable release is promoted, switch to `ghcr.io/aegisnir/sd-webui-forge-neo-unraid:latest`.

### Maintenance

This image will likely need occasional rebuilds to pick up upstream changes and dependency updates. At a minimum, keep an eye on:

- Upstream Forge Neo releases (a pull request opens automatically)
- Unraid updates
- NVIDIA driver/toolkit changes
- Any extensions or models you add yourself

The image pins `torch`, `torchvision` and `gradio` to the versions Forge Neo itself installs. When Neo changes them in a release, update the matching build arguments in the same pull request.

---

## Quick Reference

| Item | Value |
|---|---|
| **Default WebUI URL** | `http://<unraid-ip>:7860` |
| **Default login** | `admin` / `changeme` |
| **Auth file (host)** | `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/auth/webui-auth.txt` |
| **Models directory (host)** | `/mnt/user/ai/data/models/Stable-diffusion/` |
| **Outputs directory (host)** | `/mnt/user/ai/data/output/` |
| **Config directory (host)** | `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/` |
| **Data directory (host)** | `/mnt/user/ai/data/` |
| **Container UID/GID** | `99` / `100` (`nobody` / `users`) |
| **Minimum driver** | ≥ 580 (CUDA 13.0 requirement) |
| **Start time** | Usually 1–2 minutes (no downloads at startup) |
| **GPU check command** | `docker run --rm --gpus all nvidia/cuda:13.0.2-runtime-ubuntu22.04 nvidia-smi` |

---

## Licensing and Third-Party Notices

This repository is licensed under AGPL-3.0 (see `LICENSE`), consistent with the upstream Forge Neo license.

For third-party license details, see:

- `THIRD_PARTY_NOTICES.md`
- `LICENSES/AGPL-3.0.txt`

If you distribute images or artifacts that include AGPL-covered components, include corresponding source and license notices for those components.

## Disclaimer

This repository is shared as-is.

I am trying to make it useful and reasonably security-conscious, but I am learning as I go and I will make mistakes. Nothing here should be treated as a guarantee of security, stability, or suitability for your environment. Please validate everything against your own needs, threat model, and risk tolerance.
