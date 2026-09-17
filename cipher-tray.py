#!/usr/bin/env python3
"""
cipher-tray - a small tray icon that opens a Kanboard-style floating chat
panel (bottom-right, always-on-top, close-to-tray) pointed at Cipher over Matrix.

Deps (Debian/Ubuntu, Cinnamon/MATE):
  apt install python3-gi gir1.2-webkit2-4.1 gir1.2-appindicator3-0.1 gir1.2-gtk-3.0
"""
import json
import os
import sys
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, Gdk, GLib, WebKit2  # noqa: E402

CONFIG = os.path.join(os.path.expanduser("~"), ".config", "cipher-tray.json")
HOME_DIR = os.path.expanduser("~")

# Default URL: your Matrix DM with Cipher. Change it in the config file if needed.
DEFAULT_URL = "https://board.utkarshraj.work/cinny/#/dm/@cipher:utkarshraj.work"


class CipherTray:
    def __init__(self):
        self.url = self._load_url()

        # ---- persistent state ----
        self.geom = self._load_geom()
        self.visible = False

        # ---- the app window ----
        self.win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
        self.win.set_title("Cipher")
        self.win.set_default_size(self.geom[2], self.geom[3])
        self.win.set_keep_above(True)          # always on top
        self.win.set_decorated(False)          # borderless = chat bubble look
        self.win.set_type_hint(Gdk.WindowTypeHint.DIALOG)  # float above windows

        try:
            self.win.set_icon_name("chat")
        except Exception:
            pass

        self.web = WebKit2.WebView()
        self.web.load_uri(self.url)
        self.win.add(self.web)
        self.win.connect("delete-event", self._on_delete)
        self.win.connect("configure-event", self._on_configure)

        # drag-to-move on borderless window
        self.win.connect("button-press-event", self._on_press)
        self.win.connect("button-release-event", self._on_release)
        self._press_xy = None

        # ---- start hidden (the tray icon is the launcher) ----
        self.win.hide()

        # ---- tray icon ----
        self.tray = self._build_tray()

    # ------------------------------------------------------------------ utils
    def _load_url(self):
        try:
            with open(CONFIG) as f:
                return json.load(f).get("url", DEFAULT_URL)
        except Exception:
            return DEFAULT_URL

    def _load_geom(self):
        try:
            with open(CONFIG) as f:
                g = json.load(f).get("geometry", {})
                return (g.get("x", 40), g.get("y", 40), g.get("w", 380), g.get("h", 560))
        except Exception:
            return (40, 40, 380, 560)

    def _save_geom(self, x, y, w, h):
        try:
            with open(CONFIG, "w") as f:
                json.dump({"url": self.url, "geometry": {"x": x, "y": y, "w": w, "h": h}}, f, indent=2)
        except Exception:
            pass

    # ------------------------------------------------------------------ window
    def _on_delete(self, *a):
        # close = hide to tray, don't quit
        self.win.hide()
        self.visible = False
        return True

    def _on_configure(self, *a):
        # persist position/size so it returns to the same spot next launch
        if self.win.get_window() is not None:
            x, y = self.win.get_position()
            w, h = self.win.get_size()
            self._save_geom(x, y, w, h)
        return False

    def _on_press(self, win, ev):
        if ev.button == 1:
            self._press_xy = (ev.x_root, ev.y_root, win.get_position())
        return False

    def _on_release(self, win, ev):
        if ev.button == 1 and self._press_xy:
            _, _, (ox, oy) = self._press_xy
            wx, wy = self._start_move_to(win, ev)
            if wx is None:
                win.move(ox + int(ev.x_root) - self._press_xy[0],
                         oy + int(ev.y_root) - self._press_xy[1])
            self._press_xy = None
        return False

    def _start_move_to(self, win, ev):
        # GTK begin_move_drag for reliable dragging on MATE/Cinnamon
        try:
            win.begin_move_drag(ev.button, int(ev.x_root), int(ev.y_root),
                                ev.get_time())
            return (1, 1)
        except Exception:
            return (None, None)

    def _toggle(self, *a):
        if self.visible:
            self.win.hide()
            self.visible = False
        else:
            self._dock_bottom_right()
            self.win.show()
            self.win.present()
            self.visible = True

    def _dock_bottom_right(self):
        # only force dock when first shown; keep user-placed position afterwards
        scr = self.win.get_screen()
        wa = scr.get_monitor_workarea(scr.get_primary_monitor())
        w, h = self.win.get_size()
        self.win.move(wa.x + wa.width - w - 16, wa.y + wa.height - h - 16)

    # ------------------------------------------------------------------ tray
    def _build_tray(self):
        try:
            gi.require_version("AyatanaAppIndicator3", "0.1")
            from gi.repository import AyatanaAppIndicator3 as AI
            ind = AI.Indicator.new("cipher-tray", "chat-symbolic",
                                   AI.IndicatorCategory.APPLICATION_STATUS)
            ind.set_status(AI.IndicatorStatus.ACTIVE)
            menu = Gtk.Menu()
            for label, cb in [("Open / hide panel", self._toggle),
                              ("Reload", self._reload),
                              ("Quit", self._quit)]:
                it = Gtk.MenuItem(label=label)
                it.connect("activate", cb)
                menu.append(it)
            menu.show_all()
            ind.set_menu(menu)
            return ind
        except Exception as e:
            print("cipher-tray: appindicator unavailable (%s); no tray icon" % e, file=sys.stderr)
            return None

    def _reload(self, *a):
        self.web.reload()

    def _quit(self, *a):
        self.win.destroy()
        Gtk.main_quit()


def main():
    # GTK needs a DISPLAY; on Cinnamon/MATE this is set when launched from the tray
    if not os.environ.get("DISPLAY"):
        print("cipher-tray: no DISPLAY - start it from your desktop session", file=sys.stderr)
        sys.exit(1)
    app = CipherTray()
    Gtk.main()


if __name__ == "__main__":
    main()
