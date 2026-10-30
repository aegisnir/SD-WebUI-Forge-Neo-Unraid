# syntax=docker/dockerfile:1
#
# Dockerfile - SD-WebUI-Forge-Neo-Unraid
#
# Forge Neo is by Haoming02 (https://github.com/Haoming02/sd-webui-forge-classic/tree/neo).
# This project only packages it for Unraid.
#
# Design intent:
#   - Bake Python, PyTorch and every WebUI dependency into the image, so the
#     image is reproducible, scannable (Trivy sees every package) and starts
#     without network access
#   - Run as a non-root user where practical
#   - Pin the CUDA base image and the uv build tool by digest
#   - Pin upstream Forge Neo to a release tag's commit SHA (WEBUI_REF)
#   - Build in two stages: Python, PyTorch and Forge Neo are prepared in
#     'build' and copied into the runtime stage with COPY --link, so an
#     Ubuntu security update does not change (or re-download) the large
#     Python layer. See README "How updates are published".
#
# This project is maintained as a personal, AI-assisted hobby project.
# These comments try to explain the reasoning behind the current choices,
# but they should not be read as a guarantee that the result is fully hardened
# or appropriate for every environment.
#
# General Docker build guidance (reference):
# https://docs.docker.com/build/building/best-practices/

# ------------------------------------------------------------------------------
# Design Notes (Why some security/ops choices are intentionally NOT baked in)
#
# 1) Runtime hardening flags:
#    This image does not embed runtime security flags (read-only FS, cap drops,
#    no-new-privileges, tmpfs, etc.) because those controls are applied by the
#    container runtime (Unraid/Docker) and may need tuning per environment.
#    If you choose not to apply them, the deployment may be less constrained than
#    originally intended.
#
# 2) Network exposure & authentication:
#    This image starts a local web service. It does not configure TLS, auth, or
#    reverse-proxy integration by default because those are deployment concerns
#    that vary by environment. If you expose the service beyond a trusted network,
#    the resulting setup may not be as safe as originally intended.
#
# 3) GPU drivers:
#    NVIDIA kernel drivers live on the host. This image includes user-space CUDA
#    components and expects GPU access to be granted explicitly at runtime.
#
# 4) Supply chain & updates:
#    - The CUDA base image and the uv image are pinned by digest.
#    - The WebUI source is pinned to a Forge Neo release tag's commit SHA via
#      WEBUI_REF. A scheduled workflow opens a PR when Neo tags a new release.
#    - Python packages are pinned to the versions Neo itself installs.
#      The one exception is what Neo's built-in ControlNet preprocessor
#      installer pulls (for example insightface), which Neo does not pin.
#
# 5) Extensions:
#    The baked packages are read-only at runtime. Packages that extensions
#    install go to a per-user site under /data/python-user (PYTHONUSERBASE),
#    which Python searches before the baked packages. Deleting that folder
#    resets extension packages without touching the image.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Versions shared by both stages. Build arguments declared before the first
# FROM are global; each stage re-declares the ones it uses (ARG NAME, without
# a value) to read them. Declared inside one stage, the other stage would get
# an empty value (that broke the banner's Neo version and the torch check once).
# ------------------------------------------------------------------------------
# Forge Neo release to build. This must be the commit SHA of a release tag
# (https://github.com/Haoming02/sd-webui-forge-classic/tags), not a branch.
# The update-neo workflow bumps both values together.
#
# Security note:
# Avoid passing secrets through build arguments. Industry guidance generally
# treats build args as poor places for sensitive values because they may show up
# in build metadata, layer history, logs, or external attestations depending on
# how and where the image is built.
ARG WEBUI_TAG=2.31
ARG WEBUI_REF=c358e55deace6a086af0a547026652ef36daa9c4

# PyTorch build Neo installs by default (modules/launch_utils.py, prepare_environment).
ARG TORCH_VERSION=2.14.0+cu130
ARG TORCHVISION_VERSION=0.29.0+cu130
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130

