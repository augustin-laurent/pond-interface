import QtQuick
import Quickshell.Widgets
import "." as Notifications
import ".." as Shell

Item {
  id: root
  property real collapseProgress: 0
  property real rowHeight: 48
  property bool horizontal: false
  property bool inlinePreviews: !horizontal
  readonly property alias blurRegion: background.blurRegion
  onYChanged: blurRegion.changed()
  readonly property bool empty: Notifications.State.notificationCount === 0
  signal panelRequested
  property real transientProgress: Notifications.State.transientVisible ? 1 : 0
  readonly property real inlineAmount: !inlinePreviews ? 0
      : transientProgress * (1 - Shell.Theme.collapseHeight(collapseProgress))
  readonly property real previewOpacity: inlineAmount >= 0.54 ? 1 : 0
  readonly property var notification: Notifications.State.currentTransient
  readonly property real widthProgress: Shell.Theme.collapseWidth(collapseProgress)
  readonly property real summaryIconSize: Notifications.Style.summaryIconSize + 6 * widthProgress
  readonly property int appCount: Notifications.State.recentApps.length
  readonly property real summaryWidth: !horizontal || empty
      ? Shell.Theme.sidebarCardExpandedWidth
      : Math.min(Shell.Theme.sidebarCardExpandedWidth,
          Shell.Theme.sidebarRowHorizontalPadding * 2 + primary.width
          + (appCount > 0 ? 17 + appCount * (root.summaryIconSize + 8) - 8 : 0))
  implicitWidth: Shell.Theme.lerp(summaryWidth,
      Shell.Theme.sidebarCardCollapsedWidth, widthProgress)
  implicitHeight: rowHeight + (preview.height - 1) * inlineAmount
  Behavior on transientProgress { Shell.Motion {} }

  Shell.Card {
    id: background
    anchors.fill: parent
    radius: Shell.Theme.lerp(root.empty ? 12 : Shell.Theme.sidebarCardRadius,
        Shell.Theme.sidebarCardRadius, root.widthProgress)
    Item {
      id: summary
      width: parent.width
      height: root.rowHeight

      implicitHeight: Shell.Theme.sidebarSimpleRowHeight

      Item {
        id: primary
        width: root.summaryIconSize + (root.empty ? 0 : 2 + caption.width)
        opacity: root.previewOpacity && Notifications.State.notificationCount === 1 ? 0.5 : 1
        x: Math.round(Shell.Theme.lerp(
            Shell.Theme.sidebarRowHorizontalPadding,
            (summary.width - width) / 2,
            Shell.Theme.collapseWidth(root.collapseProgress)))
        y: Math.round((summary.height - height) / 2)
        height: root.summaryIconSize

        Image {
          width: root.summaryIconSize
          height: root.summaryIconSize
          source: Qt.resolvedUrl("../assets/bell.svg")
          opacity: root.empty ? 0.88 : 1
          sourceSize: Qt.size(root.summaryIconSize * 2,
                              root.summaryIconSize * 2)
          fillMode: Image.PreserveAspectFit
          smooth: true
          antialiasing: true
        }

        Text {
          id: caption
          x: root.summaryIconSize + (root.empty ? 8 : 2)
          y: 3 + metrics.capitalHeight - baselineOffset
          width: root.empty ? implicitWidth : Math.max(14, implicitWidth)
          height: root.summaryIconSize
          text: root.empty ? qsTrId("pond.notifications") : String(Notifications.State.notificationCount)
          visible: !root.empty || root.collapseProgress < 0.31
          opacity: root.empty ? 0.6 : 1
          color: root.empty ? Notifications.Style.foreground : "#B7B7B7"
          font.family: Shell.Theme.fontFamily
          font.weight: Font.Medium
          font.pixelSize: 13
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: root.empty ? Text.AlignLeft : Text.AlignHCenter
          FontMetrics { id: metrics; font: caption.font }
        }
      }

      Row {
        id: applications
        x: primary.x + primary.width + 8
        y: primary.y
        width: Math.max(0, summary.width - x - (root.horizontal ? Shell.Theme.sidebarRowHorizontalPadding : 0))
        height: root.summaryIconSize
        clip: root.horizontal
        spacing: 8
        opacity: root.collapseProgress < 0.31 ? 1 : 0
        visible: !root.empty && opacity > 0.001

        Rectangle {
          width: 1
          height: root.summaryIconSize
          color: Notifications.Style.divider
        }

        Repeater {
          model: Notifications.State.recentApps

          delegate: IconImage {
            required property var modelData
            required property int index

            width: root.summaryIconSize
            height: root.summaryIconSize
            visible: !root.horizontal || index < Math.floor((applications.width - 1) / (root.summaryIconSize + 8))
            source: modelData.iconSource || ""
            asynchronous: true
            smooth: true
            opacity: index === 0 ? 1 : Notifications.Style.secondaryIconOpacity
          }
        }
      }
    }

    Notifications.Card {
      id: preview
      y: root.rowHeight - 1 + (1 - root.previewOpacity) * 4
      width: root.width
      inlinePreview: true
      notification: root.notification
      closeEnabled: false
      extraHovered: inlineClose.hovered
      opacity: root.previewOpacity
      enabled: root.notification !== null && root.inlineAmount > 0.5
      onActivated: Notifications.State.activate(root.notification)
    }
  }

  MouseArea {
    width: parent.width
    height: root.rowHeight
    enabled: !root.empty
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.panelRequested()
  }

  Notifications.CloseButton {
    id: inlineClose
    compact: true
    x: root.width - width / 2
    y: root.rowHeight + 12
    z: 3
    opacity: preview.hovered && root.inlineAmount > 0.7 ? 1 : 0
    visible: opacity > 0.001
    enabled: opacity > 0.5
    onClicked: Notifications.State.remove(root.notification)
  }
}
