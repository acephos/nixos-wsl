# nixos-wsl

Fully reproducible **NixOS on WSL2** system configuration.

Clone this repo on any machine, rebuild, and you get the **same packages, same
versions, same shell, same services** — bit-for-bit parity enforced by
[`flake.lock`](./flake.lock).

```
Windows 11 + WSL2
        │
        ▼
   NixOS-WSL base image
        │
        ▼
   this flake  ──►  identical system everywhere
```

## What is pinned

| Input | Source | Role |
|-------|--------|------|
| `nixpkgs` | `NixOS/nixpkgs` @ exact rev | All system packages |
| `nixos-wsl` | `nix-community/NixOS-WSL` `release-26.05` | WSL integration module |
| `herdr` | `ogulcancelik/herdr` | Agent multiplexer |

The lockfile is the contract. Two machines on the same `flake.lock` evaluate to
the same store paths (for a given system, currently `x86_64-linux`).

## Fresh install (new Windows machine)

### 1. Prerequisites (Windows)

- Windows 11 (or Win10 with WSL2)
- Admin PowerShell:

```powershell
wsl --install --no-distribution
wsl --set-default-version 2
```

Reboot if prompted. Install a recent [WSLg-capable WSL](https://github.com/microsoft/WSL/releases).

### 2. Install NixOS-WSL base

From [NixOS-WSL releases](https://github.com/nix-community/NixOS-WSL/releases)
grab the latest `.wsl` (or `.tar.gz`) for your arch and install:

```powershell
# .wsl double-click works on recent WSL, or:
wsl --install --from-file .\nixos.wsl
# older method:
# wsl --import NixOS $env:USERPROFILE\NixOS .\nixos-wsl.tar.gz --version 2
```

First boot creates the default user. Then:

```bash
sudo nix-channel --update   # only needed on the stock channel image
```

### 3. Apply this flake

```bash
# install git if the base image is bare
sudo nix-env -iA nixos.git   # or use the image's git

git clone https://github.com/acephos/nixos-wsl.git ~/nixos-wsl
cd ~/nixos-wsl
./scripts/install-hooks.sh   # enable repo git hooks

# optional: fork? set your username in flake.nix (username / hostName)

./scripts/rebuild.sh switch  # or after first switch: nrs
```

Log out / open a new shell. You should be on zsh with the full toolset.

### 4. One-time human state (not in the flake)

Nix can reproduce the OS. It cannot (and should not) check in secrets or
machine-local identity:

```bash
# Rust toolchain (rustup is installed; toolchain is user state)
rustup default stable

# Git identity
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"

# GitHub CLI
gh auth login

# Optional: SSH key, age/sops keys, cloud CLIs, etc.
```

## Day-to-day on an existing machine

Repo lives at `~/nixos-wsl` (aliases assume that path).

| Command | What it does |
|---------|----------------|
| `nrs` / `rebuild` | switch **and** on success: commit → tag `known-good` → push |
| `nrt` | test rebuild only (no commit/push) |
| `nrf` | switch + `--refresh` flake inputs |
| `nfu` | `nix flake update` then `nrs` |
| `ngood [msg]` | checkpoint git **without** rebuilding (before experiments) |
| `nlist` | list system generations |
| `nroll` | `nixos-rebuild switch --rollback` |
| `ns <pkg>` | ephemeral `nix shell nixpkgs#<pkg>` |

Edit `configuration.nix` → `nrs`.

### Git automation (what runs when)

**Nothing is on a timer.** The remote updates only when you rebuild (or checkpoint).

| Event | Commit? | Tag `known-good`? | Push? |
|-------|---------|-------------------|-------|
| `nrs` success | yes, if tree dirty | yes (moved to HEAD) | yes (default) |
| `nrs --no-push` | yes | yes | no |
| `ngood "before X"` | yes, if dirty | yes | yes (default) |
| failed rebuild | **no** | **no** | **no** |
| plain `git commit` | your call | no | no |

Disable push for one shot or forever:

```bash
nrs --no-push
export NIXOS_AUTO_PUSH=0    # session default off
```

Git hooks (enable once per clone: `./scripts/install-hooks.sh`):

- `githooks/pre-commit` — refuse secret-looking files; require `flake.lock` with `flake.nix`; parse-check staged `*.nix`

There is **no** cron/systemd timer. Frequency = how often you run `nrs`.

### Updating the world

```bash
nfu                       # flake update + rebuild + commit + push
# or step by step:
cd ~/nixos-wsl && nix flake update && nrs
```

Other machines: `git pull && nrs` → same closure (from `flake.lock`).

Rollback map:

- **OS packages/services:** `nroll` or `nlist` + switch-generation
- **Config files:** `git checkout known-good` (or an older commit) then `nrs`

## Repo layout

```
flake.nix              # inputs + nixosConfigurations.nixos
flake.lock             # THE pin — commit this always
configuration.nix      # full system config (packages, shell, services)
scripts/rebuild.sh     # nrs backend: switch + checkpoint + push
scripts/checkpoint.sh  # ngood backend
scripts/install-hooks.sh
githooks/pre-commit    # secret/lockfile/syntax guards
templates/devshell/    # copy into projects + direnv
```

## 100% parity — what that means

**Guaranteed identical (via flake.lock):**

- Every package in `environment.systemPackages` and their dependency closure
- Enabled modules: docker, zsh/oh-my-zsh, starship, tmux, direnv, nix-ld, …
- Systemd unit enablement that comes from those modules
- Shell aliases, git defaults, editor/env vars declared here
- `herdr` version

**Intentionally not in git (per-machine / secret):**

| State | Why |
|-------|-----|
| `~/.ssh`, age/sops keys | secrets |
| `gh` / cloud auth tokens | secrets |
| `git config user.*` | personal identity (add to config if you want it shared) |
| `rustup` installed toolchains | user profile under `~/.rustup` |
| npm/bun global user installs | prefer project flakes/direnv |
| Docker images/volumes | runtime data |
| herdr session layout | runtime data under `~/.config/herdr` |
| Windows side (WSL version, `.wslconfig`, GPU drivers) | host OS |

**Architecture note:** this flake targets `x86_64-linux` (WSL2 on Intel/AMD).
For Windows-on-Arm, change `system` in `flake.nix` to `aarch64-linux` and
re-lock/rebuild.

## Bootstrap this repo onto the live system

If you are on the machine that authored the config and `/etc/nixos` still uses
channels:

```bash
cd ~/nixos-wsl
sudo nixos-rebuild switch --flake .#nixos
# optional: stop using channels
# sudo nix-channel --remove nixos
# sudo nix-channel --remove nixos-wsl
```

Keep channels or remove them — once the flake is active, rebuilds should always
go through `--flake ~/nixos-wsl#nixos` (the `nrs` alias).

## License

MIT — do whatever. Attribution appreciated but not required.