# uv is only used during the build, to install Python and packages quickly.
FROM ghcr.io/astral-sh/uv:0.13.6@sha256:af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0 AS uv


# ------------------------------------------------------------------------------
# Base image: NVIDIA CUDA runtime (Ubuntu 22.04), pinned by digest.
# Update this digest intentionally whenever you choose to refresh the base image.
# ------------------------------------------------------------------------------
FROM nvidia/cuda:13.0.2-runtime-ubuntu22.04@sha256:cc28faec68e3dffcf6803683d34a03dcd62fe29e58a0b34b710b800a3d7b73b3 AS build

# Use bash with -euo pipefail for safer RUN pipelines (matches set -euo in scripts).
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# ------------------------------------------------------------------------------
# Build-time configuration
# ------------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive

ARG WEBUI_TAG
ARG WEBUI_REF

# Python minor version Neo targets (modules/launch_utils.py warns below 3.13).
# The exact patch release is whatever the pinned uv version installs for 3.13.
ARG PYTHON_VERSION=3.13

ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCH_INDEX_URL

# Packages Neo installs outside requirements.txt (same file, same function).
# SECURITY MITIGATION, MAY BREAK: Neo 2.31 pins gradio 4.40.0, which has 28
# known CVEs. 4.44.1 is the last 4.x release and fixes 5 of them. Neo's UI is
# written for gradio 4.40, so this upgrade is not tested by upstream. If the
# WebUI misbehaves, set GRADIO_VERSION=4.40.0 and rebuild. The remaining CVEs
# are listed in README.md ("Known security issues") and .trivyignore.
ARG GRADIO_VERSION=4.44.1
ARG GRADIO_RANGESLIDER_VERSION=0.0.8

# SECURITY MITIGATION, MAY BREAK: newer than the versions Neo 2.31 pins, to fix
# HIGH vulnerabilities found by the image scan (see README "Known security issues"):
#   GitPython 3.1.62 -> 3.2.1   (5 issues; Neo uses it to install extensions)
#   diffusers 0.37.1 -> 0.38.0  (2 issues; remote-code loading bypass)
#   setuptools 78.1.0 -> 81.0.0 (3 issues incl. its bundled jaraco.context and wheel).
#     81 is the last release that still ships pkg_resources, which Neo's built-in
#     oneformer (detectron2) preprocessor imports. Do not go to 82+ without checking.
ARG GITPYTHON_VERSION=3.2.1
ARG DIFFUSERS_VERSION=0.38.0
ARG SETUPTOOLS_VERSION=81.0.0
ARG PACKAGING_VERSION=26.3
ARG PIP_VERSION=26.2.2

# Build-time environment. IMAGE_VERSION is deliberately NOT set here: it
# changes on every commit and would invalidate every cached layer.
ENV WEBUI_DIR="/opt/forge-neo"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV TORCH_VERSION="${TORCH_VERSION}"
ENV TORCHVISION_VERSION="${TORCHVISION_VERSION}"


# ------------------------------------------------------------------------------
# Install minimal runtime dependencies.
# Docker guidance recommends keeping images small and rebuilding regularly to
# pick up updates. https://docs.docker.com/build/building/best-practices/
# ------------------------------------------------------------------------------
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  ca-certificates \
  openssl \
  git \
  # build-essential: Required in final image (not just build stage) because
  # extensions compile C dependencies at runtime via pip install. Removing the
  # compiler breaks extension installation. Attack surface is marginal given
  # extensions already have arbitrary code execution. See SECURITY.md.
  build-essential \
  libglib2.0-0 \
  libgomp1 \
  libsm6 \
  libxrender1 \
  libxext6 \
  libgl1 \
  && apt-get upgrade -y gnupg \
  && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Python 3.13 (Ubuntu 22.04 ships 3.10). uv installs a standalone CPython build
