#!/usr/bin/env bash
#
# waydroid-androidtv-installer.sh
#
# One-shot installer/uninstaller for:
#   - Waydroid
#   - Android TV image from supechicken/waydroid-androidtv-build
#
# Features:
#   - OS detection (Debian/Ubuntu/RPi OS and derivatives)
#   - Kernel page size + psi/cgroup checks
#   - Pi 5 16K -> 4K kernel switch (Pi-Apps style)
#   - Per-arch Android TV image selection (arm64 / x86_64)
#   - Embedded README:  --write-readme  -> waydroid-atv-readme.txt
#
# Install:
#   sudo ./waydroid-androidtv-installer.sh
#
# Uninstall:
#   sudo ./waydroid-androidtv-installer.sh --uninstall
#
# Write README:
#   ./waydroid-androidtv-installer.sh --write-readme
#

set -e

log() { echo "[Waydroid-ATV] $*"; }
err() { echo "[Waydroid-ATV ERROR] $*" >&2; }

###########################################################################
# EMBEDDED README
###########################################################################

write_readme() {
  local OUT="waydroid-atv-readme.txt"
  cat > "$OUT" << 'EOF_README'
WAYDROID + ANDROID TV (ONE-SHOT INSTALLER)
==========================================

This installer sets up:

- Waydroid
- Android TV 13 image from supechicken/waydroid-androidtv-build
- OS + kernel detection (Debian/Ubuntu/RPi OS and derivatives)
- Raspberry Pi 5 16K -> 4K kernel fix (Pi-Apps style)
- psi=1 + cgroup flags on Raspberry Pi
- Smart launcher that waits for Android to fully boot
- Full uninstaller

It is designed to behave like a working Raspberry Pi setup, but adds
extra detection and safer behavior on other APT-based Linux systems.

------------------------------------------
SUPPORTED ENVIRONMENT (CURRENTLY)
------------------------------------------

- APT-based distributions:
  - Raspberry Pi OS Bookworm (Pi 4 / Pi 5)
  - Debian 12 / 11
  - Ubuntu and derivatives (Mint, Pop!_OS, etc.)

- Architectures:
  - arm64 / aarch64  -> uses arm64 ATV image
  - x86_64           -> uses x86_64-minigbm ATV image

Non-APT systems (Fedora, Arch, etc.) are detected and refused with a
clear error instead of half-installing.

------------------------------------------
INSTALL
------------------------------------------

1) Make the installer executable:

   chmod +x waydroid-androidtv-installer.sh

2) Run it as root:

   sudo ./waydroid-androidtv-installer.sh

3) On Raspberry Pi 5 with the default 16K PageSize kernel:

   - The script OFFERs to switch you to the 4K kernel by adding:

       [pi5]
       kernel=kernel8.img

     to /boot/firmware/config.txt (or /boot/config.txt).

   - After switching, it exits and instructs you to reboot:

       sudo reboot

   - After reboot (now on 4K kernel), run the installer again:

       sudo ./waydroid-androidtv-installer.sh

4) On other systems:

   - If your kernel PageSize is not 4096, the installer will abort and
     tell you that a 4K PageSize kernel is required.
   - On Raspberry Pi, psi/cgroup flags are written into cmdline.txt.
   - On non-RPi systems, if /proc/pressure is missing, you get a warning
     telling you to enable psi=1 manually via your bootloader.

------------------------------------------
WAYDROID + ANDROID TV SETUP
------------------------------------------

- The script installs Waydroid using:

  - The official Waydroid repo on Debian/Ubuntu-like systems
  - Or the distro's waydroid package as a fallback when appropriate

- It selects Android TV image based on architecture:

  - arm64 / aarch64  -> arm64 ATV build
  - x86_64           -> x86_64-minigbm ATV build

- It places:

    system.img
    vendor.img

  into:

    /etc/waydroid-extra/images

- It initializes Waydroid to use that Android TV image:

    WAYDROID_EXTRA_IMAGES_PATH=/etc/waydroid-extra/images waydroid init -f

------------------------------------------
USING THE LAUNCHER
------------------------------------------

After install (and any requested reboot), run as your NORMAL user:

   waydroid-atv-launch

The launcher:

- Starts "waydroid session start" in the background if not running
- Waits up to 60 seconds for Android to report:

    sys.boot_completed = 1

- If boot completes, it runs:

    waydroid show-full-ui

