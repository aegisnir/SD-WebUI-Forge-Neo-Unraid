"""Build Forge Neo's launch flags from the Unraid template options.

start.sh runs this once per launch. It reads the NEO_* template options and
COMMANDLINE_ARGS (the template's "Extra Launch Flags"), and prints the final
flag string, shell-quoted, on stdout. Messages for the log go to stderr.

  1. Flags the container manages are always added: --listen --port 7860
     --data-dir /data.
  2. Each NEO_* option adds its flag. Defaults match Forge Neo (all off),
     except the three maintainer's choices noted in OPTIONS.
  3. Extra Launch Flags come last. Flags that an option controls, that the
     container manages, or that are not allowed in this container are
     removed, with a message naming what to use instead. Options always win.

An invalid option value exits with EXIT_CONFIG (78), which start.sh treats as
"needs a human" and does not restart.

Forge Neo's flags: modules/cmd_args.py, backend/args.py and
modules/paths_internal.py at the pinned release.
"""

import os
import re
import shlex
import sys

EXIT_CONFIG = 78

FIXED = ["--listen", "--port", "7860", "--data-dir", "/data"]

TRUE = {"true", "yes", "on", "1"}
FALSE = {"false", "no", "off", "0"}


def flag(name):
    """true/false option that adds one flag."""
    return ("bool", name)


def choice(mapping):
    """Dropdown option: value -> list of flags ("" or None adds nothing)."""
    return ("choice", mapping)


def value(name, kind):
    """Free-text option passed as --name VALUE after validation."""
    return ("value", name, kind)


def _precision(suffix, values):
    return {"auto": [], **{v: [f"--{v}-{suffix}"] for v in values}}