# under /opt/python, the same approach as Neo's own docker/Dockerfile.
# The EXTERNALLY-MANAGED marker is removed so pip can install extension
# packages into the per-user site at runtime.
# ------------------------------------------------------------------------------
# PY_REFRESH: the build workflows pass the current year-month. A new value
# rebuilds this stage once a month, picking up updates to the Python
# packages Neo does not pin. Unchanged, every step below is reused from the
# build cache.
ARG PY_REFRESH=none
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/opt/python \
  UV_NO_CACHE=1 \
  UV_COMPILE_BYTECODE=1
RUN echo "python refresh: ${PY_REFRESH}" \
  && uv python install "${PYTHON_VERSION}" \
  && py="$(uv python find "${PYTHON_VERSION}")" \
  && ln -sf "${py}" /usr/local/bin/python3 \
  && ln -sf "${py}" /usr/local/bin/python \
  && readlink -f /usr/local/bin/python3 > /opt/python/.python3-path \
  && find /opt/python -name EXTERNALLY-MANAGED -delete \
  && python3 --version

# Packages go into the interpreter's own site-packages (read-only at runtime).
# torch comes only from the PyTorch index, which also hosts all of its
# dependencies (the same as PyTorch's own install command).
# UV_COMPILE_BYTECODE: precompile, because the read-only filesystem stops
# Python from caching bytecode at runtime.
RUN uv pip install --python /usr/local/bin/python3 --break-system-packages \
  "pip==${PIP_VERSION}" "packaging==${PACKAGING_VERSION}" \
  && uv pip install --python /usr/local/bin/python3 --break-system-packages \
  "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" \
  --index-url "${TORCH_INDEX_URL}"


# ------------------------------------------------------------------------------
# Fetch Forge Neo source at the pinned release commit.
# Fetching only that one commit keeps the build small. .git is removed, so
# the WebUI reports its version from modules_forge/forge_version.py instead.
# ------------------------------------------------------------------------------
RUN git init -q "${WEBUI_DIR}" \
  && git -C "${WEBUI_DIR}" fetch -q --depth 1 https://github.com/Haoming02/sd-webui-forge-classic.git "${WEBUI_REF}" \
  && git -C "${WEBUI_DIR}" checkout -q FETCH_HEAD \
  && test "$(git -C "${WEBUI_DIR}" rev-parse HEAD)" = "${WEBUI_REF}" \
  && rm -rf "${WEBUI_DIR}/.git"

