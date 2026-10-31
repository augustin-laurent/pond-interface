import QtQuick
import "." as Installs
import ".." as Shell
import "../updates" as Updates

Shell.Card {
  id: root
  property real collapseProgress: 0
  // Set by the bottom bar: collapse into a single 48x48 status tile instead of
  // stacking one row per job.
  property bool horizontal: false
  readonly property real widthProgress: Shell.Theme.collapseWidth(collapseProgress)
  readonly property real heightProgress: Shell.Theme.collapseHeight(collapseProgress)
  readonly property bool horizontalCompact: horizontal && collapseProgress >= 0.56
  readonly property int contentPadding: 4
  readonly property int rowHeight: Shell.Theme.sidebarCardCollapsedWidth - 2 * contentPadding
  readonly property int count: Installs.State.jobs.count
  implicitWidth: Shell.Theme.lerp(Shell.Theme.sidebarCardExpandedWidth,
      Shell.Theme.sidebarCardCollapsedWidth, widthProgress)
  implicitHeight: count === 0 ? 0
      : horizontal ? Shell.Theme.lerp(2 * contentPadding + count * rowHeight, 48, heightProgress)
      : 2 * contentPadding + count * rowHeight
  visible: count > 0
  radius: Shell.Theme.lerp(12, Shell.Theme.sidebarCardRadius, widthProgress)

  Repeater {
    model: Installs.State.jobs
    delegate: Item {
      id: row
      required property int index
      required property string jobId
      required property string name
      required property string status
      required property real progress
      required property string icon
      readonly property bool canLaunch: status === "installed" && jobId !== "system-update"
          && Installs.State.findApp(name) !== null
      readonly property bool showDismiss: dismiss.visible && (rowHover.hovered || dismiss.hovered)
      readonly property string summary: status === "installed" ? qsTrId("pond.installed")
          : status === "failed" ? qsTrId("pond.failed") : progress < 0 ? qsTrId("pond.installing")
          : qsTrId("pond.installing_1").arg(Math.round(progress * 100))
      y: root.contentPadding + index * root.rowHeight
      width: root.width
      height: root.rowHeight
      visible: !root.horizontalCompact
      Accessible.role: Accessible.ListItem
      readonly property string displayName: jobId !== "system-update" ? name
          : status === "installed" ? qsTrId("pond.update_complete")
          : status === "failed" ? qsTrId("pond.update_failed")
          : qsTrId("pond.updating")
      Accessible.name: jobId === "system-update" ? displayName : name + ": " + summary
      Accessible.onPressAction: Installs.State.dismiss(jobId)

      HoverHandler { id: rowHover }
      Item {
        x: root.contentPadding
        width: Math.max(0, parent.width - root.rowHeight - 2 * root.contentPadding)
        height: parent.height
        opacity: 1 - Shell.Theme.ramp(root.collapseProgress, 0, 0.3)
        HoverFill {
          anchors.fill: parent
          active: row.canLaunch && nameHover.hovered
        }
        Image {
          id: appIcon
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 16
          height: 16
          visible: status === Image.Ready
          source: row.icon
          sourceSize: Qt.size(32, 32)
          fillMode: Image.PreserveAspectFit
        }
        Text {
          x: appIcon.visible ? 36 : 12
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 1
          width: Math.max(0, parent.width - 12 - x)
          text: row.displayName
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: "white"
          font.family: Shell.Theme.fontFamily
          font.pixelSize: 13
          font.weight: Font.Medium
        }
        HoverHandler {
          id: nameHover
          cursorShape: row.canLaunch ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
          enabled: row.canLaunch
          onTapped: Installs.State.launch(row.jobId)
        }
      }
      Installs.Indicator {
        id: indicator
        visible: (row.jobId !== "system-update" || row.status !== "installing") && !row.showDismiss
        x: dismiss.x + (dismiss.width - width) / 2
        y: (parent.height - height) / 2
        progress: row.progress
        status: row.status
      }
      Updates.Indicator {
        id: updateIndicator
        visible: row.jobId === "system-update" && row.status === "installing"
        x: indicator.x
        y: indicator.y
      }
      Shell.IconButton {
        id: dismiss
        visible: row.status !== "installing"
        opacity: row.showDismiss ? 1 : 0
        x: parent.width - width - root.contentPadding
        width: root.rowHeight
        height: parent.height
        iconSource: Qt.resolvedUrl("../assets/installs/cross.svg")
        iconWidth: 16
        iconHeight: 16
        onClicked: Installs.State.dismiss(row.jobId)
        HoverFill {
          anchors.fill: parent
          z: -1
          active: dismiss.hovered
        }
      }
    }
  }

  Item {
    id: compactLayer
    anchors.fill: parent
    visible: root.horizontalCompact
    opacity: Shell.Theme.ramp(root.collapseProgress, 0.56, 1)

    Repeater {
      model: Installs.State.jobs
      delegate: Item {
        required property int index
        required property string jobId
        required property string status
        required property real progress
        visible: index === 0
        anchors.centerIn: parent
        width: 16
        height: 16

        Installs.Indicator {
          anchors.fill: parent
          visible: parent.jobId !== "system-update" || parent.status !== "installing"
          progress: parent.progress
          status: parent.status
        }
        Updates.Indicator {
          anchors.fill: parent
          visible: parent.jobId === "system-update" && parent.status === "installing"
        }
      }
    }

    Rectangle {
      visible: root.count > 1
      x: parent.width - width - 6
      y: 6
      width: 14
      height: 14
      radius: 7
      color: "#d9d9d9"

      Text {
        anchors.centerIn: parent
        text: root.count
        color: "#1e1e1e"
        font.family: Shell.Theme.fontFamily
        font.pixelSize: 9
        font.weight: Font.Medium
      }
    }
  }

  component HoverFill: Rectangle {
    property bool active
    radius: root.radius - root.contentPadding
    color: Shell.Theme.daylight ? Shell.Theme.sidebarHoverFill : "#262626"
    opacity: active ? 1 : 0
    Behavior on opacity { Shell.HoverAnimation {} }
  }
}
