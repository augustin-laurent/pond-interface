//@ pragma Env QSG_RENDER_LOOP = threaded
import Pond.Localization
import QtQuick
import Quickshell
import Quickshell.Io
import "battery" as Battery
import "calendar" as Calendar
import "settings" as Settings
import "settings/appearance" as Appearance
import "notifications" as Notifications
import Pond.Wallpaper as Wallpaper

ShellRoot {
  id: root
  property bool expanded: true
  Component.onCompleted: Localization.useUserPreferences()

  Shortcuts {}

  FileView {
    path: Quickshell.screens.length
        ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pond-interface/manual-shown"
        : ""
    printErrors: false
    onLoadFailed: error => {
      if (error !== FileViewError.FileNotFound) return;
      Settings.State.open("", "manual");
      Qt.callLater(() => setText("shown\n"));
    }
  }

  IpcHandler {
    target: "sidebar"
    function toggle() { root.expanded = !root.expanded; }
  }

  IpcHandler {
    target: "manual"
    function open() { Settings.State.open("", "manual"); }
  }

  IpcHandler {
    target: "settings"
    function toggle() { Settings.State.toggle(); }
    function open(page: string) {
      if (page && Settings.State.pages.indexOf(page) < 0) return;
      Settings.State.open("", page);
    }
    function close() { Settings.State.close(); }
  }

  Variants {
    model: Quickshell.screens
    delegate: Scope {
      id: screenScope
      required property var modelData
      Wallpaper.Window {
        screen: modelData
        custom: Appearance.State.wallpaperMode === "custom"
        dimmed: Theme.daylight
        imageSource: Appearance.State.wallpaperUrl
      }
      Loader {
        id: barArea
        sourceComponent:
            Appearance.State.barLayout === "bottom" ? bottomBar : sideBar
      }
      Component {
        id: bottomBar
        Bar {
          screen: screenScope.modelData
          expanded: root.expanded
          onToggleRequested: root.expanded = !root.expanded
        }
      }
      Component {
        id: sideBar
        Sidebar {
          screen: screenScope.modelData
          expanded: root.expanded
          onToggleRequested: root.expanded = !root.expanded
        }
      }
      Notifications.ToastWindow { id: toast; bar: barArea.item }
      Notifications.CenterWindow { bar: barArea.item }
      Calendar.Window { bar: barArea.item }
      Battery.Window { bar: barArea.item }
      Battery.Notification { bar: barArea.item; above: toast }
      PanelDismissWindow { bar: barArea.item }
      Settings.Window { menuScreen: modelData }
    }
  }
}
