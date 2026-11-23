#!/usr/bin/env bash
# Umbleek v1.1.0 (amd64): Debian 13 + GNOME, mac-style dock/menu bar, glass blur,
# Windows-style window buttons (top right), Wine, widgets, Umbrowser, App Store,
# volume popup + per-app mixer, Bluetooth/Wi-Fi/USB/fingerprint support.
set -euo pipefail
apt-get update && apt-get install -y live-build
mkdir -p umbleek && cd umbleek

lb config \
  --distribution trixie --architectures amd64 \
  --archive-areas "main contrib non-free-firmware" \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application Umbleek --iso-volume Umbleek --image-name umbleek

EXT=config/includes.chroot/usr/share/gnome-shell/extensions/umbleek@umbleek.org
mkdir -p config/package-lists config/hooks/live "$EXT" \
         config/includes.chroot/usr/bin config/includes.chroot/usr/share/applications \
         config/includes.chroot/etc/dconf/db/local.d config/includes.chroot/etc/dconf/profile

# ---------------- Packages ----------------
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
wine wine64 winetricks cabextract
network-manager bluez rfkill libspa-0.2-bluetooth
pipewire-audio wireplumber pipewire-pulse
udisks2 gvfs gvfs-backends ntfs-3g exfatprogs
fprintd libpam-fprintd
iio-sensor-proxy power-profiles-daemon
firmware-iwlwifi firmware-realtek firmware-atheros firmware-misc-nonfree
python3 python3-gi gir1.2-gtk-4.0 gir1.2-webkit-6.0
EOF

# ---------------- Hooks ----------------
cat > config/hooks/live/010-wine.hook.chroot <<'EOF'
#!/bin/sh
dpkg --add-architecture i386
apt-get update
apt-get install -y wine32:i386 || true
update-desktop-database || true
EOF

