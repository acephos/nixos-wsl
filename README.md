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

# optional: fork? set your username in flake.nix (username / hostName)

sudo nixos-rebuild switch --flake .#nixos
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
| `nrs` / `rebuild` | `nixos-rebuild switch` this flake |
| `nrt` | test rebuild (no boot entry) |
| `nrf` | switch + refresh flake inputs from network |
| `nfu` | `nix flake update` then switch |
| `ns <pkg>` | ephemeral `nix shell nixpkgs#<pkg>` |

Edit `configuration.nix` → `nrs`.

### Updating the world

```bash
cd ~/nixos-wsl
nix flake update          # bumps nixpkgs / nixos-wsl / herdr in flake.lock
git diff flake.lock       # review
nrs                       # build + activate
git add -A && git commit -m "flake: update inputs"
git push
```

Other machines: `git pull && nrs` → same generations.

## Repo layout

```
flake.nix              # inputs + nixosConfigurations.nixos
flake.lock             # THE pin — commit this always
configuration.nix      # full system config (packages, shell, services)
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
