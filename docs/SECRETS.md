# Secrets: why sops-nix (not agenix)

| | **sops-nix** (chosen) | **agenix** |
|--|----------------------|------------|
| Format | One YAML/JSON with many keys | One file per secret |
| Tooling | `sops` CLI (already in systemPackages) | `agenix` CLI |
| Multi-machine | Add age pubkeys in `.sops.yaml` | Add to secrets.nix list |
| Non-Nix use | Decrypt with plain `sops -d` | Nix-oriented |
| Agent env blobs | Natural (`agent-env` multiline) | Awkward (many files) |
| Complexity | Medium | Lower for 1–2 files |

We use **sops-nix + age** because pi/herdr need a **bundle of API keys**
and a webhook string — one encrypted YAML is the right shape.

## Layout

```
.sops.yaml                 # which age pubkeys may decrypt
secrets/secrets.yaml       # encrypted (committed)
secrets/secrets.example.yaml
~/.config/sops/age/keys.txt  # PRIVATE — never commit
```

## New machine

1. Restore `keys.txt` **before** expecting decrypted secrets.
2. `bootstrap.sh` / `nrs`
3. Confirm: `sops -d ~/nixos-wsl/secrets/secrets.yaml`

## Add a second machine’s key

```bash
# on new machine
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt   # copy pubkey

# on any machine with existing key: add pubkey under .sops.yaml keys:
# then re-encrypt:
sops updatekeys secrets/secrets.yaml
```
