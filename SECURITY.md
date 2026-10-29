# Security

I care a lot about security, but I want to be clear that I am learning as I go.

This is a personal, AI-assisted hobby project. I am not a security expert, and nothing in this repository should be treated as a guarantee of safety or a complete security solution.

## Intended use

This project is primarily aimed at private, self-managed setups, especially on trusted home-lab style networks.

Public internet exposure is not the intended default use case.

## What I try to do

Where practical, I try to:
- follow safer defaults
- avoid unnecessary bloat
- document important tradeoffs
- reduce obvious risk where I can
- be honest about limitations

## Security baseline regression checklist

This is a quick pass/fail checklist for validating the repository defaults after changes.
Use it as a release gate and after any edit to runtime flags, startup scripts, or auth flow.

Automated runner:

```bash
./scripts/security-check.sh
```

### Runtime hardening defaults

- [ ] PASS if `template.xml` keeps `Privileged` set to `false`.
- [ ] PASS if default `ExtraParams` includes all of the following:
	`--read-only`, `--tmpfs /tmp:rw,noexec,nosuid,nodev,size=2g`,
	`--security-opt no-new-privileges:true`, `--cap-drop=ALL`,
	`--cap-add=CHOWN`, `--cap-add=FOWNER`, `--cap-add=SETUID`, `--cap-add=SETGID`,
	and `--pids-limit=2048` (or documented equivalent).
- [ ] PASS if defaults do not require `--privileged`.

Verification command:

```bash
grep -n "<ExtraParams>\|<Privileged>" template.xml
```

### Startup privilege model

- [ ] PASS if `entrypoint.sh` performs limited root-only setup and then drops to uid 99/gid 100 before running the app.
- [ ] PASS if `start.sh` refuses to run as root (`id -u == 0` check).
- [ ] PASS if entrypoint diagnostics include runtime context for blocked host/runtime policies (NoNewPrivs, Seccomp, CapEff).

Verification command:

```bash
grep -n "id -u\|setpriv\|NoNewPrivs\|CapEff" entrypoint.sh start.sh
```

### Authentication guardrails

- [ ] PASS if startup seeds a default auth-file containing `admin:changeme` on first launch when the file is missing.
- [ ] PASS if startup requires a present, non-empty, parseable auth-file before launch.
- [ ] PASS if `WEBUI_AUTH_FILE` is supported and documented as the sole supported credential mechanism.
- [ ] PASS if API auth is not silently left open when WebUI auth is configured (mirror behavior or explicit override required).

Verification command:

```bash
grep -n 'WEBUI_AUTH_FILE\|api-auth\|gradio-auth\|WEBUI_AUTH_SAMPLE_FILE\|no usable credentials\|auth file is empty' start.sh README.md
```

### Safety checks and docs consistency

- [ ] PASS if syntax checks pass for startup scripts:
	`bash -n entrypoint.sh && bash -n start.sh`
- [ ] PASS if shellcheck passes for startup scripts:
	`shellcheck -s bash entrypoint.sh start.sh`
- [ ] PASS if template XML parses:
	`python3 -c "import xml.etree.ElementTree as ET; ET.parse('template.xml')"`
- [ ] PASS if README, template, and changelog describe the same hardening defaults.

### Build hardening

- [ ] PASS if Dockerfile `HEALTHCHECK` is present with `--start-period` of at least 300s.
- [ ] PASS if Dockerfile strips all SUID/SGID bits from binaries at build time.
- [ ] PASS if `WebUI/launch.py` contains credential redaction logic (`_redact_cli_args`).

Verification command:

```bash
grep -n 'HEALTHCHECK\|chmod a-s' Dockerfile
grep -n '_redact_cli_args' WebUI/launch.py
```

### Credential file permissions

- [ ] PASS if auth file writes in `start.sh` use `umask 077` so credentials are created mode 600 and are never world-readable.

Verification command:

```bash
grep -n 'umask 077' start.sh
```