# Install gradio, then Neo's own requirements, in two separate steps and in
# that order, the same way Neo's launcher does. gradio declares Pillow<11 but
# Neo pins Pillow 13; the second step overrides it, exactly as upstream does.
# A single combined install would refuse to resolve. pip (not uv) is used here
# because it installs the way Neo's launcher does.
# Then run Neo's environment preparation once with --exit so built-in
# extension installers run now instead of at first start. Neo skips ALL
# extension installers (built-in ones too) when <data-dir>/extensions is
# missing, so that folder is created first.
# Neo also unpacks bundled tokenizer files into its own folder on first
# start (backend/huggingface process()). The program folder is read-only
# at runtime, so that runs here too; it checks each file's SHA-256 itself.
# Gradio patch (maintainer's own, see README "Known security issues"):
# 4.44.1 serves every type outside XSS_SAFE_MIMETYPES as a download, which
# includes Neo's CSS and JavaScript, so the UI loads half-built. Add exactly
# those types. HTML and SVG, which can run scripts when opened, stay as
# downloads. Skipped when the list doesn't exist (GRADIO_VERSION=4.40.0).
# --skip-torch-cuda-test: the build host has no GPU.
# The last step fails the build if anything replaced the pinned torch.
# compileall: "|| true" because a few bundled third-party files may not
# compile on 3.13; Python then compiles those in memory when imported.
WORKDIR ${WEBUI_DIR}
# hadolint ignore=DL3013
RUN python3 -m pip install --no-cache-dir --prefer-binary \
  "gradio==${GRADIO_VERSION}" "gradio_rangeslider==${GRADIO_RANGESLIDER_VERSION}" \
  && python3 -m pip install --no-cache-dir --prefer-binary -r requirements.txt \
  && python3 -m pip install --no-cache-dir --prefer-binary \
  "GitPython==${GITPYTHON_VERSION}" "diffusers==${DIFFUSERS_VERSION}" "setuptools==${SETUPTOOLS_VERSION}" \
  && python3 -c "import importlib.util, pathlib, py_compile; \
p = pathlib.Path(importlib.util.find_spec('gradio.routes').origin); s = p.read_text(); \
o = '    \"application/json\",\n}'; \
n = '    \"application/json\",\n    \"text/css\",\n    \"text/javascript\",\n    \"application/javascript\",\n}'; \
assert 'XSS_SAFE_MIMETYPES' not in s or s.count(o) == 1, 'gradio patch: anchor not found'; \
'XSS_SAFE_MIMETYPES' in s and (p.write_text(s.replace(o, n)), py_compile.compile(str(p), doraise=True))" \
  && mkdir -p /tmp/neo-build/extensions \
  && COMMANDLINE_ARGS="" python3 launch.py --skip-torch-cuda-test --skip-python-version-check \
  --data-dir /tmp/neo-build --exit \
  && python3 -c "from backend.huggingface import process; process()" \
  && rm -rf /tmp/neo-build "${WEBUI_DIR}/tmp" /root/.cache \
  && { python3 -m compileall -q "${WEBUI_DIR}" > /dev/null || true; } \
  && GRADIO_VERSION="${GRADIO_VERSION}" GITPYTHON_VERSION="${GITPYTHON_VERSION}" \
  DIFFUSERS_VERSION="${DIFFUSERS_VERSION}" SETUPTOOLS_VERSION="${SETUPTOOLS_VERSION}" \
  python3 -c "import os, importlib.metadata as m, torch, torchvision, gradio; \
assert m.version('GitPython') == os.environ['GITPYTHON_VERSION'], m.version('GitPython'); \
assert m.version('diffusers') == os.environ['DIFFUSERS_VERSION'], m.version('diffusers'); \
assert m.version('setuptools') == os.environ['SETUPTOOLS_VERSION'], m.version('setuptools'); \
assert tuple(int(x) for x in m.version('urllib3').split('.')[:2]) >= (2, 8), 'urllib3 ' + m.version('urllib3'); \
import pkg_resources; \
import mimetypes, gradio.routes as gr_routes; X = getattr(gr_routes, 'XSS_SAFE_MIMETYPES', None); \
assert X is None or (mimetypes.guess_type('a.js')[0] in X and mimetypes.guess_type('a.css')[0] in X and not {'text/html', 'image/svg+xml'} & X), X; \
m.version('onnxruntime'); m.version('depth_anything'); m.version('depth_anything_v2'); \
from backend.huggingface import Token; \
missing = [p for p in vars(Token).values() if isinstance(p, str) and p.endswith('tokenizer.json') and not os.path.isfile(p)]; \
assert not missing, missing; \
assert torch.__version__ == os.environ['TORCH_VERSION'], torch.__version__; \
assert torchvision.__version__ == os.environ['TORCHVISION_VERSION'], torchvision.__version__; \
assert gradio.__version__ == os.environ['GRADIO_VERSION'], gradio.__version__; \
print('torch', torch.__version__, 'torchvision', torchvision.__version__, 'gradio', gradio.__version__)"

