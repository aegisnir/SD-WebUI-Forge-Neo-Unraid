# Changelog

This file is here to keep a simple record of notable changes.

I am keeping this intentionally lightweight. This is a personal, AI-assisted hobby project, so the goal is to make changes easier to follow, not to pretend there is a full formal release process behind every update.


## [Unreleased]

### Fixed (first Aether test, 2026-10-29)

- **Crash loop on first start:** Forge Neo unpacks its bundled tokenizer files into its own program folder on first start, which is read-only in this image (`OSError: [Errno 30] Read-only file system`). The build now unpacks them, and checks their SHA-256 using Neo's own code.
- **Built-in preprocessor packages installed at startup instead of build time:** Neo skips all extension installers when `<data-dir>/extensions` doesn't exist, so the build never installed the ControlNet preprocessor packages and they were downloaded into `/data/python-user` on first start. The build now creates that folder, so they are baked in and covered by the image scan.

### Added (template: launch options)

- **Launch options instead of a flag string.** About 40 Forge Neo flags are template options (dropdowns), common ones visible and the rest under "Show more settings" (`NEO_*` variables). Defaults match Forge Neo (all off), except two maintainer's choices: extension installs from the WebUI and `--cuda-malloc` (Neo's own RTX recommendation), both on.
- **Extra Launch Flags** (`COMMANDLINE_ARGS`) is now empty by default and added after the options. Flags controlled by an option, flags the container manages (`--listen`, `--port`, `--data-dir`, ...) and flags not allowed in a container (`--share`, `--ngrok`, ...) are removed with a log message. Existing containers' old value keeps working.
- **Optional Models and Outputs directories** (`/data/models`, `/data/output`).
- **`NVIDIA_VISIBLE_DEVICES`** (default `all`) and **`NVIDIA_DRIVER_CAPABILITIES`** (`compute,utility`) in the template.
- README: every Extra Parameters flag explained in plain English, with what happens if you remove it.

### Fixed (ownership repair)

- Startup no longer re-owns folders mapped in separately inside `/data` (for example a models share). It warns, with the fix, when the WebUI can't write to one.

### Changed (build and updates)

- **Build cache:** builds reuse unchanged layers from a `:buildcache` tag in GHCR (`type=registry`, `mode=max`), the same setup as jim60105's image. Updates no longer re-download the 3 GB layer when it didn't change.
- **Staged build:** Python, PyTorch and Forge Neo are built in a separate stage and copied in with `COPY --link`, so an Ubuntu security update only replaces the system layer. This also removes a `chown -R` that stored Neo's whole folder twice.
- **Image version moved to the end of the Dockerfile:** it changes on every commit, and declaring it early invalidated every layer after it.
- **Nightly update check (4 AM ET):** rebuilds with today's Ubuntu updates (monthly: Python packages too), lists every package, and publishes only when that list differs from `package_versions.txt` (linuxserver.io's method).

### Changed (login page)