- If the session crashes or never boots, it prints a clear error and
  tells you to inspect:

    waydroid status
    waydroid log

A desktop entry is also created:

   Android TV (Waydroid)

------------------------------------------
UNINSTALL / RESET
------------------------------------------

Run:

   sudo ./waydroid-androidtv-installer.sh --uninstall

It will:

- Stop the waydroid-container service
- Purge the waydroid package
- Remove:

    /var/lib/waydroid
    /var/cache/waydroid
    /etc/waydroid
    /etc/waydroid-extra

- On Raspberry Pi, it removes any psi/cgroup flags that were added to
  cmdline.txt.

Note: It does NOT revert the Pi 5 4K kernel change. To revert that:

- Edit /boot/firmware/config.txt (or /boot/config.txt)
- Remove:

    [pi5]
    kernel=kernel8.img

- Reboot.

------------------------------------------
TROUBLESHOOTING
------------------------------------------

If "waydroid-atv-launch" fails:

1. Check status:

   waydroid status

2. Check logs:

   waydroid log

3. Verify:

   - 4K PageSize kernel (PAGE_SIZE=4096)
   - Binder present:

     grep ' binder$' /proc/devices

   - On Raspberry Pi: psi/cgroup flags exist in cmdline.txt

------------------------------------------
END OF FILE
------------------------------------------
EOF_README
  log "README written to $OUT"
}

###########################################################################
# ROOT & PLATFORM CHECKS
###########################################################################

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Run this script with sudo."
    exit 1
  fi
}

check_apt() {
  if ! command -v apt >/dev/null 2>&1; then
    err "This installer currently supports only APT-based systems (Debian/Ubuntu/RPi OS and derivatives)."
    err "Detected non-APT system. Aborting."
    exit 1
  fi
}

is_rpi() {
  if [ -f /proc/device-tree/model ] && grep -qi "raspberry pi" /proc/device-tree/model; then
    return 0
  fi
  return 1
}

