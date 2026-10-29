#!/usr/bin/env bash
#
# entrypoint.sh - Root-level container entry point.
#
# Purpose:
#   Run as root just long enough to self-heal /data ownership if needed, then
#   drop privileges and exec start.sh as the application user (sdwebui / UID 99).
#
# This is the standard "init as root, drop to unprivileged user" pattern used by
# many production container images (postgres, nginx, redis, etc.). The attack
# surface of this script is intentionally minimal: stat, chown, chmod, exec.
#
# The /data bind-mount can end up owned by root when:
#   - The host directory was deleted and Docker transparently recreated it.
#   - The Unraid share path changed or was remapped.
#   - The host directory was created by a root process outside Docker.
#
# In any of those cases this script corrects ownership automatically so the
# container can start without any manual intervention from the user.
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Color palette
# ─────────────────────────────────────────────────────────────────────────────
# C_INFO   (violet)  → informational / status messages
# C_WARN   (orange)  → caution / warnings that need attention but are not fatal
# C_CRIT   (scarlet) → critical errors requiring user action
# C_ACCENT (cyan)    → accent / highlights (URLs, commands, structural chrome)
# Colors are enabled by default because Docker/Unraid log viewers render ANSI.
# Set NO_COLOR=1 or TERM=dumb in the container environment to suppress them.
if [[ "${NO_COLOR:-}" == "" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\e[0m'
  C_ACCENT=$'\e[96m'; C_INFO=$'\e[95m'; C_WARN=$'\e[93m'; C_CRIT=$'\e[91m'
else
  C_RESET='' C_ACCENT='' C_INFO='' C_WARN='' C_CRIT=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
# EXPECTED_UID / EXPECTED_GID match the sdwebui user created in the Dockerfile.
# On Unraid, UID 99 (nobody) and GID 100 (users) are the conventional defaults.

DATA_DIR="/data"
EXPECTED_UID="${APP_UID:-99}"
EXPECTED_GID="${APP_GID:-100}"

if [[ "${EXPECTED_UID}" == "0" || "${EXPECTED_GID}" == "0" ]]; then
  echo "${C_CRIT}${C_BOLD}FATAL:${C_RESET}${C_CRIT} APP_UID/APP_GID must not be 0. Refusing to run as root.${C_RESET}" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic helpers
# ─────────────────────────────────────────────────────────────────────────────
# These functions provide actionable error messages when the container runtime
# blocks operations that this script needs (chown, chmod, setpriv). They read
# kernel-level security state from /proc/self/status so the user can see
# exactly what policy is preventing the operation.

print_runtime_diagnostics() {
  local no_new_privs="unknown"
  local seccomp_mode="unknown"
  local cap_eff="unknown"

  if [[ -r /proc/self/status ]]; then
    no_new_privs="$(awk '/^NoNewPrivs:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    seccomp_mode="$(awk '/^Seccomp:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    cap_eff="$(awk '/^CapEff:/ {print $2}' /proc/self/status 2>/dev/null || true)"
    no_new_privs="${no_new_privs:-unknown}"
    seccomp_mode="${seccomp_mode:-unknown}"
    cap_eff="${cap_eff:-unknown}"
  fi

  echo "${C_ACCENT}[entrypoint] Runtime diagnostics: uid=$(id -u) gid=$(id -g) NoNewPrivs=${no_new_privs} Seccomp=${seccomp_mode} CapEff=${cap_eff}${C_RESET}" >&2
  if [[ "${cap_eff}" == "0000000000000000" ]]; then
    echo "${C_WARN}[entrypoint] CapEff is zero (all capabilities dropped). Add required caps or remove --cap-drop=ALL.${C_RESET}" >&2
  else
    echo "${C_WARN}[entrypoint] Likely causes: rootless/userns remap, no-new-privileges policy, NFS root-squash, or share ACL/mount restrictions.${C_RESET}" >&2
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Error / warning handlers
# ─────────────────────────────────────────────────────────────────────────────

# warn_repair_blocked: Called when chown/chmod on /data fails. Instead of
# aborting, we continue into start.sh which has its own /data writability
# check and will print detailed remediation steps for the user.
warn_repair_blocked() {
  echo "${C_CRIT}[entrypoint] Automatic /data repair was blocked by the host filesystem or mount policy.${C_RESET}" >&2
  echo "${C_WARN}[entrypoint] Continuing startup so start.sh can print the final remediation steps.${C_RESET}" >&2
  print_runtime_diagnostics
}

# fatal_priv_drop_blocked: Called when setpriv cannot switch from root to the
# app user. This is unrecoverable -- we cannot run the WebUI as root -- so we
# print host-side fix instructions and exit.
fatal_priv_drop_blocked() {
  echo "${C_CRIT}[entrypoint] Cannot drop privileges to uid=${EXPECTED_UID}:gid=${EXPECTED_GID}.${C_RESET}" >&2
  echo "${C_CRIT}[entrypoint] This container runtime is blocking user/group switching (setuid/setgid).${C_RESET}" >&2
  print_runtime_diagnostics
  echo "" >&2
  echo "${C_WARN}[entrypoint] Host-side actions to resolve:${C_RESET}" >&2
  echo "${C_ACCENT}  1) Ensure the container is not forced into a mode that strips setuid/setgid transitions.${C_RESET}" >&2
  echo "${C_ACCENT}  2) Verify /data is writable by UID 99 on the host (adjust the path to match${C_RESET}" >&2
  echo "${C_ACCENT}     your Unraid container template -- check the /data bind-mount path):${C_RESET}" >&2
  echo "${C_ACCENT}       chown nobody:users <your-data-path>${C_RESET}" >&2
  echo "${C_ACCENT}       chmod 775 <your-data-path>${C_RESET}" >&2
  echo "${C_ACCENT}  3) Restart the container after applying the host fixes.${C_RESET}" >&2
  exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Privilege drop
# ─────────────────────────────────────────────────────────────────────────────

# exec_as_app_user: Drop from root to the unprivileged app user (sdwebui) and
# exec start.sh. Uses setpriv rather than su/sudo to avoid spawning an extra
# process -- exec replaces PID 1 so Docker signals reach start.sh directly.
exec_as_app_user() {
  # Probe first so we can print a clear remediation message rather than failing
  # with a terse setpriv error when the runtime forbids setuid/setgid operations.
  if ! setpriv --reuid="${EXPECTED_UID}" --regid="${EXPECTED_GID}" --clear-groups true >/dev/null 2>&1; then
    fatal_priv_drop_blocked
  fi
  exec setpriv --reuid="${EXPECTED_UID}" --regid="${EXPECTED_GID}" --clear-groups /start.sh
}

# ─────────────────────────────────────────────────────────────────────────────
# /data ownership & permission self-healing
# ─────────────────────────────────────────────────────────────────────────────
# This is the core logic of entrypoint.sh. It inspects the /data bind-mount
# and repairs ownership/permissions so the unprivileged app user can read and
# write to it. There are two repair scenarios:
#
#   1) Wrong owner  -- /data is owned by a different UID (e.g. root created it).
#                     We chown everything to uid 99:gid 100 and fix modes.
#
#   2) Right owner, wrong modes -- /data is owned by uid 99 but the permission
#                     bits are too restrictive (e.g. someone ran chmod 700 on
#                     the host). We restore mode 775 and fix child modes.
#
# If neither condition applies, /data is healthy and we skip straight to the
# privilege drop.

# Only attempt ownership/permission repair if we are running as root.
# If the container was started with --user 99:100 (skipping the root entrypoint
# pattern), we are already the app user and cannot chown/chmod anything.
# In that case, skip straight to exec-ing start.sh and let it validate /data.
if [[ "$(id -u)" == "0" ]] && [[ -d "${DATA_DIR}" ]]; then
  data_owner_uid="$(stat -c '%u' "${DATA_DIR}")"
  data_owner_gid="$(stat -c '%g' "${DATA_DIR}")"

  # ── Scenario 1: Wrong owner ──────────────────────────────────────────────
  if [[ "${data_owner_uid}" != "${EXPECTED_UID}" || "${data_owner_gid}" != "${EXPECTED_GID}" ]]; then
    echo "${C_WARN}[entrypoint] /data is owned by uid=${data_owner_uid}:gid=${data_owner_gid}, expected ${EXPECTED_UID}:${EXPECTED_GID}.${C_RESET}" >&2
    echo "${C_WARN}[entrypoint] Correcting ownership and permissions under /data...${C_RESET}" >&2

    # Fix ownership on top-level dir first so the app user can write immediately.
    if ! chown "${EXPECTED_UID}:${EXPECTED_GID}" "${DATA_DIR}"; then
      warn_repair_blocked
      exec_as_app_user
    fi
    if ! chmod 775 "${DATA_DIR}"; then
      warn_repair_blocked
      exec_as_app_user
    fi

    # Correct ownership on all children that ended up under wrong ownership.
    # find's filter (! -user) limits the walk to only misowned entries so this
    # is fast on a healthy volume and only slow on a truly broken one.
    _repair_errors="$(mktemp 2>/dev/null || echo /tmp/entrypoint-repair.err)"
    _repair_count="$(find "${DATA_DIR}" -not -type l \( ! -user "${EXPECTED_UID}" -o ! -group "${EXPECTED_GID}" \) 2>/dev/null | wc -l | tr -d ' ')"
    find "${DATA_DIR}" -not -type l \( ! -user "${EXPECTED_UID}" -o ! -group "${EXPECTED_GID}" \) -exec chown "${EXPECTED_UID}:${EXPECTED_GID}" {} + 2>"${_repair_errors}" || true
    if [[ -s "${_repair_errors}" ]]; then
      echo "${C_WARN}[entrypoint] Some files could not be repaired:${C_RESET}" >&2
      head -5 "${_repair_errors}" >&2
    fi
    rm -f "${_repair_errors}"

    # Restore sane permission modes after ownership repair.
    find "${DATA_DIR}" -type d ! -perm -u+rwx -exec chmod u+rwx {} + 2>/dev/null || true
    find "${DATA_DIR}" -type f ! -perm -u+r   -exec chmod u+r   {} + 2>/dev/null || true

    echo "${C_INFO}[entrypoint] Repaired ${_repair_count} files under /data. Continuing startup.${C_RESET}" >&2

  # ── Permission repair (idempotent) ────────────────────────────────────────
  # Runs unconditionally when ownership is already correct. Catches the case
  # where someone ran chmod 000/700 on the host. The previous conditional
  # ([[ ! -w || ! -x ]]) was dead code: root bypasses -w/-x via CAP_DAC_OVERRIDE.
  else
    chmod 775 "${DATA_DIR}" 2>/dev/null || true
    find "${DATA_DIR}" -type d ! -perm -u+rwx -exec chmod u+rwx {} + 2>/dev/null || true
    find "${DATA_DIR}" -type f ! -perm -u+r   -exec chmod u+r   {} + 2>/dev/null || true
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# /config ownership self-healing
# ─────────────────────────────────────────────────────────────────────────────
# /config holds auth files and state markers. It is a separate bind-mount from
# /data so it can live in appdata and be backed up independently.
# Apply the same simple ownership check as /data: if Docker created the host
# appdata directory as root, fix it now while we are still root.
if [[ "$(id -u)" == "0" ]] && [[ -d "/config" ]]; then
  config_owner_uid="$(stat -c '%u' /config)"
  if [[ "${config_owner_uid}" != "${EXPECTED_UID}" ]]; then
    echo "${C_WARN}[entrypoint] /config is owned by uid=${config_owner_uid}, expected uid=${EXPECTED_UID}.${C_RESET}" >&2
    echo "${C_WARN}[entrypoint] Correcting /config ownership...${C_RESET}" >&2
    if ! find /config -not -type l -exec chown "${EXPECTED_UID}:${EXPECTED_GID}" {} + 2>/dev/null; then
      echo "${C_WARN}[entrypoint] Could not fix /config ownership. Auth file seeding may fail.${C_RESET}" >&2
    else
      echo "${C_INFO}[entrypoint] /config ownership corrected.${C_RESET}" >&2
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Hand off to start.sh
# ─────────────────────────────────────────────────────────────────────────────
# Drop privileges and exec start.sh as the application user.
# Using exec preserves the PID so Docker signals (stop/kill) reach start.sh
# correctly -- there is no intermediate shell process to eat the signal.

if [[ "$(id -u)" == "0" ]]; then
  echo "${C_ACCENT}[entrypoint] /data is healthy. Dropping to unprivileged user (uid=${EXPECTED_UID}).${C_RESET}" >&2
  exec_as_app_user
else
  # Already running as the app user (e.g. container started with --user 99:100).
  # No privilege drop needed -- exec start.sh directly.
  echo "${C_ACCENT}[entrypoint] Already running as uid=$(id -u). Skipping privilege drop.${C_RESET}" >&2
  exec /start.sh
fi
