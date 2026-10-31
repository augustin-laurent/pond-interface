import QtQuick
import "." as Minimap
import ".." as Shell

Item {
  id: root
  property bool livePreview: true
  property int orientation: Qt.Vertical
  property bool freeWorkspaceDrag: false
  property var backend: Shell.NiriMsg
  property var source: null
  property Item destination: null
  property bool held: false
  property bool committing: false
  property bool resetting: false
  property bool preparingOverview: false
  property bool movingPreview: false
  property bool previewed: false
  property var applied: null
  onDestinationChanged: if (livePreview && windowDrag && held) preview.restart()
  Connections {
    target: root.windowDrag ? root.destination : null
    function onSlotChanged() { if (root.livePreview && root.held) preview.restart(); }
    function onWorkspaceIdChanged() { if (root.livePreview && root.held) preview.restart(); }
  }
  readonly property bool active: source !== null
  onActiveChanged: root.backend.workspaceDragActive = active
  Component.onDestruction: if (active) root.backend.workspaceDragActive = false
  readonly property bool windowDrag: source?.kind === "window"
  property point origin
  property point press
  property point pointer
  property point grabOffset
  readonly property bool sourcePresent: !source || (windowDrag
      ? root.backend.windowExists(source.windowData.winId)
      : root.backend.workspaces.some(w => w.id === source.workspaceId))
  onSourcePresentChanged: if (!sourcePresent) cancel()
  readonly property real rowOffset: !source || windowDrag || freeWorkspaceDrag ? 0
      : held ? Math.max((1 - source.number) * Shell.Theme.workspaceRowPitch,
          Math.min((source.count - source.number) * Shell.Theme.workspaceRowPitch, pointer.y - press.y))
      : ((destination?.number ?? source.number) - source.number) * Shell.Theme.workspaceRowPitch

  z: 100
  width: Shell.Theme.workspaceControlSize
  height: width
  visible: active
  Drag.source: root
  Drag.keys: [windowDrag ? "pond-window" : "pond-workspace"]
  Drag.hotSpot.x: grabOffset.x
  Drag.hotSpot.y: grabOffset.y
  Drag.supportedActions: Qt.MoveAction
  Drag.proposedAction: Qt.MoveAction

  function begin(data, item, pressPoint, currentPoint) {
    if (active || backend.workspaceModeBusy || !item.contains(item.mapFromItem(null, pressPoint.x, pressPoint.y)))
      return;
    source = data;
    origin = item.mapToItem(parent, 0, 0);
    press = parent.mapFromItem(null, pressPoint.x, pressPoint.y);
    grabOffset = Qt.point(press.x - origin.x, press.y - origin.y);
    held = true;
    move(currentPoint);
    Drag.active = true;
    if (windowDrag && livePreview) {
      applied = { workspaceId: data.workspaceId, slot: data.slot };
      preparingOverview = root.backend.showWindowOverview(data.windowData.winId, success => {
        preparingOverview = false;
        if (!success) cancel();
        else if (held) preview.restart();
        else settle.restart();
      });
      if (!preparingOverview) cancel();
    }
  }

  function move(scenePoint) {
    if (!held)
      return;
    pointer = parent.mapFromItem(null, scenePoint.x, scenePoint.y);
    x = windowDrag || freeWorkspaceDrag || orientation === Qt.Horizontal ? pointer.x - grabOffset.x : origin.x;
    y = windowDrag || freeWorkspaceDrag ? pointer.y - grabOffset.y
        : orientation === Qt.Horizontal ? origin.y : origin.y + rowOffset;
  }

  function release() {
    if (!held)
      return;
    held = false;
    const accepted = Drag.drop() !== Qt.IgnoreAction;
    if (!accepted) destination = null;
    const target = destination ? destination.snapPosition() : origin;
    x = target.x;
    y = target.y;
    settle.restart();
  }

  function cancel() {
    if (!active || committing)
      return;
    Drag.cancel();
    destination = null;
    held = false;
    x = origin.x;
    y = origin.y;
    settle.restart();
  }

  function clear() {
    if (livePreview && windowDrag && root.backend.finishWindowDrag(!destination && previewed, finish))
      return;
    finish();
  }

  function updatePreview() {
    if (!livePreview || preparingOverview || movingPreview) return;
    const target = destination
        ? { workspaceId: destination.workspaceId, slot: destination.slot } : null;
    if (!target || (applied?.workspaceId === target.workspaceId && applied.slot === target.slot)) {
      if (!held) clear();
      return;
    }
    movingPreview = root.backend.moveWindow(source.windowData.winId,
        target.workspaceId, target.slot, success => {
          movingPreview = false;
          if (success) applied = target;
          else { destination = null; held = false; }
          if (held) preview.restart();
          else settle.restart();
        });
    if (movingPreview) previewed = true;
    else { destination = null; held = false; clear(); }
  }

  function commitDrop() {
    if (!destination || !sourcePresent
        || !backend.workspaces.some(w => w.id === destination.workspaceId)) {
      clear();
      return;
    }
    committing = true;
    const started = backend.moveWindow(source.windowData.winId,
        destination.workspaceId, destination.slot, success => finish());
    if (!started) finish();
  }

  function finish() {
    resetting = true;
    preview.stop();
    applied = null;
    previewed = false;
    source = null;
    destination = null;
    committing = false;
    Qt.callLater(() => resetting = false);
  }

  Timer {
    id: preview
    interval: 32
    onTriggered: if (root.held && root.windowDrag) root.updatePreview()
  }

  Timer {
    id: settle
    interval: Shell.Theme.workspaceDragSnapDuration
    onTriggered: {
      if (root.preparingOverview || root.movingPreview) return;
      if (root.windowDrag) {
        if (root.livePreview) {
          root.committing = true;
          root.updatePreview();
        } else root.commitDrop();
        return;
      }
      if (!root.destination) { root.clear(); return; }
      root.committing = true;
      const done = success => root.clear();
      const started = root.backend.moveWorkspace(root.source.workspaceId,
          root.destination.workspaceId, done);
      if (!started) root.clear();
    }
  }

  Behavior on x { enabled: !root.held; Shell.HoverAnimation { duration: Shell.Theme.workspaceDragSnapDuration } }
  Behavior on y { enabled: !root.held; Shell.HoverAnimation { duration: Shell.Theme.workspaceDragSnapDuration } }

  Rectangle {
    anchors.fill: parent
    visible: root.active && !root.windowDrag && root.orientation === Qt.Horizontal
    radius: 12
    color: Shell.Theme.workspaceDragBackground
    Text {
      anchors.centerIn: parent
      text: root.source?.number ?? ""
      color: "white"
    }
  }

  Minimap.WindowIcon {
    anchors.fill: parent
    visible: root.windowDrag
    windowData: root.source?.windowData ?? ({})
    lifted: true
    interactive: false
  }
}
