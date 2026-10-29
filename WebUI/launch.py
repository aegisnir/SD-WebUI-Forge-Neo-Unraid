"""
launch.py -- Custom wrapper for Forge Neo's launch.py.

This file replaces the upstream launch.py inside the Docker image. It mirrors
upstream's main() step for step, with three container-specific changes:

  1. Log redaction: sensitive CLI arguments (auth credentials and auth file
     paths) are never printed in plain text to the container log.
  2. No interactive prompt: upstream's verify_version() calls input() when
     config.json comes from an older WebUI version. A container has no
     keyboard, so that would hang or crash. This wrapper backs up the old
     settings files, starts fresh and logs what it did. Only if that fails
     does it exit with EXIT_CONFIG, which start.sh treats as fatal instead
     of restarting in a loop.
  3. Login protection: Gradio's login has no limit on attempts. Before the
     WebUI starts, Gradio's launch() is wrapped so the username/password list
     Forge Neo passes becomes a checker that locks a username after repeated
     failures (_throttled_auth). Forge Neo's own files are not changed.

How it works:
  - Re-exports the same names as upstream launch.py at module level, so other
    modules and extensions that do `import launch; launch.run_pip(...)`
    continue to work normally.
  - main() follows upstream's order: sysinfo dump, version check, environment
    preparation, model-path references, then start().

If you need to add new sensitive flags in the future, add them to the
`sensitive_flags` set in _redact_cli_args().
"""

import json
import os
import shlex
import sys
import time

from modules import launch_utils

# Same names upstream launch.py exports. Extensions call these via `import launch`.
args = launch_utils.args
python = launch_utils.python
git = launch_utils.git
index_url = launch_utils.index_url
dir_repos = launch_utils.dir_repos

git_tag = launch_utils.git_tag

run = launch_utils.run
is_installed = launch_utils.is_installed
repo_dir = launch_utils.repo_dir

run_pip = launch_utils.run_pip
check_run_python = launch_utils.check_run_python
git_clone = launch_utils.git_clone
git_pull_recursive = launch_utils.git_pull_recursive
list_extensions = launch_utils.list_extensions
run_extension_installer = launch_utils.run_extension_installer
prepare_environment = launch_utils.prepare_environment

# Exit code for "configuration needs a human". start.sh does not restart on it.
# 78 is EX_CONFIG from BSD sysexits.h.
EXIT_CONFIG = 78


def _redact_cli_args(argv):
    """Return a copy of *argv* with sensitive flag values replaced by '<redacted>'.

    Handles both space-separated (--flag value) and equals-separated (--flag=value)
    forms. The flag name is always preserved so the user can see which auth
    mechanisms are active; only the secret value is hidden.

    To protect a new flag, add it to the sensitive_flags set below.
    """
    redacted = []
    sensitive_flags = {"--gradio-auth", "--gradio-auth-path", "--api-auth", "--ngrok"}
    i = 0

    while i < len(argv):
        arg = argv[i]
        # Check if this arg matches any sensitive flag (exact or --flag=value form).
        matched_flag = next((flag for flag in sensitive_flags if arg == flag or arg.startswith(flag + "=")), None)
        if matched_flag is None:
            # Not sensitive -- pass through unchanged.
            redacted.append(arg)
            i += 1
            continue

        if arg == matched_flag:
            # Space-separated form: "--gradio-auth mysecret"
            # Keep the flag name, replace the next token (the value) with <redacted>.
            redacted.extend([arg, "<redacted>"])
            i += 2  # skip over the value token
        else:
            # Equals-separated form: "--gradio-auth=mysecret"
            # Replace everything after the '=' with <redacted>.
            redacted.append(f"{matched_flag}=<redacted>")
            i += 1

    return redacted


