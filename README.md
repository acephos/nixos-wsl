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
| `home-manager` | `release-26.05` | User dotfiles |
| `sops-nix` | `Mic92/sops-nix` | Encrypted secrets |
| `herdr` | `ogulcancelik/herdr` | Agent multiplexer (auto-updated) |

The lockfile is the contract. Two machines on the same `flake.lock` evaluate to
the same store paths (for a given system, currently `x86_64-linux`).

## Fresh install (new machine)

### Recommended: one script

**Windows (Admin PowerShell)** — installs WSL2, latest NixOS-WSL base image,
then applies this repo at tag **`known-good`**:

```powershell
irm https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/install.ps1 | iex
```

Reboot if WSL features were just enabled, then re-run the same command.

**Already inside NixOS-WSL** (or any NixOS):

```bash
curl -fsSL https://raw.githubusercontent.com/acephos/nixos-wsl/main/scripts/bootstrap.sh | bash
```

That will:

1. Install prerequisites (`git`, flakes, …) if missing  
2. Clone/update `~/nixos-wsl` at **`known-good`** (falls back to `main`)  
3. `nixos-rebuild switch` your full system from `flake.lock`  
4. Print the few human steps left (auth, rustup)

Options:

```bash
bash <(curl -fsSL …/bootstrap.sh) --ref known-good   # default
bash <(curl -fsSL …/bootstrap.sh) --ref main
bash <(curl -fsSL …/bootstrap.sh) --no-rebuild        # fetch only
bash <(curl -fsSL …/bootstrap.sh) --push              # push after switch
```

After bootstrap:

```bash
exec zsh                 # pick up aliases (not: source ./zshrc)
rustup default stable
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
gh auth login && gh auth setup-git
nrs                      # turn on auto-push now that gh works
nsync-status             # 4h backup timer
```

> Flake user is `acephos`. Create that user on first boot, or change
> `username` in `flake.nix` before switching.

### Manual install (if you prefer)

1. Windows: `wsl --install --no-distribution` → reboot → install
   [NixOS-WSL](https://github.com/nix-community/NixOS-WSL/releases) `.wsl`
2. Inside NixOS:
   ```bash
   git clone https://github.com/acephos/nixos-wsl.git ~/nixos-wsl
   cd ~/nixos-wsl && git checkout known-good
   ./scripts/install-hooks.sh
   ./scripts/rebuild.sh switch --no-push
   exec zsh
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
| `nreload` | `exec zsh` — pick up new aliases after `nrs` |
| `nsync` / `nsync-status` | run backup now / show timer status |
| `ns <pkg>` | ephemeral `nix shell nixpkgs#<pkg>` |

Edit `configuration.nix` → `nrs` → `nreload` (or open a new terminal).

### Reload shell (the `./zshrc` issue)

System aliases live in **`/etc/zshrc`**, not `./zshrc` or even only `~/.zshrc`.

```bash
exec zsh              # best — or: nreload
source /etc/zshrc     # also works
source ~/.zshrc       # personal overrides only
# WRONG:  source ./zshrc   ← file does not exist
```

### Git automation (what runs when)

| Event | Commit? | Tag `known-good`? | Push? |
|-------|---------|-------------------|-------|
| `nrs` success | yes, if tree dirty | yes | yes (default) |
| **timer every 4h** | yes, if dirty | yes | yes |
| `ngood "before X"` | yes, if dirty | yes | yes |
| failed rebuild | **no** | **no** | **no** |

#### Periodic timer (default: every 4 hours)

In `configuration.nix`:

```nix
nixosWsl.autoSync = {
  enable = true;
  interval = "4h";       # "30min", "6h", "1d", …
  onBoot = "30min";
  onlyWhenDirty = false; # true = skip when clean+pushed
  updateFlake = false;   # keep nixpkgs pinned
  updateAgents = true;   # herdr (flake) + pi (npm @latest) every tick
  push = true;
};
```

**Always-latest agents** (herdr + pi), base OS stays pinned:

| Tool | Channel | How it updates |
|------|---------|----------------|
| `herdr` | flake input | `nix flake update herdr` on each timer / `nup` |
| `pi` | npm `@latest` → `~/.local` | `npm i -g …@latest` on each timer / `nup` |
| nixpkgs | `flake.lock` | only when you run `nfu` / set `updateFlake` |

Versions last resolved are recorded in [`agents.lock.json`](./agents.lock.json).

```bash
nup              # update herdr+pi now, rebuild, push
nup-agents       # update only (no rebuild)
nsync-status
nsync            # full timer job once + logs
journalctl -u nixos-wsl-auto-sync.service -n 50
```

Disable push: `nrs --no-push` or `export NIXOS_AUTO_PUSH=0`.

Git hooks (once per clone: `./scripts/install-hooks.sh`): block secrets, require `flake.lock`, parse-check `*.nix`.

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
flake.nix                 # inputs + nixosConfigurations.nixos
flake.lock                # THE pin — commit this always
configuration.nix         # thin knobs (autoSync / notify)
modules/
  wsl.nix  nix.nix  packages.nix  shell.nix  dev.nix
  auto-sync.nix  notify.nix  secrets.nix  home.nix
home/default.nix          # Home Manager user files
secrets/secrets.yaml      # sops-encrypted (age)
docs/SECRETS.md  docs/RESTORE.md
scripts/                  # bootstrap, rebuild, nup, ndrill, …
.github/workflows/ci.yml  # nix build + flake check
templates/devshell/
```

## 100% parity — what that means

**Guaranteed identical (via flake.lock):**

- Every package in `environment.systemPackages` and their dependency closure
- Enabled modules: docker, zsh/oh-my-zsh, starship, tmux, direnv, nix-ld, …
- Systemd unit enablement that comes from those modules
- Shell aliases, git defaults, editor/env vars declared here
- `herdr` version

**Also automated:**

| | |
|--|--|
| Backup timer | `nsync-status` — rebuild + push every 4h |
| Agents | `nup` — herdr flake + pi npm `@latest` |
| Secrets | `sops secrets/secrets.yaml` → `/run/secrets/*` |
| CI | GitHub Actions builds `.#nixos` on push |
| Restore audit | `ndrill` — see [docs/RESTORE.md](./docs/RESTORE.md) |
| Failure notify | webhook via sops `notify-webhook` |

**Intentionally not in git (per-machine / secret):**

| State | Why |
|-------|-----|
| `~/.config/sops/age/keys.txt` | **private** age key — password manager |
| `~/.ssh` | secrets |
| `gh` / cloud auth tokens | secrets |
| `git config user.*` | set in `home/default.nix` if you want it shared |
| `rustup` toolchains | `rustup default stable` |
| pi binary | npm `~/.local` (version in `agents.lock.json`) |
| Docker volumes | runtime data |
| Windows side | host OS |

See [docs/SECRETS.md](./docs/SECRETS.md) (sops-nix vs agenix).

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
