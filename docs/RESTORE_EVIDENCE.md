# Restore evidence and mutable-state boundary

## Current evidence — 2026-10-01

This revision has seven passing recovery-script tests using real temporary Git repositories and fixture system commands. They cover source-only snapshots, nonzero rebuilds including exit 4, mismatched active closures, dirty `--no-commit`, source changes during a build, successful exact-revision receipts, test activation without tags, locked-version planning, and rejection of credential-like staged paths. Shell syntax passes. These are control-flow tests, not a Nix build or WSL restore.

CI builds the pinned NixOS system closure. A successful CI build proves evaluation/build on the Linux runner; it does not prove WSL boot, secret restoration, OAuth compatibility, or workstation recovery. No fresh WSL restore was performed on this Linux workstation. A dated real restore record remains required before claiming recoverability or a recovery-time objective.

## Verification tags

`source-snapshot` is a convenient source-only checkpoint. It conveys no build or restore proof. `ngood` retains its old alias for convenience but now creates this source-only tag.

A successful `rebuild.sh switch|boot` must return zero, keep its source unchanged, and match the freshly built closure to the active/boot profile. It records an immutable `build-verified-<UTC>-<commit>` tag with closure/action/revision and moves the `build-verified` convenience pointer. Stage intended new source files before building; tracked changes are staged by the script. Nonzero activation (including exit 4), dirty `--no-commit`, source changes, or closure mismatch never create a verification tag. `test` validates its active closure without committing/tagging/pushing. These receipts prove a build/profile match, not a completed disaster-recovery exercise or bit-for-bit workstation parity.

Old `known-good` tags are historical and may have been created without a rebuild; they are not upgraded into verified evidence. Bootstrap now defaults to `build-verified` and refuses missing refs or dirty existing checkouts without forcing a fallback. Before the first verified build exists, explicitly select `--ref main`, review the source, and run the build. Prefer an immutable receipt tag or full Git SHA for a drill.

## Fresh-distro drill

On a Windows machine with WSL2 available, download a recorded NixOS-WSL image and verify its published source/hash. Run from this checkout:

```powershell
.\scripts\restore-drill.ps1 -Archive C:\private\nixos-wsl.tar.gz -ArchiveSha256 <64-hex-image-hash> -Revision <40-hex-git-sha> -EvidencePath C:\private\restore-evidence.json
```

The script requires a unique `NixOS-drill-*` distribution and an unused install/evidence path. It never unregisters a distribution or changes the default. It imports the specified image, bootstraps the exact revision, and records elapsed time, image hash, revision, closure and success/failure. It retains the distribution for inspection. Bootstrap must run as the image's normal user; prepare the image/user according to NixOS-WSL instructions if needed. Missing secrets or required credentials can make activation fail; failure is recorded instead of claiming restoration. Clean up the throwaway distro manually only after inspecting it.

`core-restored` means the system closure was activated. Verify services, shell, application behavior, and restored mutable data separately, then append a reviewed dated report. `restore-drill.sh` / `ndrill` is only a read-only readiness audit and no longer prints an unregister/install recipe that could target the main distro.

## What is and is not pinned

The flake pins the declarative x86_64-linux system. Bootstrap installs Pi and OMP at the exact package versions in `agents.lock.json` using `update-agents.sh --locked`, leaves Herdr/tuicr flake inputs unchanged, skips extension updates/reconciliation, and preserves the lock record. This is a core CLI baseline, not a complete transitive npm/Bun integrity lock.

Explicit `nup-agents` and the configured periodic updater still intentionally resolve latest agents and record the result. That mode changes the baseline. Pi extension sources, Rustup's selected toolchain, Android SDK downloads, WSL base-image selection, caches, auth tokens, editor state and project data have independent mutable lifecycles. Extension versions are not restored by locked mode. These boundaries prevent a claim that `flake.lock` alone recreates an identical workstation.

Keep age identities and OAuth credentials outside this repository and recover them through an independent trusted backup. Document evidence without plaintext keys, tokens, private project contents, or decrypted secret values.