cat > config/hooks/live/020-brand.hook.chroot <<'EOF'
#!/bin/sh
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Umbleek 1.1.0"/; s/^NAME=.*/NAME="Umbleek"/' /etc/os-release
echo 'VERSION="1.1.0"' >> /etc/os-release
echo "umbleek" > /etc/hostname
systemctl enable bluetooth NetworkManager || true
pam-auth-update --enable fprintd || true
glib-compile-schemas /usr/share/glib-2.0/schemas || true
dconf update || true
update-desktop-database || true
EOF
chmod +x config/hooks/live/*.chroot

# ---------------- Umbrowser (built-in browser, also used for the App Store) ----------------
cat > config/includes.chroot/usr/bin/umbrowser <<'PYEOF'
#!/usr/bin/env python3
import sys, gi
gi.require_version("Gtk", "4.0"); gi.require_version("WebKit", "6.0")
from gi.repository import Gtk, WebKit, GLib

HOME = "https://duckduckgo.com"

class Win(Gtk.ApplicationWindow):
    def __init__(self, app, url, appmode):
        super().__init__(application=app, title="Umbleek App Store" if appmode else "Umbrowser")
        self.appmode = appmode
        self.set_default_size(1150, 760)
        self.nb = Gtk.Notebook(scrollable=True, show_tabs=not appmode)
        self.set_child(self.nb)
        hb = Gtk.HeaderBar(); self.set_titlebar(hb)
        if not appmode:
            for icon, fn in (("go-previous-symbolic", lambda *_: self.cur().go_back()),
                             ("go-next-symbolic", lambda *_: self.cur().go_forward()),
                             ("view-refresh-symbolic", lambda *_: self.cur().reload())):
                b = Gtk.Button(icon_name=icon); b.connect("clicked", fn); hb.pack_start(b)
            self.entry = Gtk.Entry(hexpand=True, placeholder_text="Search or enter address")
            self.entry.connect("activate", self.go); hb.set_title_widget(self.entry)
            nt = Gtk.Button(icon_name="tab-new-symbolic")
            nt.connect("clicked", lambda *_: self.tab(HOME)); hb.pack_end(nt)
        self.tab(url)

    def cur(self):
        return self.nb.get_nth_page(self.nb.get_current_page())

    def tab(self, url):
        v = WebKit.WebView(); v.load_uri(url)
        v.connect("notify::uri", lambda w, _: (not self.appmode) and w is self.cur() and self.entry.set_text(w.get_uri() or ""))
        v.connect("notify::title", lambda w, _: self.nb.set_tab_label_text(w, (w.get_title() or "New tab")[:24]))
        i = self.nb.append_page(v, Gtk.Label(label="New tab")); self.nb.set_current_page(i)

    def go(self, e):
        t = e.get_text().strip()
        if "." in t and " " not in t:
            u = t if "://" in t else "https://" + t
        else:
            u = "https://duckduckgo.com/?q=" + GLib.uri_escape_string(t, None, True)
        self.cur().load_uri(u)

args = sys.argv[1:]
appmode = args[:1] == ["--app"] and len(args) > 1
url = args[1] if appmode else (args[0] if args else HOME)
app = Gtk.Application(application_id="org.umbleek.AppStore" if appmode else "org.umbleek.Umbrowser")
app.connect("activate", lambda a: Win(a, url, appmode).present())
app.run([sys.argv[0]])
PYEOF
chmod +x config/includes.chroot/usr/bin/umbrowser

cat > config/includes.chroot/usr/share/applications/umbrowser.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Umbrowser
Exec=umbrowser %u
Icon=web-browser
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
EOF

cat > config/includes.chroot/usr/share/applications/umbleek-appstore.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=App Store
Exec=umbrowser --app https://sites.google.com/view/umbleek/appstore
Icon=system-software-install
Categories=System;
EOF

# ---------------- GNOME Shell extension: widgets, volume popup + mixer, launcher key ----------------
cat > "$EXT/metadata.json" <<'EOF'
{"uuid":"umbleek@umbleek.org","name":"Umbleek Shell","description":"Widgets, volume popup with mixer, Super key opens app launcher","shell-version":["48","49"],"version":1}
EOF

cat > "$EXT/stylesheet.css" <<'CSSEOF'
.umb-widget{background-color:rgba(255,255,255,0.18);border:1px solid rgba(255,255,255,0.4);border-radius:22px;padding:14px;spacing:12px;color:#fff;width:252px}
.umb-title{font-weight:bold;font-size:14px}
.umb-sub{font-size:12px;color:rgba(255,255,255,0.8)}
.umb-big{font-size:34px;font-weight:300}
.umb-btn{padding:6px 10px;border-radius:99px;color:#fff}
.umb-btn:hover{background-color:rgba(255,255,255,0.25)}
.umb-vol{background-color:rgba(30,30,36,0.72);border:1px solid rgba(255,255,255,0.35);border-radius:20px;padding:12px;spacing:8px;width:240px;color:#fff}
.umb-bar{background-color:rgba(255,255,255,0.25);border-radius:99px;height:6px}
.umb-fill{background-color:#fff;border-radius:99px;height:6px}
.umb-dialog{spacing:10px;min-width:300px}
CSSEOF

cat > "$EXT/extension.js" <<'JSEOF'
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Soup from 'gi://Soup?version=3.0';
import Gvc from 'gi://Gvc';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as ModalDialog from 'resource:///org/gnome/shell/ui/modalDialog.js';
import {Slider} from 'resource:///org/gnome/shell/ui/slider.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PFX = 'org.mpris.MediaPlayer2.';
const CFG = GLib.build_filenamev([GLib.get_user_config_dir(), 'umbleek', 'widgets.json']);
const dec = new TextDecoder();
const session = new Soup.Session();

function loadCfg() {
    try { return JSON.parse(dec.decode(GLib.file_get_contents(CFG)[1])); } catch (e) { return {widgets: []}; }
}
function saveCfg(c) {
    GLib.mkdir_with_parents(GLib.path_get_dirname(CFG), 0o755);
    GLib.file_set_contents(CFG, new TextEncoder().encode(JSON.stringify(c)));
}
function apiKey() {
    for (const p of ['/etc/umbleek/accuweather.key',
                     GLib.build_filenamev([GLib.get_user_config_dir(), 'umbleek', 'accuweather.key'])]) {
        try { const k = dec.decode(GLib.file_get_contents(p)[1]).trim(); if (k) return k; } catch (e) { /* none */ }
    }
    return null;
}
function fetchJSON(url) {
    return new Promise((res, rej) => {
        const msg = Soup.Message.new('GET', url);
        session.send_and_read_async(msg, GLib.PRIORITY_DEFAULT, null, (s, r) => {
            try {
                const b = s.send_and_read_finish(r);
                if (msg.get_status() !== Soup.Status.OK) throw new Error('HTTP ' + msg.get_status());
                res(JSON.parse(dec.decode(b.get_data())));
            } catch (e) { rej(e); }
        });
    });
}
function busNames() {
    return Gio.DBus.session.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'ListNames', null, null, Gio.DBusCallFlags.NONE, -1, null).deepUnpack()[0];
}
function listPlayers() {
    const out = [], seen = new Set();
    try {
        for (const n of busNames().filter(x => x.startsWith(PFX))) {
            const base = n.slice(PFX.length).replace(/\.instance.*$/, '');
            if (seen.has(base)) continue;
            seen.add(base);
            let label = base;
            try {
                const p = Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, null,
                    n, '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2', null);
                label = p.get_cached_property('Identity')?.unpack() ?? base;
            } catch (e) { /* use base */ }
            out.push({base, label});
        }
    } catch (e) { /* none */ }
    return out;
}

