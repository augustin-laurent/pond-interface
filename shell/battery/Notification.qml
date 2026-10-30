import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "." as Battery
import ".." as Shell

PanelWindow {
  id: root
  required property var bar
  required property var above
  readonly property bool bottomBar: bar ? bar.barLayout === "bottom" : false
  screen: bar ? bar.screen : null
  visible: bar ? Battery.State.alert > 0 && bar.collapseProgress > 0.42 : false
  color: "transparent"
  implicitWidth: card.width + 68
  implicitHeight: card.height + 145
  mask: Region { item: card }

  anchors { left: true; top: !root.bottomBar; bottom: root.bottomBar }
  margins {
    left: root.bar ? root.bottomBar
        ? 20 - card.x
        : Math.round(Shell.Theme.sidebarOuterMargin + root.bar.cardWidth + 20) - card.x
        : 0
    // Sidebar layout: chips stack below the toast at the top-left. Bottom
    // layout: rise from above the bar, stacking on top of the toast so the
    // two never overlap.
    top: root.bottomBar ? 0 : (above.visible ? 20 + above.implicitHeight : 20) - card.y
    bottom: root.bottomBar
        ? Math.round((bar ? bar.stripHeight : 0) + 10
                     + (above.visible ? above.implicitHeight + 12 : 0))
        : 0
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-battery-alert-" + (screen ? screen.name : "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  Item {
    id: card
    x: 34
    y: 14
    width: 140
    height: 34

    Shell.Shadow {
      anchors.fill: parent
      cornerRadius: 8
      shadows: Shell.PanelStyle.controlShadows
    }

    Rectangle {
      anchors.fill: parent
      radius: 8
      color: Battery.State.lowSurface
    }

    FontMetrics { id: metrics; font: label.font }

    Text {
      id: label
      x: 12
      y: (parent.height - metrics.capitalHeight) / 2 + metrics.capitalHeight - baselineOffset
      text: qsTrId("pond.battery_at_1").replace("%1", Battery.State.level)
      color: Battery.State.lowColor
      font.family: Shell.Theme.fontFamily
      font.weight: Font.Medium
      font.pixelSize: 13
    }

    Rectangle {
      x: 111
      y: 5
      width: 24
      height: 24
      radius: 4
      color: dismiss.hovered ? Qt.alpha(Battery.State.lowColor, 0.1) : "transparent"
    }

    Shell.IconButton {
      id: dismiss
      x: 111
      y: 5
      iconSource: Qt.resolvedUrl("../assets/battery/dismiss.svg")
      iconWidth: 24
      iconHeight: 24
      restingOpacity: 0.3
      animateGlyphOpacity: false
      layer.enabled: true
      layer.effect: MultiEffect { colorization: 1; colorizationColor: Battery.State.lowColor }
      onClicked: Battery.State.alert = 0
      Accessible.role: Accessible.Button
      Accessible.name: qsTrId("pond.dismiss")
      Accessible.onPressAction: Battery.State.alert = 0
    }
  }
}
