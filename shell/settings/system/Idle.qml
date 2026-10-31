pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
  id: root
  readonly property var defaults: ({lock: 0, display: 0, sleep: 0})
  readonly property var choices: [0, 60, 120, 180, 300, 600, 900, 1200, 1500, 1800, 2700, 3600, 7200, 10800, 14400, 18000]
  readonly property var options: choices.map(seconds => ({label: label(seconds), value: String(seconds)}))
  property var timeouts: ({pluggedIn: defaults, battery: defaults})
  readonly property string source: UPower.onBattery ? "battery" : "pluggedIn"
  readonly property var current: timeouts[source]

  function label(seconds) {
    if (!seconds) return qsTrId("settings.never");
    const hours = seconds >= 3600;
    return hours ? qsTrId("time.hours", Math.round(seconds / 3600))
        : qsTrId("time.minutes", Math.round(seconds / 60));
  }
  function set(power, key, seconds) {
    timeouts = Object.assign({}, timeouts, {[power]: Object.assign({}, timeouts[power], {[key]: seconds})});
    file.setText(JSON.stringify(timeouts) + "\n");
  }

  FileView {
    id: file
    path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/pond-interface/idle.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const saved = JSON.parse(text());
        root.timeouts = {
          pluggedIn: Object.assign({}, root.defaults, saved.pluggedIn),
          battery: Object.assign({}, root.defaults, saved.battery)
        };
      } catch (e) { console.warn("Idle timeouts:", e); }
    }
  }
}