class Dialog extends ModalDialog.ModalDialog {
    constructor(title) {
        super({styleClass: 'umb-dialog'});
        this.contentLayout.add_child(new St.Label({text: title, style_class: 'umb-title'}));
    }
}

class NowPlaying {
    constructor(cfg, onRemove) {
        this.cfg = cfg; this.proxy = null; this._art = null;
        this.actor = new St.BoxLayout({style_class: 'umb-widget', visible: false, reactive: true});
        this.art = new St.Icon({icon_name: 'audio-x-generic-symbolic', icon_size: 72});
        const col = new St.BoxLayout({vertical: true, x_expand: true});
        this.title = new St.Label({style_class: 'umb-title', text: ''});
        this.artist = new St.Label({style_class: 'umb-sub', text: ''});
        const ctr = new St.BoxLayout();
        const mk = (icon, m) => {
            const b = new St.Button({style_class: 'umb-btn', child: new St.Icon({icon_name: icon, icon_size: 18})});
            b.connect('clicked', () => this.proxy?.call(m, null, Gio.DBusCallFlags.NONE, -1, null, null));
            return b;
        };
        this.ppIcon = new St.Icon({icon_name: 'media-playback-pause-symbolic', icon_size: 18});
        this.pp = mk('media-playback-pause-symbolic', 'PlayPause'); this.pp.child = this.ppIcon;
        ctr.add_child(mk('media-skip-backward-symbolic', 'Previous'));
        ctr.add_child(this.pp);
        ctr.add_child(mk('media-skip-forward-symbolic', 'Next'));
        const x = new St.Button({style_class: 'umb-btn', child: new St.Icon({icon_name: 'window-close-symbolic', icon_size: 12})});
        x.connect('clicked', () => onRemove(this));
        col.add_child(this.title); col.add_child(this.artist); col.add_child(ctr);
        this.actor.add_child(this.art); this.actor.add_child(col); this.actor.add_child(x);
        this._id = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => { this._tick(); return GLib.SOURCE_CONTINUE; });
    }
    _tick() {
        try {
            if (!this.proxy) {
                const n = busNames().find(x => x.startsWith(PFX + this.cfg.player));
                if (!n) { this.actor.hide(); return; }
                this.proxy = Gio.DBusProxy.new_for_bus_sync(Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, null,
                    n, '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player', null);
            }
            if (!this.proxy.get_name_owner()) { this.proxy = null; this.actor.hide(); return; }
            const playing = this.proxy.get_cached_property('PlaybackStatus')?.unpack() === 'Playing';
            this.actor.visible = playing;
            if (!playing) return;
            const md = this.proxy.get_cached_property('Metadata')?.recursiveUnpack() ?? {};
            const artist = md['xesam:artist'];
            this.title.text = md['xesam:title'] ?? '';
            this.artist.text = Array.isArray(artist) ? artist.join(', ') : (artist ?? '');
            const url = md['mpris:artUrl'];
            if (url && url !== this._art) {
                this._art = url;
                try { this.art.gicon = Gio.FileIcon.new(Gio.File.new_for_uri(url)); } catch (e) { /* keep icon */ }
            }
        } catch (e) { this.proxy = null; }
    }
    destroy() { GLib.source_remove(this._id); this.actor.destroy(); }
}

