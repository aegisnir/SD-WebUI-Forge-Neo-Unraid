#!/usr/bin/env bash
#
# start.sh - Container entrypoint for SD-WebUI-Forge-Neo-Unraid
#
# Forge Neo is by Haoming02 (https://github.com/Haoming02/sd-webui-forge-classic/tree/neo).
# This project only packages it for Unraid.
#
# Purpose:
#   Start the WebUI from within the container using configuration provided via
#   environment variables. This script includes basic sanity checks and clearer
#   error messages to help with troubleshooting.
#
# This project is maintained as a personal, AI-assisted learning project.
#
# Python, PyTorch and the WebUI's dependencies are baked into the image.
# Packages that extensions install at runtime go to PYTHONUSERBASE
# (/data/python-user), because the image's own packages are read-only.
#
# The checks below are intended to catch obvious problems early, but they should
# not be read as proof that the runtime is secure, correct, or production-ready.
#
# Notes:
#   - This script does not attempt to configure networking, authentication,
#     or reverse proxy behavior. Those are deployment concerns and may vary by environment.
#   - If you change runtime flags (e.g., network exposure), the risk characteristics
#     of the deployment may not match the original intent of this repository.
#

set -euo pipefail

# Signal handling: set early so SIGTERM during bootstrap (pip install) is caught.
_DELIBERATE_STOP=0
_WEBUI_PID=""
_forward_signal() {
  _DELIBERATE_STOP=1
  if [[ -n "${_WEBUI_PID}" ]]; then
    kill -TERM "${_WEBUI_PID}" 2>/dev/null || true
    ( sleep 15; kill -KILL "${_WEBUI_PID}" 2>/dev/null ) &
  fi
}
trap '_forward_signal' TERM INT