def verify_version():
    """Non-interactive replacement for launch_utils.verify_version().

    Same checks as upstream: a missing config.json is created with the current
    VERSION_UID, a matching one passes. Upstream asks for a clean settings
    reset when config.json comes from an older WebUI version and waits for
    Enter. Here the old config.json and ui-config.json are moved to dated
    backups instead (nothing is deleted), a fresh config.json is written, and
    the log says what happened. If the move fails, startup stops with
    EXIT_CONFIG and instructions.
    """
    settings_file = args.ui_settings_file
    expected = launch_utils.VERSION_UID

    if not os.path.isfile(settings_file):
        # Fresh install: same as upstream.
        with open(settings_file, "w", encoding="utf8") as file:
            json.dump({"VERSION_UID": expected}, file)
        return

    with open(settings_file, "r", encoding="utf8") as file:
        settings = json.load(file)

    if settings.get("VERSION_UID", None) == expected:
        return

    # realpath: on this container these are symlinks into /config/webui, and
    # the files themselves must move, not the links.
    stamp = time.strftime("%Y%m%d-%H%M%S")
    moved = []
    try:
        for path in (settings_file, args.ui_config_file):
            real = os.path.realpath(path)
            if os.path.isfile(real):
                backup = f"{real}.pre-neo-{stamp}.bak"
                os.replace(real, backup)
                moved.append(backup)
        with open(settings_file, "w", encoding="utf8") as file:
            json.dump({"VERSION_UID": expected}, file)
    except OSError as exc:
        settings_dir = os.path.dirname(os.path.realpath(settings_file))
        print("", file=sys.stderr)
        print("=" * 72, file=sys.stderr)
        print("STOPPED: config.json is from an older WebUI version, and moving it", file=sys.stderr)
        print(f"aside failed ({exc.__class__.__name__}: {exc}).", file=sys.stderr)
        print(f"Fix: move config.json and ui-config.json out of {settings_dir}", file=sys.stderr)
        print("     (on Unraid: the container's appdata folder, under webui/),", file=sys.stderr)
        print("     then restart the container. Models and outputs are not affected.", file=sys.stderr)
        print("=" * 72, file=sys.stderr)
        sys.exit(EXIT_CONFIG)

    print("", file=sys.stderr)
    print("=" * 72, file=sys.stderr)
    print("NOTICE: config.json was from an older WebUI version (for example", file=sys.stderr)
    print("AUTOMATIC1111). Forge Neo needs fresh settings, so the old files were", file=sys.stderr)
    print("kept as backups and the WebUI starts with default settings:", file=sys.stderr)
    for backup in moved:
        print(f"  {backup}", file=sys.stderr)
    print("Re-apply any settings you want in the Settings tab.", file=sys.stderr)
    print("Models, outputs and extensions are not affected.", file=sys.stderr)
    print("=" * 72, file=sys.stderr)
    print("", file=sys.stderr)


def _throttled_auth(creds, max_attempts, lockout_seconds):
    """Return a Gradio auth callable that checks *creds* and slows down guessing.

    Gradio's built-in login has no limit on attempts. This wraps the same
    (username, password) list Forge Neo would hand to Gradio:
      - every failed attempt waits FAIL_DELAY seconds before answering
      - after *max_attempts* failures within *lockout_seconds* for one
        username, that username is locked for *lockout_seconds*; even the
        right password is refused while locked
      - a successful login clears that username's failures
    State lives in memory only, so restarting the container clears every
    lockout. Usernames are tracked whether or not they exist, so attempts
    do not reveal which usernames are real. Passwords are never logged.
    """
    import hmac
    import threading

    FAIL_DELAY = 1.0      # seconds; short, because each waiting attempt holds a server thread
    MAX_TRACKED = 1000    # cap memory if someone sprays random usernames

    lock = threading.Lock()
    failures = {}         # username -> list of failure timestamps
    locked_until = {}     # username -> unlock time

    def _matches(username, password):
        ok = False
        for user, pw in creds:
            # Compare every entry, in constant time, so timing reveals nothing.
            ok |= hmac.compare_digest(user.encode(), username.encode()) & hmac.compare_digest(pw.encode(), password.encode())
        return ok

    def _label(username):
        return repr(username[:64])

    def auth(username, password):
        now = time.monotonic()
        with lock:
            until = locked_until.get(username, 0)
            if until > now:
                print(f"[login] Refused {_label(username)}: locked for {int(until - now)} more seconds.", file=sys.stderr)
                return False
        if _matches(username, password):
            with lock:
                failures.pop(username, None)
                locked_until.pop(username, None)
            return True
        with lock:
            if username not in failures and len(failures) >= MAX_TRACKED:
                failures.pop(next(iter(failures)))
            recent = [t for t in failures.get(username, []) if now - t < lockout_seconds] + [now]
            failures[username] = recent
            if len(recent) >= max_attempts:
                locked_until[username] = now + lockout_seconds
                failures.pop(username, None)
                print(f"[login] {_label(username)} LOCKED for {lockout_seconds // 60} minutes after {len(recent)} failed attempts. "
                      "Restart the container to clear it.", file=sys.stderr)
            else:
                print(f"[login] Failed login for {_label(username)} ({len(recent)}/{max_attempts}).", file=sys.stderr)
        time.sleep(FAIL_DELAY)
        return False

    return auth


