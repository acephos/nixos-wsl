# Android dev environment (NixOS-WSL)

## What you get

| Piece | Where |
|-------|--------|
| JDK 17 (Temurin) | Nix package → `JAVA_HOME` |
| `adb` / `fastboot` | Nix `android-tools` |
| Gradle | Nix (projects still use `./gradlew`) |
| Android SDK | `~/Android/Sdk` (user install) |
| Check | `android-env` |

Emulator is **not** installed by default on WSL (slow/fragile). Use a **physical phone** or **Windows Android Studio emulator** + `adb connect`.

## One-time setup

```bash
nrs                                          # apply modules/android.nix
exec zsh                                     # reload env
~/nixos-wsl/scripts/setup-android-sdk.sh     # ~/Android/Sdk
android-env                                  # verify
```

Optional huge emulator image:

```bash
WITH_EMULATOR=1 ~/nixos-wsl/scripts/setup-android-sdk.sh
```

## Daily

```bash
cd ~/im-ok-maa
direnv allow          # once per clone
./gradlew :app:assembleDebug
./scripts/install-phone.sh
```

### Phone over USB (WSL2)

From **Windows Admin PowerShell** (usbipd):

```powershell
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

Then in WSL: `adb devices`.

### Phone wireless

Phone → Developer options → Wireless debugging → pair/connect:

```bash
adb pair IP:PAIR_PORT
adb connect IP:PORT
adb devices
```

### Windows Android Studio (UI / Layout Inspector)

1. Install Android Studio on Windows.
2. Open `\\wsl$\nixos\home\acephos\im-ok-maa` **or** keep coding in Zed/WSL and only use Studio’s emulator.
3. Point SDK at a Windows SDK **or** use WSL `./gradlew` for builds.

## Project SDK file

`local.properties` → `sdk.dir=/home/acephos/Android/Sdk` (gitignored; written by setup + direnv).
