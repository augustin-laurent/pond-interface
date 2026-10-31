import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Notifications
import ".." as Shell

// Collapsed-sidebar arrival surface. Its left edge tracks the animated
// sidebar edge, so it never temporarily overlaps and then jumps with the
// compositor's work-area change. In the bottom layout it instead rises
// from just above the clock in the bottom bar.
PanelWindow {
  id: root

  required property var bar

  readonly property string outputName: bar && bar.screen ? bar.screen.name : ""
  readonly property bool bottomBar: bar ? bar.barLayout === "bottom" : false
  // Keep the notification above the clock and inside the output.
  readonly property real toastLeft: !bottomBar || !bar ? 0 : Math.max(
      Notifications.Style.desktopMargin,
      Math.min(bar.clockCenterX - Notifications.Style.interactiveWidth / 2,
               screen.width - Notifications.Style.desktopMargin
                   - Notifications.Style.interactiveWidth))
  readonly property bool outputMatches: Notifications.State.transientOutputName === ""
      || Notifications.State.transientOutputName === outputName
  readonly property bool requested: outputMatches
      && Notifications.State.transientVisible

  property real reveal: requested ? 1 : 0
  property var displayedNotification: ({})

  screen: bar ? bar.screen : null
  visible: requested || reveal > 0.001
  color: "transparent"
  implicitWidth: Notifications.Style.interactiveWidth
  implicitHeight: toastCard.implicitHeight

  anchors {
    left: true
    top: !root.bottomBar
    bottom: root.bottomBar
  }
  margins {
    left: root.bottomBar ? root.toastLeft
        : Math.round(Shell.Theme.sidebarOuterMargin + bar.cardWidth
                     + Notifications.Style.desktopMargin)
    top: root.bottomBar ? 0 : Notifications.Style.desktopMargin
    bottom: root.bottomBar
        ? Math.round((bar ? bar.height - bar.clockTop : 0) + Notifications.Style.desktopMargin)
        : 0
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-notification-toast-"
      + (outputName || "unknown")
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  Behavior on reveal { Shell.Motion { duration: Notifications.Style.panelDuration } }

  Component.onCompleted: {
    if (Notifications.State.currentTransient)
      displayedNotification = Notifications.State.currentTransient;
  }

  Connections {
    target: Notifications.State
    function onCurrentTransientChanged() {
      if (Notifications.State.currentTransient)
        root.displayedNotification = Notifications.State.currentTransient;
    }
  }

  Notifications.Card {
    id: toastCard
    x: root.bottomBar ? 0 : (1 - root.reveal) * -4
    y: root.bottomBar ? (1 - root.reveal) * 6 : 0
    width: Notifications.Style.interactiveWidth
    height: implicitHeight
    opacity: root.reveal
    notification: root.displayedNotification
    onActivated: Notifications.State.activate(root.displayedNotification)
    onDismissed: Notifications.State.remove(root.displayedNotification)
  }
}