def _install_login_throttle():
    """Wrap Gradio's launch() so the login list Neo passes becomes _throttled_auth.

    Only touches a plain list of (username, password) pairs, which is what
    Forge Neo passes (webui.py, auth=gradio_auth_creds). Anything else, or
    WEBUI_LOGIN_MAX_ATTEMPTS=0, leaves Gradio's behaviour unchanged.
    """
    try:
        max_attempts = int(os.environ.get("WEBUI_LOGIN_MAX_ATTEMPTS", "5"))
        lockout_minutes = int(os.environ.get("WEBUI_LOGIN_LOCKOUT_MINUTES", "15"))
    except ValueError:
        print("[login] WEBUI_LOGIN_MAX_ATTEMPTS / WEBUI_LOGIN_LOCKOUT_MINUTES must be whole numbers.", file=sys.stderr)
        sys.exit(EXIT_CONFIG)
    if max_attempts <= 0:
        print("[login] Login throttling is OFF (WEBUI_LOGIN_MAX_ATTEMPTS=0).", file=sys.stderr)
        return
    lockout_minutes = max(lockout_minutes, 1)

    import gradio as gr

    original_launch = gr.Blocks.launch

    def launch(self, *a, **kw):
        creds = kw.get("auth")
        if isinstance(creds, (list, tuple)) and creds and all(isinstance(c, (list, tuple)) and len(c) == 2 for c in creds):
            kw["auth"] = _throttled_auth([(str(u), str(p)) for u, p in creds], max_attempts, lockout_minutes * 60)
            print(f"[login] Login throttling on: {max_attempts} failed attempts locks a username for {lockout_minutes} minutes.", file=sys.stderr)
            # Gradio's login page can only say "Incorrect credentials", even when
            # the username is locked, so state the rule above the form.
            if not kw.get("auth_message"):
                kw["auth_message"] = (f"{max_attempts} failed logins lock that username for {lockout_minutes} minutes. "
                                      "Restarting the container clears it.")
        return original_launch(self, *a, **kw)

    gr.Blocks.launch = launch


def start():
    """Upstream launch_utils.start() with the launch line redacted."""
    mode = "API server" if "--nowebui" in sys.argv else "Web UI"
    # Print the launch line with sensitive values replaced by <redacted>.
    print(f"Launching {mode} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}")

    from modules import logging_config

    logging_config.setup_logging(args.loglevel)

    _install_login_throttle()

    # Import webui here (not at module level) because it depends on
    # prepare_environment() having already run.
    import webui

    if "--nowebui" in sys.argv:
        webui.api_only()  # headless API mode
    else:
        webui.webui()  # full Gradio web interface

    from modules_forge import main_thread

    main_thread.loop()


def main() -> None:
    if args.dump_sysinfo:
        filename = launch_utils.dump_sysinfo()
        print(f"Sysinfo saved as {filename}. Exiting...")
        sys.exit(0)

    verify_version()

    launch_utils.startup_timer.record("initial startup")

    with launch_utils.startup_timer.subcategory("prepare environment"):
        if not args.skip_prepare_environment:
            prepare_environment()

    if args.forge_ref_a1111_home:
        launch_utils.configure_a1111_reference(args.forge_ref_a1111_home)
    if args.forge_ref_comfy_home:
        launch_utils.configure_comfy_reference(args.forge_ref_comfy_home)
    if args.forge_ref_comfy_yaml:
        launch_utils.configure_comfy_yaml(args.forge_ref_comfy_yaml)

    # Anything that calls launch_utils.start() also gets the redacted version.
    launch_utils.start = start
    start()


if __name__ == "__main__":
    main()