# uv is not needed at runtime.
# Point the folders Neo writes under its own install directory at writable
# volumes, so the WebUI works with a read-only container filesystem:
#   tmp/           restart marker, Gradio theme cache, config.json backups
#   config_states/ extension state snapshots
#   the built-in Spectrum extension's presets.json, which it creates on first
#   load and rewrites when a preset is saved (created on first load if missing;
#   the build fails if upstream starts shipping that file, so it gets reviewed)
# The target directories are created by start.sh on each launch.
RUN rm -rf "${WEBUI_DIR}/tmp" "${WEBUI_DIR}/config_states" \
  && ln -s /data/tmp/webui "${WEBUI_DIR}/tmp" \
  && ln -s /config/webui/config_states "${WEBUI_DIR}/config_states" \
  && test ! -e "${WEBUI_DIR}/extensions-builtin/sd_forge_spectrum/presets.json" \
  && ln -s /config/webui/spectrum-presets.json "${WEBUI_DIR}/extensions-builtin/sd_forge_spectrum/presets.json"

# ==============================================================================
# Runtime stage
# ==============================================================================
FROM nvidia/cuda:13.0.2-runtime-ubuntu22.04@sha256:cc28faec68e3dffcf6803683d34a03dcd62fe29e58a0b34b710b800a3d7b73b3

# Use bash with -euo pipefail for safer RUN pipelines (matches set -euo in scripts).
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG WEBUI_TAG
ARG WEBUI_REF
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCH_INDEX_URL

# Unraid-friendly defaults (nobody/users). Adjust if you use a different strategy.
ARG APP_UID=99
ARG APP_GID=100

# ------------------------------------------------------------------------------
# Runtime defaults
# NOTE: --listen binds to all interfaces. On a trusted LAN this is often OK,
# but exposing this service beyond a trusted network may not be as safe as intended.
# If a user wants stronger exposure controls, those should usually be enforced
# by network design, reverse proxies, VPNs, access controls, and container
# runtime settings rather than trying to rely on this image alone.
#
# No attention package (xformers, sage, flash) is installed. Neo then uses
# PyTorch's built-in scaled_dot_product_attention, which Neo's README calls
# "usually as fast, and also more stable".
# ------------------------------------------------------------------------------
# Launch flags come from the template's NEO_* options (WebUI/neo_args.py, run
# by start.sh), which also always adds --listen --port 7860 --data-dir /data.
# COMMANDLINE_ARGS is the template's "Extra Launch Flags": empty by default.
ENV COMMANDLINE_ARGS=""
ENV WEBUI_DIR="/opt/forge-neo"
ENV PYTHONUSERBASE="/data/python-user"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV TORCH_VERSION="${TORCH_VERSION}"
ENV TORCHVISION_VERSION="${TORCHVISION_VERSION}"
ENV TORCH_INDEX_URL="${TORCH_INDEX_URL}"
ENV APP_UID="${APP_UID}"
ENV APP_GID="${APP_GID}"

# ------------------------------------------------------------------------------
# Install minimal runtime dependencies.
# Docker guidance recommends keeping images small and rebuilding regularly to
# pick up updates. https://docs.docker.com/build/building/best-practices/
# ------------------------------------------------------------------------------
# APT_REFRESH: the build workflows pass today's date (US Eastern), so this
# layer is rebuilt once a day with current Ubuntu security updates. The
# Python and Forge Neo layers below are COPY --link layers: they do not
# depend on this one and are reused unchanged.
ARG APT_REFRESH=none
RUN echo "apt refresh: ${APT_REFRESH}" \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  ca-certificates \
  openssl \
  git \
  # build-essential: Required in final image (not just build stage) because
  # extensions compile C dependencies at runtime via pip install. Removing the
  # compiler breaks extension installation. Attack surface is marginal given
  # extensions already have arbitrary code execution. See SECURITY.md.
  build-essential \
  libglib2.0-0 \
  libgomp1 \
  libsm6 \
  libxrender1 \
  libxext6 \
  libgl1 \
  && apt-get upgrade -y \
  && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Create a dedicated non-root runtime user with Unraid-friendly UID/GID defaults.
