#!/usr/bin/env bash
# Umbleek build kit: Debian 13 + GNOME, mac-style dock/menu bar,
# liquid-glass blur, Windows-style window buttons (top right), Wine preinstalled.
# ARM64 build. Run on an arm64 Debian/Ubuntu host as root.
set -euo pipefail
apt-get update && apt-get install -y live-build
mkdir -p umbleek && cd umbleek

lb config \
  --distribution trixie --architectures arm64 --linux-flavours arm64 \
  --archive-areas "main contrib non-free-firmware" \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application Umbleek --iso-volume Umbleek --image-name umbleek

mkdir -p config/package-lists config/hooks/live \
         config/includes.chroot/etc/dconf/db/local.d \
         config/includes.chroot/etc/dconf/profile \
         config/includes.chroot/etc/skel/.config/gtk-4.0

# ---- Packages ----
cat > config/package-lists/umbleek.list.chroot <<'EOF'
task-gnome-desktop
gnome-shell-extension-dashtodock
gnome-shell-extension-blur-my-shell
gnome-shell-extension-appindicator
gnome-tweaks
fonts-inter
papirus-icon-theme
plymouth plymouth-themes
firefox-esr
wine wine64
cabextract
EOF

# ---- Wine: 32-bit support so most .exe files run ----
cat > config/hooks/live/010-wine.hook.chroot <<'EOF'
#!/bin/sh
# Wine on ARM64 runs ARM Windows apps natively. For normal x86 .exe files
# an x86 translator (box64) is needed; install it if the repo has it.
apt-get update
apt-get install -y box64 || echo "box64 not in repo: x86 .exe files will not run"
update-desktop-database || true
EOF

# ---- Branding ----
cat > config/hooks/live/020-brand.hook.chroot <<'EOF'
#!/bin/sh
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Umbleek"/; s/^NAME=.*/NAME="Umbleek"/' /etc/os-release
echo "Umbleek" > /etc/hostname
glib-compile-schemas /usr/share/glib-2.0/schemas || true
dconf update || true
EOF
chmod +x config/hooks/live/*.chroot

# ---- Desktop behaviour (dconf) ----
cat > config/includes.chroot/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

cat > config/includes.chroot/etc/dconf/db/local.d/00-umbleek <<'EOF'
[org/gnome/desktop/wm/preferences]
# Windows-style buttons: minimize, maximize, close on the TOP RIGHT
button-layout=':minimize,maximize,close'
titlebar-font='Inter Semi-Bold 11'

[org/gnome/desktop/interface]
enable-animations=true
font-name='Inter 11'
icon-theme='Papirus'
color-scheme='prefer-light'
clock-show-weekday=true

[org/gnome/shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com','blur-my-shell@aunetx','appindicatorsupport@rgcjonas.gmail.com']
favorite-apps=['org.gnome.Nautilus.desktop','firefox-esr.desktop','wine.desktop','org.gnome.Settings.desktop']

# macOS-style floating dock with magnified, glassy look
[org/gnome/shell/extensions/dash-to-dock]
dock-position='BOTTOM'
extend-height=false
dash-max-icon-size=56
transparency-mode='FIXED'
background-opacity=0.25
custom-theme-shrink=true
show-trash=true
click-action='minimize-or-previews'
animation-time=0.25

# Liquid glass: blur the top bar, dock, overview and panels
[org/gnome/shell/extensions/blur-my-shell/panel]
blur=true
sigma=30
brightness=0.9

[org/gnome/shell/extensions/blur-my-shell/dash-to-dock]
blur=true
sigma=40
brightness=0.8
static-blur=false

[org/gnome/shell/extensions/blur-my-shell/overview]
blur=true
sigma=35
EOF

echo "Building ISO (takes a while)..."
lb build
echo "Done: $(pwd)/umbleek-arm64.hybrid.iso"
