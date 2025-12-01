# Waydroid Android TV Installer

This repository provides a **one-shot Bash installer** that:

- Installs [Waydroid](https://waydro.id/)
- Downloads and configures an **Android TV 13** image from **[supechicken/waydroid-androidtv-build](https://github.com/supechicken/waydroid-androidtv-build)**
- Applies the kernel and cgroup tweaks needed for Waydroid on:
  - Raspberry Pi OS (Pi 4 / Pi 5)
  - Debian / Ubuntu and derivatives
- Creates a `waydroid-atv-launch` helper and desktop entry to start Android TV cleanly

**Repo name suggestion:** `waydroid-androidtv-installer`  
Suggested GitHub URL: `https://github.com/comp6062/waydroid-androidtv-installer`

> ✅ This is based on your working installer script and is designed to behave like a Pi-Apps-style one-click setup.

---

## Credits

- Android TV image and base work: **[supechicken/waydroid-androidtv-build](https://github.com/supechicken/waydroid-androidtv-build)**
- Waydroid project: **[Waydroid](https://github.com/waydroid/waydroid)**
- Kernel / psi / cgroup handling patterns inspired by Pi-Apps Waydroid installer.

This repo only glues those pieces together into a **single, robust installer**.

---

## Supported Environment

- **Package manager:** APT (Debian / Ubuntu / Raspberry Pi OS and derivatives)
- **Architectures:**
  - `arm64` / `aarch64` → Android TV `arm64` image
  - `x86_64` → Android TV `x86_64-minigbm` image

Non-APT systems (Arch, Fedora, etc.) are **detected and refused** with a clear error.

---

## Remote Install (curl)

From any supported system:

```bash
curl -fsSL https://raw.githubusercontent.com/comp6062/waydroid-androidtv-installer/main/waydroid-androidtv-installer.sh \
  -o waydroid-androidtv-installer.sh

chmod +x waydroid-androidtv-installer.sh
sudo ./waydroid-androidtv-installer.sh
