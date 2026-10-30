pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "audio" as Audio
import "bluetooth" as Bluetooth
import "settings" as Settings
import "wifi" as Wifi
import "calendar" as Calendar
import "media" as Media
import "minimap" as Minimap
import "notifications" as Notifications
import "installs" as Installs
import Pond.Screenshot as Screenshot

// Bottom-dock variant of the sidebar. The same modules run unmodified in a
// horizontal strip along the screen's bottom edge; hover panels, popups and
// feedback cards extend upward instead of to the right.
PanelWindow {
  id: root
  required property bool expanded
  property string popup: ""
  property real collapseProgress: expanded ? 0 : 1
  signal toggleRequested
  readonly property real cardWidth: Theme.lerp(Theme.sidebarCardExpandedWidth,
      Theme.sidebarCardCollapsedWidth, Theme.collapseWidth(collapseProgress))
  readonly property string barLayout: "bottom"

  // Reserved strip: outer margin above and below the tallest visible row.
  readonly property real stripHeight: Theme.sidebarOuterMargin * 2
      + Math.max(mainRow.height, auxRow.height)
  // Window coordinate of the strip's top edge (the window is full-width).
  readonly property real stripTop: height - stripHeight
  readonly property real clockCenterX: mainRow.x + timeCard.x + timeCard.width / 2
  readonly property real notificationCardCenterX: mainRow.x + notificationCard.x
      + notificationCard.width / 2
  // Compatibility value for the sidebar-mode notification center; unused here.
  readonly property real notificationCardCenterY: stripTop + notificationCard.height / 2

  readonly property bool panelOpen: wifiPanel.opened || audioPanel.opened || bluetoothPanel.opened
  readonly property var activePanel: wifiPanel.opened ? wifiPanel : audioPanel.opened ? audioPanel : bluetoothPanel.opened ? bluetoothPanel : null
  property string pendingPanel: ""
  readonly property var panels: ({wifi: wifiPanel, audio: audioPanel, bluetooth: bluetoothPanel})

  function dismissPanels() {
    panelSwitchDelay.stop();
    pendingPanel = "";
    for (const panel of Object.values(panels)) panel.closeAll();
  }

  function togglePanel(name) {
    const panel = panels[name];
    if (!panel) return;
    const wasOpen = panel.opened;
    const wasVisible = Object.values(panels).some(item => item.visible);
    dismissPanels();
    if (wasOpen) return;
    Settings.State.close();
    popup = "";
    Notifications.State.closePanel();
    if (wasVisible) {
      pendingPanel = name;
      panelSwitchDelay.restart();
    } else panel.open();
  }

  function togglePopup(name) {
    dismissPanels();
    Notifications.State.closePanel();
    popup = popup === name ? "" : name;
  }

  Timer {
    id: panelSwitchDelay
    interval: 200
    onTriggered: {
      const panel = root.panels[root.pendingPanel];
      if (panel) panel.open();
      root.pendingPanel = "";
    }
  }

  Connections {
    target: Settings.State
    function onOpening() {
      root.dismissPanels();
      root.popup = "";
      Notifications.State.closePanel();
    }
  }
  Connections {
    target: Notifications.State
    function onPanelOpenChanged() { if (Notifications.State.panelOpen) root.popup = ""; }
  }
  Connections {
    target: Bluetooth.State
    function onPanelCommand(command, outputName) {
      if (outputName !== root.screen.name) return;
      if (command === "close") bluetoothPanel.closeAll();
      else if (command === "toggle" || !bluetoothPanel.opened) root.togglePanel("bluetooth");
    }
  }
  Connections {
    target: Audio.State
    function onKeyboardOutputVolumeChanged(value) {
      if (NiriMsg.focusedOutputName === "" || root.screen.name === NiriMsg.focusedOutputName)
        controls.showKeyboardVolume();
    }
  }

  color: "transparent"
  BackgroundEffect.blurRegion: Theme.daylight ? cardBlur : null
  onStripHeightChanged: cardBlur.changed()
  Region {
    id: cardBlur
    regions: [timeCard.blurRegion, workspacesCard.blurRegion, mediaCard.blurRegion,
      notificationCard.blurRegion, installsCard.blurRegion, controls.blurRegion]
  }
  // Only the input area tracks the strip; everything else is click-through.
  mask: Region {
    width: root.width
    height: root.height
    // The window reserves room for panels above the strip; without one open,
    // everything above the strip passes clicks through to the background.
    Region {
      y: 0
      width: root.width
      height: root.panelOpen && root.activePanel
          ? Math.max(0, root.activePanel.y)
          : Math.max(0, root.height - stripHeight)
      intersection: Intersection.Subtract
    }
    // Let the background receive clicks between the two card groups.
    Region {
      x: Math.ceil(mainRow.x + mainRow.width)
      width: Math.max(0, Math.floor(auxRow.x) - x)
      y: Math.max(0, root.height - stripHeight)
      height: stripHeight
      intersection: Intersection.Subtract
    }
    // Region.item can retain the opening animation's scaled bounds and leave
    // the close button outside the input mask. Track the panel bounds directly.
    Region {
      x: root.activePanel ? root.activePanel.x : 0
      y: root.activePanel ? root.activePanel.y : 0
      width: root.activePanel ? root.activePanel.width : 0
      height: root.activePanel ? root.activePanel.height : 0
    }
  }
  anchors { left: true; right: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "pond-bottom-bar"
  WlrLayershell.keyboardFocus: workspacesCard.dragSession.active
      ? WlrKeyboardFocus.Exclusive : panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Normal
  exclusiveZone: stripHeight
  Behavior on collapseProgress { Motion {} }

  // Window height must contain the bar plus any panel opened above it; the
  // layer reservation still reflects the strip alone, so tiles never move.
  implicitHeight: Math.ceil(Math.max(
      Theme.sidebarOuterMargin * 2 + 168,
      wifiPanel.visible ? stripHeight + Theme.sidebarCardGap + wifiPanel.height + 67 : 0,
      audioPanel.visible ? stripHeight + Theme.sidebarCardGap + audioPanel.height + 67 : 0,
      bluetoothPanel.visible ? stripHeight + Theme.sidebarCardGap + bluetoothPanel.height + 67 : 0))

  Row {
    id: mainRow
    anchors {
      left: parent.left; leftMargin: Theme.sidebarOuterMargin
      bottom: parent.bottom; bottomMargin: Theme.sidebarOuterMargin
    }
    spacing: Theme.sidebarCardGap

    Calendar.Clock {
      id: timeCard
      width: root.cardWidth
      y: parent.height - height
      collapseProgress: root.collapseProgress
      onClicked: root.togglePopup("calendar")
      onBatteryClicked: root.togglePopup("battery")
    }

    Minimap.Map {
      id: workspacesCard
      screen: root.screen
      collapseProgress: root.collapseProgress
      // The map grows in rows, which stack vertically inside the strip; cap it
      // to half the screen minus the reserved strip.
      maximumHeight: Math.max(64, root.screen.height * 0.5 - root.stripHeight)
      onFocusRequested: index => NiriMsg.focusWorkspace(index)
      onWindowRequested: windowId => NiriMsg.focusWindow(windowId)
      onAddRequested: workspaceId => NiriMsg.openLauncher(workspaceId)
      y: parent.height - height
    }

    Media.Player {
      id: mediaCard
      collapseProgress: root.collapseProgress
      y: parent.height - height
    }

    Notifications.SidebarCard {
      id: notificationCard
      width: root.cardWidth
      y: parent.height - height
      collapseProgress: root.collapseProgress
      onPanelRequested: { root.dismissPanels(); Notifications.State.togglePanel(root.screen.name); }
    }

    Installs.SidebarCard {
      id: installsCard
      width: root.cardWidth
      y: parent.height - height
      collapseProgress: root.collapseProgress
    }
    KeyboardFeedback {
      id: keyboardFeedback
      screen: root.screen
      barHost: root
      collapseProgress: root.collapseProgress
      expandedTopMargin: mainRow.y + keyboardFeedback.y
    }
  }

  TapHandler {
    enabled: root.panelOpen
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    gesturePolicy: TapHandler.DragThreshold
    property var panelAtPress: null
    onPressedChanged: if (pressed) panelAtPress = root.activePanel
    onTapped: eventPoint => {
      const panel = root.activePanel;
      if (!panel || panel !== panelAtPress) return;
      const x = eventPoint.position.x - panel.x;
      const y = eventPoint.position.y - panel.y;
      if (x < 0 || x > panel.width || y < 0 || y > panel.height)
        root.dismissPanels();
    }
  }

  Wifi.Panel {
    id: wifiPanel
    z: 80
    anchors { right: parent.right; bottom: parent.bottom }
    anchors.rightMargin: Theme.sidebarOuterMargin
    anchors.bottomMargin: root.stripHeight + Theme.sidebarCardGap
  }

  Audio.Panel {
    id: audioPanel
    z: 80
    anchors { right: parent.right; bottom: parent.bottom }
    anchors.rightMargin: Theme.sidebarOuterMargin
    anchors.bottomMargin: root.stripHeight + Theme.sidebarCardGap
  }

  Bluetooth.Panel {
    id: bluetoothPanel
    z: 80
    anchors { right: parent.right; bottom: parent.bottom }
    anchors.rightMargin: Theme.sidebarOuterMargin
    anchors.bottomMargin: root.stripHeight + Theme.sidebarCardGap
  }

  Row {
    id: auxRow
    anchors {
      right: parent.right; rightMargin: Theme.sidebarOuterMargin
      bottom: parent.bottom; bottomMargin: Theme.sidebarOuterMargin
    }
    spacing: Theme.sidebarCardGap
    Screenshot.Preview {
      width: root.cardWidth
      y: parent.height - height
      outputName: root.screen.name
      collapsed: root.collapseProgress > 0.5
    }
    BrightnessFeedback {
      screen: root.screen
      barHost: root
      collapseProgress: root.collapseProgress
      expandedBottomMargin: Theme.sidebarOuterMargin + controls.height + 8
      y: parent.height - height
    }
    BottomControls {
      id: controls
      y: parent.height - height
      collapseProgress: root.collapseProgress
      barHost: root
      wifiOpen: wifiPanel.opened
      soundOpen: audioPanel.opened
      settingsOpen: Settings.State.opened && Settings.State.outputName === root.screen.name
      onWifiClicked: root.togglePanel("wifi")
      onSoundClicked: root.togglePanel("audio")
      onSettingsClicked: Settings.State.toggle(root.screen.name)
      onCollapseClicked: root.toggleRequested()
    }
  }
}
