#!/usr/bin/env bash
# Re-apply local fix for pi-web-access curator crash on headless/WSL.
# Upstream (≤0.13.0): sendCuratorFallbackUpdate is const-declared inside try
# and referenced from catch → ReferenceError uncaughtException kills pi.
#
# Idempotent. Called from update-agents.sh after extension reconcile.
set -euo pipefail

TARGET="${PI_WEB_ACCESS_INDEX:-$HOME/.pi/agent/npm/node_modules/pi-web-access/index.ts}"
LOG_TAG="patch-pi-web-access"

log() { echo "[$LOG_TAG] $*"; }

[[ -f "$TARGET" ]] || { log "skip: $TARGET missing"; exit 0; }

# Already patched?
if grep -q 'sendCuratorFallbackUpdate must live here' "$TARGET" 2>/dev/null; then
  log "already patched"
  exit 0
fi

# Only patch the known broken pattern
if ! grep -q 'sendCuratorFallbackUpdate("Search curator is running' "$TARGET" 2>/dev/null; then
  log "skip: unexpected upstream shape (maybe fixed)"
  exit 0
fi

python3 - "$TARGET" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
src = path.read_text()

# Remove the try-scoped helper (block ending right before pc.onUpdate curating message)
helper = re.compile(
    r"\n\t\t\tconst sendCuratorFallbackUpdate = \(message: string\) => \{\n"
    r"\t\t\t\tpc\.onUpdate\?\.\(\{\n"
    r"\t\t\t\t\tcontent: \[\{ type: \"text\", text: `\$\{message\}\\nOpen manually: \$\{handle\.url\}` \}\],\n"
    r"\t\t\t\t\tdetails: \{\n"
    r"\t\t\t\t\t\tphase: \"curator-fallback\",\n"
    r"\t\t\t\t\t\tprogress: searchesComplete \? 1 : 0\.5,\n"
    r"\t\t\t\t\t\tcuratorUrl: handle\.url,\n"
    r"\t\t\t\t\t\ttimeoutSeconds: pc\.timeoutSeconds,\n"
    r"\t\t\t\t\t\tshortcut: curateKey,\n"
    r"\t\t\t\t\t\tbrowserOpenError: pc\.browserOpenError,\n"
    r"\t\t\t\t\t\},\n"
    r"\t\t\t\t\}\);\n"
    r"\t\t\t\};\n",
    re.M,
)
src2, n = helper.subn("\n", src, count=1)
if n != 1:
    print(f"[{path}] helper block not found (n={n})", file=sys.stderr)
    sys.exit(1)

old_call = (
    '\t\t\tif (handle && activeCurators.get(callId) === handle && pendingCurates.get(callId) === pc) {\n'
    '\t\t\t\tpc.browserOpenError = message;\n'
    '\t\t\t\tsendCuratorFallbackUpdate("Search curator is running, but the browser did not open automatically.");\n'
    '\t\t\t}'
)
new_call = (
    '\t\t\t// sendCuratorFallbackUpdate must live here — it closes over `handle` from the try.\n'
    '\t\t\t// (Upstream bug: const was declared inside try and referenced from catch → ReferenceError.)\n'
    '\t\t\tif (handle && activeCurators.get(callId) === handle && pendingCurates.get(callId) === pc) {\n'
    '\t\t\t\tpc.browserOpenError = message;\n'
    '\t\t\t\tpc.onUpdate?.({\n'
    '\t\t\t\t\tcontent: [{\n'
    '\t\t\t\t\t\ttype: "text",\n'
    '\t\t\t\t\t\ttext: `Search curator is running, but the browser did not open automatically.\\nOpen manually: ${handle.url}`,\n'
    '\t\t\t\t\t}],\n'
    '\t\t\t\t\tdetails: {\n'
    '\t\t\t\t\t\tphase: "curator-fallback",\n'
    '\t\t\t\t\t\tprogress: searchesComplete ? 1 : 0.5,\n'
    '\t\t\t\t\t\tcuratorUrl: handle.url,\n'
    '\t\t\t\t\t\ttimeoutSeconds: pc.timeoutSeconds,\n'
    '\t\t\t\t\t\tshortcut: curateKey,\n'
    '\t\t\t\t\t\tbrowserOpenError: pc.browserOpenError,\n'
    '\t\t\t\t\t},\n'
    '\t\t\t\t});\n'
    '\t\t\t}'
)
if old_call not in src2:
    print(f"[{path}] catch call site not found", file=sys.stderr)
    sys.exit(1)
src2 = src2.replace(old_call, new_call, 1)
path.write_text(src2)
print(f"patched {path}")
PY

log "patched $TARGET"