class Weather {
    constructor(cfg, onRemove) {
        this.cfg = cfg; this._loc = null;
        this.actor = new St.BoxLayout({style_class: 'umb-widget', vertical: true});
        const top = new St.BoxLayout();
        const left = new St.BoxLayout({vertical: true, x_expand: true});
        this.town = new St.Label({style_class: 'umb-title', text: cfg.town});
        this.temp = new St.Label({style_class: 'umb-big', text: '--°'});
        left.add_child(this.town); left.add_child(this.temp);
        const x = new St.Button({style_class: 'umb-btn', child: new St.Icon({icon_name: 'window-close-symbolic', icon_size: 12})});
        x.connect('clicked', () => onRemove(this));
        top.add_child(left); top.add_child(x);
        this.hours = new St.BoxLayout({x_expand: true});
        this.actor.add_child(top); this.actor.add_child(this.hours);
        this._refresh();
        this._id = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1800, () => { this._refresh(); return GLib.SOURCE_CONTINUE; });
    }
    async _refresh() {
        const key = apiKey();
        if (!key) { this.temp.text = '--°'; this.town.text = 'Add AccuWeather key'; return; }
        const base = 'https://dataservice.accuweather.com';
        try {
            if (!this._loc) {
                const r = await fetchJSON(`${base}/locations/v1/cities/search?apikey=${key}&q=${encodeURIComponent(this.cfg.town)}`);
                if (!r.length) { this.town.text = 'Town not found'; return; }
                this._loc = r[0];
            }
            this.town.text = this._loc.LocalizedName;
            const cur = await fetchJSON(`${base}/currentconditions/v1/${this._loc.Key}?apikey=${key}`);
            this.temp.text = Math.round(cur[0].Temperature.Imperial.Value) + '°';
            const hr = await fetchJSON(`${base}/forecasts/v1/hourly/12hour/${this._loc.Key}?apikey=${key}`);
            this.hours.destroy_all_children();
            for (const h of hr.slice(0, 5)) {
                const b = new St.BoxLayout({vertical: true, x_expand: true});
                const t = new Date(h.DateTime).toLocaleTimeString([], {hour: 'numeric'});
                b.add_child(new St.Label({style_class: 'umb-sub', text: t}));
                b.add_child(new St.Label({style_class: 'umb-title', text: Math.round(h.Temperature.Value) + '°'}));
                this.hours.add_child(b);
            }
        } catch (e) { this.town.text = 'Weather unavailable'; }
    }
    destroy() { GLib.source_remove(this._id); this.actor.destroy(); }
}