is_rpi5() {
  if [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi 5" /proc/device-tree/model; then
    return 0
  fi
  return 1
}

detect_os() {
  OS_ID="unknown"
  OS_NAME="Unknown"
  OS_VERSION="?"
  OS_LIKE=""

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${NAME:-Unknown}"
    OS_VERSION="${VERSION_ID:-?}"
    OS_LIKE="${ID_LIKE:-}"
  fi

  log "Detected OS: ${OS_NAME} (ID=${OS_ID}, VERSION_ID=${OS_VERSION}, LIKE=${OS_LIKE})"
}

###########################################################################
# WAYDROID UNINSTALL
###########################################################################

clean_waydroid_runtime() {
  log "Pre-cleaning Waydroid runtime (net + processes)..."

  # Stop container + net helper if present
  systemctl stop waydroid-container 2>/dev/null || true
  /usr/lib/waydroid/data/scripts/waydroid-net.sh stop 2>/dev/null || true

  # Kill dnsmasq instances bound to the Waydroid subnet / interface
  pkill -f "dnsmasq.*waydroid" 2>/dev/null || true
  pkill -f "dnsmasq.*192.168.240.1" 2>/dev/null || true
  pkill -f "dnsmasq.*waydroid0" 2>/dev/null || true

  # Drop waydroid0 iface if it exists
  ip link delete waydroid0 2>/dev/null || true

  # Remove NAT rule if present
  iptables -t nat -D POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE 2>/dev/null || true

  # Remove route if present
  ip route del 192.168.240.0/24 dev waydroid0 2>/dev/null || true
}

###########################################################################
# MAIN UNINSTALL
###########################################################################

uninstall_all() {
  log "==================== UNINSTALLING WAYDROID + ATV ===================="

  # Stop services and runtime first
  log "Stopping Waydroid services..."
  systemctl stop waydroid-container 2>/dev/null || true
  systemctl disable waydroid-container 2>/dev/null || true

  clean_waydroid_runtime

  log "Purging waydroid package (if installed)..."
  if command -v waydroid >/dev/null 2>&1; then
    apt purge -y waydroid || true
  else
    log "Waydroid binary not found, skipping package purge."
  fi

  log "Removing Waydroid data, configs, and images..."
  rm -rf /var/lib/waydroid \
         /var/cache/waydroid \
         /etc/waydroid \
         /etc/waydroid-extra \
         /usr/local/share/waydroid \
         /usr/share/waydroid \
         /usr/lib/waydroid

  log "Removing Waydroid APT repo + keyring (if present)..."
  rm -f /etc/apt/sources.list.d/waydroid.list
  rm -f /usr/share/keyrings/waydroid.gpg

  log "Removing Android TV launcher script..."
  rm -f /usr/local/bin/waydroid-atv-launch

  log "Removing system-wide desktop entries..."
  rm -f /usr/share/applications/waydroid*.desktop
  rm -f /usr/share/applications/*Waydroid*.desktop
  rm -f /usr/share/applications/*waydroid*.desktop

  log "Removing user-level Waydroid desktop entries (all users)..."
  for HOME_DIR in /home/* /root; do
    [ -d "$HOME_DIR/.local/share/applications" ] || continue
    rm -f "$HOME_DIR/.local/share/applications"/waydroid*.desktop 2>/dev/null || true
    rm -f "$HOME_DIR/.local/share/applications"/*Waydroid*.desktop 2>/dev/null || true
    rm -f "$HOME_DIR/.local/share/applications"/*waydroid*.desktop 2>/dev/null || true
  done

  log "Refreshing desktop database (if available)..."
  update-desktop-database /usr/share/applications 2>/dev/null || true

  # Raspberry Pi boot parameter cleanup
  if is_rpi; then
    log "Cleaning Raspberry Pi boot flags (psi/cgroup)..."

    if [ -f /boot/firmware/cmdline.txt ]; then
      CMDLINE_FILE="/boot/firmware/cmdline.txt"
    elif [ -f /boot/cmdline.txt ]; then
      CMDLINE_FILE="/boot/cmdline.txt"
    else
      CMDLINE_FILE=""
    fi

    if [ -n "$CMDLINE_FILE" ]; then
      sed -i 's/\<psi=1\>//g' "$CMDLINE_FILE"
      sed -i 's/\<cgroup_enable=cpuset\>//g' "$CMDLINE_FILE"
      sed -i 's/\<cgroup_memory=1\>//g' "$CMDLINE_FILE"
      sed -i 's/\<cgroup_enable=memory\>//g' "$CMDLINE_FILE"
      log "Removed psi/cgroup flags from $CMDLINE_FILE. Reboot recommended."
    else
      log "No cmdline.txt found for boot flag cleanup."
    fi
  fi

  log "Final cleanup: you may optionally run: sudo apt autoremove -y"

  log "==================== UNINSTALL COMPLETE ===================="
}

###########################################################################
# ENTRY POINT
###########################################################################

require_root
uninstall_all
exit 0

}

###########################################################################
# ENTRY POINT: HANDLE SPECIAL FLAGS
###########################################################################

# Allow README extraction without root
if [ "$1" = "--write-readme" ]; then
  write_readme
  exit 0
fi

require_root
check_apt
detect_os

if [ "$1" = "--uninstall" ]; then
  uninstall_all
fi

###########################################################################
# ARCH + KERNEL DETECTION
###########################################################################

ARCH="$(uname -m)"
log "Architecture: $ARCH"

case "$ARCH" in
  aarch64|arm64)
    ATV_VARIANT="arm64"
    ;;
  x86_64)
    ATV_VARIANT="x86_64-minigbm"
    ;;
  *)
    err "Unsupported arch: $ARCH (supported: arm64/aarch64, x86_64)"
    exit 1
    ;;
esac

PAGE_SIZE="$(getconf PAGE_SIZE 2>/dev/null || getconf PAGESIZE 2>/dev/null || echo 4096)"
log "Detected kernel page size: $PAGE_SIZE bytes"

if is_rpi5 && [ "$PAGE_SIZE" -eq 16384 ]; then
  log "Raspberry Pi 5 with 16K PageSize kernel detected."

  if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
  elif [ -f /boot/config.txt ]; then
    BOOT_CONFIG="/boot/config.txt"
  else
    err "Cannot find /boot/firmware/config.txt or /boot/config.txt to switch kernel."
    exit 1
  fi

  echo
  echo "Your Pi 5 is using the 16K PageSize kernel, which is incompatible with Waydroid."
  echo
  echo "Switch to 4K kernel now?"
  echo "  1) No, keep 16K kernel and EXIT"
  echo "  2) Yes, switch to 4K kernel ([pi5]/kernel=kernel8.img) and EXIT"
  echo

  read -r -p "Select [1-2]: " ANSWER
  case "$ANSWER" in
    2)
      {
        echo ""
        echo "[pi5]"
        echo "kernel=kernel8.img"
      } >> "$BOOT_CONFIG"
      log "Enabled 4K kernel via [pi5]/kernel=kernel8.img in $BOOT_CONFIG"
      log "Please REBOOT now, then re-run this installer."
      echo
      echo "Example:"
      echo "  sudo reboot"
      echo
      exit 0
      ;;
    *)
      err "Cannot continue with 16K kernel. Exiting."
      exit 1
      ;;
  esac
fi

if ! is_rpi && [ "$PAGE_SIZE" -ne 4096 ]; then
  err "Non-4K kernel page size ($PAGE_SIZE) detected on a non-RPi system."
  err "Waydroid generally expects a 4K PageSize kernel. Please move to a 4K kernel."
  exit 1
fi

###########################################################################
# psi=1 + cgroup flags (Raspberry Pi only)
###########################################################################

NEEDS_REBOOT=0

if is_rpi; then
  if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
  elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
  else
    CMDLINE_FILE=""
  fi

  if [ -z "$CMDLINE_FILE" ]; then
    log "Warning: no cmdline.txt found to add psi/cgroup flags. You may need to do this manually."
  else
    ORIG_CMDLINE="$(cat "$CMDLINE_FILE")"
    NEW_CMDLINE="$ORIG_CMDLINE"

    for FLAG in psi=1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory; do
      if ! echo "$NEW_CMDLINE" | grep -qw "$FLAG"; then
        NEW_CMDLINE="$NEW_CMDLINE $FLAG"
      fi
    done

    if [ "$NEW_CMDLINE" != "$ORIG_CMDLINE" ]; then
      log "Updating $CMDLINE_FILE with psi/cgroup flags..."
      printf '%s\n' "$NEW_CMDLINE" > "$CMDLINE_FILE"
      NEEDS_REBOOT=1
    else
      log "psi/cgroup flags already present in $CMDLINE_FILE"
    fi
  fi
else
  if [ ! -e /proc/pressure ]; then
    log "Warning: /proc/pressure is missing. On some systems you must enable psi=1 in your bootloader manually."
  fi
fi

###########################################################################
# Install dependencies & Waydroid
###########################################################################

log "Installing dependencies..."
apt update -y
apt install -y curl ca-certificates wget unzip lsb-release

if command -v waydroid >/dev/null 2>&1; then
  log "Waydroid already installed."
else
  if echo "$OS_ID $OS_LIKE" | grep -Eq 'debian|ubuntu|raspbian|linuxmint|pop'; then
    log "Adding Waydroid APT repository for ${OS_NAME}..."
    mkdir -p /usr/share/keyrings
    curl -Sf https://repo.waydro.id/waydroid.gpg --output /usr/share/keyrings/waydroid.gpg
    CODENAME="$(lsb_release -cs)"
    echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ ${CODENAME} main" \
      > /etc/apt/sources.list.d/waydroid.list

    log "Installing Waydroid from official repo..."
    apt update -y
    apt install -y waydroid
  else
    log "OS not clearly Debian/Ubuntu-like. Trying distro waydroid package..."
    apt install -y waydroid || {
      err "Failed to install waydroid. Your OS may not be supported."
      exit 1
    }
  fi
fi

###########################################################################
# Binder / Ashmem check
###########################################################################

log "Checking binder / ashmem modules..."
modprobe binder_linux 2>/dev/null || true
modprobe ashmem_linux 2>/dev/null || true
modprobe binder 2>/dev/null || true
modprobe ashmem 2>/dev/null || true

if ! grep -q ' binder$' /proc/devices 2>/dev/null; then
  err "Binder kernel module is missing. /dev/binder will not be available."
  err "Your kernel may not support Waydroid. On RPi, ensure you are on 4K kernel8.img."
  exit 1
fi

###########################################################################
# Android TV Image Download (per-arch)
###########################################################################

ATV_TAG="20250913"
ATV_BASE="https://github.com/supechicken/waydroid-androidtv-build/releases/download/${ATV_TAG}"

if [ "$ATV_VARIANT" = "arm64" ]; then
  ATV_ZIP="lineage-20.0-${ATV_TAG}-UNOFFICIAL-WayDroidATV_arm64.zip"
else
  ATV_ZIP="lineage-20.0-${ATV_TAG}-UNOFFICIAL-WayDroidATV_x86_64-minigbm.zip"
fi

ATV_URL="${ATV_BASE}/${ATV_ZIP}"

log "Using Android TV image:"
log "  $ATV_URL"

WORKDIR="/tmp/waydroid-atv"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log "Downloading Android TV image (~1GB)..."
wget -O "$ATV_ZIP" "$ATV_URL"

log "Extracting system.img and vendor.img..."
unzip -j "$ATV_ZIP" 'system.img' 'vendor.img'

if [ ! -f system.img ] || [ ! -f vendor.img ]; then
  err "system.img/vendor.img not found after unzip. Aborting."
  exit 1
fi

###########################################################################
# Install ATV images
###########################################################################

IMG_DIR="/etc/waydroid-extra/images"
log "Placing images into $IMG_DIR..."
mkdir -p "$IMG_DIR"
cp system.img "$IMG_DIR/system.img"
cp vendor.img "$IMG_DIR/vendor.img"

###########################################################################
# Initialize Waydroid with ATV image
###########################################################################

log "Stopping Waydroid container service before init..."
stop_waydroid

log "Initializing Waydroid with Android TV image..."
WAYDROID_EXTRA_IMAGES_PATH="$IMG_DIR" waydroid init -f

log "Waydroid init done."

###########################################################################
# Create launcher (CLI + desktop)
###########################################################################

LAUNCHER_SCRIPT="/usr/local/bin/waydroid-atv-launch"
log "Creating CLI launcher: $LAUNCHER_SCRIPT"

cat > "$LAUNCHER_SCRIPT" << 'EOF_LAUNCH'
#!/usr/bin/env bash
# Android TV launcher for Waydroid
# Usage: run as normal user (NO sudo)

set -e

if [ "$(id -u)" -eq 0 ]; then
  echo "Please run waydroid-atv-launch as a normal user, not root."
  exit 1
fi

echo "[Waydroid-ATV] Starting or reusing Waydroid session..."

# Start session if not already running
if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
  echo "[Waydroid-ATV] Session is not running. Starting in background..."
  waydroid session start &
  sleep 2
fi

echo "[Waydroid-ATV] Waiting for Android TV to boot (sys.boot_completed)..."

BOOTED=0
for i in $(seq 1 60); do
  # Check if session is still running
  if ! waydroid status 2>/dev/null | grep -q "RUNNING"; then
    if [ "$i" -gt 10 ]; then
      echo "[Waydroid-ATV ERROR] Waydroid session failed to stay running."
      echo "Check 'waydroid log' and 'waydroid status' for details."
      exit 1
    fi
  fi

  BOOT_PROP="$(waydroid prop get sys.boot_completed 2>/dev/null || echo 0)"

  if [ "$BOOT_PROP" = "1" ]; then
    BOOTED=1
    break
  fi

  sleep 1
done

if [ "$BOOTED" -ne 1 ]; then
  echo "[Waydroid-ATV ERROR] Android TV did not report sys.boot_completed=1 within 60 seconds."
  echo "Run:  waydroid log"
  echo "and:  waydroid status"
  echo "to see why the container isn't booting."
  exit 1
fi

echo "[Waydroid-ATV] Android TV booted. Launching full UI..."
waydroid show-full-ui
EOF_LAUNCH

chmod +x "$LAUNCHER_SCRIPT"

DESKTOP_FILE="/usr/share/applications/waydroid-atv.desktop"
log "Creating desktop launcher: $DESKTOP_FILE"

cat > "$DESKTOP_FILE" << 'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Android TV (Waydroid)
Comment=Launch Android TV environment in Waydroid
Exec=waydroid-atv-launch
Icon=waydroid
Terminal=false
Categories=System;Utility;
EOF_DESKTOP

log "Launchers created."

###########################################################################
# FINAL MESSAGE
###########################################################################

# Drop README next to script if user wants later
if [ ! -f "waydroid-atv-readme.txt" ]; then
  log "Tip: generate a text README with:"
  log "  ./$(basename "$0") --write-readme"
fi

echo
echo "==============================================================="
echo " Waydroid + Android TV installation complete."
echo "==============================================================="

if is_rpi && [ "${NEEDS_REBOOT:-0}" -eq 1 ]; then
  echo "A reboot is RECOMMENDED now so psi/cgroup flags take effect:"
  echo "  sudo reboot"
  echo
fi

echo "To launch Android TV (after any required reboot), run as normal user:"
echo "  waydroid-atv-launch"
echo
echo "To uninstall/reset later:"
echo "  sudo $0 --uninstall"
echo
exit 0
