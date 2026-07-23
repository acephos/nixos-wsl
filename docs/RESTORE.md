# Restore / impermanence mindset

Goal: **wipe the distro and be productive again in ~20–30 minutes**
(after base image download).

## What is declarative (comes back via git + rebuild)

| Item | Where |
|------|--------|
| OS packages, services, zsh, docker | `modules/*.nix` |
| User dotfiles (npmrc, zshrc stub) | `home/default.nix` |
| pi settings + extension list | `home/pi/settings.json` (HM symlink → `~/.pi/agent/settings.json`) |
| herdr pin | `flake.lock` (+ auto `nup`) |
| pi version record | `agents.lock.json` (binary via npm on bootstrap) |
| pi extension packages | installed by `update-agents.sh` from settings `packages` |
| Encrypted secrets ciphertext | `secrets/secrets.yaml` |
| Install path | `scripts/bootstrap.sh` / `install.ps1` |

## What is NOT in git (you must keep elsewhere)

| Item | Where to store | Restore |
|------|----------------|---------|
| **age private key** | Password manager | `~/.config/sops/age/keys.txt` mode 600 |
| gh auth | GitHub | `gh auth login` |
| SSH keys | Password manager / 1Password | `~/.ssh` |
| rustup toolchains | recreate | `rustup default stable` |
| git user.name / email | memory / HM config | edit `home/default.nix` or `git config` |
| Docker volumes / DB data | backups if needed | re-create |
| Project working trees | git remotes | `git clone` |
| pi `auth.json` / sessions | secrets + runtime | API keys via sops `agent-env`; sessions ephemeral |

## Age key (critical)

```bash
# Show public key (safe to share / already in .sops.yaml)
age-keygen -y ~/.config/sops/age/keys.txt

# Backup private key NOW if you have not:
cat ~/.config/sops/age/keys.txt
# → store in password manager. Without it, secrets.yaml is bricked.
```

## Edit secrets

```bash
sops secrets/secrets.yaml
# notify-webhook:  https://hooks.slack.com/... or Discord webhook
# agent-env:       export ANTHROPIC_API_KEY=...
nrs
```

## Drill

```bash
ndrill    # read-only audit + printed wipe plan
```

Do a real drill on a **second** WSL distro name before you trust a wipe.