# (environment variable, template option name, kind, default)
OPTIONS = [
    # Maintainer's choice (Neo default: false). See README "Extensions".
    ("NEO_EXTENSION_ACCESS", "Install extensions from the WebUI", flag("--enable-insecure-extension-access"), "true"),
    ("NEO_API", "API", flag("--api"), "false"),
    ("NEO_API_ONLY", "API only", flag("--nowebui"), "false"),
    # Maintainer's choice (Neo default: false). Neo's own log recommends it on
    # RTX cards and skips it on cards that can't use it.
    ("NEO_CUDA_MALLOC", "CUDA malloc", flag("--cuda-malloc"), "true"),
    ("NEO_CUDA_STREAM", "CUDA streams", choice({"off": [], "2": ["--cuda-stream", "2"], "4": ["--cuda-stream", "4"]}), "off"),
    ("NEO_PIN_SHARED_MEMORY", "Pin shared memory", flag("--pin-shared-memory"), "false"),
    ("NEO_VRAM_MODE", "VRAM mode", choice({"normal": [], "gpu-only": ["--gpu-only"], "highvram": ["--highvram"],
                                           "lowvram": ["--lowvram"], "novram": ["--novram"]}), "normal"),
    ("NEO_ATTENTION_PACKAGE", "Attention package", choice({"none": [], "xformers": ["--xformers"], "sage": ["--sage"],
                                                           "flash": ["--flash"]}), "none"),
    ("NEO_THEME", "Theme", choice({"default": [], "dark": ["--theme", "dark"], "light": ["--theme", "light"]}), "default"),
    # Advanced
    ("NEO_API_LOG", "API request logging", flag("--api-log"), "false"),
    ("NEO_API_SERVER_STOP", "API server stop/restart", flag("--api-server-stop"), "false"),
    ("NEO_EXPANDABLE_SEGMENTS", "Expandable segments", flag("--expandable-segments"), "false"),
    ("NEO_FAST_FP8", "Fast fp8", flag("--fast-fp8"), "false"),
    ("NEO_FAST_FP16", "Fast fp16", flag("--fast-fp16"), "false"),
    ("NEO_AUTOTUNE", "Autotune", flag("--autotune"), "false"),
    ("NEO_CK_ATTENTION", "Comfy-Kitchen attention", flag("--use-ck-attention"), "false"),
    ("NEO_TRITON_BACKEND", "Triton backend", flag("--enable-triton-backend"), "false"),
    ("NEO_PYNVML", "pyNVML VRAM tracking", flag("--pynvml"), "false"),
    ("NEO_NUNCHAKU", "Nunchaku", flag("--nunchaku"), "false"),
    ("NEO_TILED_CONV2D", "Tiled Conv2d", choice({"0": [], **{v: ["--tiled-conv2d", v] for v in ("64", "128", "256", "512")}}), "0"),
    ("NEO_RESERVE_VRAM", "Reserve VRAM (GB)", value("--reserve-vram", "number"), ""),
    ("NEO_DISABLE_SMART_MEMORY", "Disable smart memory", flag("--disable-smart-memory"), "false"),
    ("NEO_FORCE_NON_BLOCKING", "Force non-blocking", flag("--force-non-blocking"), "false"),
    ("NEO_PRECISION", "Precision", choice({"auto": [], "fp32": ["--force-fp32"], "fp16": ["--force-fp16"]}), "auto"),
    ("NEO_UNET_PRECISION", "Diffusion model precision",
     choice(_precision("unet", ["fp32", "bf16", "fp16", "fp8_e4m3fn", "fp8_e5m2", "fp8_e8m0fnu"])), "auto"),
    ("NEO_VAE_PRECISION", "VAE precision", choice(_precision("vae", ["fp32", "bf16", "fp16"])), "auto"),
    ("NEO_TEXT_ENC_PRECISION", "Text encoder precision",
     choice(_precision("text-enc", ["fp32", "bf16", "fp16", "fp8_e4m3fn", "fp8_e5m2"])), "auto"),
    ("NEO_CPU_VAE", "VAE on CPU", flag("--cpu-vae"), "false"),
    ("NEO_CPU_TEXT_ENC", "Text encoder on CPU", flag("--cpu-text-enc"), "false"),
    ("NEO_DISABLE_SAGE", "Disable sage", flag("--disable-sage"), "false"),
    ("NEO_DISABLE_FLASH", "Disable flash", flag("--disable-flash"), "false"),
    ("NEO_DISABLE_XFORMERS", "Disable xformers", flag("--disable-xformers"), "false"),
    ("NEO_MODEL_REF", "Models folder override", value("--model-ref", "path"), ""),
    ("NEO_COMFY_MODELS", "ComfyUI models", value("--forge-ref-comfy-home", "path"), ""),
    ("NEO_A1111_MODELS", "A1111 models", value("--forge-ref-a1111-home", "path"), ""),
    ("NEO_FREEZE_SETTINGS", "Lock settings", flag("--freeze-settings"), "false"),
    ("NEO_HIDE_UI_DIR_CONFIG", "Hide folder settings", flag("--hide-ui-dir-config"), "false"),
    ("NEO_EXTENSIONS", "Extensions", choice({"enabled": [], "builtin-only": ["--disable-extra-extensions"],
                                             "disabled": ["--disable-all-extensions"]}), "enabled"),
    # Maintainer's choice (Neo default: false): keep extensions current.
    ("NEO_UPDATE_EXTENSIONS", "Update extensions on start", flag("--update-all-extensions"), "true"),
    ("NEO_SUBPATH", "Reverse-proxy subpath", value("--subpath", "subpath"), ""),
    ("NEO_NO_HASHING", "No checkpoint hashing", flag("--no-hashing"), "false"),
    ("NEO_LOGLEVEL", "Log level", choice({"default": [], **{v: ["--loglevel", v] for v in
                                                             ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")}}), "default"),
]

# Options that only work when API is on.
NEEDS_API = {"NEO_API_LOG", "NEO_API_SERVER_STOP"}

# Flags that take a value: 1 = always, "?" = optional (Neo's nargs="?").
TAKES_VALUE = {
    "--port": 1, "--data-dir": 1, "--ui-config-file": 1, "--ui-settings-file": 1,
    "--ngrok": 1, "--ngrok-options": 1, "--ngrok-region": 1, "--server-name": 1, "--directml": "?",
    "--cuda-stream": "?", "--theme": 1, "--tiled-conv2d": 1, "--reserve-vram": 1,
    "--model-ref": 1, "--forge-ref-comfy-home": 1, "--forge-ref-a1111-home": 1,
    "--subpath": 1, "--loglevel": 1,
}

MANAGED = {
    "--listen": "always set by the container",
    "--port": "always 7860 inside the container; change the WebUI port in the template instead",
    "--data-dir": "always /data; change the Data Directory path in the template instead",
    "--ui-config-file": "kept in appdata by the container",
    "--ui-settings-file": "kept in appdata by the container",
    "--reinstall-torch": "the image ships a pinned, scanned PyTorch",
    "--reinstall-xformers": "use the Attention package option",
    "--uv": "packages are baked into the image",
    "--uv-symlink": "packages are baked into the image",
    "--uv-local-cache": "packages are baked into the image",
    "--dump-sysinfo": "it writes a file and quits, which would loop",
}

NOT_ALLOWED = {
    "--share": "public internet tunnel; use a reverse proxy or a Cloudflare Tunnel instead",
    "--ngrok": "public internet tunnel; use a reverse proxy or a Cloudflare Tunnel instead",
    "--ngrok-options": "public internet tunnel; use a reverse proxy or a Cloudflare Tunnel instead",
    "--ngrok-region": "public internet tunnel (and Neo says it does nothing)",
    "--autolaunch": "there is no browser inside a container",
    "--server-name": "conflicts with --listen",
    "--directml": "this image is for NVIDIA GPUs",
    "--cpu": "this image is for NVIDIA GPUs",
    "--add-stop-route": "Neo says it does nothing",
    "--administrator": "undocumented; not supported here",
    "--no-download-sd-model": "not in Forge Neo (it never downloads a model on its own)",
    "--disable-safe-unpickle": "not in Forge Neo (it always loads checkpoints safely)",
    "--allow-code": "not in Forge Neo",
}


def _option_flags():
    """Every flag an option can produce -> the option that owns it."""
    owned = {}
    for env, label, kind, _ in OPTIONS:
        if kind[0] == "bool":
            owned[kind[1]] = (env, label)
        elif kind[0] == "choice":
            for flags in kind[1].values():
                for f in flags:
                    if f.startswith("--"):
                        owned[f] = (env, label)
        else:
            owned[kind[1]] = (env, label)
    return owned


class ConfigError(Exception):
    pass


def _resolve(env, label, kind, default, environ):
    raw = environ.get(env, "")
    raw = raw.strip() if raw.strip() else default
    if kind[0] == "bool":
        low = raw.lower()
        if low in TRUE:
            return [kind[1]], True
        if low in FALSE:
            return [], False
        raise ConfigError(f"{label} ({env}) must be true or false, not {raw!r}.")
    if kind[0] == "choice":
        for key, flags in kind[1].items():
            if raw.lower() == key.lower():
                return list(flags), bool(flags)
        raise ConfigError(f"{label} ({env}) must be one of: {', '.join(kind[1])}. Got {raw!r}.")
    _, name, vkind = kind
    if raw == "":
        return [], False
    if vkind == "number":
        try:
            if float(raw) < 0:
                raise ValueError
        except ValueError:
            raise ConfigError(f"{label} ({env}) must be a number of GB, 0 or more. Got {raw!r}.") from None
    elif vkind == "path":
        if not raw.startswith("/") or any(c in raw for c in "\n\r\t\0"):
            raise ConfigError(f"{label} ({env}) must be a container path starting with /, for example /comfyui. Got {raw!r}.")
    elif vkind == "subpath":
        if not re.fullmatch(r"[A-Za-z0-9._~/-]+", raw):
            raise ConfigError(f"{label} ({env}) may only contain letters, digits and . _ ~ / -. Got {raw!r}.")
    return [name, raw], True


def build(environ, warn):
    """Return the final flag list. Raises ConfigError on a bad option value."""
    args = list(FIXED)
    enabled = {}
    for env, label, kind, default in OPTIONS:
        flags, on = _resolve(env, label, kind, default, environ)
        enabled[env] = on
        if env in NEEDS_API and on and not (enabled["NEO_API"] or enabled["NEO_API_ONLY"]):
            warn(f"{label} ({env}) is on, but it needs API (NEO_API) to be true. Ignoring it.")
            continue
        if kind[0] == "value" and on and kind[2] == "path" and not os.path.isdir(flags[1]):
            warn(f"{label} ({env}): {flags[1]} doesn't exist inside the container. "
                 "Add a Path mapping for it in the template.")
        args += flags
    # --nowebui starts the API on its own. Add --api too, so start.sh sees the
    # API as on and applies API_AUTH_FILE_MODE to it.
    if enabled["NEO_API_ONLY"] and not enabled["NEO_API"]:
        args.append("--api")

    owned = _option_flags()
    try:
        extra = shlex.split(environ.get("COMMANDLINE_ARGS", ""))
    except ValueError as e:
        raise ConfigError(f"Extra Launch Flags (COMMANDLINE_ARGS) could not be read: {e}.") from None

    i = 0
    while i < len(extra):
        token = extra[i]
        name, eq, _ = token.partition("=")
        span = 1
        if not eq and name in TAKES_VALUE and i + 1 < len(extra) and not extra[i + 1].startswith("--"):
            if TAKES_VALUE[name] == 1 or re.fullmatch(r"-?\d+", extra[i + 1]):
                span = 2
        removed = " ".join(extra[i:i + span])
        if name in MANAGED:
            warn(f"Removed {removed!r} from Extra Launch Flags: {MANAGED[name]}.")
        elif name in NOT_ALLOWED:
            warn(f"Removed {removed!r} from Extra Launch Flags: {NOT_ALLOWED[name]}.")
        elif name in owned:
            env, label = owned[name]
            warn(f"Removed {removed!r} from Extra Launch Flags: use the template option {label!r} ({env}) instead.")
        else:
            args += extra[i:i + span]
        i += span
    return args


def main():
    def warn(msg):
        print(msg, file=sys.stderr)

    try:
        args = build(os.environ, warn)
    except ConfigError as e:
        print(f"Launch option error: {e}", file=sys.stderr)
        sys.exit(EXIT_CONFIG)
    print(shlex.join(args))


if __name__ == "__main__":
    main()