### Supply chain integrity

- [ ] PASS if the Dockerfile base image is pinned by SHA256 digest (not a mutable version tag).
- [ ] PASS if all GitHub Actions `uses:` references are pinned to full immutable commit SHAs.
- [ ] PASS if `.github/dependabot.yml` is present and configured for Actions and Docker base image.
- [ ] PASS if the Forge Neo source is pinned to a release tag's commit SHA (`WEBUI_REF` in the Dockerfile), and the build checks that the fetched commit matches.
- [ ] PASS if images are only published under `:dev`, `:latest` or `:vX.Y.Z` after the Trivy image scan in `.github/workflows/build-image.yml` passes (the scan step must use `exit-code: "1"`).
- [ ] PASS if image builds authenticate with the workflow's `GITHUB_TOKEN`, not a personal access token.
- [ ] PASS if every `.trivyignore` vulnerability entry has a reason comment and an `exp:` date, and is listed in the README "Known security issues" section.

### HTTPS

- [ ] PASS if `WEBUI_TLS` defaults to `auto` (HTTPS on) in both the Dockerfile/start.sh and `template.xml`.
- [ ] PASS if the self-signed private key is created under `umask 077` and `/config/tls` is mode 700.
- [ ] PASS if `WEBUI_TLS_HOSTNAMES` entries are validated against a strict hostname/IPv4 pattern before reaching `openssl`.
- [ ] PASS if `start.sh` never adds `--disable-tls-verify` (verification uses the `SSL_CERT_FILE` trust bundle instead).

Verification commands:

```bash
grep -E '^FROM .+@sha256:' Dockerfile
grep -rn 'uses:' .github/workflows/ | grep -vE '@[0-9a-f]{40}'  # should return nothing
```

### Current baseline (as of 2026-05-05)

- Runtime hardening defaults: PASS
- Startup privilege model: PASS
- Authentication guardrails: PASS
- Safety checks/docs consistency: PASS
- Build hardening: PASS
- Credential file permissions: PASS
- Supply chain integrity: PASS


## What you should assume

> [!WARNING]
> If you choose to use anything from this repository, I recommend assuming that:
> - mistakes are possible
> - important security considerations may still be missing
> - your environment may have different risks than mine
> - you should validate the setup against your own threat model and risk tolerance

## Known tradeoffs

### Dev toolchain in final image

`build-essential` is installed in the runtime image (not stripped via multi-stage build), and the bundled Python includes its headers. This is intentional: WebUI extensions compile C dependencies at runtime via `pip install`. Removing the compiler breaks extension installation for users.

The incremental attack surface is marginal because extensions already have arbitrary code execution within the container. The container runs non-root with `--read-only`, `--cap-drop=ALL`, `--no-new-privileges`, and `--pids-limit`, which limits what a compromised extension can escalate to.

If a future version removes extension support, the dev toolchain should be stripped.

### tmpfs /tmp bypasses noexec for interpreted scripts (M-6)

The `--tmpfs /tmp:rw,noexec,nosuid,nodev` mount prevents direct binary execution but does not prevent `python /tmp/script.py` or `bash /tmp/script.sh`. This is a fundamental limitation of `noexec`: it only blocks the kernel `execve` syscall, not interpreters reading files. Removing `/tmp` entirely would break Python (pip, tempfile) and many WebUI operations. Accepted as a defense-in-depth layer, not a complete execution barrier.

### Gradio auth has no server-side rate limiting (M-7)

The WebUI's Gradio authentication does not implement rate limiting or account lockout. This was confirmed for Gradio 3 under A1111. Forge Neo uses Gradio 4.40, which has not been re-checked yet, so assume the same. Brute-force protection depends on network-level controls (firewall rules, reverse proxy rate limiting). This is an upstream limitation. The container is designed for trusted home-lab networks where this risk is low. If exposing to the internet, deploy behind a reverse proxy with rate limiting.

