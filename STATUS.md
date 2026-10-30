# Project Status

> For change history and last updated date, see [git log](../../commits/dev).

## Completed

> Items up to "Release posture decided" describe the old AUTOMATIC1111 image (venv, xformers, `build-push.sh`). They are kept as history; the Forge Neo image no longer uses them.

- Container/runtime hardening implemented and documented:
  - read-only root filesystem
  - tmpfs for `/tmp`
  - `no-new-privileges`
  - `cap-drop=ALL` + minimal `cap-add` set (`CHOWN`, `FOWNER`, `SETUID`, `SETGID`)
  - default `--pids-limit=2048` with tuning guidance
- Automatic WebUI restart loop:
  - container restarts the WebUI process automatically on crash or clean exit (Restart button)
  - SIGTERM from Docker stop/Unraid exits the container cleanly without restart
  - crash (non-zero exit): exponential backoff up to `RESTART_DELAY_MAX`
  - clean exit (code 0): flat `RESTART_DELAY` before restart
  - configurable via: `RESTART_ON_EXIT`, `RESTART_DELAY`, `RESTART_DELAY_MAX`, `RESTART_MAX_ATTEMPTS`
- Appdata/data split:
  - `/config/webui/` holds WebUI config files (config.json, ui-config.json, styles.csv, config_states), backed up with appdata
  - `/data/` holds models, outputs, venv, extensions), large working set, outside appdata
  - auth file at `/config/auth/webui-auth.txt`
  - symlinks created at startup so A1111 finds everything at expected paths
  - automatic migration from old `/data/` paths on first start with new image
- Startup/bootstrap flow hardened:
  - persistent `/data/venv` and `/data/repositories`
  - read-only-safe symlink validation
  - free-space checks and clearer startup errors
  - `build-essential` + `python3-dev` in base image so C extension builds (e.g. hnswlib) work without workarounds
- Authentication flow improved:
  - default WebUI login enabled; auth-file seeded on first launch (`admin:changeme`)
  - `WEBUI_AUTH_FILE` support
  - API auth mirroring behavior controls
  - runtime auth-file sanitizer prevents Gradio crash on comments/blank lines
  - credential format validation with clear error messages
- Documentation and template:
  - template defaults to the published `:dev` image
  - README Quick Start updated with manual template import instructions (not yet in CA)
  - all `blob/main/` links in template.xml corrected to `blob/dev/`
  - explicit notes for expected `No checkpoints found` behavior with `--no-download-sd-model`
- Licensing/docs added:
  - AGPL-3.0 repo license
  - AGPL copy and third-party notices included
- Log credential redaction:
  - custom `launch.py` wrapper redacts sensitive auth flag values from log output
- Docker healthcheck:
  - `HEALTHCHECK` with conservative timers (10 min start grace, 2 min interval, 30 s timeout, 5 retries)
- Console output:
  - semantic color palette, pre-launch banner, inline annotations for known noisy messages
  - independent background port poller for `[READY]` banner
- Code quality:
  - both shell scripts pass `shellcheck` cleanly
- GitHub Actions CI:
  - automated shellcheck + security baseline checks run on push/PR to `dev` and `main`
  - extended with: `hadolint` (Dockerfile lint), `bandit` (Python security scan),
    `yamllint` (YAML validation), `trivy config` (Dockerfile misconfiguration scan),
    `gitleaks` (secret detection across git history)
  - `trivy-image.yml`: weekly scheduled CVE scan of the published GHCR image (fixable HIGH/CRITICAL only)
  - `.github/dependabot.yml`: automated version-bump PRs for GitHub Actions and Docker base image (weekly)
- Pre-release security audit: all findings fixed (29/29 checks pass)
- CUDA base upgraded from `nvidia/cuda:12.9.1-runtime-ubuntu22.04` to `13.0.2`;
  PyTorch index updated from `cu128` to `cu130`; pinned versions bumped:
  `torch` 2.7.0→2.10.0, `torchvision` 0.22.0→0.25.0, `xformers` 0.0.30→0.0.35
- xformers 0.0.35 CUDA extension fix: `torch` pinned back from 2.11.0→2.10.0 and
  `torchvision` from 0.26.0→0.25.0. The cu130 wheel was compiled against 2.10.0;
  mismatched versions silently disabled memory-efficient attention
- xformers pip install fix: added `--extra-index-url` to the xformers install in `start.sh`
  so pip resolves the cu130 wheel from the PyTorch index instead of the cu128 wheel from PyPI;
  without this flag the correct torch version alone is not enough. CUDA extensions still fail
- Real-world validation of v1.0.3 completed on RTX 4090 hardware:
  - `torch=2.10.0+cu130`, `torchvision=0.25.0+cu130`, `xformers=0.0.35` all confirmed loading
  - xformers CUDA extensions confirmed: no `xFormers can't load C++/CUDA extensions` warning
  - `[READY]` banner confirmed firing; WebUI confirmed reachable
