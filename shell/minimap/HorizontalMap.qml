pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "." as Minimap
import ".." as Shell

Shell.Card {
  id: root
  objectName: "workspaceMap"
  property var screen: null
  property bool vertical: false
  property real maximumHeight: 10000
  property real collapseProgress: 0
  property real maximumWidth: 400
  property real rowHeight: 48
  readonly property real workspaceIconGap: 4
  readonly property alias dragSession: session
  readonly property real expandedAmount: 1 - Shell.Theme.collapseWidth(collapseProgress)
  signal focusRequested(int workspaceIndex, var workspaceId)
  signal windowRequested(var windowId)
  signal addRequested(var workspaceId)

  function activateWorkspace(workspaceId, workspaceIndex, isActive) {
    if (session.active || session.resetting || Shell.NiriMsg.workspaceModeBusy) return;
    if (isActive) Shell.NiriMsg.cycleWorkspaceMode(workspaceId);
    else focusRequested(workspaceIndex, workspaceId);
  }

  readonly property bool compact: collapseProgress >= 0.56
  readonly property int visibleCount: {
    let count = 0;
    for (let i = 0; i < Shell.NiriMsg.workspaceRows.count; i++) {
      const row = Shell.NiriMsg.workspaceRows.get(i);
      if (!screen || row.outputName === "" || row.outputName === screen.name) count++;
    }
    return count;
  }
  readonly property real naturalWidth: {
    let result = 40;
    for (let i = 0; i < groups.count; i++) {
      const group = groups.itemAt(i);
      if (group?.visible) result = Math.max(result, group.width);
    }
    return result;
  }
  width: vertical ? 48 + 108 * expandedAmount
      : Math.min(maximumWidth, compact ? visibleCount * 44 + 4 : naturalWidth + 16)
  height: vertical ? Math.min(maximumHeight, visibleCount * 44 - 4 + (compact ? 8 : 16)) : rowHeight
  radius: Shell.Theme.daylight ? 16 - 4 * expandedAmount : Shell.Theme.sidebarCardRadius
  focus: session.active
  Keys.onEscapePressed: session.cancel()
  onCollapseProgressChanged: if (collapseProgress > 0 && session.held) session.cancel()
  onWidthChanged: Qt.callLater(revealActive)
  onCompactChanged: { viewport.contentX = 0; viewport.contentY = 0; Qt.callLater(revealActive); }

  function revealActive() {
    if (session.active || viewport.moving) return;
    for (let i = 0; i < groups.count; i++) {
      const group = groups.itemAt(i);
      if (!group || !group.visible || !group.model.isActive) continue;
      if (vertical) {
        viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
            group.y < viewport.contentY ? group.y
                : group.y + group.height > viewport.contentY + viewport.height
                    ? group.y + group.height - viewport.height : viewport.contentY));
      } else if (compact) {
        viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width,
            group.x - Math.max(0, viewport.width - group.width)));
      } else viewport.contentY = group.y;
      return;
    }
  }

  Minimap.DragSession {
    id: session
    parent: root.Window.window?.contentItem ?? root
    livePreview: true
    orientation: Qt.Horizontal
    freeWorkspaceDrag: true
    onActiveChanged: {
      if (active) viewport.cancelFlick();
      else Qt.callLater(root.revealActive);
    }
  }

  Flickable {
    id: viewport
    objectName: "pondViewport"
    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
    anchors.leftMargin: root.compact ? 4 : 8
    anchors.rightMargin: root.compact ? 4 : 8
    height: root.vertical ? Math.max(40, root.height - (root.compact ? 8 : 16)) : 40
    contentWidth: workspaceRow.width
    contentHeight: root.compact && !root.vertical ? height : Math.max(height, root.visibleCount * 44 - 4)
    flickableDirection: root.compact && !root.vertical ? Flickable.HorizontalFlick : Flickable.AutoFlickDirection
    boundsBehavior: Flickable.StopAtBounds
    interactive: !session.active
    clip: true
    onContentXChanged: if (session.held) dropTarget.updateTarget()
    onContentYChanged: if (session.held) dropTarget.updateTarget()
    onMovementEnded: if (!root.compact && !root.vertical) contentY = Math.max(0, Math.min(contentHeight - height, Math.round(contentY / 44) * 44))
    WheelHandler {
      enabled: !session.held
      target: null
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: event => root.handleWheel(event)
    }


    Item {
      id: workspaceRow
      width: root.compact ? (root.vertical ? 40 : root.visibleCount * 44 - 4) : root.naturalWidth
      height: viewport.contentHeight
      Repeater {
        id: groups
        model: Shell.NiriMsg.workspaceRows
        delegate: Item {
          id: group
          required property var model
          readonly property real appGap: windows.length > 0 ? root.workspaceIconGap : 8
          readonly property real appOffset: 40 + appGap * root.expandedAmount
          readonly property int workspaceId: Number(model.workspaceId)
          readonly property var windows: JSON.parse(model.windowsJson || "[]")
          readonly property int number: Number(model.sidebarWorkspaceNumber)
              || Number(model.sidebarRowOrdinal) + 1
          readonly property int remainingWindows: windows.filter(w =>
              !session.windowDrag || w.winId !== session.source?.windowData.winId).length
          visible: !root.screen || model.outputName === "" || model.outputName === root.screen.name
          width: visible ? 40 + (appGap + (windows.length + 1) * 48 - 8) * root.expandedAmount : 0
          height: 40
          x: root.compact && !root.vertical ? Number(model.sidebarRowOrdinal) * 44 : 0
          y: root.compact && !root.vertical ? 0 : Number(model.sidebarRowOrdinal) * 44
          onWidthChanged: Qt.callLater(root.revealActive)
          // Model role notifications are also tracked by this binding.
          property bool activeWorkspace: model.isActive
          onActiveWorkspaceChanged: Qt.callLater(root.revealActive)
          Component.onCompleted: Qt.callLater(root.revealActive)

          Rectangle {
            // Paint outside the 40px scrolling viewport so the taller backing
            // does not reveal neighbouring workspace rows or change hit areas.
            parent: viewport.parent
            z: -1
            objectName: "workspaceHighlight-" + group.workspaceId
            x: viewport.x + group.x - viewport.contentX - 4 * root.expandedAmount
            y: viewport.y + group.y - viewport.contentY - (height - group.height) / 2
            width: 40 + (group.windows.length > 0
                ? group.appGap + group.windows.length * 48 : 8) * root.expandedAmount
            height: Math.min(48, Math.max(40, root.height - 8))
            radius: Math.max(0, root.radius - 4)
            antialiasing: true
            visible: group.visible
                && group.y + group.height > viewport.contentY
                && group.y < viewport.contentY + viewport.height
                && (group.model.isActive || session.destination?.workspaceId === group.workspaceId)
            color: Shell.Theme.workspaceActiveIndicatorColor
          }

          Item {
            id: numberButton
            objectName: "workspaceNumber-" + group.workspaceId
            width: 40; height: 40
            readonly property bool floating: group.model.layoutMode === "floating"
            readonly property color modeColor: floating
                ? Shell.Theme.workspaceFloatingColor : Shell.Theme.workspaceScrollColor
            readonly property color modeTextColor: floating
                ? Shell.Theme.workspaceFloatingTextColor : Shell.Theme.workspaceScrollTextColor
            readonly property string modeName: floating
                ? qsTrId("pond.workspace_layout_floating") : qsTrId("pond.workspace_layout_scroll")
            readonly property string actionText: group.model.isActive
                ? (floating ? qsTrId("pond.workspace_layout_switch_scroll") : qsTrId("pond.workspace_layout_switch_floating"))
                : qsTrId("pond.workspace_select")
            readonly property string label: qsTrId("pond.workspace_layout_description")
                .arg(group.number).arg(modeName).arg(actionText)
            Rectangle {
              objectName: "workspaceModeSquare"
              anchors.centerIn: parent
              width: 32 + 8 * root.expandedAmount
              height: width
              radius: width / 4
              antialiasing: true
              readonly property bool hovered: numberPointer.containsMouse && !session.active
              readonly property bool pressed: numberPointer.pressed && !session.active
              border.width: 1
              border.color: Qt.rgba(numberButton.modeTextColor.r, numberButton.modeTextColor.g,
                  numberButton.modeTextColor.b, hovered || pressed ? 0.5 : 0.3)
              color: pressed ? Qt.tint(numberButton.modeColor, Qt.rgba(0, 0, 0, 0.12))
                  : hovered ? Qt.tint(numberButton.modeColor, Qt.rgba(1, 1, 1, 0.12))
                  : numberButton.modeColor
              Behavior on color { ColorAnimation { duration: Shell.Theme.sidebarHoverDuration; easing.type: Easing.OutCubic } }
              Behavior on border.color { ColorAnimation { duration: Shell.Theme.sidebarHoverDuration; easing.type: Easing.OutCubic } }
            }
            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: root.compact && group.windows.length > 0 ? -3 : 0
              text: group.number
              color: numberButton.modeTextColor
              font.family: Shell.Theme.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
            }
            Row {
              objectName: "workspaceAppDots"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 30
              spacing: 2
              visible: root.compact && group.windows.length > 0
              Repeater {
                model: Math.min(4, group.windows.length)
                delegate: Rectangle {
                  width: 4; height: 4
                  radius: 2
                  color: numberButton.modeTextColor
                  opacity: 0.75
                  antialiasing: true
                }
              }
            }
            MouseArea {
              id: numberPointer
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activateWorkspace(group.workspaceId, group.model.workspaceIndex, group.model.isActive)
            }
            ToolTip {
              id: modeTooltip
              objectName: "workspaceModeTooltip"
              parent: root.Window.window?.contentItem ?? root
              popupType: Popup.Item
              visible: numberPointer.containsMouse && !numberPointer.pressed && !session.active
              delay: 600
              padding: 12
              implicitWidth: Math.min(280, Math.max(tooltipTitle.implicitWidth,
                  tooltipAction.implicitWidth) + leftPadding + rightPadding)
              property point buttonCenter: Qt.point(0, 0)
              property real cardTop: 0
              property real cardLeft: 0
              function updateAnchor() {
                // mapToItem does not subscribe to ancestor layout changes.
                // Sample the settled scene position when shown and while animating.
                buttonCenter = numberButton.mapToItem(parent, numberButton.width / 2, 0);
                const origin = root.mapToItem(parent, 0, 0);
                cardTop = origin.y;
                cardLeft = origin.x;
              }
              onAboutToShow: updateAnchor()
              Timer {
                interval: 16
                repeat: true
                running: modeTooltip.visible
                onTriggered: modeTooltip.updateAnchor()
              }
              x: root.vertical
                  ? Math.max(8, Math.min(cardLeft + root.width + 10, parent.width - width - 8))
                  : Math.max(8, Math.min(buttonCenter.x - width / 2, parent.width - width - 8))
              y: root.vertical ? Math.max(8, Math.min(buttonCenter.y + numberButton.height / 2 - height / 2,
                  parent.height - height - 8)) : cardTop >= height + 18 ? cardTop - height - 10
                  : Math.min(parent.height - height - 8, cardTop + root.height + 10)
              background: Rectangle {
                color: Shell.PanelStyle.surface
                border.color: Shell.PanelStyle.border
                border.width: 1
                radius: Shell.PanelStyle.rowRadius
                antialiasing: true
              }
              contentItem: Column {
                spacing: 4
                Text {
                  id: tooltipTitle
                  width: parent.width
                  text: group.number + " · " + numberButton.modeName
                  textFormat: Text.PlainText
                  color: Shell.Theme.sidebarV3Foreground
                  font.family: Shell.Theme.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.Medium
                }
                Text {
                  id: tooltipAction
                  width: parent.width
                  text: numberButton.actionText
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: Shell.Theme.sidebarV3Foreground
                  opacity: 0.65
                  font.family: Shell.Theme.fontFamily
                  font.pixelSize: 12
                }
              }
              enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
              }
              exit: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: 90 }
              }
            }
            Accessible.role: Accessible.Button
            Accessible.name: label
            Accessible.onPressAction: root.activateWorkspace(group.workspaceId, group.model.workspaceIndex, group.model.isActive)
            DragHandler {
              target: null
              enabled: root.collapseProgress === 0 && group.model.sidebarWorkspaceNumber > 0
                  && (!session.active || active)
              acceptedButtons: Qt.LeftButton
              dragThreshold: 6
              grabPermissions: PointerHandler.CanTakeOverFromAnything
              onActiveChanged: {
                if (active) session.begin({kind: "workspace", workspaceId: group.workspaceId,
                    number: group.number}, numberButton, centroid.scenePressPosition, centroid.scenePosition);
                else session.release();
              }
              onCentroidChanged: if (active) session.move(centroid.scenePosition)
              onCanceled: session.cancel()
            }
          }
          Item {
            x: group.appOffset
            width: group.width - group.appOffset
            height: 40
            clip: true
            opacity: root.expandedAmount
            enabled: root.collapseProgress === 0
            Repeater {
              model: group.windows.length
              delegate: Minimap.WindowIcon {
                id: app
                required property int index
                windowData: group.windows[index]
                x: index * 48
                width: 40; height: 40
                opacity: session.windowDrag && session.source.windowData.winId === windowData.winId ? 0.3 : 1
                onActivated: windowId => root.windowRequested(windowId)
                DragHandler {
                  target: null
                  enabled: root.collapseProgress === 0 && (!session.active || active)
                  acceptedButtons: Qt.LeftButton
                  dragThreshold: 6
                  grabPermissions: PointerHandler.CanTakeOverFromAnything
                  onActiveChanged: {
                    if (active) session.begin({kind: "window", windowData: Object.assign({}, app.windowData),
                        workspaceId: group.workspaceId, slot: app.index}, app,
                        centroid.scenePressPosition, centroid.scenePosition);
                    else session.release();
                  }
                  onCentroidChanged: if (active) session.move(centroid.scenePosition)
                  onCanceled: session.cancel()
                }
              }
            }
            Minimap.PlusButton {
              x: group.windows.length * 48
              width: 40; height: 40
              revealed: !session.active
              onActivated: root.addRequested(group.workspaceId)
            }
          }
          Rectangle {
            visible: session.held && session.windowDrag && dropTarget.workspaceId === group.workspaceId
                && session.destination === dropTarget
            x: Math.min(group.width - 3, group.appOffset + dropTarget.slot * 48)
            y: 4
            width: 3; height: 32
            radius: 1.5
            color: Shell.PanelStyle.accent
          }
        }
      }
    }
  }

  DropArea {
    id: dropTarget
    anchors.fill: viewport
    keys: ["pond-window", "pond-workspace"]
    property int workspaceId: -1
    property int slot: 0
    property int number: 0
    function updateTarget() {
      if (!session.held) return;
      const point = viewport.mapFromItem(session.parent, session.pointer.x, session.pointer.y);
      if (point.x < 0 || point.x > viewport.width || point.y < 0 || point.y > viewport.height) {
        session.destination = null;
        return;
      }
      const contentX = point.x + viewport.contentX;
      const contentY = point.y + viewport.contentY;
      let found = false;
      for (let i = 0; i < groups.count; i++) {
        const group = groups.itemAt(i);
        if (!group || !group.visible || contentX < group.x || contentX > group.x + group.width
            || contentY < group.y || contentY > group.y + group.height) continue;
        if (!session.windowDrag && group.model.sidebarWorkspaceNumber <= 0) break;
        workspaceId = group.workspaceId;
        number = group.number;
        const position = Math.max(0, Math.floor((contentX - group.x - group.appOffset + 24) / 48));
        const sourceIndex = group.windows.findIndex(w => w.winId === session.source?.windowData?.winId);
        slot = Math.min(group.remainingWindows, position - (sourceIndex >= 0 && position > sourceIndex ? 1 : 0));
        session.destination = dropTarget;
        found = true;
        break;
      }
      if (!found) session.destination = null;
    }
    function snapPosition() {
      for (let i = 0; i < groups.count; i++) {
        const group = groups.itemAt(i);
        if (group?.workspaceId === workspaceId)
          return group.mapToItem(session.parent, session.windowDrag ? group.appOffset + slot * 48 : 0, 0);
      }
      return session.origin;
    }
    onEntered: updateTarget()
    onPositionChanged: updateTarget()
    onExited: if (session.held) session.destination = null
    onDropped: drop => { if (session.destination === dropTarget) drop.acceptProposedAction(); }
  }

  // The drag icon lives on the window content item and owns the pointer grab.
  // Receive wheels at that same level, including outside the small Pond card.
  WheelHandler {
    parent: root.Window.window?.contentItem ?? root
    target: null
    enabled: session.held
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => root.handleWheel(event)
  }

  function scrollWorkspace(direction) {
    if (session.active || Shell.NiriMsg.workspaceModeBusy) return;
    const visibleGroups = [];
    for (let i = 0; i < groups.count; i++) {
      const group = groups.itemAt(i);
      if (group?.visible) visibleGroups.push(group);
    }
    if (visibleGroups.length === 0) return;
    const active = visibleGroups.findIndex(group => group.model.isActive);
    const next = Math.max(0, Math.min(visibleGroups.length - 1,
        (active < 0 ? 0 : active) + direction));
    if (next === active) return;
    const target = visibleGroups[next];
    focusRequested(target.model.workspaceIndex, target.workspaceId);
  }

  function handleWheel(event) {
    if (event.angleDelta.y || event.pixelDelta.y) {
      const delta = event.pixelDelta.y || event.angleDelta.y;
      if (!wheelCooldown.running) {
        if (compact) scrollWorkspace(delta < 0 ? 1 : -1);
        else scrollRow(delta < 0 ? 1 : -1);
        wheelCooldown.restart();
      }
    } else {
      const delta = event.pixelDelta.x || event.angleDelta.x;
      viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width,
          viewport.contentX - delta / 3));
    }
    event.accepted = true;
  }

  function scrollRow(direction) {
    viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
        Math.round(viewport.contentY / 44) * 44 + direction * 44));
  }

  Timer { id: wheelCooldown; interval: 160 }
  Timer {
    interval: 350
    repeat: true
    running: session.held && !root.compact
    onTriggered: {
      const point = viewport.mapFromItem(session.parent, session.pointer.x, session.pointer.y);
      if (point.x < 0 || point.x > viewport.width || point.y < -16 || point.y > viewport.height + 16) return;
      const direction = point.y < 10 ? -1 : point.y > viewport.height - 10 ? 1 : 0;
      root.scrollRow(direction);
      if (root.vertical) {
        const horizontalDirection = point.x < 12 ? -1 : point.x > viewport.width - 12 ? 1 : 0;
        viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width,
            viewport.contentX + horizontalDirection * 48));
      }
      dropTarget.updateTarget();
    }
  }
}
