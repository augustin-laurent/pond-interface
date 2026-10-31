pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Battery
import ".." as Shell

PanelWindow {
  id: root
  required property var bar
  readonly property bool bottomBar: bar ? bar.barLayout === "bottom" : false

  screen: bar ? bar.screen : null
  visible: bar ? bar.popup === "battery" : false
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-battery-" + (screen ? screen.name : "unknown")
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  mask: Region {
    intersection: Intersection.Subtract
    regions: root.bar ? [root.bar.mask] : []
  }

  onVisibleChanged: if (visible) card.forceActiveFocus();

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: if (root.bar) root.bar.popup = ""
  }

  Battery.Card {
    id: card
    x: root.bottomBar && root.bar
        ? Math.max(Shell.Theme.sidebarOuterMargin,
                   Math.min(root.bar.clockCenterX - card.width / 2,
                            width - Shell.Theme.sidebarOuterMargin - card.width))
        : root.bar ? Shell.Theme.sidebarOuterMargin + root.bar.cardWidth + 10 : 0
    y: root.bottomBar
        ? Math.max(Shell.Theme.sidebarOuterMargin, root.bar.clockTop - 10 - card.height)
        : Shell.Theme.sidebarOuterMargin
    Keys.onEscapePressed: if (root.bar) root.bar.popup = ""
  }
}