# ── Color palette ────────────────────────────────────────────────────────────
# C_INFO   (magenta) → informational / status messages
# C_WARN   (orange)  → caution / warnings that need attention but are not fatal
# C_CRIT   (scarlet) → critical errors requiring user action
# C_ACCENT (cyan)    → accent / highlights (URLs, commands, structural chrome)
# Colors are enabled by default because Docker/Unraid log viewers render ANSI.
# Set NO_COLOR=1 or TERM=dumb in the container environment to suppress them.
if [[ "${NO_COLOR:-}" == "" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_ACCENT=$'\e[96m'
  C_INFO=$'\e[95m'; C_WARN=$'\e[93m'; C_CRIT=$'\e[91m'
else
  C_RESET='' C_BOLD='' C_ACCENT='' C_INFO='' C_WARN='' C_CRIT=''
fi

# Set HOME for the non-root user to /data for consistent config/cache locations
export HOME=/data

# Use persistent temp storage in /data so large downloads (for example torch wheels)
# do not exhaust the container's limited writable temp space.
export TMPDIR=/data/tmp

# Use persistent pip cache in /data for faster extension installs
export PIP_CACHE_DIR=/data/pip-cache

# Packages installed by extensions at runtime (pip falls back to a per-user
# install because the baked site-packages are read-only). Python searches this
# before the baked packages. Deleting the folder resets extension packages.
export PYTHONUSERBASE="${PYTHONUSERBASE:-/data/python-user}"

# Force unbuffered Python output so log annotations appear immediately.
# Upstream webui.sh passes `python -u`; we call launch.py directly and need this.
export PYTHONUNBUFFERED=1

# Tells Neo something is watching to restart it, which enables the WebUI's
# Restart button. Neo then writes tmp/restart and exits with code 0, and the
# restart loop at the bottom of this script starts it again. Upstream webui.sh
# sets this without `export`, so Neo never sees it there.
export SD_WEBUI_RESTART="tmp/restart"

if [[ "$(id -u)" == "0" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Refusing to run as root. Please use a non-root user (UID 99 recommended for Unraid).${C_RESET}" >&2
  exit 1
fi

# ── Paths & version pins ─────────────────────────────────────────────────────
# These defaults are designed for the Docker image layout. Override via env vars
# if testing locally or using a non-standard data volume path.

WEBUI_DIR="${WEBUI_DIR:-/opt/forge-neo}"                           # Forge Neo source, fetched at image build time
LOCAL_WEBUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/WebUI"  # Fallback for local (non-Docker) development
PYTHON_BIN="python3"                                               # Baked Python 3.13 (see Dockerfile)
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu130}"  # Used by Neo if --xformers/--sage install a package
if [[ ! "${TORCH_INDEX_URL}" =~ ^https:// ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} TORCH_INDEX_URL must use https://. Got: ${TORCH_INDEX_URL}${C_RESET}" >&2
  exit 1
fi
APPDATA_DIR="/config/webui"                                        # WebUI settings in appdata (config.json etc.)
RUNTIME_CONFIG_STATES_DIR="${APPDATA_DIR}/config_states"           # Persistent extension state snapshots (in appdata)
RUNTIME_WEBUI_TMP_DIR="/data/tmp/webui"                            # Neo's tmp/ (restart marker, theme cache)
TORCH_VERSION="${TORCH_VERSION:-}"                                 # Baked versions, set by the Dockerfile
TORCHVISION_VERSION="${TORCHVISION_VERSION:-}"
RESTART_ON_EXIT="${RESTART_ON_EXIT:-1}"            # 1 = restart WebUI after any exit; 0 = exit container cleanly
RESTART_DELAY="${RESTART_DELAY:-5}"                # Seconds to wait before restarting after a clean exit
RESTART_DELAY_MAX="${RESTART_DELAY_MAX:-60}"       # Backoff ceiling for crash restarts (seconds)
RESTART_MAX_ATTEMPTS="${RESTART_MAX_ATTEMPTS:-0}"  # 0 = retry indefinitely; N = stop after N consecutive restarts

# ── Authentication paths ─────────────────────────────────────────────────────
# The user-facing auth file (WEBUI_AUTH_FILE) can contain comments and blank
# lines for readability. The runtime copy (WEBUI_AUTH_RUNTIME_FILE) is a
# sanitized version with only username:password lines that Gradio can parse.
WEBUI_AUTH_FILE_DEFAULT="/config/auth/webui-auth.txt"
WEBUI_AUTH_FILE="${WEBUI_AUTH_FILE:-${WEBUI_AUTH_FILE_DEFAULT}}"
WEBUI_AUTH_RUNTIME_FILE="/config/auth/.webui-auth.runtime.txt"

# mirror-webui-file = copy WebUI credentials to --api-auth when --api is enabled
# disabled        = do not auto-set --api-auth; user manages it manually
API_AUTH_FILE_MODE="${API_AUTH_FILE_MODE:-disabled}"

UMASK="${UMASK:-}"                                                 # Optional: override default umask for all file creation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_AUTH_SAMPLE_FILE="${SCRIPT_DIR}/webui-auth.txt"              # Bundled sample; copied to /config/auth on first launch
EXIT_CONFIG=78                                                     # WebUI/launch.py: settings need a human, do not restart

if [[ -n "${UMASK}" ]]; then
  if [[ ! "${UMASK}" =~ ^[0-7]{3,4}$ ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} UMASK must be a 3- or 4-digit octal value (for example 027 or 0027).${C_RESET}" >&2
    exit 1
  fi
  umask "${UMASK}"
  echo "${C_ACCENT}Using UMASK=${UMASK}${C_RESET}" >&2
fi

if [[ ! -d "${WEBUI_DIR}" && -d "${LOCAL_WEBUI_DIR}" ]]; then
  echo "${C_WARN}Container WebUI directory not found; falling back to local workspace path: ${LOCAL_WEBUI_DIR}${C_RESET}" >&2
  WEBUI_DIR="${LOCAL_WEBUI_DIR}"
fi

# Basic sanity checks to make failures easier to diagnose.
# These are here mostly to fail fast with clearer messages instead of producing
# a less helpful Python or file-not-found error later in startup.
if [[ ! -d "${WEBUI_DIR}" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Expected WebUI directory not found: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_CRIT}       The image build may have failed or WEBUI_DIR may be incorrect.${C_RESET}" >&2
  exit 1
fi

if [[ ! -f "${WEBUI_DIR}/launch.py" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} launch.py not found in: ${WEBUI_DIR}${C_RESET}" >&2
  echo "${C_CRIT}       The repository contents may be incomplete or not checked out as expected.${C_RESET}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} python3 is not available in PATH.${C_RESET}" >&2
  echo "${C_CRIT}       The base image or dependency installation may be incomplete.${C_RESET}" >&2
  exit 1
fi

if [[ ! -d "/data" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Expected mapped data directory not found at /data${C_RESET}" >&2
  echo "${C_CRIT}       Map /data to a writable host path before starting the container.${C_RESET}" >&2
  exit 1
fi

if [[ ! -w "/data" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} /data exists but is not writable by the current user (uid=$(id -u)).${C_RESET}" >&2
  echo "${C_CRIT}       The container entrypoint attempted to correct this automatically but could not.${C_RESET}" >&2
  echo "${C_CRIT}       This can happen with NFS root squash, unusual host permissions, or SELinux policies.${C_RESET}" >&2
  echo "" >&2
  echo "${C_WARN}       To fix manually, run the following on the Unraid host (as root) and then restart${C_RESET}" >&2
  echo "${C_WARN}       the container (adjust the path to match your container template's /data bind-mount):${C_RESET}" >&2
  echo "" >&2
  echo "${C_ACCENT}         chown nobody:users <your-data-path>${C_RESET}" >&2
  echo "${C_ACCENT}         chmod 775 <your-data-path>${C_RESET}" >&2
  echo "" >&2
  echo "${C_WARN}       Adjust the path above if your Unraid share path is different.${C_RESET}" >&2
  exit 1
fi

cd "${WEBUI_DIR}"

mkdir -p "${TMPDIR}"
# Clean up any leftover temp files from previous crashed or interrupted runs.
# Partial pip downloads and extracted archives can silently accumulate under
# /data/tmp across restarts and eat disk on the persistent share.
# ${TMPDIR:?} expands with a fatal error if unset, preventing a bare rm -rf /*.
# find -mindepth 1 -delete catches dotfiles that glob expansion misses.
find "${TMPDIR:?}" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "${RUNTIME_WEBUI_TMP_DIR}"
mkdir -p "${PIP_CACHE_DIR}"
mkdir -p "${PYTHONUSERBASE}"
# Ensure standard data subtrees exist so the WebUI finds expected paths on a
# fresh or restored /data volume without requiring the user to re-create them.
# Neo's default output folder is /data/output (A1111 used /data/outputs).
mkdir -p /data/models/Stable-diffusion
mkdir -p /data/models/VAE
mkdir -p /data/models/Lora
mkdir -p /data/output
mkdir -p /data/extensions
mkdir -p /config/auth

# ── Appdata migration from the A1111 image ───────────────────────────────────
# Earlier releases of this container (AUTOMATIC1111) kept WebUI settings in
# /config/a1111. Rename it once. Neo will then ask for a settings reset (see
# verify_version in WebUI/launch.py) because A1111 settings are not compatible.
if [[ -d "/config/a1111" && ! -e "${APPDATA_DIR}" ]]; then
  echo "${C_WARN}Migrating /config/a1111 -> ${APPDATA_DIR}${C_RESET}" >&2
  mv /config/a1111 "${APPDATA_DIR}"
fi
mkdir -p "${APPDATA_DIR}"

# ── Appdata symlinks ──────────────────────────────────────────────────────────
# The WebUI writes config.json, ui-config.json, styles.csv, and config_states/
# under /data by default. We redirect them to /config/webui via symlinks so they
# live in appdata, are included in CA Backup, and survive a /data wipe or rebuild.
#
# All extension settings that use the WebUI opts API (visible in the Settings tab)
# are stored in config.json and are therefore covered here. Extension-specific
# standalone files (e.g. civitai browser favourites/ban lists, search history)
# live inside /data/extensions/<name>/ and survive as long as /data does.
_ensure_appdata_link() {
  # _ensure_appdata_link <target-in-/config> <link-in-/data>
  # Ensures LINK is a symlink pointing to TARGET.
  # Migration: if LINK is a real file/dir, moves it to TARGET first.
  # If both exist as real content, TARGET (appdata) wins.
  local target="$1" link="$2"
  if [[ -L "${link}" && "$(readlink "${link}")" == "${target}" ]]; then
    return 0
  fi
  [[ -L "${link}" ]] && rm "${link}"
  if [[ -e "${link}" && ! -e "${target}" ]]; then
    mv "${link}" "${target}"
  elif [[ -e "${link}" && -e "${target}" ]]; then
    cp -a "${link}" "${link}.bak.$(date +%s)" 2>/dev/null || true
    echo "${C_WARN}Both ${link} and ${target} exist. Backed up ${link} before removing.${C_RESET}" >&2
    rm -rf "${link}"
  fi
  ln -sf "${target}" "${link}"
}

_ensure_appdata_link "${APPDATA_DIR}/config.json"    /data/config.json
_ensure_appdata_link "${APPDATA_DIR}/ui-config.json" /data/ui-config.json
_ensure_appdata_link "${APPDATA_DIR}/styles.csv"     /data/styles.csv

# config_states: migrate from /data if upgrading from a pre-appdata-split image
if [[ -d "/data/config_states" && ! -L "/data/config_states" ]]; then
  echo "${C_WARN}Migrating /data/config_states -> ${RUNTIME_CONFIG_STATES_DIR}${C_RESET}" >&2
  if [[ ! -d "${RUNTIME_CONFIG_STATES_DIR}" ]]; then
    mv /data/config_states "${RUNTIME_CONFIG_STATES_DIR}"
  else
    rm -rf /data/config_states
  fi
fi
mkdir -p "${RUNTIME_CONFIG_STATES_DIR}"

available_kb="$(df -Pk /data | awk 'NR==2 {print $4}')"
if [[ -z "${available_kb}" || ! "${available_kb}" =~ ^[0-9]+$ ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Unable to determine free space for /data.${C_RESET}" >&2
  echo "${C_CRIT}       Verify that /data is mounted and writable before starting the container.${C_RESET}" >&2
  exit 1
fi
echo "${C_ACCENT}Detected free space in /data: $(( available_kb / 1024 )) MiB${C_RESET}"

_validate_build_symlink() {
  local name="$1" link_path="$2" expected_target="$3"
  if [[ -e "${link_path}" && ! -L "${link_path}" ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${link_path} exists and is not a symlink.${C_RESET}" >&2
    echo "${C_CRIT}       On a read-only container filesystem, start.sh cannot replace it at runtime.${C_RESET}" >&2
    echo "${C_WARN}       Rebuild the image without that path, or remove it before enabling --read-only.${C_RESET}" >&2
    exit 1
  fi
  if [[ -L "${link_path}" ]]; then
    local existing_target
    existing_target="$(readlink "${link_path}")"
    if [[ "${existing_target}" != "${expected_target}" ]]; then
      echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${link_path} points to ${existing_target}, expected ${expected_target}.${C_RESET}" >&2
      echo "${C_WARN}       Rebuild the image so the ${name} symlink matches the persistent runtime path.${C_RESET}" >&2
      exit 1
    fi
  else
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${link_path} symlink is missing.${C_RESET}" >&2
    echo "${C_WARN}       This image now expects that symlink to be created at build time so startup works with --read-only.${C_RESET}" >&2
    exit 1
  fi
}

_validate_build_symlink "config_states" "${WEBUI_DIR}/config_states" "${RUNTIME_CONFIG_STATES_DIR}"
_validate_build_symlink "tmp" "${WEBUI_DIR}/tmp" "${RUNTIME_WEBUI_TMP_DIR}"

# Leftover from the A1111 image, which installed Python packages here on first
# start. Not used anymore. Not deleted automatically, in case it is not ours.
if [[ -d "/data/venv" ]]; then
  echo "${C_WARN}Note: /data/venv is from the old A1111 image and is no longer used. You can delete it to free space.${C_RESET}" >&2
fi

if [[ "${_DELIBERATE_STOP}" == "1" ]]; then
  echo "${C_WARN}[start.sh] Stop signal received during startup. Exiting cleanly.${C_RESET}" >&2
  exit 0
fi

# ── Dependency sanity check ──────────────────────────────────────────────────
# torch and torchvision are baked into the image. An extension can install a
# different version into PYTHONUSERBASE, which then shadows the baked one and
# usually breaks GPU support. Fail early with the fix instead.
if ! TORCH_VERSION="${TORCH_VERSION}" TORCHVISION_VERSION="${TORCHVISION_VERSION}" "${PYTHON_BIN}" - <<'PY'
import importlib
import os
import sys

expected = {
  "torch": os.environ["TORCH_VERSION"],
  "torchvision": os.environ["TORCHVISION_VERSION"],
}

installed = {}
errors = []

for name, expected_version in expected.items():
  try:
    module = importlib.import_module(name)
    installed_version = getattr(module, "__version__", "unknown")
    installed[name] = installed_version
    if expected_version and installed_version != expected_version:
      errors.append(f"{name}: expected {expected_version}, found {installed_version} at {module.__file__}")
  except Exception as exc:
    errors.append(f"{name}: not importable ({exc.__class__.__name__})")

print("Dependency sanity check: " + ", ".join(f"{name}={installed.get(name, 'missing')}" for name in expected))

if errors:
  print("Dependency version mismatch detected:", file=sys.stderr)
  for error in errors:
    print(f" - {error}", file=sys.stderr)
  sys.exit(1)
PY
then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} torch or torchvision does not match the version baked into this image.${C_RESET}" >&2
  echo "${C_WARN}       An extension probably installed its own copy into ${PYTHONUSERBASE}.${C_RESET}" >&2
  echo "${C_WARN}       Fix: delete that folder on the host (it holds only extension packages), then restart.${C_RESET}" >&2
  echo "${C_WARN}       Extensions reinstall what they need on the next start.${C_RESET}" >&2
  exit 1
fi

# ── Flags the A1111 image used that Forge Neo removed ────────────────────────
# Neo stops at startup on any unknown flag. These were common in A1111 setups
# (including this container's old default Extra Args), so drop them with a
# warning instead of failing. Removing them never lowers security:
#   --no-download-sd-model  Neo never downloads a model on its own
#   --disable-safe-unpickle Neo always loads checkpoints with weights_only=True
#   --allow-code            the custom-code script no longer exists
if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  _cleaned_args="$("${PYTHON_BIN}" - <<'PY'
import os
import shlex
import sys

removed = {"--no-download-sd-model", "--disable-safe-unpickle", "--allow-code"}
args = shlex.split(os.environ.get("COMMANDLINE_ARGS", ""))
kept = [a for a in args if a not in removed]
for a in args:
    if a in removed:
        print(f"Removed flag not supported by Forge Neo: {a}", file=sys.stderr)
print(shlex.join(kept))
PY
)"
  export COMMANDLINE_ARGS="${_cleaned_args}"
fi

# ── Auth argument construction ────────────────────────────────────────────────
# AUTH_ARGS accumulates --gradio-auth-path and/or --api-auth flags that get
# appended to COMMANDLINE_ARGS right before launch. USING_WEBUI_AUTH_FILE
# tracks whether we're sourcing auth from the managed file (vs. the user
# providing their own --gradio-auth in COMMANDLINE_ARGS).
AUTH_ARGS=()
USING_WEBUI_AUTH_FILE=0

# _auth_file_tool: Unified auth file parser. Reads username:password entries
# from an auth file (ignoring comments and blank lines).
# Mode --csv: print all entries as comma-separated string (for --api-auth).
# Mode --write <dest>: write sanitized one-entry-per-line file (for Gradio).
_auth_file_tool() {
  local mode="$1" source_file="$2"
  shift 2
  local dest_file="${1:-}"
  python3 - <<'PY' "${mode}" "${source_file}" "${dest_file}"
import sys
from pathlib import Path

mode, src_path = sys.argv[1], Path(sys.argv[2])
dst_path = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
entries = []

for raw_line in src_path.read_text(encoding='utf-8').splitlines():
    line = raw_line.strip()
    if not line or line.startswith('#'):
        continue
    for cred in line.split(','):
        cred = cred.strip()
        if cred:
            entries.append(cred)

if mode == '--csv':
    print(','.join(entries))
elif mode == '--write' and dst_path:
    Path(dst_path).write_text("\n".join(entries) + "\n", encoding='utf-8')
else:
    print(f"Unknown mode: {mode}", file=sys.stderr)
    sys.exit(1)
PY
}

extract_auth_file_csv() {
  _auth_file_tool --csv "$1"
}

write_runtime_auth_file() {
  _auth_file_tool --write "$1" "$2"
}

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth([=[:space:]]|$) ]]; then
  echo "${C_INFO}WebUI authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
elif [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--gradio-auth-path([=[:space:]]|$) ]]; then
  echo "${C_INFO}WebUI authentication file is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
else
  # Seed the default auth file on first launch if it does not exist yet.
  if [[ ! -f "${WEBUI_AUTH_FILE}" && -f "${WEBUI_AUTH_SAMPLE_FILE}" ]]; then
    # Create the seeded auth file with restrictive permissions from the start
    # so credentials are never world-readable, even briefly (umask 077 → 600).
    ( umask 077; cp "${WEBUI_AUTH_SAMPLE_FILE}" "${WEBUI_AUTH_FILE}" )
    echo "${C_WARN}Seeded default auth file at ${WEBUI_AUTH_FILE}.${C_RESET}" >&2
  fi

  if [[ ! -f "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file is missing: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Create the auth file or mount it from the host. Recommended path: /config/auth/webui-auth.txt${C_RESET}" >&2
    exit 1
  fi
  if [[ ! -s "${WEBUI_AUTH_FILE}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file is empty: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    exit 1
  fi

  auth_file_csv="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
  if [[ -z "${auth_file_csv}" ]]; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file has no usable credentials: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Add at least one entry in username:password format.${C_RESET}" >&2
    exit 1
  fi

  # Validate credential formatting up front so malformed entries fail fast
  # with a clear message instead of later crashing inside Gradio auth parsing.
  # The awk check ensures every entry has a non-empty username AND password
  # separated by a colon. Entries like ":password", "user:", or "nocolon" fail.
  # awk exit convention: bad?1:0 means exit 1 (failure) when malformed entries are found.
  # The outer `if !` then triggers the CRITICAL message.
  # (Historically coded as bad?0:1 with a plain `if`, which worked but was counter-intuitive.)
  if ! echo "${auth_file_csv}" | tr ',' '\n' | awk -F: '($1=="" || $2=="" || NF<2){bad=1} END{exit bad?1:0}'; then
    echo "${C_CRIT}${C_BOLD}CRITICAL:${C_RESET}${C_CRIT} WebUI auth file contains malformed credential entries: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "${C_CRIT}         Expected format is username:password (one per line or comma-separated).${C_RESET}" >&2
    echo "${C_CRIT}         Remove trailing commas and ensure every entry includes both username and password.${C_RESET}" >&2
    exit 1
  fi

  # Gradio auth-path parsing is strict and can crash on comments/blank lines.
  # Build a sanitized runtime auth file with only username:password entries.
  # umask 077 ensures the file is created as mode 600 if it does not yet exist,
  # eliminating the race window between creation and a subsequent chmod.
  # The explicit chmod 600 afterward handles the upgrade case where the file
  # already exists from a previous run with looser permissions (e.g. 644 from
  # an older version of this script that used cp-then-chmod ordering).
  ( umask 077; write_runtime_auth_file "${WEBUI_AUTH_FILE}" "${WEBUI_AUTH_RUNTIME_FILE}" )
  chmod 600 "${WEBUI_AUTH_RUNTIME_FILE}" 2>/dev/null || true

  AUTH_ARGS+=("--gradio-auth-path" "${WEBUI_AUTH_RUNTIME_FILE}")
  USING_WEBUI_AUTH_FILE=1
  echo "${C_INFO}WebUI authentication file is enabled via WEBUI_AUTH_FILE.${C_RESET}" >&2

  if grep -q 'admin:changeme' "${WEBUI_AUTH_FILE}" 2>/dev/null; then
    echo "" >&2
    echo "${C_WARN}${C_BOLD}  WARNING: Default credentials detected (admin:changeme)${C_RESET}" >&2
    echo "${C_WARN}  Anyone on your network can log in with these credentials.${C_RESET}" >&2
    echo "${C_WARN}  Change your password in: ${WEBUI_AUTH_FILE}${C_RESET}" >&2
    echo "" >&2
  fi
fi

API_ENABLED=0
if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api([=[:space:]]|$) ]]; then
  API_ENABLED=1
  echo "${C_INFO}API is explicitly enabled via COMMANDLINE_ARGS (--api).${C_RESET}" >&2
else
  echo "${C_ACCENT}API is disabled by default. Add --api to COMMANDLINE_ARGS to enable it.${C_RESET}" >&2
fi

if [[ "${API_ENABLED}" == "1" ]]; then
  if [[ "${USING_WEBUI_AUTH_FILE}" == "1" ]]; then
    if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
      echo "${C_INFO}API authentication is being managed via COMMANDLINE_ARGS.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "mirror-webui-file" ]]; then
      api_auth_value="$(extract_auth_file_csv "${WEBUI_AUTH_FILE}")"
      if [[ -z "${api_auth_value}" ]]; then
        echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} WEBUI_AUTH_FILE is set but no usable credentials were found in ${WEBUI_AUTH_FILE}${C_RESET}" >&2
        exit 1
      fi
      AUTH_ARGS+=("--api-auth" "${api_auth_value}")
      echo "${C_INFO}API authentication is mirrored from WEBUI_AUTH_FILE.${C_RESET}" >&2
    elif [[ "${API_AUTH_FILE_MODE}" == "disabled" ]]; then
      echo "${C_ACCENT}API auth mirroring from WEBUI_AUTH_FILE disabled via API_AUTH_FILE_MODE=disabled.${C_RESET}" >&2
    else
      echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Unrecognized API_AUTH_FILE_MODE=${API_AUTH_FILE_MODE}. Expected mirror-webui-file or disabled.${C_RESET}" >&2
      exit 1
    fi
  else
    echo "${C_ACCENT}API auth mirroring skipped because auth is not sourced from WEBUI_AUTH_FILE.${C_RESET}" >&2
  fi
else
  if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--api-auth([=[:space:]]|$) ]]; then
    echo "${C_WARN}[WARNING] --api-auth was provided but --api is not enabled. API auth flags will be ignored unless --api is set.${C_RESET}" >&2
  fi
fi

# ── HTTPS / TLS ──────────────────────────────────────────────────────────────
# WEBUI_TLS=auto (default): serve HTTPS. Uses /config/tls/custom.crt and
#   custom.key if both exist, otherwise a self-signed certificate that this
#   script creates and renews in /config/tls/.
# WEBUI_TLS=off: plain HTTP.
# Passing your own --tls-keyfile/--tls-certfile in COMMANDLINE_ARGS skips all
# of this, the same way your own auth flags skip the managed auth file.
#
# Verification stays on. Instead of --disable-tls-verify, the certificate is
# added to a trust bundle (SSL_CERT_FILE), so Gradio's startup request to its
# own HTTPS address is still checked.
TLS_ARGS=()
TLS_SCHEME="http"
TLS_DIR="/config/tls"
WEBUI_TLS="${WEBUI_TLS:-auto}"
TLS_RENEW_SECONDS=$(( 30 * 24 * 3600 ))   # renew self-signed certs 30 days before expiry

# _tls_fingerprint <cert>: SHA-256 fingerprint, for checking against the browser.
_tls_fingerprint() {
  openssl x509 -noout -fingerprint -sha256 -in "$1" 2>/dev/null | cut -d= -f2
}

# _tls_san_list: subjectAltName value for the self-signed certificate.
# Each WEBUI_TLS_HOSTNAMES entry is validated strictly because it is passed
# to openssl; anything that is not a plain IPv4 address or hostname stops startup.
_tls_san_list() {
  local -a sans=("DNS:localhost" "IP:127.0.0.1")
  local name
  name="$(hostname 2>/dev/null || true)"
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] && sans+=("DNS:${name}")
  local -a extra=()
  IFS=',' read -r -a extra <<< "${WEBUI_TLS_HOSTNAMES:-}"
  [[ -n "${WEBUI_HOST_IP:-}" ]] && extra+=("${WEBUI_HOST_IP}")
  for name in "${extra[@]}"; do
    name="${name//[[:space:]]/}"
    [[ -z "${name}" ]] && continue
    if [[ "${name}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      sans+=("IP:${name}")
    elif [[ "${name}" =~ ^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then
      sans+=("DNS:${name}")
    else
      echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} WEBUI_TLS_HOSTNAMES has an invalid entry: ${name}${C_RESET}" >&2
      echo "${C_WARN}       Use comma-separated hostnames or IPv4 addresses, for example: aether.local,10.0.0.5${C_RESET}" >&2
      exit 1
    fi
  done
  local IFS=','
  echo "${sans[*]}"
}

if [[ -n "${COMMANDLINE_ARGS:-}" && " ${COMMANDLINE_ARGS} " =~ [[:space:]]--tls-(keyfile|certfile)([=[:space:]]|$) ]]; then
  TLS_SCHEME="https"
  echo "${C_INFO}HTTPS is being managed via COMMANDLINE_ARGS (--tls-keyfile / --tls-certfile).${C_RESET}" >&2
elif [[ "${WEBUI_TLS,,}" == "off" ]]; then
  echo "${C_WARN}HTTPS is off (WEBUI_TLS=off). Logins and images cross the network unencrypted.${C_RESET}" >&2
elif [[ "${WEBUI_TLS,,}" != "auto" ]]; then
  echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Unrecognized WEBUI_TLS=${WEBUI_TLS}. Expected auto or off.${C_RESET}" >&2
  exit 1
else
  if ! command -v openssl >/dev/null 2>&1; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} openssl is missing from the image, so HTTPS cannot be set up. Set WEBUI_TLS=off to start without it.${C_RESET}" >&2
    exit 1
  fi
  ( umask 077; mkdir -p "${TLS_DIR}" )
  chmod 700 "${TLS_DIR}" 2>/dev/null || true

  if [[ -f "${TLS_DIR}/custom.crt" && -f "${TLS_DIR}/custom.key" ]]; then
    tls_cert="${TLS_DIR}/custom.crt"
    tls_key="${TLS_DIR}/custom.key"
    chmod 600 "${tls_key}" 2>/dev/null || true
    # The key must belong to the certificate; compare their public keys.
    cert_pub="$(openssl x509 -noout -pubkey -in "${tls_cert}" 2>/dev/null | openssl sha256 2>/dev/null || true)"
    key_pub="$(openssl pkey -pubout -in "${tls_key}" 2>/dev/null | openssl sha256 2>/dev/null || true)"
    if [[ -z "${cert_pub}" || "${cert_pub}" != "${key_pub}" ]]; then
      echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} ${TLS_DIR}/custom.crt and custom.key are unreadable or do not belong together.${C_RESET}" >&2
      echo "${C_WARN}       Fix or remove both files (the container then uses a self-signed certificate), or set WEBUI_TLS=off.${C_RESET}" >&2
      exit 1
    fi
    if ! openssl x509 -noout -checkend 0 -in "${tls_cert}" >/dev/null 2>&1; then
      echo "${C_CRIT}[WARNING] ${TLS_DIR}/custom.crt has EXPIRED. Browsers will refuse it. Replace it.${C_RESET}" >&2
    elif ! openssl x509 -noout -checkend "${TLS_RENEW_SECONDS}" -in "${tls_cert}" >/dev/null 2>&1; then
      echo "${C_WARN}[WARNING] ${TLS_DIR}/custom.crt expires within 30 days. Replace it soon.${C_RESET}" >&2
    fi
    echo "${C_INFO}HTTPS enabled with your certificate (${TLS_DIR}/custom.crt).${C_RESET}" >&2
  else
    tls_cert="${TLS_DIR}/selfsigned.crt"
    tls_key="${TLS_DIR}/selfsigned.key"
    tls_san="$(_tls_san_list)"
    # (Re)create when missing, expiring within 30 days, or covering different names.
    if [[ ! -f "${tls_cert}" || ! -f "${tls_key}" ]] \
      || ! openssl x509 -noout -checkend "${TLS_RENEW_SECONDS}" -in "${tls_cert}" >/dev/null 2>&1 \
      || [[ "$(cat "${TLS_DIR}/selfsigned.san" 2>/dev/null)" != "${tls_san}" ]]; then
      echo "${C_INFO}Creating a self-signed HTTPS certificate for: ${tls_san}${C_RESET}" >&2
      # ECDSA P-256, valid 825 days (the longest Apple platforms accept).
      # umask 077: the private key is never readable by anyone else, not even briefly.
      if ! ( umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
          -keyout "${tls_key}.new" -out "${tls_cert}.new" -days 825 \
          -subj "/CN=SD-WebUI-Forge-Neo-Unraid" \
          -addext "subjectAltName=${tls_san}" \
          -addext "basicConstraints=critical,CA:FALSE" \
          -addext "keyUsage=critical,digitalSignature" \
          -addext "extendedKeyUsage=serverAuth" ) >/dev/null 2>&1; then
        echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} Could not create the HTTPS certificate in ${TLS_DIR}. Set WEBUI_TLS=off to start without HTTPS.${C_RESET}" >&2
        rm -f "${tls_key}.new" "${tls_cert}.new"
        exit 1
      fi
      mv -f "${tls_key}.new" "${tls_key}"
      mv -f "${tls_cert}.new" "${tls_cert}"
      printf '%s' "${tls_san}" > "${TLS_DIR}/selfsigned.san"
    fi
    echo "${C_INFO}HTTPS enabled with a self-signed certificate. Your browser will warn once; compare this fingerprint before accepting:${C_RESET}" >&2
  fi
  echo "${C_ACCENT}  SHA-256 fingerprint: $(_tls_fingerprint "${tls_cert}")${C_RESET}" >&2

  # Trust bundle: the normal public CAs plus this certificate, so verification
  # can stay on. SSL_CERT_FILE replaces the default list, hence the public CAs.
  tls_bundle="${RUNTIME_WEBUI_TMP_DIR}/tls-trust-bundle.pem"
  certifi_bundle="$("${PYTHON_BIN}" -c 'import certifi; print(certifi.where())' 2>/dev/null || true)"
  if [[ -n "${certifi_bundle}" && -f "${certifi_bundle}" ]]; then
    cat "${certifi_bundle}" "${tls_cert}" > "${tls_bundle}"
    export SSL_CERT_FILE="${tls_bundle}"
  else
    echo "${C_WARN}[WARNING] Could not find the public CA bundle (certifi); the WebUI's startup self-check may fail.${C_RESET}" >&2
  fi

  TLS_ARGS+=("--tls-keyfile" "${tls_key}" "--tls-certfile" "${tls_cert}")
  TLS_SCHEME="https"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Startup output helpers
# ─────────────────────────────────────────────────────────────────────────────

# print_launch_notice: print a friendly pre-launch summary so users know what
# to expect before WebUI output starts scrolling. Covers first-run scenarios,
# missing models, and a table of known harmless warnings.
print_launch_notice() {
  local model_count=0
  if [[ -d "/data/models/Stable-diffusion" ]]; then
    model_count="$(find /data/models/Stable-diffusion \( -name '*.safetensors' -o -name '*.ckpt' \) 2>/dev/null | wc -l | tr -d ' ')"
  fi

  local ACCENT="${C_ACCENT}" INFO="${C_INFO}" WARN="${C_WARN}" RESET="${C_RESET}"

  echo ""
  # Versions come from the image (Dockerfile ENV). The Unraid Docker page does
  # not show the image tag, so this is the quickest place to check them.
  # ASCII only inside the padded lines: printf pads by bytes, not characters.
  echo "${ACCENT}╭─────────────────────────────────────────────────────────────────────╮"
  printf '│  %-67s│\n' "SD-WebUI-Forge-Neo-Unraid ${IMAGE_VERSION:-unknown}"
  printf '│  %-67s│\n' "Forge Neo ${WEBUI_TAG:-unknown} by Haoming02"
  printf '│  %-67s│\n' "Packaged for Unraid by Aegisnir"
  printf '│  %-67s│\n' "Upstream: github.com/Haoming02/sd-webui-forge-classic/tree/neo"
  echo "╰─────────────────────────────────────────────────────────────────────╯${RESET}"
  echo ""

  if [[ "${model_count}" -eq 0 ]]; then
    echo "  ${WARN}⚠  No model checkpoints found in /data/models/Stable-diffusion/"
    echo "     The WebUI will still start, but cannot generate images until you add a model."
    echo "     Fix: add a .safetensors or .ckpt file to:"
    echo "            /data/models/Stable-diffusion/"
    echo "          then restart the container or use Settings → Refresh in the UI.${RESET}"
  else
    echo "  ${INFO}✓  Found ${model_count} checkpoint(s) in /data/models/Stable-diffusion/${RESET}"
  fi

  echo ""
  echo "  ${ACCENT}Known harmless messages you may see in the log below:${RESET}"
  echo "  ${ACCENT}▸ 'FutureWarning: Importing from timm.models.layers'${RESET}"
  echo "    ${INFO}→ Upstream library deprecation notice. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ 'UserWarning: TypedStorage is deprecated'${RESET}"
  echo "    ${INFO}→ Internal PyTorch notice. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ 'FutureWarning: resume_download is deprecated'${RESET}"
  echo "    ${INFO}→ huggingface_hub deprecation notice during model or extension loading. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ '[ERROR]: Config states .../civitai_subfolders.json, \"created_at\" does not exist'${RESET}"
  echo "    ${INFO}→ CivitAI Shortcut extension schema notice. Safe to ignore.${RESET}"
  echo "  ${ACCENT}▸ 'CivitAI Browser+: Basemodel fetch error'${RESET}"
  echo "    ${INFO}→ CivitAI network API call failed at startup. Safe to ignore; retried on demand.${RESET}"
  echo "  ${ACCENT}▸ 'Stable diffusion model failed to load' (only when no checkpoint exists)${RESET}"
  echo "    ${WARN}→ Expected until a model is placed in /data/models/Stable-diffusion/.${RESET}"
  echo "  ${ACCENT}▸ 'ERROR: Exception in ASGI application' with 'WebSocketDisconnect: 1001'${RESET}"
  echo "    ${INFO}→ Browser dropped its WebSocket when the server shut down (Restart / stop).${RESET}"
  echo "    ${INFO}  Code 1001 = 'Going Away' -- the normal browser close. Not a real error.${RESET}"
  echo ""
  echo "  ${INFO}Inline notes marked [NOTE] or [KNOWN WARNING] are added by this container${RESET}"
  echo "  ${INFO}and are not part of the upstream WebUI output.${RESET}"
  echo ""
  echo "${ACCENT}─────────────────────────────────────────────────────────────────────────${RESET}"
  echo ""
  echo "  ${WARN}╭─ [STARTING UP] ─────────────────────────────────────────────────────╮"
  echo "  │  There may be a pause of several minutes while Python initialises,  │"
  echo "  │  extensions load, and the model is read into VRAM.                  │"
  echo "  │  Time varies by system. The [READY] banner appears when live.       │"
  echo "  ╰─────────────────────────────────────────────────────────────────────╯${RESET}"
  echo ""
}

# monitor_webui_output: pass all WebUI stdout/stderr through unchanged, and
# emit inline notes after recognised noisy lines so users are not alarmed.
# Runs in a subshell reading from the WebUI output pipe.
monitor_webui_output() {
  local _saw_timm=0 _saw_storage=0

  while IFS= read -r line; do
    printf '%s\n' "${line}"

    # timm FutureWarning -- appears on every start, always harmless
    if [[ $_saw_timm -eq 0 && "${line}" == *"Importing from timm.models.layers is deprecated"* ]]; then
      _saw_timm=1
      echo "  ${C_INFO}[NOTE] ↑ Harmless upstream deprecation warning from the timm library. Safe to ignore.${C_RESET}"
    fi

    # PyTorch TypedStorage deprecation -- common internal notice, harmless
    if [[ $_saw_storage -eq 0 && "${line}" == *"TypedStorage is deprecated"* ]]; then
      _saw_storage=1
      echo "  ${C_INFO}[NOTE] ↑ Harmless internal PyTorch deprecation notice. Safe to ignore.${C_RESET}"
    fi

    # CivitAI Shortcut 'created_at' schema notice -- shows as [ERROR] but is harmless
    if [[ "${line}" == *"Config states"* && "${line}" == *'"created_at" does not exist'* ]]; then
      echo "  ${C_INFO}[NOTE] ↑ CivitAI Shortcut extension schema notice. Safe to ignore.${C_RESET}"
    fi

    # Uvicorn WebSocket disconnect on graceful shutdown (Restart button / container stop).
    # The browser drops its WebSocket connection while the server is shutting down.
    # Uvicorn logs this as "Exception in ASGI application" with WebSocketDisconnect: 1001.
    # 1001 = "Going Away" -- the normal browser-initiated close code. Not a real error.
    if [[ "${line}" == *"Exception in ASGI application"* ]]; then
      echo "  ${C_INFO}[NOTE] ↑ Browser WebSocket disconnected during shutdown (code 1001 = normal 'Going Away'). Safe to ignore.${C_RESET}"
    fi

    # CUDA out of memory -- actionable GPU issue
    # Match both "CUDA out of memory" and "OutOfMemoryError: CUDA out of memory"
    if [[ "${line}" == *"CUDA out of memory"* || "${line}" == *"OutOfMemoryError"* ]]; then
      echo ""
      echo "  ${C_CRIT}╭─ [GPU MEMORY ERROR] ────────────────────────────────────────────────╮"
      echo "  │  Your GPU ran out of VRAM during this operation.                    │"
      echo "  │                                                                     │"
      echo "  │  Quick fix (add as container env var, then restart):                │"
      echo "  │    PYTORCH_ALLOC_CONF = expandable_segments:True                   │"
      echo "  │    Reduces fragmentation; often resolves marginal OOM.              │"
      echo "  │                                                                     │"
      echo "  │  Other tips:                                                        │"
      echo "  │    • Disable Hires. fix or reduce its scale (biggest VRAM saver)    │"
      echo "  │    • Reduce image resolution or batch size                          │"
      echo "  │    • Add --lowvram to COMMANDLINE_ARGS (slower, uses less VRAM)     │"
      echo "  ╰─────────────────────────────────────────────────────────────────────╯${C_RESET}"
      echo ""
    fi

    # GPU not visible to PyTorch -- likely missing --runtime=nvidia or NVIDIA plugin issue
    if [[ "${line}" == *"PyTorch is not able to access any compute device"* || "${line}" == *"torch.cuda.is_available() = False"* ]]; then
      echo ""
      echo "  ${C_CRIT}╭─ [GPU NOT DETECTED] ────────────────────────────────────────────────╮"
      echo "  │  PyTorch cannot see a CUDA-capable GPU.                             │"
      echo "  │  Check:                                                             │"
      echo "  │    • --runtime=nvidia is present in Extra Parameters in the template│"
      echo "  │    • The Unraid NVIDIA plugin is installed and working              │"
      echo "  │    • Run on the host to verify:                                     │"
      echo "  │        docker run --rm --runtime=nvidia ubuntu nvidia-smi           │"
      echo "  ╰─────────────────────────────────────────────────────────────────────╯${C_RESET}"
      echo ""
    fi

  done
}

# _poll_for_ready: independent background poller that prints the READY banner
# once the WebUI port is confirmed accepting TCP connections.
# Runs completely outside the log monitor so it is not affected by log content
# or Gradio version changes. Uses bash's built-in /dev/tcp -- no external tools.
_poll_for_ready() {
  local _port="7860"
  # Extract --port value from COMMANDLINE_ARGS if the user overrode the default.
  # Handles both space-separated (--port 7861) and equals-separated (--port=7861) forms.
  if [[ "${COMMANDLINE_ARGS:-}" =~ --port[[:space:]]+([0-9]+) ]]; then
    _port="${BASH_REMATCH[1]}"
  elif [[ "${COMMANDLINE_ARGS:-}" =~ --port=([0-9]+) ]]; then
    _port="${BASH_REMATCH[1]}"
  fi

  # Determine the URL host -- checked in order:
  #   1. WEBUI_HOST_IP env var (explicit override; required in bridge/NAT mode)
  #   2. Container's own outbound IP if it is a real LAN address
  #      (macvlan / Unraid br0 / --network=host -- container IP is directly reachable)
  #   3. Placeholder with hint to set WEBUI_HOST_IP
  local _host_ip=""
  if [[ -n "${WEBUI_HOST_IP:-}" ]]; then
    _host_ip="${WEBUI_HOST_IP}"
  else
    # Python3 is always available (it runs the WebUI). The UDP connect() resolves the
    # source address without actually sending any data to 8.8.8.8.
    local _own_ip
    _own_ip="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("8.8.8.8",80)); print(s.getsockname()[0]); s.close()' 2>/dev/null || true)"
    # Docker allocates bridge subnets from 172.16.0.0/12 (172.16–172.31.x.x).
    # If the container's IP is outside that range it has a real LAN address and
    # IS directly reachable by browsers -- use it.  In bridge/NAT mode the container
    # only sees a 172.x.x.x address; the host's real LAN IP is not discoverable
    # from inside the container without WEBUI_HOST_IP being set.
    if [[ -n "${_own_ip}" && ! "${_own_ip}" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
      _host_ip="${_own_ip}"
    fi
  fi

  local _timeout=600   # Give up after 10 min (matches HEALTHCHECK start-period)
  local _interval=5    # Poll every 5 s
  local _elapsed=0

  while [[ $_elapsed -lt $_timeout ]]; do
    sleep "${_interval}"
    _elapsed=$(( _elapsed + _interval ))
    # /dev/tcp is a bash built-in -- opens a TCP connection without any external binary
    # shellcheck disable=SC2188
    if (: < /dev/tcp/127.0.0.1/"${_port}") 2>/dev/null; then
      local _url
      if [[ -n "${_host_ip}" ]]; then
        _url="${TLS_SCHEME}://${_host_ip}:${_port}/"
      else
        _url="${TLS_SCHEME}://<your-unraid-ip>:${_port}/"
      fi
      echo ""
      echo "  ${C_ACCENT}${C_BOLD}╭─ [READY] ───────────────────────────────────────────────────────────╮"
      echo "  │  WebUI is LIVE -- open it in your browser:                           │"
      printf  "  │  %-67s│\n" "${_url}"
      echo "  ╰─────────────────────────────────────────────────────────────────────╯${C_RESET}"
      echo ""
      return 0
    fi
  done
  # Timed out without confirming -- silently give up (HEALTHCHECK will flag unhealthy)
}

# is_truthy: Accepts common boolean-like env var values (1, true, yes, on)
# and returns 0 (success); anything else returns 1 (failure).
is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Build final COMMANDLINE_ARGS with auth and TLS flags appended, then launch.
#
# Note: --api-auth credentials are appended here as a plain string because
# The WebUI has no file-based equivalent for API auth. This means credentials
# are visible via docker inspect / /proc/<pid>/environ. See README for
# the full discussion and mitigation options.
# ─────────────────────────────────────────────────────────────────────────────
if [[ $(( ${#AUTH_ARGS[@]} + ${#TLS_ARGS[@]} )) -gt 0 ]]; then
  quoted_auth_args=()
  for arg in "${AUTH_ARGS[@]}" "${TLS_ARGS[@]}"; do
    quoted_auth_args+=("$(python3 -c "import shlex,sys; print(shlex.quote(sys.argv[1]))" "${arg}")")
  done
  export COMMANDLINE_ARGS="${COMMANDLINE_ARGS:-} ${quoted_auth_args[*]}"
fi

if [[ -n "${COMMANDLINE_ARGS:-}" ]]; then
  echo "${C_ACCENT}Starting WebUI (COMMANDLINE_ARGS set).${C_RESET}"
else
  echo "${C_ACCENT}Starting WebUI (no COMMANDLINE_ARGS provided).${C_RESET}"
fi

# ── Launch with output monitoring and automatic restart ─────────────────────
#
# Architecture: named-pipe pattern
#   WebUI (stdout+stderr) → named pipe → monitor_webui_output → user terminal
#
#   This lets us inject inline [NOTE] / [KNOWN WARNING] annotations after
#   recognised log lines without buffering or modifying the WebUI process.
#
# Restart policy:
#   RESTART_ON_EXIT=1 (default): restart the WebUI after any exit -- whether
#     the user clicked Restart in the WebUI, or the process crashed.
#     A deliberate container stop (docker stop / Unraid Stop) sends SIGTERM,
#     which sets _DELIBERATE_STOP=1 and suppresses the restart so the
#     container exits cleanly without Unraid needing to SIGKILL it.
#
#   Exit code 78 (EXIT_CONFIG): WebUI/launch.py found settings that need a
#     human (config.json from an older WebUI version). Restarting cannot fix
#     that, so the container exits and the log explains what to do.
#
#   Crash backoff: after a non-zero exit the delay doubles each attempt
#     (RESTART_DELAY → RESTART_DELAY*2 → ...) up to RESTART_DELAY_MAX, so a
#     persistent crash loop does not hammer the system.  A clean exit (exit 0,
#     e.g. the Restart button) always uses the flat RESTART_DELAY.
#
# Note on the Restart button:
#   Neo's restart writes tmp/restart and exits with code 0 (only when
#   SD_WEBUI_RESTART is set, which this script exports). The loop below then
#   starts it again. Neo removes the tmp/restart marker on the next start.
#
_MONITOR_DIR=""
_LOG_PIPE=""
_WEBUI_PID=""
_POLLER_PID=""
_DELIBERATE_STOP=0   # set to 1 when SIGTERM/INT is received from Docker/Unraid

# shellcheck disable=SC2317 # These are invoked by trap, not direct calls.
_cleanup_monitor() {
  if [[ -n "${_POLLER_PID}" ]]; then kill "${_POLLER_PID}" 2>/dev/null || true; fi
  _POLLER_PID=""
  if [[ -n "${_MONITOR_DIR:-}" && -d "${_MONITOR_DIR}" ]]; then rm -rf "${_MONITOR_DIR}" || true; fi
  _MONITOR_DIR=""
  _LOG_PIPE=""
}
# shellcheck disable=SC2317
_forward_signal() {
  _DELIBERATE_STOP=1
  if [[ -n "${_WEBUI_PID}" ]]; then
    kill -TERM "${_WEBUI_PID}" 2>/dev/null || true
    ( sleep 15; kill -KILL "${_WEBUI_PID}" 2>/dev/null ) &
  fi
}

trap '_cleanup_monitor' EXIT
trap '_forward_signal' TERM INT

_RESTART_ATTEMPT=0
_CRASH_DELAY="${RESTART_DELAY}"
_WEBUI_EXIT_FINAL=0

while true; do
  _MONITOR_DIR="$(mktemp -d /tmp/webui-monitor.XXXXXX)"
  _LOG_PIPE="${_MONITOR_DIR}/webui.log.pipe"
  mkfifo "${_LOG_PIPE}"

  if [[ "${_RESTART_ATTEMPT}" -gt 0 ]]; then
    echo "" >&2
    _attempt_suffix=""
    [[ "${RESTART_MAX_ATTEMPTS}" -gt 0 ]] && _attempt_suffix=" of ${RESTART_MAX_ATTEMPTS}"
    echo "${C_WARN}${C_BOLD}── Restarting WebUI (attempt ${_RESTART_ATTEMPT}${_attempt_suffix}) ──────────────────────────${C_RESET}" >&2
    echo "" >&2
  else
    print_launch_notice
  fi

  # Start the output monitor first -- the reader must open the pipe before the
  # writer, otherwise the writer blocks indefinitely waiting for a reader.
  monitor_webui_output < "${_LOG_PIPE}" &
  _MONITOR_PID=$!

  # Launch the WebUI. Both stdout and stderr go through the pipe so
  # monitor_webui_output sees all output (Python warnings go to stderr).
  "${PYTHON_BIN}" launch.py > "${_LOG_PIPE}" 2>&1 &
  _WEBUI_PID=$!

  # Start the background poller -- runs independently, prints READY banner when
  # port is confirmed live. Killed between restarts via _cleanup_monitor.
  _poll_for_ready &
  _POLLER_PID=$!

  # Wait for the WebUI to exit and capture its exit code.
  _WEBUI_EXIT=0
  wait "${_WEBUI_PID}" || _WEBUI_EXIT=$?

  # Kill the poller and tear down the named pipe before the next iteration.
  _cleanup_monitor

  # Let the monitor drain any remaining buffered output before we restart.
  wait "${_MONITOR_PID}" 2>/dev/null || true

  _WEBUI_EXIT_FINAL="${_WEBUI_EXIT}"

  # ── Restart decision ───────────────────────────────────────────────────────
  # 1. Deliberate stop -- docker stop, Unraid Stop button, etc.
  if [[ "${_DELIBERATE_STOP}" == "1" ]]; then
    echo "${C_INFO}Container stop signal received. Exiting cleanly.${C_RESET}" >&2
    _WEBUI_EXIT_FINAL=0
    break
  fi

  # 2. Settings need a human -- restarting will not help.
  if [[ "${_WEBUI_EXIT}" -eq "${EXIT_CONFIG}" ]]; then
    echo "${C_CRIT}WebUI stopped because its settings need attention (see the message above). Container exiting.${C_RESET}" >&2
    _WEBUI_EXIT_FINAL=1
    break
  fi

  # 3. Restart policy disabled via env var.
  if ! is_truthy "${RESTART_ON_EXIT}"; then
    if [[ "${_WEBUI_EXIT}" -eq 0 ]]; then
      echo "${C_INFO}WebUI exited cleanly. RESTART_ON_EXIT is off -- container exiting.${C_RESET}" >&2
    else
      echo "${C_CRIT}WebUI exited with code ${_WEBUI_EXIT}. RESTART_ON_EXIT is off -- container exiting.${C_RESET}" >&2
    fi
    break
  fi

  # 4. Max restart attempts exceeded.
  _RESTART_ATTEMPT=$(( _RESTART_ATTEMPT + 1 ))
  if [[ "${RESTART_MAX_ATTEMPTS}" -gt 0 && "${_RESTART_ATTEMPT}" -gt "${RESTART_MAX_ATTEMPTS}" ]]; then
    echo "${C_CRIT}${C_BOLD}ERROR:${C_RESET}${C_CRIT} WebUI has restarted ${RESTART_MAX_ATTEMPTS} time(s) and keeps exiting. Giving up.${C_RESET}" >&2
    _WEBUI_EXIT_FINAL=1
    break
  fi

  # 5. Choose restart delay and print reason.
  if [[ "${_WEBUI_EXIT}" -eq 0 ]]; then
    # Clean exit (Restart button, "Apply and restart") -- flat delay, reset crash backoff and attempt counter.
    _delay="${RESTART_DELAY}"
    _CRASH_DELAY="${RESTART_DELAY}"
    _RESTART_ATTEMPT=0
    echo "${C_WARN}WebUI exited cleanly (Restart requested?). Restarting in ${_delay}s...${C_RESET}" >&2
  else
    # Crash or unexpected exit -- exponential backoff.
    _delay="${_CRASH_DELAY}"
    _next=$(( _CRASH_DELAY * 2 ))
    if [[ "${_next}" -gt "${RESTART_DELAY_MAX}" ]]; then
      _CRASH_DELAY="${RESTART_DELAY_MAX}"
    else
      _CRASH_DELAY="${_next}"
    fi
    echo "${C_CRIT}WebUI crashed or exited unexpectedly (code ${_WEBUI_EXIT}). Restarting in ${_delay}s...${C_RESET}" >&2
  fi

  sleep "${_delay}"
done

exit "${_WEBUI_EXIT_FINAL}"
