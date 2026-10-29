# SD-WebUI-Forge-Neo-Unraid

**[Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo) by Haoming02, packaged for Unraid by Aegisnir.**

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

Forge Neo's own repository includes a basic [Docker setup](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo/docker). This project is a separate, Unraid-focused packaging with its own hardening, HTTPS and login handling.

I couldn't find a Forge Neo container built for Unraid, so I made one. I had been running Forge Neo from a generic Docker image I found online, but since it wasn't built for Unraid, I ran into issues with automatic updates and other quirks. I'm making this repo public in the hopes that it will be useful to others.

> [!NOTE]
> This project started as an AUTOMATIC1111 container. AUTOMATIC1111 stopped receiving updates in March 2026 and has unpatched security issues, so it was rebased on Forge Neo. If you are coming from the old A1111 image, see [Migration Notes](#migration-notes).

This is a personal hobby project and it is heavily AI-assisted. This is also a learning experience for me as I have never made my own container before or produced anything on this scale for others. I care a lot about security and I am trying to make thoughtful choices, but I am not a programmer or security expert, so mistakes and inaccuracies are likely. If you notice something I could do better, please let me know. I welcome constructive criticism and feedback, and I am willing to learn and correct my mistakes. Thank you for your interest and I hope you find this useful.

> [!WARNING]
> **This container ships software with known, unfixed vulnerabilities**, mainly in Gradio, the web framework Forge Neo is built on. They are all listed in [Known security issues](#known-security-issues), with what this container does about them. Please read that section before you install.

> [!CAUTION]
> Public internet exposure is **not** the intended use case.
> If you expose this beyond a trusted network, the risk profile changes significantly and you should make those decisions carefully for your own environment.

## Built for my setup

I built this container for my own Unraid server and the way I use it, then shared it. Some defaults reflect **my** preferences rather than the most locked-down option. Each one is marked **Maintainer's choice** where it is described, with the trade-off and how to change it. In short:

| Default | Why I chose it | The trade-off | How to change it |
|---|---|---|---|
| Installing extensions from the WebUI is **on** | I install extensions from the WebUI | Anyone who can log in can run code in the container | Remove `--enable-insecure-extension-access` from Extra Args ([details](#extension-management-is-on-by-default)) |
| Gradio **4.44.1** instead of Forge Neo's 4.40.0 | Fixes 5 known vulnerabilities | Not tested by Forge Neo; parts of the UI may break | [Build with Gradio 4.40.0](#build-with-the-original-gradio-4400) |
| Newer **GitPython, diffusers and setuptools** than Forge Neo pins | Fixes 10 high-rated vulnerabilities | Not tested by Forge Neo; may break | Build with `--build-arg GITPYTHON_VERSION=3.1.62` (and `DIFFUSERS_VERSION`, `SETUPTOOLS_VERSION`), the same way as [the Gradio build](#build-with-the-original-gradio-4400) |
| A starter login `admin` / `changeme` is created and the WebUI still starts | The WebUI is never without a login, and first setup stays simple | Weak until you change it | Change the password in the auth file ([details](#authentication-defaults)) |
| HTTPS with a **self-signed** certificate | Encryption on my network without extra setup | Your browser warns once | Use your own certificate, or `WEBUI_TLS=off` ([details](#https--tls)) |
| Login lockout after **5** failed attempts for **15** minutes | Slows down password guessing | Typos can lock you out for a while | `WEBUI_LOGIN_MAX_ATTEMPTS`, `WEBUI_LOGIN_LOCKOUT_MINUTES` ([details](#login-protection)) |
| Files in `/data` readable from the host (no strict `UMASK`) | I manage models and images over SMB | Other users and apps on the server can read them | Set `UMASK=0027` ([details](#storage-and-permissions)) |
| The WebUI restarts itself when it exits | No manual restarts after crashes or "Apply and restart UI" | A crash loop keeps retrying (with growing delays) | `RESTART_ON_EXIT=0` ([details](#automatic-restart)) |
| Old settings from another WebUI are backed up and replaced automatically | Upgrades just work | You redo your settings once | Restore from the `*.pre-neo-*.bak` files ([details](#what-if-something-goes-wrong)) |
| Data folder `/mnt/user/ai/data` in the template | Keeps large files out of appdata | None, if you have an `ai` share | Change the **Data Directory** path in the template |

---

## Table of Contents

- [Built for my setup](#built-for-my-setup)
- [Known security issues](#known-security-issues)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [First Launch: What to Expect](#first-launch-what-to-expect)
- [Getting Your First Model](#getting-your-first-model)
- [Directory Layout](#directory-layout)
- [Configuration](#configuration)
  - [Authentication](#authentication-defaults)
  - [Login protection](#login-protection)
  - [COMMANDLINE_ARGS](#commandline_args)
  - [HTTPS / TLS](#https--tls)
  - [Data Directory](#--data-dir)
- [Storage and Permissions](#storage-and-permissions)
- [Security Hardening](#security-hardening-defaults)
- [Operational Notes](#operational-notes)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Quick Reference](#quick-reference)
- [Licensing and Third-Party Notices](#licensing-and-third-party-notices)

---

## Known security issues

I want to be upfront about this: the WebUI in this container depends on software with known vulnerabilities that I cannot fully fix. Everything I know of is listed here. The newest check was on 2026-10-29.

### The main problem: Forge Neo is built on Gradio 4

Forge Neo 2.31 pins **Gradio 4.40.0**, the web framework that draws the whole UI. Gradio 4.40.0 has **28 published vulnerabilities**, including one rated critical. Gradio fixed most of them only in versions 5 and 6, and Forge Neo's UI code does not work with those. Some have no fix in any version. This is an upstream limitation: it also affects every other way of running Forge Neo, not just this container.

### What this container does about it

- **Mitigation attempt (may break things, maintainer's choice):** this image upgrades Gradio from 4.40.0 to **4.44.1**, the last Gradio 4 release. That fixes 5 of the 28 ([CVE-2024-47084](https://osv.dev/vulnerability/CVE-2024-47084), a high-rated CORS bypass, plus [CVE-2024-47166](https://osv.dev/vulnerability/CVE-2024-47166), [CVE-2024-47168](https://osv.dev/vulnerability/CVE-2024-47168), [CVE-2024-47869](https://osv.dev/vulnerability/CVE-2024-47869) and [CVE-2024-48052](https://osv.dev/vulnerability/CVE-2024-48052)). Forge Neo itself is not tested with 4.44.1, so parts of the UI might misbehave. If you hit a problem, please [open an issue](https://github.com/aegisnir/sd-webui-forge-neo-unraid/issues). You can also [build your own image with Gradio 4.40.0](#build-with-the-original-gradio-4400).
- **Login is always on**, and it is managed by the container (see [Authentication](#authentication-defaults)).
- **HTTPS is on by default**, so your password and images are encrypted as they cross your network. This is this container's own feature, not part of Forge Neo. On first start the container creates its own certificate (a *self-signed* certificate: one it vouches for itself, rather than a public authority). Your browser warns about it once; you can confirm it is genuine by comparing a fingerprint from the log. You can also supply your own certificate. See [HTTPS / TLS](#https--tls).
- **The container runs with a read-only filesystem, no root, and dropped privileges** (see [Security Hardening](#security-hardening-defaults)).
- **Installing extensions from the WebUI is ON by default**, for convenience. Anyone who can log in can install an extension, and extensions run their own code inside the container. See [Extensions](#extension-management-is-on-by-default) for how to turn it off.
- **The build still scans every image** with Trivy and refuses to publish on new high or critical findings. The Gradio vulnerabilities below are accepted one by one in [`.trivyignore`](.trivyignore), each with its reason. Every entry expires on 2027-01-31, which forces a fresh review.

### Remaining Gradio 4.44.1 vulnerabilities

**How to read this table.** "Severity" is the official rating, which assumes the worst case: an app open to the whole internet. Your real risk depends on who can reach the WebUI. Keeping it on a private home network (LAN) and off the internet **lowers** the risk of most of these a lot, because an attacker first has to get onto your network. It never makes the risk zero: a compromised device, a guest on your Wi-Fi, or a malicious web page open in your own browser can still reach the WebUI.

"Does it affect this container?" was checked against the Forge Neo 2.31 source code (for example, whether Forge Neo uses the affected Gradio feature at all). Extensions can add Gradio features, so an extension can bring a "No" back into play. "Fixed in" is the first Gradio version with the fix; "none" means there is no fix yet.

| Severity | ID | What it means | Does it affect this container? | Fixed in |
|---|---|---|---|---|
| Critical | [CVE-2025-23042](https://osv.dev/vulnerability/CVE-2025-23042) | Gradio keeps a list of files the WebUI must never serve. On systems where file names ignore upper/lower case, changing the case of a name slips past that list. | **Unlikely.** The container runs Linux, where file names are case-sensitive, so the trick does not work on the container's own files. | 5.6.0 |
| High | [CVE-2024-10569](https://osv.dev/vulnerability/CVE-2024-10569) | Uploading a "zip bomb" (a tiny file that expands enormously) into a table input can crash the server. | **Not in Forge Neo itself**: it has no table input. An extension could add one. A crash would be restarted automatically. | none |
| High | [CVE-2024-10624](https://osv.dev/vulnerability/CVE-2024-10624) | Typing a specially crafted date or time can make the server's CPU spin for a long time. | **No.** Forge Neo has no date/time input. | none |
| High | [CVE-2024-10648](https://osv.dev/vulnerability/CVE-2024-10648) | A trick in the audio component can empty out a file the server can write to. | **Very unlikely.** Forge Neo only uses audio to play a finished-sound, which users cannot send anything to. | none |
| High | [CVE-2024-47867](https://osv.dev/vulnerability/CVE-2024-47867) | The helper Gradio downloads for public share links is not checked for tampering. | **Not by default.** Only matters if you add `--share`. Don't. | 5.0.0 |
| High | [CVE-2024-47870](https://osv.dev/vulnerability/CVE-2024-47870) | A timing trick can make the WebUI page send your traffic, including your login session, to an attacker's server. | **Yes, possibly.** Someone must be able to reach the WebUI. On a private LAN that means a device or person already on your network; on the internet, anyone. | 5.0.0 |
| High | [CVE-2024-47871](https://osv.dev/vulnerability/CVE-2024-47871) | Public share links use an unencrypted connection, so uploads can be read or changed in transit. | **Not by default.** Only with `--share`. | 5.0.0 |
| High | [CVE-2024-8966](https://osv.dev/vulnerability/CVE-2024-8966) | An upload with an absurdly long internal separator keeps the server busy and unreachable. | **Yes.** Forge Neo accepts uploads. Effect: the WebUI stops responding until the request ends. No data is exposed. Anyone who can reach the WebUI could try it, so exposure to the internet raises this a lot. | none |
| High | [CVE-2026-28414](https://osv.dev/vulnerability/CVE-2026-28414) | On Windows with Python 3.13+, an attacker can read any file. | **No.** Windows only; this container is Linux. | 6.7.0 |
| High | [CVE-2026-28416](https://osv.dev/vulnerability/CVE-2026-28416) | Apps that load another Gradio app from Hugging Face can be tricked into making web requests for an attacker. | **No.** Forge Neo does not load remote Gradio apps. | 6.6.0 |
| High | [CVE-2026-48545](https://osv.dev/vulnerability/CVE-2026-48545) | Apps that proxy Hugging Face Spaces can have cookies injected across users. | **No.** Same reason: no remote Spaces are loaded. | 6.15.0 |
| High | [CVE-2026-49119](https://osv.dev/vulnerability/CVE-2026-49119) | The file-browser component can be tricked into reading files outside its folder. | **No.** Forge Neo does not use that component. | 6.16.0 |
| Moderate | [CVE-2024-12217](https://osv.dev/vulnerability/CVE-2024-12217) | On Windows, a special file-name syntax slips past the blocked-files list. | **No.** Windows only. | none |
| Moderate | [CVE-2024-47164](https://osv.dev/vulnerability/CVE-2024-47164) | A check that a file is inside an allowed folder can be fooled with `..` paths, which could expose files. | **Possibly.** It could expose files the container can read, such as settings. Your models and images are already visible to anyone logged in. | 5.0.0 |
| Moderate | [CVE-2024-47165](https://osv.dev/vulnerability/CVE-2024-47165) | When the WebUI is opened as `localhost`, a hostile web page in your browser can send requests to it. | **Mostly no.** On Unraid you open it by IP or hostname, not `localhost`. Being on your LAN does not protect against this one, because the request comes from your own browser. | 5.0.0 |
| Moderate | [CVE-2024-47167](https://osv.dev/vulnerability/CVE-2024-47167) | The server can be made to fetch any web address, letting an attacker probe other devices on your network through it. | **Possibly**, for someone who can reach the WebUI. Worth knowing because the WebUI sits inside your network. | 5.0.0 |
| Moderate | [CVE-2024-47868](https://osv.dev/vulnerability/CVE-2024-47868) | Several components can be made to hand back files they should not. | **Possibly.** Same kind of exposure as CVE-2024-47164. | 5.0.0 |
| Moderate | [CVE-2024-47872](https://osv.dev/vulnerability/CVE-2024-47872) | A logged-in user can upload an HTML or SVG file with script in it; whoever opens it runs that script in their browser. | **Only matters with several users.** If you are the only one who logs in, there is nobody to target. | 5.0.0 |
| Moderate | [CVE-2025-48889](https://osv.dev/vulnerability/CVE-2025-48889) | Gradio's "flagging" feature can be made to copy files and fill the disk. | **No.** Forge Neo does not use flagging. | 5.31.0 |
| Moderate | [CVE-2026-28415](https://osv.dev/vulnerability/CVE-2026-28415) | An open redirect in Gradio's Hugging Face login flow. | **No.** That login flow is not used; this container uses its own password login. | 6.6.0 |
| Low | [CVE-2026-10783](https://osv.dev/vulnerability/CVE-2026-10783) | A weak checksum in the audio cache. | **No practical effect** here. | 6.15.1 |
| Low | [CVE-2026-27167](https://osv.dev/vulnerability/CVE-2026-27167) | With Hugging Face login buttons outside Hugging Face, the server's own Hugging Face token can leak. | **No.** No such login button is used, and the container has no Hugging Face token unless you add one. | 6.6.0 |
| Low | [GHSA-26jh-r8g2-6fpr](https://osv.dev/vulnerability/GHSA-26jh-r8g2-6fpr) | Drop-down menus accept values that are not in the list if someone sends a hand-made request. | **Yes, minor.** At worst, a setting gets an unexpected value. | 5.0.0 |

Source: [OSV](https://osv.dev/list?ecosystem=PyPI&q=gradio), package `gradio`, version 4.44.1. Plain-English summaries are mine; follow each link for the official description.

### Other packages flagged by the image scan

The build scans the finished image with [Trivy](https://trivy.dev/). Besides Gradio, its first scan found 21 high-rated issues in Python packages that Forge Neo pins. None were critical, and the operating system layer had none.

**Fixed in this image (10)** by upgrading past Forge Neo's pinned versions. This is a mitigation attempt (maintainer's choice) that Forge Neo does not test, so it may break things:

| Package | Forge Neo pins | This image | What it fixes, in plain English |
|---|---|---|---|
| GitPython | 3.1.62 | 3.2.1 | 5 issues, including running code or reading files through a malicious git repository. This matters here because the WebUI installs extensions from git repositories, and extension installs are on by default. |
| setuptools | 78.1.0 | 81.0.0 | 3 issues (in setuptools and two helpers it bundles) that only matter while packages are being installed. 81.0.0 is the newest release that still includes `pkg_resources`, which a Forge Neo built-in preprocessor needs. |
| diffusers | 0.37.1 | 0.38.0 | 2 issues where a downloaded model could run its own code even when that is supposed to be blocked. |

**Accepted (11)** because the fix needs a major new version that Forge Neo does not support, or because no fixed release exists yet:

| Package | ID | What it means | Does it affect this container? |
|---|---|---|---|
| transformers 4.57.6 | [CVE-2026-4372](https://osv.dev/vulnerability/CVE-2026-4372), [CVE-2026-5241](https://osv.dev/vulnerability/CVE-2026-5241) | Loading a model from Hugging Face that ships its own code could run that code, even with the safety switch off. Fixed only in transformers 5.x. | **Low.** Forge Neo loads model files you put in `/data`; it does not normally download models with custom code. Only add models from sources you trust. |
| transformers 4.57.6 | [CVE-2026-9856](https://osv.dev/vulnerability/CVE-2026-9856) | Saving a model with a crafted template name can write files outside the intended folder. | **Low.** Forge Neo does not save models through this function in normal use. |
| protobuf 4.25.9 | [CVE-2026-0994](https://osv.dev/vulnerability/CVE-2026-0994) | A crafted data file can crash the reader with deep nesting. Fixed only in protobuf 5.x/6.x. | **Low.** Only when a crafted file is loaded, for example through an untrusted model or extension. A crash is restarted automatically. |
| starlette 0.50.0 | [CVE-2026-48818](https://osv.dev/vulnerability/CVE-2026-48818) | On Windows, a crafted path can make the server reach out to another machine. | **No.** Windows only. |
| starlette 0.50.0 | [CVE-2026-54283](https://osv.dev/vulnerability/CVE-2026-54283) | Size limits are skipped for one kind of form, so a huge form can tie up memory. Fixed only in starlette 1.x, which needs a newer FastAPI than Forge Neo and Gradio 4 support. | **Yes, possibly.** The login form is that kind of form, so someone who can reach the WebUI could try it before logging in. A DoS, not a break-in. Keeping it off the internet lowers this a lot. |
| msgpack 1.1.2, urllib3 2.7.0, setuptools 70.3.0 (bundled inside pip) | [CVE-2026-114613](https://osv.dev/vulnerability/CVE-2026-114613), [GHSA-6v7p-g79w-8964](https://osv.dev/vulnerability/GHSA-6v7p-g79w-8964), [CVE-2026-97687](https://osv.dev/vulnerability/CVE-2026-97687), [CVE-2026-97689](https://osv.dev/vulnerability/CVE-2026-97689), [CVE-2025-47273](https://osv.dev/vulnerability/CVE-2025-47273) | Memory and crash issues, a proxy setting override, and a path issue in old copies that pip carries inside itself. pip 26.2.2 is the newest pip, so there is no update yet. | **Low.** These copies only run while pip installs packages for an extension. The WebUI's own urllib3 and setuptools are already the fixed versions (the build checks this). |

Each accepted item is listed in [`.trivyignore`](.trivyignore) with its reason and the same 2027-01-31 expiry.

### Forge Neo issues (not Gradio)

Found in a review of Forge Neo 2.31 and not fixed by this container:

- **Stored XSS in the extra-networks cards** (`modules/ui_extra_networks.py`): model file names and search terms are not escaped. A model with a crafted file name or metadata could run script in your browser. Same pattern as AUTOMATIC1111's CVE-2026-111984.
- **No size limit when reading `.safetensors` metadata** (`modules/sd_models.py`): a crafted model file can use a lot of memory. Same pattern as AUTOMATIC1111's CVE-2026-111985.

**Can this container fix them?** Both have small, well-understood fixes. Patching Forge Neo's code inside the image is possible, but it means this image no longer runs exactly the upstream code. That is being considered; until then, the safest protection is to only add models from sources you trust. The plan is also to report both upstream.

Forge Neo did remove AUTOMATIC1111's `.yaml` model-config code-execution path (CVE-2026-111986), and it always loads checkpoints with PyTorch's safer `weights_only=True` mode.

### Risks from how this container works

| Risk | Why it exists | What you can do |
|---|---|---|
| Default login `admin` / `changeme` on first start | So the WebUI is never without a login | Change it right away. The log warns until you do. |
| Password guessing | Gradio itself has no limit on login attempts | This container locks a username after 5 failures for 15 minutes ([Login protection](#login-protection)). Keep it off the internet as well. |
| Extensions run their own code, and anyone who can log in can install one | That is how WebUI extensions work; installing from the WebUI is on by default | Only install extensions you trust. Remove `--enable-insecure-extension-access` from Extra Args to lock the Extensions tab. |
| `/data/python-user` holds packages installed by extensions, and runs on every start | The image itself is read-only, so extension packages live here | If you suspect a problem, delete that folder and restart the container. Extensions reinstall what they need during that start. |
| API password in an environment variable | Only if you enable the API **and** set `API_AUTH_FILE_MODE=mirror-webui-file`; the WebUI has no file option for API auth | Leave the API off unless you need it |
| A compiler is included in the image | Some extensions compile code when they install | None needed; a compromised extension could already run code anyway |
| A few packages installed by Forge Neo's built-in ControlNet preprocessors are not version-pinned | Forge Neo does not pin them | They are scanned with the rest of the image |
| The build ignores vulnerabilities that have no fix yet | Otherwise no image could ever be published | The weekly scan still reports them |

### How to keep your risk low

- Use it only on your home network. Do not forward its port to the internet.
- Change the default password, and use HTTPS (the default).
- For two-factor login or passkeys, put an authenticating reverse proxy such as [Authelia](https://www.authelia.com/) or [Authentik](https://goauthentik.io/) in front. The WebUI itself only supports a username and password.
- Only add models and extensions from sources you trust.
- Update when a new image is published.

If you find something I missed, please see [SECURITY.md](SECURITY.md) or open an issue.

---

## Prerequisites

Before you start, make sure you have:

| Requirement | Details |
|---|---|
| **Unraid** | Built and used on Unraid 7.3.4. Older versions may work if the NVIDIA Driver plugin offers driver 580 or newer for them. |
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
   - Bridge: `https://<unraid-ip>:7860`
   - Host: `https://<unraid-ip>:7860`
   - Custom network: `https://<container-ip>:7860`

   You can also use a hostname instead of the IP, for example `https://<your-server-name>:7860`. That is the name of your Unraid server (Settings → Identification; Unraid's default is `Tower`), which many home networks also answer as `<your-server-name>.local`, or any DNS name you set up. Add that name to `WEBUI_TLS_HOSTNAMES` so the certificate matches it. Recommended: the server's full hostname (FQDN, the complete address like `myserver.example.com`) first, then the server's IP, comma-separated with no spaces, for example `myserver.example.com,192.168.1.10`. Note the **https**: plain `http://` does not work while HTTPS is on. The first time, your browser warns about the self-signed certificate; see [HTTPS / TLS](#https--tls).

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
HTTPS enabled with a self-signed certificate. Your browser will warn once; compare this fingerprint before accepting:
  SHA-256 fingerprint: 8B:56:E7:...
...
Launching Web UI with arguments: --listen --port 7860 --data-dir /data --enable-insecure-extension-access --gradio-auth-path <redacted> --tls-keyfile /config/tls/selfsigned.key --tls-certfile /config/tls/selfsigned.crt
...
Running on local URL: https://localhost:7860
```

A `[READY]` box appears once the WebUI accepts connections. If the container finds no model, it says so before launch. That is **normal**. See [Getting Your First Model](#getting-your-first-model).

### What if something goes wrong?

- Extensions can install their own Python packages on start. Those go to `/data/python-user`, never into the image. If an extension breaks things (for example by installing a different PyTorch), delete that folder on the host and restart. The container checks the PyTorch version on every start and tells you when this happens.
- If you reuse settings from an older WebUI (for example AUTOMATIC1111), Forge Neo cannot use them. The container moves `config.json` and `ui-config.json` aside as dated backups (`*.pre-neo-<date>.bak`, in the appdata `webui/` folder), starts with default settings, and says so in the log. Nothing is deleted.

---

## Getting Your First Model

After the container starts, you will see a login page. Log in with `admin` / `changeme` (the default credentials). If you have not added a model yet, the WebUI starts but cannot generate images. This is expected.

You need at least one model (checkpoint) to generate images. Models are usually `.safetensors` files (Neo also loads `.gguf` and `.ckpt`), typically 2–7 GB each. Forge Neo also runs newer model families such as Flux, Qwen and Wan.

### Option: a CivitAI browser extension

A CivitAI browser extension lets you search [CivitAI](https://civitai.com/) and download models straight into the right folder from inside the WebUI. This is how I do it.

> [!NOTE]
> I am not affiliated with any of these projects and do not vouch for their code. This is just the process I use. Extensions run their own code inside the container, so review an extension before you install it.

**Extensions and Forge Neo, in short:**

- Many AUTOMATIC1111 extensions do not work on Forge Neo. Often someone has made a fork (a modified copy) for Neo, so search GitHub for the extension's name plus "neo" or "forge".
- The community keeps a list of Neo-compatible forks: [Extensions for Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/discussions/1128) (a discussion in the Forge Neo repository, maintained by a user, not by Haoming02). Start there.
- **The Extensions → Available tab is the AUTOMATIC1111 list.** Everything you find there was written for the original AUTOMATIC1111 WebUI and may or may not work on Forge Neo. Extensions made for Forge Neo are **not** listed there at all (checked in the Forge Neo 2.31 source: it loads AUTOMATIC1111's extension index). Install Neo extensions with **Install from URL** instead.
- If an extension from that tab does not work, that is not a Forge Neo or container bug. Please do not report it to Forge Neo; look for a Neo fork instead.
- Forge Neo's own README says it ignores issues about third-party extensions, so report extension problems to the extension's author.

**CivitAI browser extensions I know of (as of 2026-10-29):**

| Extension | Forge Neo? | Notes |
|---|---|---|
| [CivitAI Browser Neo](https://github.com/eduardoabreu81/sd-civitai-browser-neo) | Made for Forge Neo | Rebuilt from CivitAI Browser+ for Neo. The one I use. |
| [CivBrowser](https://github.com/SignalFlagZ/sd-webui-civbrowser) | "Experimental" per its README | Actively updated. Not tested here. |
| [CivitAI Browser+](https://github.com/BlafKing/sd-civitai-browser-plus) | No | Archived on GitHub (no more updates). Listed so you know why to skip it. |

> [!WARNING]
> In April 2026 CivitAI moved its adult content to a separate domain (`civitai.red`), and some extensions could no longer download from there ([example report](https://github.com/eduardoabreu81/sd-civitai-browser-neo/issues/6)). CivitAI changes break these extensions from time to time; check the extension's issue tracker if downloads fail.

#### Installing an extension from its URL

1. In the WebUI, go to **Extensions** → **Install from URL**.
2. Paste the extension's repository URL, for example `https://github.com/eduardoabreu81/sd-civitai-browser-neo.git`.
3. Click **Install**, then go to **Installed** → **Apply and restart UI**. The container restarts the WebUI for you (see [Automatic restart](#automatic-restart)).

### Manual download

If you prefer to download models manually:

1. Download a `.safetensors` file from [CivitAI](https://civitai.com/), [Hugging Face](https://huggingface.co/), or another trusted source.
2. Place it in the models directory on your Unraid host:
   ```
   <data-path>/models/Stable-diffusion/
   ```
   `<data-path>` means the host folder you mapped to `/data` (the template default is `/mnt/user/ai/data`).
   You can copy files via SMB share, SCP, or the Unraid terminal:
   ```bash
   # Example: download a model via the Unraid terminal
   wget -P <data-path>/models/Stable-diffusion/ <model-download-url>
   ```
3. In the WebUI, click the **refresh** button next to the checkpoint dropdown (top left) to detect the new model, then select it.

### Model types you might encounter

| Type | Where it goes | Typical size |
|---|---|---|
| Checkpoint (SD 1.5) | `models/Stable-diffusion/` | 2–4 GB |
| Checkpoint (SDXL) | `models/Stable-diffusion/` | 6–7 GB |
| LoRA / LyCORIS | `models/Lora/` | 10–200 MB |
| VAE | `models/VAE/` | 300–800 MB |
| Textual Inversion / Embedding | `models/embeddings/` | 10–100 KB |

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
├── auth/
│   └── webui-auth.txt            Login credentials (chmod 600)
└── tls/                          HTTPS certificate and key (folder chmod 700)
    ├── selfsigned.crt / .key     Created automatically
    └── custom.crt / .key         Optional: your own certificate

/data/                            (host: <data-path>, template default /mnt/user/ai/data/)
├── models/
│   ├── Stable-diffusion/         Model checkpoints (.safetensors, .gguf, .ckpt)
│   ├── VAE/                      VAE models
│   ├── Lora/                     LoRA/LyCORIS models
│   └── embeddings/               Textual inversions
├── output/                       Generated images
├── extensions/                   Installed extensions
├── python-user/                  Packages installed by extensions (safe to delete)
├── pip-cache/                    Cached pip downloads for extensions
└── tmp/                          Temporary files (cleaned on start)
```

**Why two paths?** `/config` holds small configuration files that belong in your appdata backup. `/data` holds large, fast-growing content (models, outputs, extensions) that should live on a drive with plenty of space, preferably an SSD.

---

## Configuration

### Authentication defaults

This container enables the WebUI login page by default. The API is disabled by default unless you explicitly add `--api` to `COMMANDLINE_ARGS`.

> [!IMPORTANT]
> **Maintainer's choice.** The container creates a starter login and still starts, so the WebUI is never left without one. The trade-off is a weak password until you change it, and the log keeps warning until you do.

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

> [!TIP]
> **More detail below:** click **Auth file details: permissions, SMB access, API mirroring** to expand it.

<details>
<summary><b>🔽 Click to expand: Auth file details: permissions, SMB access, API mirroring</b></summary>

#### File permissions

The auth file is created with `chmod 600` (owner read/write only). This prevents other processes and containers sharing the `/data` volume from reading your credentials.

**Unraid terminal (recommended):** The Unraid terminal runs as `root`, so root always has access regardless of permissions.

**SMB share:** Unraid serves SMB. If you access the share with your Unraid admin credentials, you can read and write `chmod 600` files normally. However, because the container runs as `nobody` (UID 99) and Unraid's Samba guest account is also `nobody` (UID 99), a **Public** or **Secure** share maps anonymous connections to the same UID that owns the auth file, meaning SMB guests can read it. Set the `appdata` share to **Private** if you want to restrict SMB access to this file.

**In summary:** Unraid terminal or SSH is the simplest and most reliable method. Authenticated SMB (Private share) works. The `chmod 600` permission does **not** protect the auth file from SMB access on a Public or Secure share. The Samba guest account maps to the file's owner UID.

#### API auth mirroring

If API is enabled (`--api`), the container can copy the auth-file credentials into `--api-auth`. This is **off** by default. Control it with:

- `API_AUTH_FILE_MODE=mirror-webui-file`: copy the credentials
- `API_AUTH_FILE_MODE=disabled` (default): leave API auth to you

> [!WARNING]
> **API auth exposure:** The WebUI's `--api-auth` flag accepts credentials as a plain string (not a file path). When mirroring is active, the container appends `--api-auth user:password` to the `COMMANDLINE_ARGS` environment variable. This means credentials are readable via `docker inspect` and `/proc/<pid>/environ` by any process or user that can inspect the container. This is a known upstream limitation of the WebUI's API auth mechanism (inherited from AUTOMATIC1111). There is no file-based equivalent for `--api-auth`. If this exposure is unacceptable for your environment, set `API_AUTH_FILE_MODE=disabled` and do not enable the API, or place the entire service behind a reverse proxy that handles API auth at the network layer.

#### Manual auth flags

If you want to manage authentication manually, you can still pass your own auth flags in `COMMANDLINE_ARGS`:

- `--gradio-auth username:password`
- `--gradio-auth-path /path/to/auth-file`
- `--api-auth username:password`

If you provide your own auth flags in `COMMANDLINE_ARGS`, the container will not add duplicate auth arguments.
If `--api-auth` is provided without `--api`, startup logs now warn that API auth flags are ignored until API is explicitly enabled.

</details>

### Login protection

Gradio's login page has no limit on password guesses. This container adds one. It is this project's own code (in `WebUI/launch.py`), not part of Forge Neo or Gradio.

> [!IMPORTANT]
> **Maintainer's choice.** 5 failed attempts locks that username for 15 minutes. That slows guessing a lot, but a few typos can lock you out too.

**How it works:**
- Every failed login waits 1 second before answering.
- After `WEBUI_LOGIN_MAX_ATTEMPTS` (default **5**) failed logins for the same username within the lockout window, that username is locked for `WEBUI_LOGIN_LOCKOUT_MINUTES` (default **15**). While locked, even the correct password is refused.
- A successful login clears that username's failures. Other usernames are not affected.
- Unknown usernames are treated the same way, so attempts don't reveal which usernames exist.
- The container log shows each failed login and each lockout, with the username but never the password.
- Passwords are compared in constant time, so response timing reveals nothing.

**Locked yourself out?** Restart the container. Lockouts are kept in memory only, so a restart clears them all. Or wait out the lockout time.

**Limits:** it locks per username, not per device, because Gradio does not tell the login check who is connecting. Someone guessing can therefore lock *your* username for a while (a nuisance, not a break-in). It does not cover the separate API login (`--api-auth`). Set `WEBUI_LOGIN_MAX_ATTEMPTS=0` to turn it off.

**Two-factor login and passkeys** are not possible on Gradio's login page. For those, put an authenticating reverse proxy in front, such as [Authelia](https://www.authelia.com/) or [Authentik](https://goauthentik.io/).

### `COMMANDLINE_ARGS`

`COMMANDLINE_ARGS` is passed directly to `launch.py`.

> [!NOTE]
> **Log redaction:** Sensitive auth flags (`--gradio-auth`, `--gradio-auth-path`, `--api-auth`) have their values replaced with `<redacted>` in startup log output. The flag names remain visible so you can confirm they are active.

**Default** (from the Unraid template):

```
--listen --port 7860 --data-dir /data --enable-insecure-extension-access
```

> [!WARNING]
> Forge Neo stops at startup on any flag it does not know. Check [Neo's flag list](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo) before adding one. Three common A1111 flags that Neo removed (`--no-download-sd-model`, `--disable-safe-unpickle`, `--allow-code`) are dropped automatically with a log message.

> [!TIP]
> The container automatically appends `--gradio-auth-path <runtime-auth-file>` at launch (see [Authentication](#authentication-defaults)). You do not need to add auth flags yourself. They are injected by `start.sh` based on your `WEBUI_AUTH_FILE`.

API is intentionally not part of the default args. Add `--api` only when you explicitly need API access.

Use the defaults as a starting point, then tune for your own hardware, risk tolerance, and workflow.

For a complete list of supported arguments, see the [Forge Neo README](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo).

> [!TIP]
> **More detail below:** click **Flag details and security considerations** to expand it.

<details>
<summary><b>🔽 Click to expand: Flag details and security considerations</b></summary>

- **Attention (`--xformers`, `--sage`, `--flash`)** (not set by default): The image ships without these packages, so Neo uses PyTorch's built-in attention, which Neo's README calls "usually as fast, and also more stable". These flags only *install* the package (into `/data/python-user`) on the next start. Once installed, Neo uses it automatically. Use `--disable-xformers` (and so on) to switch one off again.

- **`--enable-insecure-extension-access`** (set by default): Allows installing/updating extensions from the WebUI. Risk: anyone who can log in can install an extension from any git URL, and its code runs inside the container on every start. Remove it for a safer posture and manage extensions on disk.

- **`--api`** (not set by default): Enables the REST API. Only add this when you explicitly need programmatic access.

If you change these arguments, keep in mind that some flags can weaken the container's security posture. Be especially careful with anything that increases network exposure.

</details>

### HTTPS / TLS

> [!IMPORTANT]
> **Maintainer's choice.** HTTPS with a self-signed certificate is on by default. It encrypts traffic on your network without setup, at the cost of one browser warning. Use your own certificate or `WEBUI_TLS=off` to change it (both below).

HTTPS is **on by default** (`WEBUI_TLS=auto`). This is this container's own feature, not part of Forge Neo (Forge Neo only accepts certificate files you hand it). On the first start, the container creates a self-signed certificate in `/config/tls/` and serves the WebUI over `https://`.

**The first visit:** your browser warns that the certificate is not trusted, because no public authority signed it. Before you accept, compare the certificate's SHA-256 fingerprint (in the browser's certificate details) with the one printed in the container log. If they match, you are talking to your own container. Accept the warning once per browser.

**How it works:**

- The certificate uses ECDSA P-256 and is valid for 825 days, the longest that Apple devices accept. It is renewed automatically 30 days before it expires.
- The private key is created with owner-only permissions (`600`) inside a folder only the container user can open (`700`). It is never printed to the log.
- The certificate covers `localhost`, `127.0.0.1`, the container's hostname, `WEBUI_HOST_IP` if you set it, and any names you list in `WEBUI_TLS_HOSTNAMES`. Recommended format: the full hostname (FQDN) first, then the server's IP, comma-separated with no spaces, for example `myserver.example.com,192.168.1.10`. Listing both lets you open the WebUI either way without a name-mismatch warning. Change that list and a new certificate is made on the next start. Entries that are not a plain hostname or IPv4 address stop startup with an error.
- Certificate checks stay on. Other setups often add `--disable-tls-verify`; this container adds its certificate to the trust list Gradio uses instead, so Gradio's own startup check still verifies the connection.
- The healthcheck and the `[READY]` banner work over HTTPS (the banner shows the `https://` address).

**Use your own certificate:** put `custom.crt` (the certificate, plus any intermediate certificates) and `custom.key` in `/config/tls/` (on Unraid: `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/tls/`), then restart. The container checks that the key belongs to the certificate, refuses to start if it does not, and warns when the certificate is expired or expires within 30 days. Remove both files to go back to the self-signed certificate.

**Turn HTTPS off:** set `WEBUI_TLS=off`. Logins and images then cross your network unencrypted.

**Manage it yourself:** if `COMMANDLINE_ARGS` contains `--tls-keyfile` or `--tls-certfile`, the container leaves HTTPS entirely to you.

**Reverse proxy:** if you put Nginx Proxy Manager, Traefik, Caddy or similar in front, you can either keep HTTPS on and point the proxy at `https://`, or set `WEBUI_TLS=off` and let the proxy handle HTTPS. Keep the proxy on your LAN or behind a VPN.

> [!WARNING]
> Avoid the Auto TLS-HTTPS extension. It was written for AUTOMATIC1111, and on Forge Neo it can crash startup on Python 3.13 (it pulls an old `trio` package). The built-in HTTPS above replaces it.

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

> [!TIP]
> **More detail below:** click **File permissions and umask** to expand it.

<details>
<summary><b>🔽 Click to expand: File permissions and umask</b></summary>

**Maintainer's choice:** I manage files over SMB, so no strict `UMASK` is set. The trade-off is that other users and apps on the server can read your images and models.

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

> [!TIP]
> **More detail below:** click **What each security flag does** to expand it.

<details>
<summary><b>🔽 Click to expand: What each security flag does</b></summary>

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

> [!IMPORTANT]
> **Maintainer's choice.** On by default. A WebUI that crashes over and over keeps being restarted, with growing delays. Set `RESTART_ON_EXIT=0` to let the container stop instead.

The container automatically restarts the WebUI process if it exits, so you do not have to restart the container yourself.

**Why this matters:** in most WebUI containers, the WebUI *is* the container's main process. When it exits, the container stops. That happens after a crash, and also every time you click **Apply and restart UI** after installing an extension, because the WebUI shuts itself down expecting a launcher to start it again. You would then have to go to the Unraid Docker page and start the container by hand. Here, `start.sh` acts as that launcher: it notices the exit and starts the WebUI again within seconds.

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
- If the log mentions an unrecognized argument, remove that flag from `COMMANDLINE_ARGS`. Forge Neo stops on unknown flags.

### The WebUI loads but cannot generate
- You probably have no model yet. See [Getting Your First Model](#getting-your-first-model).

### The GPU is not being used
- Re-run the [GPU sanity check](#gpu-sanity-check).
- Confirm the container still has `--runtime=nvidia` in Extra Parameters.
- Confirm Unraid is providing GPU access to the container.
- Confirm the host NVIDIA driver/plugin is working.
- If the WebUI fails with a message like `PyTorch is not able to access any compute device (GPU)`, you can temporarily add `--skip-torch-cuda-test` to `COMMANDLINE_ARGS` for troubleshooting. I do not recommend making that your long-term default, because it can hide a real GPU passthrough problem.
- If the startup sanity check reports a torch version mismatch, an extension replaced PyTorch. Delete `<data-path>/python-user` and restart.

### I am seeing permission errors
- Check that your mapped host folders are writable by the configured UID/GID.
- If `/data` ended up owned by root (e.g., after deleting and Docker recreating the host directory), the container self-heals this automatically. See below.
- If using `--read-only`, make sure required writable paths are explicitly mounted.

### Error: `Operation not permitted` in entrypoint (`chmod` or `setpriv`)
- If logs show messages like `chmod: changing permissions of '/data': Operation not permitted` or `setpriv: setresuid failed`, the host/runtime is denying metadata or UID/GID transitions.
- The container prints a short runtime diagnostic line with `NoNewPrivs`, `Seccomp`, and `CapEff` values to help identify this class of restriction.
- Typical causes: rootless/user-namespace remap behavior, no-new-privileges hardening, NFS root-squash exports, or share ACL/mount policy restrictions.
- Fix on host first, then restart:

```bash
chown nobody:users <data-path>
chmod 775 <data-path>
```

### The container fails to start after deleting `/data`

If you delete the host data directory (`<data-path>`), Docker may recreate it owned by `root` on next start.

**In most cases this is fully automatic.** The container entrypoint runs as root, detects the wrong ownership, corrects it, then drops to the unprivileged app user before startup continues. You should see a log line like:

```
[entrypoint] /data is owned by uid=0:gid=0, expected 99:100.
[entrypoint] Correcting ownership and permissions under /data...
[entrypoint] Repaired 42 files under /data. Continuing startup.
```

> [!WARNING]
> **Known issue:** the auto-fix re-owns **everything** under `/data`, including any other share you map inside it (for example a separate models share mapped to `/data/models`). If another app also uses that share and runs as a different user, it may lose write access. Until this is fixed, don't map shares that other containers use inside `/data`, or set `APP_UID`/`APP_GID` to the owner those files already have.

**If the auto-fix fails** (NFS shares with root squash, unusual SELinux policies, or other host-side restrictions), correct ownership manually on the Unraid host and restart:

```bash
chown nobody:users <data-path>
chmod 775 <data-path>
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
| `COMMANDLINE_ARGS` | `--listen --port 7860 --data-dir /data --enable-insecure-extension-access` | Arguments passed directly to the WebUI launch command |
| `WEBUI_AUTH_FILE` | `/config/auth/webui-auth.txt` | Path to the managed authentication credentials file |
| `API_AUTH_FILE_MODE` | `disabled` | Set to `mirror-webui-file` to copy WebUI creds to `--api-auth` when `--api` is enabled |
| `RESTART_ON_EXIT` | `1` | `1` = restart WebUI after any exit; `0` = exit container on WebUI stop |
| `RESTART_DELAY` | `5` | Seconds to wait before restarting after a clean exit |
| `RESTART_DELAY_MAX` | `60` | Backoff ceiling (seconds) for crash restarts |
| `RESTART_MAX_ATTEMPTS` | `0` | `0` = retry indefinitely; N = stop after N consecutive crash restarts |
| `WEBUI_TLS` | `auto` | `auto` = HTTPS with your certificate or a self-signed one; `off` = plain HTTP. See [HTTPS / TLS](#https--tls). |
| `WEBUI_TLS_HOSTNAMES` | *(unset)* | Extra hostnames or IPv4 addresses for the self-signed certificate. Recommended: FQDN first, then IP, comma-separated with no spaces (`myserver.example.com,192.168.1.10`) |
| `WEBUI_LOGIN_MAX_ATTEMPTS` | `5` | Failed logins per username before a lockout; `0` turns login protection off |
| `WEBUI_LOGIN_LOCKOUT_MINUTES` | `15` | How long a lockout lasts (also the window failures are counted in) |
| `PYTHONUSERBASE` | `/data/python-user` | Where packages installed by extensions go |
| `WEBUI_HOST_IP` | *(unset)* | Address shown in the `[READY]` log banner, and added to the self-signed certificate. Set it to your Unraid IP in bridge mode, where the container can't see it. It does not change where the WebUI listens. |
| `APP_UID` | `99` | User ID the WebUI runs as (Unraid's `nobody`). On first start, `/data` and `/config` are re-owned to this user. Must not be `0`. Values other than the default are not tested. |
| `APP_GID` | `100` | Group ID the WebUI runs as (Unraid's `users`). Same rules as `APP_UID`. |
| `UMASK` | *(unset)* | Override default umask for all file creation (e.g., `022`) |
| `NO_COLOR` | *(unset)* | Set to `1` to suppress ANSI color codes in container logs |
| `TERM` | *(unset)* | Set to `dumb` to suppress ANSI color codes (alternative to `NO_COLOR`) |

## Migration Notes

### Coming from the old A1111 image

This is a new project. The old AUTOMATIC1111 container ([aegisnir/A1111-unraid](https://github.com/aegisnir/A1111-unraid)) and its image stay where they are, so existing installs keep working. To switch, add this template as a new container. Your models in `/data` work as they are.

- **Settings:** if you point this container at the old appdata folder, it renames `/config/a1111` to `/config/webui` on first start. A1111 settings are not compatible with Forge Neo, so the container then backs up `config.json` and `ui-config.json` (`*.pre-neo-<date>.bak`) and starts with defaults. The log lists the backup files.
- **Outputs:** Neo saves to `/data/output` (A1111 used `/data/outputs`). Your old images stay where they are. To keep using the old folder, set it in **Settings → Paths for Saving**.
- **Old Python files:** `/data/venv` and `/data/repositories` are no longer used. The container leaves them alone. Delete them to free space.
- **Extensions:** many A1111 extensions do not work on Neo. Check each one for a Neo version.
- **Flags:** `--enable-insecure-extension-access` is now a default (the old container had extension installs off). `--xformers` is no longer a default (see [`COMMANDLINE_ARGS`](#commandline_args)). `--no-download-sd-model`, `--disable-safe-unpickle` and `--allow-code` are removed by Neo and dropped automatically.

### Coming from another Forge Neo container

Your `config.json` already has Neo's version marker, so settings carry over. The entrypoint changes `/data` ownership to `99:100` on first start. If the old container ran as another user, test with a **copy** of the data first, because the old container may not be able to write to it afterwards. To keep the old owner instead, set `APP_UID` and `APP_GID` to match it before the first start.

### Extension management is on by default

> [!IMPORTANT]
> **Maintainer's choice.** I install extensions from the WebUI, so it is on. The trade-off and how to turn it off are below.

The WebUI normally blocks installing extensions from its Extensions tab when it is reachable over the network (`--listen`). This container turns that block **off** by default with `--enable-insecure-extension-access`, because installing extensions from the WebUI is how most people use it. (The old A1111 container had it off.)

> [!WARNING]
> With it on, **anyone who can log in can install an extension from any git URL, and that extension runs its own code inside the container** on every start. Protect your login: change the default password, keep the WebUI off the internet, and use HTTPS.

**How to turn it off:** remove `--enable-insecure-extension-access` from `COMMANDLINE_ARGS` (the template's Extra Args). The Extensions tab then only shows what is installed.

**Installing without the WebUI:** clone an extension into `<data-path>/extensions/` from the Unraid terminal, then restart the container. This works with the flag on or off.

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

### Build with the original Gradio 4.40.0

If Gradio 4.44.1 breaks something for you, you can build your own image with Forge Neo's original Gradio 4.40.0. This brings back the 5 vulnerabilities that 4.44.1 fixes (see [Known security issues](#known-security-issues)). You need a machine with Docker and about 30 GB of free space; the Unraid terminal works.

1. Download this repository and go into it:
   ```bash
   git clone https://github.com/aegisnir/sd-webui-forge-neo-unraid.git
   cd sd-webui-forge-neo-unraid
   ```
2. Build the image with the older Gradio. This takes a while and downloads several GB:
   ```bash
   docker build --build-arg GRADIO_VERSION=4.40.0 -t sd-webui-forge-neo-unraid:gradio-4.40.0 .
   ```
3. In Unraid, edit the container and set **Repository** to `sd-webui-forge-neo-unraid:gradio-4.40.0`, then **Apply**.

Unraid's "update available" check does not work for an image you built yourself; rebuild it to update.

### Image tags

The included `template.xml` defaults to the published GHCR image:

- Repository: `ghcr.io/aegisnir/sd-webui-forge-neo-unraid:dev`

Images are built by GitHub Actions. Every build is pushed as `:sha-<commit>`, scanned with Trivy, and only then published under its channel tag (`:dev`, `:latest`, or `:vX.Y.Z`). The `:sha-` tags stay available as rollback points. A `:sha-` tag can be pulled before its scan finishes, and a build that fails the scan keeps its `:sha-` tag, so use the channel tags unless you are rolling back to a build you know passed.

For local builds, change the repository to `sd-webui-forge-neo-unraid:local`. When a stable release is promoted, switch to `ghcr.io/aegisnir/sd-webui-forge-neo-unraid:latest`.

### Maintenance

This image will likely need occasional rebuilds to pick up upstream changes and dependency updates. At a minimum, keep an eye on:

- Upstream Forge Neo releases (a pull request opens automatically)
- Unraid updates
- NVIDIA driver/toolkit changes
- Any extensions or models you add yourself

The image pins `torch` and `torchvision` to the versions Forge Neo itself installs, and `gradio` one step newer (see [Known security issues](#known-security-issues)). When Neo changes them in a release, update the matching build arguments in the same pull request.

---

## Quick Reference

| Item | Value |
|---|---|
| **Default WebUI URL** | `https://<unraid-ip>:7860` (self-signed certificate) |
| **Default login** | `admin` / `changeme` |
| **Auth file (host)** | `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/auth/webui-auth.txt` |
| **Models directory (host)** | `<data-path>/models/Stable-diffusion/` |
| **Outputs directory (host)** | `<data-path>/output/` |
| **Config directory (host)** | `/mnt/user/appdata/SD-WebUI-Forge-Neo-Unraid/` |
| **Data directory (host)** | `<data-path>` (template default `/mnt/user/ai/data/`) |
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
