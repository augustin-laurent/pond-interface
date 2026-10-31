pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root
  objectName: "keyboardFeedback"
  required property var screen
  required property real collapseProgress
  // Set by the bottom bar; feedback then anchors above the strip.
  property var barHost: null
  required property real expandedTopMargin
  readonly property bool collapsed: collapseProgress >= 0.56
  readonly property real cardHeight: 20 + NiriMsg.keyboardLayouts.length * 28
  width: Theme.sidebarCardExpandedWidth
  height: cardHeight
  visible: feedback.active && !collapsed
  onVisibleChanged: if (visible) parent.forceLayout()

  Connections {
    target: NiriMsg
    function onKeyboardLayoutSwitched() {
      if (NiriMsg.focusedOutputName !== root.screen.name) return;
      feedback.active = true;
      dismissTimer.restart();
    }
  }
  Timer { id: dismissTimer; interval: 1200; onTriggered: feedback.active = false }

  LazyLoader {
    id: feedback
    PanelWindow {
      screen: root.screen
      color: "transparent"
      BackgroundEffect.blurRegion: Theme.daylight ? card.blurRegion : null
      implicitWidth: Theme.sidebarCardExpandedWidth + (root.collapsed ? 134 : 0)
      implicitHeight: root.barHost ? root.cardHeight
          : root.cardHeight + (root.collapsed ? 107 : 0)
      anchors { left: true; top: !root.collapsed && !root.barHost; bottom: root.collapsed || !!root.barHost }
      margins.left: root.barHost
          ? Math.round((screen.width - implicitWidth) / 2)
          : root.collapsed ? Math.round((screen.width + Theme.sidebarOuterMargin
              + Theme.sidebarCardCollapsedWidth - implicitWidth) / 2) : Theme.sidebarOuterMargin
      margins.top: root.collapsed && !root.barHost ? 0 : Math.round(root.expandedTopMargin)
      margins.bottom: root.barHost ? Math.round(root.barHost.stripHeight + 10) : 0
      onMarginsChanged: contentItem.Window.window?.requestUpdate()
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "pond-keyboard"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Shadow {
        visible: root.collapsed
        anchors.fill: card
        cornerRadius: card.radius
        shadows: PanelStyle.controlShadows
      }
      Card {
        id: card
        objectName: "keyboardLayoutCard"
        x: root.collapsed ? 67 : 0
        y: root.collapsed && !root.barHost ? 67 : 0
        width: Theme.sidebarCardExpandedWidth; height: root.cardHeight
        radius: PanelStyle.rowRadius
        classicColor: PanelStyle.surface
        Column {
          x: 16; y: 16; width: parent.width - 32; spacing: 12
          Repeater {
            model: NiriMsg.keyboardLayouts
            delegate: Item {
              id: row
              required property string modelData
              required property int index
              width: card.width - 32; height: 16
              Accessible.role: Accessible.StaticText
              Accessible.name: modelData + (index === NiriMsg.keyboardLayoutIndex ? ", active" : "")
              Text {
                id: label
                width: parent.width - 24
                y: (parent.height + metrics.capitalHeight) / 2 - baselineOffset
                text: row.modelData; elide: Text.ElideRight
                color: "#f8f9f9"; opacity: 0.6
                font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                FontMetrics { id: metrics; font: label.font }
              }
              Rectangle {
                anchors.right: parent.right
                width: 16; height: 16; radius: 8
                color: Theme.sidebarInnerOutline
                Rectangle {
                  anchors.centerIn: parent
                  width: 12; height: 12; radius: 6
                  color: "white"
                  visible: row.index === NiriMsg.keyboardLayoutIndex
                }
              }
            }
          }
        }
      }
    }
  }
}