export default class UmbleekExt extends Extension {
    enable() {
        this._cfg = loadCfg(); this._widgets = [];
        this._col = new St.BoxLayout({vertical: true, style: 'spacing:14px;width:280px;'});
        Main.layoutManager._backgroundGroup.add_child(this._col);
        this._place();
        this._mon = Main.layoutManager.connect('monitors-changed', () => this._place());
        this._cfg.widgets.forEach(w => this._mk(w));

        this._btn = new PanelMenu.Button(0.0, 'Umbleek Widgets', false);
        this._btn.add_child(new St.Icon({icon_name: 'view-grid-symbolic', style_class: 'system-status-icon'}));
        this._btn.menu.addAction('Add Now Playing widget…', () => this._askPlayer());
        this._btn.menu.addAction('Add Weather widget…', () => this._askTown());
        this._btn.menu.addAction('Remove all widgets', () => {
            this._widgets.forEach(w => w.destroy()); this._widgets = [];
            this._cfg.widgets = []; saveCfg(this._cfg);
        });
        Main.panel.addToStatusArea('umbleek-widgets', this._btn);

        // Volume popup replaces the normal volume OSD
        this._mixer = new Gvc.MixerControl({name: 'Umbleek Mixer'}); this._mixer.open();
        this._buildVol();
        const osd = Main.osdWindowManager;
        this._origShow = osd.show.bind(osd);
        osd.show = (mon, icon, label, level, max) => {
            const n = (icon?.get_names?.() ?? [''])[0] ?? '';
            if (n.startsWith('audio-volume')) this._showVol(n, level);
            else this._origShow(mon, icon, label, level, max);
        };

        // Super key opens the app launcher (app grid)
        this._ov = Main.overview.connect('showing', () => {
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                try { Main.overview.dash.showAppsButton.checked = true; } catch (e) { /* ignore */ }
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    disable() {
        delete Main.osdWindowManager.show;
        Main.overview.disconnect(this._ov);
        Main.layoutManager.disconnect(this._mon);
        this._disarm(); this._vol.destroy(); this._mixer.close();
        this._btn.destroy();
        this._widgets.forEach(w => w.destroy()); this._col.destroy();
        session.abort();
        this._widgets = null; this._cfg = null;
    }

    _place() {
        const m = Main.layoutManager.primaryMonitor;
        this._col.set_position(m.x + m.width - 304, m.y + Main.panel.height + 16);
    }
    _mk(c) {
        const rm = w => {
            w.destroy(); this._widgets = this._widgets.filter(x => x !== w);
            this._cfg.widgets = this._cfg.widgets.filter(x => x !== w.cfg); saveCfg(this._cfg);
        };
        const w = c.type === 'nowplaying' ? new NowPlaying(c, rm) : new Weather(c, rm);
        this._widgets.push(w); this._col.add_child(w.actor);
    }
    _add(c) { this._cfg.widgets.push(c); saveCfg(this._cfg); this._mk(c); }

    _askPlayer() {
        const d = new Dialog('Which app’s audio should Now Playing show?');
        const ps = listPlayers();
        if (!ps.length) d.contentLayout.add_child(new St.Label({text: 'No audio apps found. Start playing something first, then try again.'}));
        for (const p of ps) {
            const b = new St.Button({label: p.label, style_class: 'button'});
            b.connect('clicked', () => { this._add({type: 'nowplaying', player: p.base}); d.close(); });
            d.contentLayout.add_child(b);
        }
        d.setButtons([{label: 'Cancel', action: () => d.close(), key: 0}]);
        d.open();
    }
    _askTown() {
        const d = new Dialog('Which town should Weather show?');
        const e = new St.Entry({hint_text: 'e.g. Baraboo', can_focus: true});
        d.contentLayout.add_child(e);
        d.setButtons([
            {label: 'Cancel', action: () => d.close(), key: 0},
            {label: 'Add', default: true, action: () => {
                const t = e.get_text().trim();
                if (t) this._add({type: 'weather', town: t});
                d.close();
            }},
        ]);
        d.open(); e.grab_key_focus();
    }

    _buildVol() {
        this._vol = new St.BoxLayout({style_class: 'umb-vol', vertical: true, reactive: true, visible: false});
        this._head = new St.Button({x_expand: true});
        const hb = new St.BoxLayout({vertical: true, x_expand: true, style: 'spacing:6px;'});
        this._volLabel = new St.Label({style_class: 'umb-title', text: 'Volume'});
        this._barBg = new St.Widget({style_class: 'umb-bar', x_expand: true});
        this._barFill = new St.Widget({style_class: 'umb-fill', style: 'width:0px;'});
        this._barBg.add_child(this._barFill);
        hb.add_child(this._volLabel); hb.add_child(this._barBg);
        this._head.child = hb;
        this._head.connect('clicked', () => this._toggleMixer());
        this._rows = new St.BoxLayout({vertical: true, visible: false, style: 'spacing:8px;'});
        this._vol.add_child(this._head); this._vol.add_child(this._rows);
        this._vol.connect('enter-event', () => this._disarm());
        this._vol.connect('leave-event', () => this._arm(2500));
        Main.layoutManager.addTopChrome(this._vol);
    }
    _showVol(iconName, level) {
        const pct = iconName.includes('muted') ? 0 : Math.round((level ?? 0) * 100);
        this._volLabel.text = iconName.includes('muted') ? 'Volume — muted' : `Volume — ${pct}%`;
        this._barFill.style = `width:${Math.min(pct, 100) * 2.1}px;`;
        const m = Main.layoutManager.primaryMonitor;
        this._vol.visible = true;
        this._vol.set_position(m.x + m.width - 252, m.y + Main.panel.height + 8);
        this._arm(this._rows.visible ? 6000 : 1800);
    }
    _toggleMixer() {
        this._rows.visible = !this._rows.visible;
        if (!this._rows.visible) { this._arm(1200); return; }
        this._rows.destroy_all_children();
        const max = this._mixer.get_vol_max_norm();
        const streams = this._mixer.get_sink_inputs();
        if (!streams.length) this._rows.add_child(new St.Label({style_class: 'umb-sub', text: 'No apps are playing audio'}));
        for (const s of streams) {
            this._rows.add_child(new St.Label({style_class: 'umb-sub', text: s.get_name() || s.get_description() || 'App'}));
            const sl = new Slider(Math.min(s.volume / max, 1));
            sl.connect('notify::value', () => { s.volume = sl.value * max; s.push_volume(); });
            this._rows.add_child(sl);
        }
        this._disarm();
    }
    _arm(ms) {
        this._disarm();
        this._hide = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._vol.visible = false; this._rows.visible = false; this._hide = 0; return GLib.SOURCE_REMOVE;
        });
    }
    _disarm() { if (this._hide) { GLib.source_remove(this._hide); this._hide = 0; } }
}
JSEOF

# ---------------- Desktop settings ----------------
cat > config/includes.chroot/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

cat > config/includes.chroot/etc/dconf/db/local.d/00-umbleek <<'EOF'
[org/gnome/desktop/wm/preferences]
button-layout=':minimize,maximize,close'
titlebar-font='Inter Semi-Bold 11'

[org/gnome/desktop/interface]
enable-animations=true
font-name='Inter 11'
icon-theme='Papirus'
color-scheme='prefer-light'
clock-show-weekday=true

[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true
natural-scroll=true

[org/gnome/shell]
disable-user-extensions=false
enabled-extensions=['dash-to-dock@micxgx.gmail.com','blur-my-shell@aunetx','appindicatorsupport@rgcjonas.gmail.com','umbleek@umbleek.org']
favorite-apps=['org.gnome.Nautilus.desktop','umbrowser.desktop','umbleek-appstore.desktop','wine.desktop','org.gnome.Settings.desktop']

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

echo "Building Umbleek 1.1.0 ISO (takes a while)..."
lb build
echo "Done: $(pwd)/umbleek-amd64.hybrid.iso"