### Plaintext credentials in auth file (M-8)

`webui-auth.txt` stores credentials as `username:password` in plaintext. This is the format the WebUI's Gradio auth expects (unchanged in Forge Neo). The file is created with mode 600 (owner-read-only) and lives on a host-mounted volume. Hashing would require patching upstream Gradio auth. Accepted: file permissions are the primary control.

### Default credentials on first launch (M-11)

The container seeds `admin:changeme` on first launch to ensure the auth gate is never absent. A prominent startup warning is displayed. Blocking startup until custom credentials exist would break the first-boot experience (container starts, user configures via WebUI or file edit). The current approach prioritizes "always authenticated" over "never uses defaults."

### SUID strip uses || true (L-6)

The `find / -exec chmod a-s {} + || true` in the Dockerfile intentionally ignores errors. Some base image files may be immutable or on virtual filesystems. Stripping as many SUID/SGID bits as possible is a net security win even if a few resist.

### Python subprocess inherits full environment (L-9)

`start.sh` launches the Python WebUI via the full shell environment. Filtering env vars before exec would risk breaking the WebUI's dependency on CUDA, PyTorch, and pip configuration variables. The container already runs non-root with dropped capabilities, limiting what env-based attacks could achieve.

### /data volume not mounted noexec (L-15)

The `/data` volume cannot use `noexec` because extensions live in `/data/extensions` and the packages they install live in `/data/python-user`, and both are executed by Python. The WebUI's own dependencies are built into the read-only image. The `--read-only` rootfs and `--no-new-privileges` flags limit the blast radius.

### Some built-in extension packages are not version-pinned

The image pins Python packages to the versions Forge Neo installs. Neo's built-in ControlNet preprocessor installer also installs a few packages without a version (for example `insightface`). Those are installed at build time, so they are fixed per image and covered by the Trivy scan, but two builds of the same release may get different versions.

## Known upstream issues (Forge Neo)

The full, user-facing list, including every Gradio CVE, is in the README section [Known security issues](README.md#known-security-issues). Keep the two in sync.

**Gradio 4 (biggest risk).** Forge Neo 2.31 pins Gradio 4.40.0, which has 28 published vulnerabilities (1 critical). Most are fixed only in Gradio 5/6, which Neo does not support. This image upgrades to Gradio 4.44.1, fixing 5 of them; this is untested upstream and may break parts of the UI (`GRADIO_VERSION` build argument to roll back). The remaining 23 are accepted in `.trivyignore`, each with a reason and a 2027-01-31 expiry that forces a re-review.

These were found during the 2026-10-28 review of Forge Neo 2.31 and are not fixed by this container:

- **Stored XSS in the extra-networks cards** (`modules/ui_extra_networks.py`): file names and search terms are not escaped. Same pattern as A1111's CVE-2026-111984. Impact needs a malicious model file name or metadata. Only add models from sources you trust.
- **No size limit when reading safetensors metadata** (`modules/sd_models.py`): a crafted file can use a lot of memory. Same pattern as A1111's CVE-2026-111985.

Neo removed the A1111 `.yaml` model-config code path (CVE-2026-111986), and always loads checkpoints with `weights_only=True`.

## Reporting security concerns

If you notice a security issue, risky assumption, or something that looks clearly unsafe, constructive feedback is welcome.

For now, the simplest approach is to open an issue **only if you are comfortable discussing it publicly**.

> [!CAUTION]
> If the concern is sensitive and should not be posted publicly, please use your judgment and avoid sharing details in a way that would unnecessarily expose other users. A more formal private reporting process may be added later if this project grows enough to justify it.

## Third-party content

Models, extensions, scripts, containers, and other third-party content should be treated as untrusted inputs unless you have reviewed and trusted them yourself.

## No guarantees

This repository is shared as-is. No guarantees are made regarding security, hardening, or safety. I will try to improve things over time, but please do not rely on this project as if it has been professionally audited or maintained.
