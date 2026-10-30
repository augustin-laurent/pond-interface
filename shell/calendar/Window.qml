pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Calendar
import ".." as Shell

PanelWindow {
  id: root
  required property var bar
  readonly property bool bottomBar: bar ? bar.barLayout === "bottom" : false
  readonly property real panelLeft: Shell.Theme.sidebarOuterMargin + bar.cardWidth + 10
  readonly property real panelTop: Shell.Theme.sidebarOuterMargin

  screen: bar ? bar.screen : null
  visible: bar ? bar.popup === "calendar" : false
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-calendar-" + (screen ? screen.name : "unknown")
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  mask: Region {
    intersection: Intersection.Subtract
    regions: root.bar ? [root.bar.mask] : []
  }

  onVisibleChanged: {
    if (visible) {
      calendar.goToday();
      calendar.forceActiveFocus();
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: if (root.bar) root.bar.popup = ""
  }

  Calendar.Card {
    id: calendar
    x: root.bottomBar
        ? Math.max(Shell.Theme.sidebarOuterMargin,
                   Math.min(root.bar.clockCenterX - calendar.width / 2,
                            width - Shell.Theme.sidebarOuterMargin - calendar.width))
        : root.panelLeft
    y: root.bottomBar
        ? root.height - root.bar.stripHeight - 10 - calendar.height
        : root.panelTop
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape && root.bar) root.bar.popup = "";
      else if (event.key === Qt.Key_PageUp) moveMonth(-1);
      else if (event.key === Qt.Key_PageDown) moveMonth(1);
      else if (event.key === Qt.Key_Home) goToday();
      else return;
      event.accepted = true;
    }
  }
}