- Log/monitor improvements (all from real-hardware validation findings):
  - `scripts/build-push.sh` added, a repeatable build+push helper for both `:dev` and `:v1.0.3` tags
  - pre-launch known-harmless table expanded: `resume_download` FutureWarning, CivitAI Shortcut
    `[ERROR]` schema notice, CivitAI Browser+ Basemodel fetch error
  - `[XFORMERS MISMATCH]` inline handler added: fires when stale cu128 wheel is detected,
    shows explicit venv-delete remediation
  - `[GPU MEMORY ERROR]` box updated with `PYTORCH_ALLOC_CONF=expandable_segments:True` as lead tip,
    Hires. fix callout, `--medvram` fallback; stale xformers tip replaced
  - Startup pause notice added after banner (gap lasts several minutes; prevents premature restarts)
  - All annotation box colors fixed: color set once on `┌` line, reset once on `└` line
- Release posture decided:
  - `v1.0.3` pre-release on `dev` branch (supersedes broken `v1.0.2`)
  - `main` and `:latest` frozen pending real-world validation

## In Progress

- Forge Neo rebase: published as `:dev` and running on the maintainer's server (2026-10-30, image
  `fb10561`). Working: login and lockout message, HTTPS, image generation, Restart button, extension
  install, launch options (CUDA malloc on, extension auto-update on), Spectrum Integrated, the 10-way
  layer split. Old A1111/Forge flags in Extra Launch Flags are now removed with a note instead of
  stopping Neo.
- Nightly update check: first run (started by hand, 2026-10-30) passed, committed
  `package_versions.txt` and published `:dev`. The registry build cache cut the next build to 8 minutes.
- Layer reuse confirmed: the update to `fb10561` on the maintainer's server took about 3 seconds.
- Lobe Theme layout fixes added as the built-in extension `lobe-theme-fixes`. The rules worked when
  pasted into a live browser tab; the Lobe-only scoping and the built image are not tested yet.

## Remaining

- Confirm the 4 AM ET scheduled run of `check-updates.yml` fires on its own (none ran on 2026-10-30;
  GitHub delays scheduled runs under load).
- Speed: compare CUDA malloc on vs off (batch of 5, fixed seed, run twice), then against the
  previous xformers-based setup.
- Investigate `driverInitFileInfo 599 result=11` log lines (generation works).
- After the first build works: switch the base image to plain `ubuntu:24.04` (digest-pinned).
  Ubuntu 22.04 standard support ends April 2027, and the `nvidia/cuda` base duplicates the CUDA
  libraries the torch wheels already install. Set `NVIDIA_VISIBLE_DEVICES` and
  `NVIDIA_DRIVER_CAPABILITIES` in the Dockerfile (the CUDA image set them), then re-test on the maintainer's server.
- Decide on optional TOTP 2FA and the two Forge Neo build-time patches (XSS escape, safetensors
  header size cap).
- Re-run fresh install, persistence, and read-only smoke tests before promoting `:latest`.
- CA App Store submission (deferred until `:latest` is ready).

## Session 14 Changes (adversarial code review remediation)

40-finding adversarial code review + fix plan executed across 8 commits on `dev`.

**Commits (not yet pushed):**
- `655ec0e` CRITICAL: stdout buffering, symlink traversal, default creds RCE chain
- `47fa9fe` HIGH: dead code, UID propagation, restart counter, torch URL, ownership, shlex.quote, API fallback
- `25456c7` MEDIUM: error reporting, GID drift, migration backup, model count, tmpfs nodev, caps strip, pip pin, ngrok redaction
- `85a244b` LOW: display bug, trap timing, dotfiles, SIGKILL escalation, DRY refactors, git version, SHELL -e, CI pins, build-essential docs
- `9c01164` Doc drift: color alignment, stale comments, timing math, env vars reference, dates, third-party licenses
- `8f7ba03` Post-impl: Dockerfile -e audit, build-push.sh comment, migration notes (breaking change), git-lfs cleanup
- `c5bcc4e` shellcheck: fixed `local` outside function, SC2317 exclusion for trap handlers
- `8d252ae` + pending: preflight report + CI comment count updates, shlex.quote test, STATUS.md update

**Security baseline:** 29/29 (shellcheck now enabled locally + in CI)

**Breaking change:** `--enable-insecure-extension-access` removed from defaults. Migration Notes section added to README.

**One deferred item:** shlex.quote integration test with running container (verified via standalone Python test with 8 adversarial inputs).

## Session 13 Changes (dev → main promotion prep)

- `template.xml`: branch refs updated to `main`/`latest` for promotion prep
  (reverted to `:dev` pending merge; `main` refs will land with the actual merge commit)
- `scripts/build-push.sh`: now branch-aware. Pushes `:latest` + `:<version>` on `main`, `:dev` + `:<version>` on dev
- PR #6 opened: dev → main, all CI checks pass

## Notes

- Last A1111 image: `:v1.0.3` (old package name). New image: `ghcr.io/aegisnir/sd-webui-forge-neo-unraid`, `:dev` published 2026-10-29.
- For production-style deployments, use `WEBUI_AUTH_FILE` when possible and treat logs as sensitive.