# This logic ensures the group and user are always named 'sdwebui', even if the UID/GID already exist with other names (Unraid compatibility).
# groupmod -n renames existing system groups (e.g. 'users' at GID 100) which may affect other image layers that reference the old name.
RUN set -eux; \
  if getent group "${APP_GID}" > /dev/null; then \
  groupmod -n sdwebui "$(getent group "${APP_GID}" | cut -d: -f1)"; \
  else \
  groupadd --gid "${APP_GID}" sdwebui; \
  fi; \
  if id -u sdwebui > /dev/null 2>&1; then \
  usermod -u "${APP_UID}" -g "${APP_GID}" sdwebui; \
  else \
  useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash sdwebui; \
  fi

# ------------------------------------------------------------------------------
# Python (with PyTorch and every WebUI package) and Forge Neo, from the build
# stage. --link makes each a self-contained layer: it keeps the same digest
# whatever changes in the layers before it, so Unraid only downloads it again
# when its own contents change. --chown sets ownership while copying (a
# separate chown -R would store Neo's whole folder a second time).
# ------------------------------------------------------------------------------
COPY --link --from=build /opt/python /opt/python
COPY --link --chown=${APP_UID}:${APP_GID} --from=build /opt/forge-neo /opt/forge-neo
# The interpreter path was recorded in the build stage.
RUN py="$(cat /opt/python/.python3-path)" \
  && test -x "${py}" \
  && ln -sf "${py}" /usr/local/bin/python3 \
  && ln -sf "${py}" /usr/local/bin/python \
  && python3 --version

# Create the /config directory that holds auth files and state.
# The actual contents are bind-mounted from the host (appdata on Unraid);
# this just ensures the mount point exists and has correct ownership in the
# image so the read-only container filesystem doesn't cause confusion.
RUN mkdir -p /config/webui && chown -R sdwebui:sdwebui /config

# Overlay the custom launch.py wrapper that redacts sensitive CLI arguments
# (--gradio-auth, --gradio-auth-path, --api-auth) from startup log output and
# replaces Neo's interactive "clean reinstall" prompt, which would hang a
# container that has no keyboard. See WebUI/launch.py.
COPY --chown=${APP_UID}:${APP_GID} WebUI/launch.py "${WEBUI_DIR}/launch.py"

# ------------------------------------------------------------------------------
# Copy entrypoint scripts (from this repository)
#
# entrypoint.sh runs as root, self-heals /data ownership if needed, then drops
# to the unprivileged application user via setpriv before exec-ing start.sh.
# This is the standard "init as root, drop privileges" pattern used by postgres,
# nginx, redis, and many other production container images.
# ------------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
COPY start.sh /start.sh
COPY WebUI/neo_args.py /usr/local/lib/sd-webui-forge-neo-unraid/neo_args.py
COPY webui-auth.txt /webui-auth.txt
RUN chmod 0755 /entrypoint.sh /start.sh \
  && chmod 0644 /webui-auth.txt \
  && chown root:root /entrypoint.sh \
  && chown root:root /start.sh

# Include license and third-party notices in the image for distribution clarity.
COPY LICENSE THIRD_PARTY_NOTICES.md /usr/share/doc/sd-webui-forge-neo-unraid/
COPY LICENSES/AGPL-3.0.txt /usr/share/doc/sd-webui-forge-neo-unraid/LICENSES/AGPL-3.0.txt

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
EXPOSE 7860