- The login page now shows the lockout rule above the form (Gradio's `auth_message`), because Gradio can only answer "Incorrect credentials", even for a locked username.

### Fixed (UI half-loaded on first Aether test, 2026-10-29)

- **Built-in Spectrum extension failed to load:** it creates `presets.json` in its own folder on first load (read-only here). That file is now a link to `/config/webui/spectrum-presets.json`, so presets are saved in appdata.
- **403 on all of Neo's scripts and styles:** Neo only lets Gradio serve files from its data folder, which by default is its program folder. This image moves data to `/data`, so the program files fell off the list. `start.sh` now adds `--gradio-allowed-path` for exactly what the browser loads: `script.js`, `style.css`, `javascript/`, `html/` and `extensions-builtin/` (narrower than upstream, which allows its whole folder).
- **Gradio 4.44.1 served CSS as a download:** build-time patch adds `text/css` and JavaScript (`text/javascript`, `application/javascript`) to Gradio's safe inline types. HTML and SVG stay blocked. The build fails if the patch stops applying.

### Added (template)

- `APP_UID` / `APP_GID` settings in the Unraid template (advanced view), defaulting to `99` / `100`. The entrypoint now rejects non-numeric values as well as `0`.

### Rebased on Forge Neo (breaking)

AUTOMATIC1111 has had no commits since 2026-03-02 and has four unpatched CVEs (2026-10-18),
so the container now packages [Forge Neo](https://github.com/Haoming02/sd-webui-forge-classic/tree/neo)
release 2.31. Container hardening, auth handling, log redaction and the restart loop are kept.

- **Renamed**: repository `sd-webui-forge-neo-unraid`, image `ghcr.io/aegisnir/sd-webui-forge-neo-unraid`,
  template `SD-WebUI-Forge-Neo-Unraid`, appdata settings folder `/config/webui` (migrated from
  `/config/a1111` on first start)
- **Upstream pin**: `WEBUI_TAG` + `WEBUI_REF` pin a Neo release tag's commit SHA; the build
  fails if the fetched commit does not match
- **Baked dependencies**: Python 3.13 (via uv, digest-pinned), torch `2.14.0+cu130`,
  torchvision `0.29.0+cu130`, gradio `4.40.0` and Neo's requirements are built into the image.
  No first-start download; `/data/venv` and `/data/repositories` are no longer used
- **Extension packages**: installed at runtime into `/data/python-user` (`PYTHONUSERBASE`);
  startup fails with the fix if an extension replaces torch or torchvision
- **Attention**: xformers removed; Neo uses PyTorch's built-in SDPA. `--xformers` / `--sage`
  still work as opt-in flags
- **Default args**: `--listen --port 7860 --data-dir /data`. `--no-download-sd-model`,
  `--disable-safe-unpickle` and `--allow-code` (removed by Neo) are dropped with a warning
- **Launcher**: `WebUI/launch.py` rewritten for Neo; replaces Neo's interactive
  "clean reinstall" prompt with a clear message and exit code 78, which `start.sh` treats as fatal
- **Restart button**: works now (`SD_WEBUI_RESTART` exported, Neo's `tmp/` redirected to `/data/tmp/webui`)
- **Output folder**: Neo default `/data/output` (was `/data/outputs`)
- **Healthcheck**: start period 600s → 300s (no first-run install)
- **Build pipeline**: GitHub Actions builds with `GITHUB_TOKEN` (no PAT), pushes `:sha-<commit>`,
  scans it with Trivy (fail-closed), then publishes `:dev` / `:latest` / `:vX.Y.Z`.
  `scripts/build-push.sh` removed
- **Upstream tracking**: daily workflow opens a PR when Neo tags a new release
- **HTTPS on by default** (`WEBUI_TLS=auto`): self-signed ECDSA certificate in `/config/tls`,
  renewed 30 days before expiry and when `WEBUI_TLS_HOSTNAMES` changes; bring your own with
  `custom.crt` / `custom.key` (key/cert match checked); verification kept on via an
  `SSL_CERT_FILE` trust bundle instead of `--disable-tls-verify`. `WEBUI_TLS=off` disables it
- **gradio 4.40.0 → 4.44.1** (security mitigation, untested by Neo upstream, may break parts of
  the UI): fixes 5 of 28 known CVEs. The remaining 23 are listed in the README
  ("Known security issues") and accepted in `.trivyignore` with reasons and a 2027-01-31 expiry
- **Extensions on by default**: `--enable-insecure-extension-access` is in the default args
  (owner decision; the A1111 image had it off). README warns that anyone who can log in can
  then install code
- **Old settings handled automatically**: a `config.json` from an older WebUI (VERSION_UID
  mismatch) is moved to `*.pre-neo-<date>.bak` with `ui-config.json`, and the WebUI starts with
  defaults and a log notice, instead of stopping. Exit code 78 remains only if the move fails
- **README**: plain-English impact for every gradio CVE (checked against Neo 2.31's use of each
  Gradio feature), extension guidance for Forge Neo, CivitAI extension status, `<data-path>`
  placeholder, how to build with gradio 4.40.0, why the restart loop exists
- **Login protection**: failed logins wait 1 s; 5 failures lock that username for 15 minutes
  (`WEBUI_LOGIN_MAX_ATTEMPTS`, `WEBUI_LOGIN_LOCKOUT_MINUTES`; 0 disables). Implemented by wrapping
  Gradio's launch() in `WebUI/launch.py`; Forge Neo's files are unchanged. Restart clears lockouts
- **README**: "Built for my setup" table of maintainer's-choice defaults with trade-offs, and a
  callout at each; explicit warning that Extensions → Available is the A1111 list
- **Python package upgrades** (security mitigation, may break): GitPython 3.1.62 → 3.2.1,
  diffusers 0.37.1 → 0.38.0, setuptools 78.1.0 → 81.0.0 (last release with `pkg_resources`),
  fixing 10 HIGH findings from the first image scan; the build asserts these versions and that
  urllib3 ≥ 2.8.0. 11 more HIGH findings (transformers, protobuf, starlette, pip-vendored
  msgpack/urllib3/setuptools) are accepted in `.trivyignore` and explained in the README
- **Build fix**: gradio and Neo's requirements are installed in two steps, as Neo does, because
  gradio declares `Pillow<11` while Neo pins Pillow 13

### Security

- **HIGH**: pin `WEBUI_REF` to upstream commit SHA instead of mutable `dev` branch; clone
  strategy changed to full clone + checkout + strip `.git` for reproducible builds
- **MEDIUM**: fix `API_AUTH_FILE_MODE` to fail closed on unrecognized values instead of
  silently falling back to `disabled`
- **MEDIUM**: add SIGTERM checkpoint after bootstrap: if Docker sends SIGTERM during pip
  install, the container now exits cleanly instead of continuing to launch the WebUI
- **MEDIUM**: validate `TORCH_INDEX_URL` requires `https://` scheme at startup
- **MEDIUM**: add dirty-tree guard to `build-push.sh` (rejects builds from uncommitted state)
- **MEDIUM**: enable SBOM and provenance attestation in build pipeline
- **MEDIUM**: add pre-push Trivy scan gate in `build-push.sh`
- **LOW**: fix `find` operator precedence in `/data` repair count (symlink exclusion now
  correctly applies to both `-user` and `-group` conditions)
- **LOW**: replace `chown -R` with symlink-safe `find -not -type l -exec chown` on `/config`
- **LOW**: reject `APP_UID=0` / `APP_GID=0` at entrypoint startup
- **LOW**: add SIGKILL escalation (15s timeout) to supervisor loop signal handler

### Documentation

- fix documentation drift: remove stale `--enable-insecure-extension-access` from README
  default args example, add missing `nodev` to tmpfs docs, fix stale check count in PR template
- document `groupmod` system group rename side effect and intentional `|| true` on SUID strip
- document 7 accepted security risks in SECURITY.md (M-6, M-7, M-8, M-11, L-6, L-9, L-15)

- **CRITICAL**: fix default credentials RCE chain: remove `--enable-insecure-extension-access`
  from default `COMMANDLINE_ARGS` in Dockerfile and `template.xml`; restores A1111's own
  `webui_is_non_local` safety mechanism that auto-disables extension management when `--listen`
  is set; adds startup warning when default creds (`admin:changeme`) are detected; changes
  `API_AUTH_FILE_MODE` default from `mirror-webui-file` to `disabled` (fail-safe)
- **CRITICAL**: fix symlink traversal in entrypoint ownership repair: add `-not -type l` to
  the `find`/`chown` command so a symlink at `/data/evil -> /etc/shadow` cannot cause `chown`
  to follow through to the host filesystem as root
- **CRITICAL**: fix Python stdout buffering: add `PYTHONUNBUFFERED=1` so log annotations
  appear immediately instead of in delayed 8KB bursts (upstream `webui.sh` passes `-u`;
  the container calls `launch.py` directly and missed this)
- **HIGH**: fix dead code in entrypoint Scenario 2: replace unreachable `-w`/`-x` conditional
  (root bypasses via `CAP_DAC_OVERRIDE`) with unconditional idempotent permission repair
- **HIGH**: fix UID/GID propagation: add `APP_UID`/`APP_GID` as `ENV` vars in Dockerfile so
  `entrypoint.sh` reads them instead of hardcoding `99`/`100`; custom builds with
  `--build-arg APP_UID=1000` no longer silently mismatch
- **HIGH**: fix restart counter: reset `_RESTART_ATTEMPT` to 0 on clean exit so repeated
  "Apply and quit" cycles (extension installs) cannot exhaust the max-attempts limit
- **HIGH**: fix `TORCH_INDEX_URL` fallback in `start.sh` from `cu128` to `cu130` to match
  the Dockerfile; prevents xformers wheel mismatch on edge cases
- **HIGH**: fix `start.sh` ownership from `sdwebui:sdwebui` to `root:root`; defense-in-depth
  for executables even on read-only rootfs
- **HIGH**: fix auth quoting: replace `printf '%q'` (bash-specific `$'...'` syntax) with
  `shlex.quote()` (POSIX single-quote wrapping); A1111 parses `COMMANDLINE_ARGS` via
  `shlex.split()` which cannot handle `$'...'` syntax
- **HIGH**: fix API auth fallback: unrecognized `API_AUTH_FILE_MODE` now falls back to
  `disabled` instead of `mirror-webui-file` (fail-safe for security settings)
- **MEDIUM**: fix silent error swallowing in ownership repair: capture and report errors from
  `find`/`chown`, report count of repaired files
- **MEDIUM**: fix GID drift detection: check both UID and GID at the top-level `stat`
  inspection; a file owned by `99:0` no longer passes silently
- **MEDIUM**: fix migration backup: back up before deleting in `_ensure_appdata_link` when
  both source and target exist; prevents silent data loss
- **MEDIUM**: fix model count recursion: remove `-maxdepth 1` from checkpoint `find`; A1111
  recurses with unlimited depth via `os.walk(followlinks=True)`
- **MEDIUM**: add `nodev` to tmpfs mount options in `template.xml` (defense-in-depth)
- **MEDIUM**: add `getcap`/`setcap` pass after SUID strip in Dockerfile; a binary with
  `cap_net_raw+ep` would survive the SUID strip alone
- **MEDIUM**: pin pip upgrade to `>=24.0,<25.0` instead of unconstrained `--upgrade`
  (supply chain discipline)
- **MEDIUM**: add `--ngrok` to `launch.py` `sensitive_flags` set; ngrok auth tokens were not
  being redacted from startup log output

### Fixed

- fix "Attempt N of 0" display when `RESTART_MAX_ATTEMPTS=0`
- move signal trap to top of `start.sh` (catches SIGTERM during bootstrap)
- replace `rm -rf` glob with `find -delete` (catches dotfiles)
- add SIGKILL escalation after 15s SIGTERM timeout
- extract `_validate_build_symlink()` helper (removes 3 copy-pasted blocks)
- merge auth file Python heredocs into unified `_auth_file_tool()`
- derive `VERSION` from git tag in `build-push.sh`
- add `-e` to Dockerfile `SHELL` instruction for consistency
- fix shellcheck findings: remove `local` keyword from top-level while loop (SC2168),
  exclude SC2317 in `security-check.sh` (false positive for trap handlers)
- pin `bandit==1.8.3` and `yamllint==1.35.1` in CI
- security baseline now 29/29 with shellcheck enabled

---

## [v1.0.3] - 2026-03-25

- Pin `torch` 2.11.0→2.10.0 and `torchvision` 0.26.0→0.25.0: `xformers` 0.0.35's cu130
  wheel was compiled against PyTorch 2.10.0; mismatched versions prevent CUDA extensions
  from loading and disable memory-efficient attention
- fix: add `--extra-index-url` to xformers pip install so the cu130 wheel is pulled from
  the PyTorch index instead of PyPI; without this flag pip resolved the cu128 PyPI wheel
  even when torch was correctly at cu130, causing `xFormers was built for: PyTorch 2.10.0+cu128`
  CUDA extension load failures at runtime even with a correctly pinned torch version
- chore: add `scripts/build-push.sh`, a repeatable helper to `docker buildx build` and push
  both `:dev` and `:v1.0.3` tags to GHCR; excluded from `.dockerignore` so it is not shipped in
  the image; shellcheck and syntax coverage added to `scripts/security-check.sh`
- fix: add inline monitor handlers and pre-launch known-harmless entries for patterns observed
  during real-hardware validation:
  - `print_launch_notice`: three new known-harmless entries:
    - `FutureWarning: resume_download is deprecated` (huggingface_hub deprecation during model/extension load)
    - `[ERROR]: Config states .../civitai_subfolders.json, "created_at" does not exist`
      (CivitAI Shortcut extension schema notice; tagged `[ERROR]` upstream but harmless)
    - `CivitAI Browser+: Basemodel fetch error` (startup network API call, benign; retried on demand)
  - `monitor_webui_output`: two new inline handlers:
    - xformers CUDA build mismatch (`cu128` wheel vs `cu130` torch) -- `[XFORMERS MISMATCH]`
      box with explicit venv-delete remediation (`rm -rf /mnt/user/ai/data/venv`)
    - CivitAI Shortcut config_states `[ERROR]` line -- `[NOTE]` tag immediately after the
      line to defuse the alarming label in context
- fix: `[GPU MEMORY ERROR]` box updated with `PYTORCH_ALLOC_CONF=expandable_segments:True`
  as the first and easiest mitigation (PyTorch's own recommendation; reduces fragmentation,
  often resolves marginal OOM without quality tradeoff); added Hires. fix callout as the
  biggest per-generation VRAM consumer on SDXL; `--medvram` tip added as fallback;
  replaced stale `Enable xformers` tip with `xformers is already enabled -- good`
  (xformers is on by default in this image)
- fix: add `⏳ Starting up` notice after the pre-launch banner; the log is silent for several
  minutes while Python initialises, extensions load, and the model is read into VRAM;
  without a notice users assume the container has hung and restart it prematurely
- fix: all multi-line annotation boxes now set color once on the opening `┌` line and reset
  only on the closing `└` line; previously each interior `│` line had its own ANSI
  color-set + color-reset, causing Unraid's Docker log viewer to render interior lines
  in default white while only the header line appeared colored; affected boxes:
  `[KNOWN WARNING]`, `[XFORMERS MISMATCH]`, `[GPU MEMORY ERROR]`, `[GPU NOT DETECTED]`, `[READY]`

---

## [v1.0.2] - 2026-03-25

- Upgrade CUDA base image from `nvidia/cuda:12.9.1-runtime-ubuntu22.04` to `13.0.2`;
  update PyTorch index URL from `cu128` to `cu130`; bump pinned dependency versions:
  `torch` 2.7.0→2.11.0, `torchvision` 0.22.0→0.26.0, `xformers` 0.0.30→0.0.35
  - Requires host driver ≥ 580 (CUDA 13.0.2 official minimum: ≥ 580.95.05; confirmed compatible with driver 595.45.04)
  - `cu130` wheels are the highest available for both PyTorch 2.10 and 2.11
  - xformers 0.0.34+ uses stable PyTorch ABI. Binary built for 2.10 runs on 2.11+
  - CUDA 13.0.2 is 5+ months old and battle-tested; chosen over 13.2.0 (8 days old, zero driver headroom at ≥595)

- CI: extended static analysis added to push/PR workflow: `hadolint` (Dockerfile lint),
  `bandit` (Python security scan), `yamllint` (YAML validation), `trivy config`
  (Dockerfile misconfiguration scan), `gitleaks` (secret detection across git history)
  - `.hadolint.yaml`: suppresses DL3008 (apt version pins), impractical for system packages
  - `.gitleaks.toml`: allowlists `webui-auth.txt` as an intentional default-credentials placeholder
  - `.trivyignore`: allowlists DS002 (run as root). Container uses entrypoint privilege-drop pattern
  - `.yamllint.yml`: relaxes line-length to 120 and removes document-start requirement
- CI: add `trivy-image.yml` for weekly scheduled CVE scan of the published `:dev` image;
  filters to fixable HIGH/CRITICAL findings only to reduce base-image noise
- Add `.github/dependabot.yml` for automated version-bump PRs for GitHub Actions and
  Docker base image (weekly cadence)

---

## [v1.0.1] - 2026-03-24

- Fix: SC2015 shellcheck warnings in `_cleanup_monitor`. `A && B || true` pattern
  rewritten as explicit `if/fi`; logic was correct but non-idiomatic and caused the
  automated security baseline to fail
- Fix: `--port=NNNN` equals-separated form ignored by `_poll_for_ready`. Was silently
  falling back to port 7860; now handles both `--port 7861` and `--port=7861` forms
- Fix: inverted awk exit codes in auth credential format validation. Logic was correct
  but coded as `bad?0:1` with a plain `if`, which is counter-intuitive and risky for
  maintainers; corrected to `bad?1:0` with matching `if !` guard
- Add: `extensions` symlink startup validation. Validates presence and correct target,
  consistent with the existing `repositories` and `config_states` checks
- Add: `/data/tmp` purged on startup to prevent partial pip downloads and extracted
  archives from accumulating silently across restarts and crashes
- Dockerfile: OCI image labels added (`org.opencontainers.image.*`). Links the GHCR
  package to the source repository, exposes license metadata, and gives vulnerability
  scanners the source context they need
- Dockerfile: `IMAGE_VERSION` build ARG added; pass `--build-arg IMAGE_VERSION=v1.0.1`
  at build time to embed the version in the `org.opencontainers.image.version` label
- Dockerfile: HEALTHCHECK section now documents the known hardcoded-port limitation
  (Docker HEALTHCHECK CMD cannot read runtime env vars; port 7860 is baked in)
- CI: added `.github/workflows/ci.yml`. Runs `scripts/security-check.sh` on every
  push and pull request to `dev` and `main`; installs shellcheck as a prerequisite

---

## [v1.0.0] - 2026-03-24

> First pre-release. Published on the `dev` branch/tag. Not yet promoted to `main` or `:latest`. Pending real-world validation.

- Automatic WebUI restart loop:
	- container now automatically restarts the WebUI process when it exits, instead of letting the container stop
	- distinguishes deliberate stops (SIGTERM from Docker stop/Unraid) from crashes or clean exits ("Apply and quit")
	- SIGTERM sets a flag that suppresses restart and lets the container exit cleanly
	- clean exit (code 0, e.g. "Apply and quit"): flat delay before restart (`RESTART_DELAY`, default 5 s), resets crash backoff counter
	- crash (non-zero exit code): exponential backoff starting at `RESTART_DELAY`, doubling each attempt up to `RESTART_DELAY_MAX` (default 60 s)
	- new env vars: `RESTART_ON_EXIT` (default `1`), `RESTART_DELAY` (default `5`), `RESTART_DELAY_MAX` (default `60`), `RESTART_MAX_ATTEMPTS` (default `0` = unlimited)
	- startup banner only printed on first start; subsequent restarts print a compact restart notice with attempt count and delay
- Appdata split extended. A1111 user config files moved to `/config/a1111/` (appdata):
	- `config.json`: all Settings tab values, including settings added by extensions via the A1111 opts API
	- `ui-config.json`: UI component defaults (slider ranges, textbox sizes)
	- `styles.csv`: saved prompt styles
	- `config_states/`: extension enable/disable snapshots
	- Symlinks are created at startup so A1111 finds everything at its expected paths under `/data`
	- Automatic migration: any existing files/directories at the old `/data/` locations are moved on first start with the new image; appdata copy wins if both exist
	- Extension-specific standalone state files (e.g. civitai browser favourites/ban lists) remain under `/data/extensions/<name>/`, covered by `/data` persistence, not appdata backup
	- Combined with the existing auth file split, the full `/data` volume can now be wiped and the container rebuilt without losing any settings; only models need to be re-downloaded

- Image: added `build-essential` and `python3-dev` to the base image apt packages so that Python extensions requiring C/C++ compilation (e.g. `hnswlib` used by `sd-webui-infinite-image-browsing`) build successfully without needing `IIB_SKIP_OPTIONAL_DEPS=1`

- Console output revisions:
	- Color detection changed from `[[ -t 2 ]]` tty guard to always-on ANSI; suppress with `NO_COLOR=1` or `TERM=dumb` (the tty check returned false in Docker when no TTY is attached, which is the normal case in Unraid's log viewer; all colors were being stripped silently)
	- `C_INFO` changed from `\e[95m` (bright magenta, rendered poorly or invisibly in some terminals) to `\e[35m` (regular magenta/violet, reliably visible)
	- All annotation boxes fully closed: content lines are now padded to exact inner width and have a right-side `│` border; previous implementation left the right side open
	- READY banner replaced log-line match on `Running on local URL` with an independent background poller (`_poll_for_ready`) that uses bash's `/dev/tcp` built-in to probe the port every 5 seconds; the log-line approach was silently failing across Gradio versions
	- READY banner now auto-detects the container's own outbound LAN IP (works in macvlan / Unraid br0 / `--network=host`); shows `http://<your-unraid-ip>:<port>/` placeholder in standard Docker bridge/NAT mode where the host's IP is not discoverable from inside the container

- Authentication behavior update:
	- removed startup hard-stop for auth files containing password `changeme`
	- startup now allows first-launch default login `admin:changeme` and logs continue normally
	- updated README/template/security metadata to document default end-user login behavior and recommended password change after first login
- Fixes:
	- fixes startup failure where `WEBUI_AUTH_FILE` could not be auto-seeded because the sample file was missing from the image
	- removed unsupported `--extensions-dir` launch argument injection (newer A1111 no longer accepts this flag)
	- added auth-file credential format validation in startup to fail fast with a clear CRITICAL error instead of Gradio `IndexError` on malformed entries
	- startup now writes a sanitized runtime auth file (comments/blank lines removed) before passing `--gradio-auth-path`, preventing Gradio `IndexError` from commented auth templates
- Security audit and documentation hardening:
	- updated `scripts/security-check.sh` `check_auth_guardrails` to test current auth-file changeme guard instead of the removed `WEBUI_PASSWORD` variable (previous check always failed after auth refactor)
	- updated `SECURITY.md` checklist to reference `changeme` auth-file guard instead of stale `changeme-now` WEBUI_PASSWORD reference; updated verification grep command to match
	- removed "WORK IN PROGRESS" banner from README top (was blocking CA App Store readiness)
	- added explicit security warning in README about `--api-auth` credentials being exposed in `COMMANDLINE_ARGS` env var when API mirroring is active (known upstream A1111 limitation)
	- cleaned up duplicate intro sentence in README auth section
- Authentication defaults and hardening:
        - switched startup to auth-file-first workflow using `WEBUI_AUTH_FILE` (default `/config/auth/webui-auth.txt`)
        - added first-run auth-file seeding from repository template `webui-auth.txt` when target file is missing
        - removed `WEBUI_USERNAME` / `WEBUI_PASSWORD` template fields to avoid credential leakage from variable-based auth paths
        - updated README/template metadata with explicit auth-file path, format, and safety-guard guidance
- API/default behavior clarification:
	- startup now treats API as explicitly opt-in: API auth injection runs only when `--api` is present in `COMMANDLINE_ARGS`
	- added startup note that API is disabled by default unless `--api` is set
	- added warning when users pass `--api-auth` without enabling `--api`
	- updated README/template docs to clarify API-off-by-default behavior and when `API_AUTH_FILE_MODE` applies
	- documented extension-access tradeoff: omitting `--enable-insecure-extension-access` does not block existing extension runtime; it mainly limits install/update/management from the WebUI
	- enabled `--enable-insecure-extension-access` by default in template and Dockerfile fallback args for this personal project workflow
	- added explicit README risk callouts for insecure extension access and documented what `--allow-code` enables vs what leaving it unset prevents
- Security review workflow:
	- added a reusable "Security baseline regression checklist" section to `SECURITY.md` with pass/fail gates for runtime hardening defaults, privilege-drop model, auth guardrails, and docs consistency
	- added quick verification commands for template flags, startup scripts, auth behavior, bash syntax, and XML parsing
	- added a README pointer to the checklist so it can be used as a standard pre-release/pre-merge safety check
	- added `scripts/security-check.sh` as a one-command automated runner for the checklist checks (runtime flags, privilege model, auth guardrails, bash syntax, and XML parse)
	- hardened startup pipe handling in `start.sh` by replacing `mktemp -u` with secure `mktemp -d` + `mkfifo` path creation
	- added an automated gate in `scripts/security-check.sh` to fail if unsafe `mktemp -u` usage appears in startup scripts
- Startup permission-repair fallback:
	- `entrypoint.sh` no longer aborts immediately if host policy blocks `chown` or `chmod` on `/data`
	- when automatic repair is denied (`Operation not permitted`), entrypoint now prints a clear host-filesystem warning and continues into `start.sh`
	- the container now fails through the existing `start.sh` remediation path instead of crashing early on the raw `chmod` error
	- privilege drop now uses `setpriv --reuid=99 --regid=100 --clear-groups` instead of `runuser`, avoiding `runuser: cannot set groups: Operation not permitted` on restricted runtimes
	- `entrypoint.sh` now preflights `setpriv` before launching `start.sh`; if setuid/setgid is blocked (`setresuid failed` class), it prints explicit host-side remediation and exits cleanly
	- added a concise entrypoint runtime diagnostics line (`NoNewPrivs`, `Seccomp`, `CapEff`) plus likely-cause hints when permission repair or privilege-drop operations are blocked
	- diagnostics now explicitly flag `CapEff=000...0` as "all capabilities dropped" and suggest adjusting capability flags
	- template defaults were corrected to keep least-privilege hardening while preserving required startup operations: `--cap-drop=ALL` plus `--cap-add=CHOWN,FOWNER,SETUID,SETGID`
- Console color palette:
	- added ANSI color output to `start.sh` and `entrypoint.sh` for terminal sessions (plain in log files via `[[ -t 2 ]]` guard)
	- color scheme: **violet** (`\e[95m`) for informational; **orange** (`\e[93m`) for caution/warnings; **scarlet** (`\e[91m`) for critical errors; **cyan** (`\e[96m`) for accent/highlights (URLs, borders, structural chrome)
	- color variables use semantic names (`C_INFO`, `C_WARN`, `C_CRIT`, `C_ACCENT`) so code intent is self-documenting regardless of actual ANSI color
	- applied consistently: ERROR lines → C_CRIT+bold label; WARNING lines → C_WARN; auth/ready/venv notices → C_INFO; borders, URLs, highlights → C_ACCENT
	- `print_launch_notice` banner and all inline annotation boxes (`[NOTE]`, `[KNOWN WARNING]`, `[GPU MEMORY ERROR]`, `[GPU NOT DETECTED]`, `[READY]`) are fully color-coded
	- `entrypoint.sh` uses the same palette for its ownership/permission repair notices
- Console output improvements:
	- added pre-launch banner (`print_launch_notice`) showing: model checkpoint count, first-run bootstrap notice, known-harmless warnings table, and access URL reminder
	- added inline output monitor (`monitor_webui_output`) that annotates known noisy lines in real time:
		- `timm.models.layers` FutureWarning → `[NOTE] ↑ Harmless upstream deprecation. Safe to ignore.`
		- `TypedStorage is deprecated` → `[NOTE] ↑ Harmless internal PyTorch notice. Safe to ignore.`
		- `No checkpoints found` → `[KNOWN WARNING]` box with fix instructions
		- `CUDA out of memory` → `[GPU MEMORY ERROR]` box with tuning tips
		- `torch.cuda.is_available() = False` / `Torch is not able to use GPU` → `[GPU NOT DETECTED]` box with host-side check steps
		- `Running on local URL` → `[READY]` box confirming WebUI is accepting connections
	- WebUI is now launched via a named pipe with signal forwarding so Docker `stop`/`kill` reaches the Python process cleanly while monitoring is active
- Self-healing startup:
	- added `entrypoint.sh` as a root-level container entrypoint that automatically corrects `/data` ownership before dropping to the unprivileged app user (`sdwebui` / UID 99)
	- uses the standard "init as root, drop privileges" pattern (same as postgres, nginx, redis)
	- handles two distinct degraded states independently:
		1. **Wrong ownership** (e.g. Docker recreated `/data` as root): `chown` top-level + `find`-based ownership repair on all children + mode restoration for any that lost traversal/read bits
		2. **Correct ownership but stomped modes** (e.g. `chmod -R 000` on the host while already owned by UID 99): `chmod 775` top-level + `find`-based permission repair restoring `u+rwx` on directories and `u+r` on files
	- the `find` walks are filtered to only process entries that actually need fixing, so they are fast on healthy volumes and no-ops when everything is correct
	- `start.sh` still has a fallback hard-error for cases that cannot be auto-fixed (NFS root squash, SELinux, or `chown` silently failing)
	- `start.sh` now auto-creates standard `/data` subdirectories (`models/Stable-diffusion`, `models/VAE`, `models/Lora`, `outputs`) on every startup so a bare or restored volume gets the expected layout without user action
- Startup/bootstrap hardening:
	- fixed the `start.sh` shebang/entrypoint format issue
	- made `/repositories` handling compatible with read-only container filesystems
	- redirected pip temp/cache usage into `/data`
	- added a `/data` free-space preflight and startup diagnostic
	- added optional `UMASK` support via template variable (not enforced by default)
	- hardened auth arg injection quoting to better handle spaces/special characters
- Dependency management:
	- aligned bootstrap dependency targets with upstream `AUTOMATIC1111` `dev` expectations
	- pinned `torch`, `torchvision`, and `xformers` as an explicit tested set
	- added installed-version logging and a dependency sanity check
- Docker healthcheck:
	- added `HEALTHCHECK` instruction to Dockerfile with conservative timers tuned for A1111 workloads
	- 10 min start-period grace for first-run bootstrap, 2 min interval, 30 s timeout, 5 retries
	- requires ~12 min of total unresponsiveness to flag unhealthy, avoiding false positives from model loading, extension installs, image browser, etc.
	- healthcheck is informational only; Docker/Unraid will not auto-restart the container
- Code quality:
	- both shell scripts pass `shellcheck` cleanly (fixed SC2295 quoting bug, suppressed SC2317 false positives on trap callbacks, fixed SC2015 `A && B || C` pattern)
	- removed unused `_original_start` variable from `launch.py`
	- updated template.xml and README to document healthcheck behavior and tuning rationale
	- relaxed the sanity check to accept valid CUDA local version suffixes such as `+cu126`
	- made `xformers` truly optional in sanity checks so startup does not fail when it is unavailable
- Pre-release security audit:
	- fixed auth file permission race: auth file seed and runtime auth file are now written under `umask 077` so credentials are never world-readable even briefly
	- fixed stale "via runuser" references in Dockerfile (code uses `setpriv`)
	- fixed missing closing quote in SECURITY.md python3 verification command
	- expanded `scripts/security-check.sh` with checks for: shellcheck, HEALTHCHECK presence, SUID bit strip, log redaction, HTTPS-only extension URLs, and auth file permission hardening
	- cleaned up stale variable names in CHANGELOG (`API_AUTH_MODE` → `API_AUTH_FILE_MODE`, clarified superseded `WEBUI_USERNAME`/`WEBUI_PASSWORD`)
	- updated `COMMANDLINE_ARGS` code comment to honestly describe the `--api-auth` env var exposure tradeoff
- Authentication/security defaults:
	- enabled WebUI login by default
	- mirrored credentials to API auth by default
	- *(superseded)* early iterations used `WEBUI_USERNAME` / `WEBUI_PASSWORD` template variables; these were removed in favor of auth-file workflow (`WEBUI_AUTH_FILE`) to avoid credential leakage via env vars
	- blocked startup when the placeholder password is unchanged unless auth is managed explicitly
	- made startup auth log redaction patch read-only-safe by patching in memory
- Documentation/template updates:
	- refreshed `README.md` structure and security guidance
	- documented authentication defaults and HTTPS/TLS options
	- updated `template.xml` to reflect current hardening and auth behavior
	- synchronized current defaults across docs, template, and scripts
	- added third-party licensing notices (`THIRD_PARTY_NOTICES.md`, AGPL copy)
	- switched template/runtime naming for local Unraid testing consistency
	- added default `--pids-limit=2048` and documented how to tune PID limits in Unraid Extra Parameters
	- added template links to the GitHub README for quick user access
	- documented that `No checkpoints found` is expected with `--no-download-sd-model` until a model is added
	- added stronger guidance to prefer `WEBUI_AUTH_FILE` for live deployments and treat `WEBUI_PASSWORD` as convenience/testing
	- added warnings that credentials may appear in logs in some startup paths when password-based auth is used

## Notes

When practical, future entries may include:
- what changed
- why it changed
- anything that may affect setup, upgrades, or security posture
- the upstream AUTOMATIC1111 source state if it feels useful to record
