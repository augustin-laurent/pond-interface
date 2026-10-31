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
  readonly property real moduleHeight: timeCard.height

  readonly property real stripHeight: Theme.sidebarOuterMargin * 2
      + Math.max(mainRow.height, auxRow.height)
  // Window coordinate of the strip's top edge (the window is full-width).
  readonly property real stripTop: height - stripHeight
  readonly property real clockCenterX: mainRow.x + timeCard.x + timeCard.width / 2
  readonly property real clockTop: mainRow.y + timeCard.y
  readonly property real notificationCardTop: mainRow.y + notificationCard.y
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
    Settings.State.close();
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
    function onPanelOpenChanged() {
      if (Notifications.State.panelOpen) { root.dismissPanels(); root.popup = ""; }
    }
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
  // Card positions are window-relative: refresh the blur region whenever the
  // surface resizes for a panel, otherwise a stale card-shaped patch is left
  // behind at the old coordinates.
  onStripHeightChanged: cardBlur.changed()
  onHeightChanged: cardBlur.changed()
  Region {
    id: cardBlur
    regions: [timeCard.blurRegion, workspacesCard.blurRegion, mediaCard.blurRegion,
      notificationCard.blurRegion, installsCard.blurRegion, controls.blurRegion]
  }
  // Only the input area tracks the strip; everything else is click-through.
  mask: Region {
    regions: [
      Region { width: workspacesCard.dragSession.active ? root.width : 0; height: workspacesCard.dragSession.active ? root.height : 0 },
      Region { item: mainRow },
      Region { item: auxRow },
      Region { x: wifiPanel.x; y: wifiPanel.y; width: wifiPanel.visible ? wifiPanel.width : 0; height: wifiPanel.visible ? wifiPanel.height : 0 },
      Region { x: audioPanel.x; y: audioPanel.y; width: audioPanel.visible ? audioPanel.width : 0; height: audioPanel.visible ? audioPanel.height : 0 },
      Region { x: bluetoothPanel.x; y: bluetoothPanel.y; width: bluetoothPanel.visible ? bluetoothPanel.width : 0; height: bluetoothPanel.visible ? bluetoothPanel.height : 0 }
    ]
  }
  anchors { left: true; right: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "pond-bottom-bar"
  WlrLayershell.keyboardFocus: workspacesCard.dragSession.active
      ? WlrKeyboardFocus.Exclusive : panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Normal
  exclusiveZone: 48 + Theme.sidebarOuterMargin * 2
  Behavior on collapseProgress { Motion {} }
  implicitHeight: screen ? screen.height : 0

  Row {
    id: mainRow
    anchors {
      left: parent.left; leftMargin: Theme.sidebarOuterMargin
      bottom: parent.bottom; bottomMargin: Theme.sidebarOuterMargin
    }
    spacing: Theme.sidebarCardGap

    Calendar.Clock {
      id: timeCard
      horizontal: true
      y: parent.height - height
      collapseProgress: root.collapseProgress
      onClicked: root.togglePopup("calendar")
      onBatteryClicked: root.togglePopup("battery")
    }

    Minimap.HorizontalMap {
      id: workspacesCard
      rowHeight: root.moduleHeight
      screen: root.screen
      collapseProgress: root.collapseProgress
      maximumWidth: Math.max(48, auxRow.x - Theme.sidebarCardGap - mainRow.x
          - timeCard.width - (mediaCard.visible ? mediaCard.width + mainRow.spacing : 0)
          - notificationCard.width - (installsCard.visible ? installsCard.width + mainRow.spacing : 0)
          - (keyboardFeedback.visible ? keyboardFeedback.width + mainRow.spacing : 0)
          - mainRow.spacing * 2)
      onFocusRequested: (index, workspaceId) => NiriMsg.focusWorkspaceById(workspaceId)
      onWindowRequested: windowId => NiriMsg.focusWindow(windowId)
      onAddRequested: workspaceId => NiriMsg.openLauncher(workspaceId)
      y: parent.height - height
    }

    Media.Player {
      id: mediaCard
      rowHeight: root.moduleHeight
      horizontal: true
      collapseProgress: root.collapseProgress
      y: parent.height - height
    }

    Notifications.SidebarCard {
      id: notificationCard
      horizontal: true
      rowHeight: root.moduleHeight
      y: parent.height - height
      collapseProgress: root.collapseProgress
      onPanelRequested: { root.dismissPanels(); Notifications.State.togglePanel(root.screen.name); }
    }

    Installs.SidebarCard {
      id: installsCard
      rowHeight: root.moduleHeight
      horizontal: true
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
    anchors.bottomMargin: root.height - (auxRow.y + controls.y) + Theme.sidebarCardGap
  }

  Audio.Panel {
    id: audioPanel
    z: 80
    anchors { right: parent.right; bottom: parent.bottom }
    anchors.rightMargin: Theme.sidebarOuterMargin
    anchors.bottomMargin: root.height - (auxRow.y + controls.y) + Theme.sidebarCardGap
  }

  Bluetooth.Panel {
    id: bluetoothPanel
    z: 80
    anchors { right: parent.right; bottom: parent.bottom }
    anchors.rightMargin: Theme.sidebarOuterMargin
    anchors.bottomMargin: root.height - (auxRow.y + controls.y) + Theme.sidebarCardGap
  }

  Row {
    id: auxRow
    anchors {
      right: parent.right; rightMargin: Theme.sidebarOuterMargin
      bottom: parent.bottom; bottomMargin: Theme.sidebarOuterMargin
    }
    spacing: Theme.sidebarCardGap
    Screenshot.Preview {
      expandedHeight: timeCard.expandedHeight
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
      rowHeight: root.moduleHeight
      horizontal: true
      y: parent.height - height
      collapseProgress: root.collapseProgress
      barHost: root
      wifiOpen: wifiPanel.opened
      bluetoothOpen: bluetoothPanel.opened
      soundOpen: audioPanel.opened
      settingsOpen: Settings.State.opened && Settings.State.outputName === root.screen.name
      onWifiClicked: root.togglePanel("wifi")
      onBluetoothClicked: root.togglePanel("bluetooth")
      onSoundClicked: root.togglePanel("audio")
      onSettingsClicked: Settings.State.toggle(root.screen.name)
      onCollapseClicked: root.toggleRequested()
    }
  }
}