# ------------------------------------------------------------------------------
# Healthcheck
# Probes whether the Gradio HTTP server is accepting TCP connections on :7860.
# This is a lightweight liveness signal, not a correctness check — a healthy
# status only means "something answered on the port," not that the app is
# fully functional or authenticated.
#
# Timer rationale (tuned for Forge Neo on Unraid):
#   --start-period 300s   Dependencies are baked in, so startup is mostly
#                         extension installers and model loading. 5 min grace
#                         covers a first start with several extensions.
#   --interval     120s   Check every 2 min — frequent enough to catch crashes,
#                         rare enough to not spam during model loads.
#   --timeout       30s   Model swaps and extension installs can briefly stall
#                         the event loop; 30 s absorbs transient pauses.
#   --retries        5    Requires 5 consecutive failures (~10+ min of total
#                         unresponsiveness) before marking unhealthy, which
#                         virtually eliminates false positives from normal
#                         heavy operations (model loading, image browser, etc.).
#
# Known limitation: the port 7860 below is baked in at build time. Docker's
# HEALTHCHECK CMD runs at the daemon level and cannot read runtime env vars
# (including COMMANDLINE_ARGS). If you change --port in COMMANDLINE_ARGS at
# runtime, this probe will target the wrong port and always report unhealthy.
# Keep your runtime --port set to 7860, or accept that the healthcheck will
# be inaccurate if you use a non-default port.
# ------------------------------------------------------------------------------
HEALTHCHECK --interval=120s --timeout=30s --start-period=300s --retries=5 \
  CMD python3 -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('127.0.0.1', 7860)); s.close()" || exit 1


# Strip all SUID/SGID bits from binaries so no binary in the image can
# escalate privileges if the container is compromised. Skips virtual
# filesystems (/proc, /sys, /dev) which are kernel-managed.
# || true: intentional. Some base image files may be immutable; stripping as many as possible is still a net win.
RUN find / -perm /6000 -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -exec chmod a-s {} + || true

# Strip Linux file capabilities (e.g. cap_net_raw+ep) which survive the SUID strip.
RUN (find / -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -exec getcap {} + 2>/dev/null || true) | awk -F' ' '{print $1}' | xargs -r setcap -r 2>/dev/null || true

# ------------------------------------------------------------------------------
# Version labels last: IMAGE_VERSION changes on every commit, so anything after
# it is rebuilt every time. Keeping it at the end keeps every layer above cached.
# ------------------------------------------------------------------------------

# Build argument for embedding the image version in OCI labels.
# Defaults to "dev" for local/untagged builds; CI passes the real version.
ARG IMAGE_VERSION=dev

# ------------------------------------------------------------------------------
# OCI image labels — links the GHCR package to this repository, exposes the
# license, and gives vulnerability scanners (Trivy, Grype, etc.) the source
# context they need to correlate findings back to the project.
# Reference: https://github.com/opencontainers/image-spec/blob/main/annotations.md
# ------------------------------------------------------------------------------
LABEL org.opencontainers.image.title="SD-WebUI-Forge-Neo-Unraid" \
  org.opencontainers.image.description="Forge Neo by Haoming02, packaged for Unraid by Aegisnir, with NVIDIA GPU support" \
  org.opencontainers.image.source="https://github.com/aegisnir/sd-webui-forge-neo-unraid" \
  org.opencontainers.image.url="https://github.com/aegisnir/sd-webui-forge-neo-unraid" \
  org.opencontainers.image.licenses="AGPL-3.0-only" \
  org.opencontainers.image.version="${IMAGE_VERSION}" \
  sd-webui-forge-neo-unraid.upstream.tag="${WEBUI_TAG}" \
  sd-webui-forge-neo-unraid.upstream.ref="${WEBUI_REF}"

# Shown in the startup log banner (start.sh).
ENV IMAGE_VERSION="${IMAGE_VERSION}"
ENV WEBUI_TAG="${WEBUI_TAG}"

# The container starts as root so entrypoint.sh can self-heal /data ownership.
# It then drops to sdwebui (UID 99) via setpriv before exec-ing start.sh.
# Runtime hardening should still be reviewed at the container runtime layer
# (for example: read-only root filesystem, dropped capabilities, no-new-
# privileges, explicit writable mounts, network exposure limits, etc.).
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
