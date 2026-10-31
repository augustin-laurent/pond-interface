pragma ComponentBehavior: Bound
import QtQuick
import "." as System
import ".." as Settings
import "../../battery" as Battery
import "../.." as Shell

Settings.Modal {
  id: root
  objectName: "lockPanel"
  title: qsTrId("settings.lock_sleep"); closeLabel: qsTrId("pond.back_to_system")
  bodyTop: Battery.State.present ? 118 : 92
  contentHeight: fields.height + 30
  property string power: System.Idle.source
  property string dropdownField: ""
  property real dropdownCenter: 0
  readonly property var rows: [
    {key: "lock", title: qsTrId("settings.lock_after_inactivity")},
    {key: "display", title: qsTrId("settings.display_after_inactivity")},
    {key: "sleep", title: qsTrId("settings.sleep_after_inactivity")}
  ]
  onBackRequested: { if (dropdownField) closeDropdown(); else Settings.State.back(); }
  Keys.onEscapePressed: { if (dropdownField) closeDropdown(); else Settings.State.back(); }
  function closeDropdown() { dropdownField = ""; forceActiveFocus(); }
  function openDropdown(key, field) {
    dropdownCenter = field.mapToItem(root, 0, field.height / 2).y;
    dropdownField = key;
    Qt.callLater(() => { const menu = dropdownLoader.item as Settings.Dropdown; if (menu) menu.forceActiveFocus(); });
  }
  Column {
    id: fields
    x: 30; width: root.width - 60; spacing: 6
    Repeater {
      model: root.rows
      delegate: Settings.Field {
        id: field
        required property var modelData
        required property int index
        objectName: "lockField" + modelData.key
        width: fields.width; step: index + 1
        title: modelData.title
        value: System.Idle.label(System.Idle.timeouts[root.power][modelData.key])
        highlighted: root.dropdownField === modelData.key
        opacity: root.dropdownField && !highlighted ? 0.3 : 1
        enabled: !root.dropdownField
        onClicked: root.openDropdown(modelData.key, field)
      }
    }
  }
  overlay: [
    Rectangle {
      objectName: "lockPower"
      visible: Battery.State.present
      x: root.width - width - 30; y: 64; width: 204; height: 41; radius: 12
      color: "transparent"; border.width: 1; border.color: "#262626"
      opacity: root.dropdownField ? 0.3 : 1
      enabled: !root.dropdownField
      Row {
        x: 2; y: 2
        Repeater {
          model: [{key: "pluggedIn", label: qsTrId("settings.plugged_in"), width: 100}, {key: "battery", label: qsTrId("settings.on_battery"), width: 100}]
          delegate: Rectangle {
            id: segment
            required property var modelData
            required property int index
            readonly property bool chosen: root.power === modelData.key
            objectName: "lockPower" + modelData.key
            width: modelData.width; height: 37
            radius: 2
            topLeftRadius: index === 0 ? 10 : 2; bottomLeftRadius: topLeftRadius
            topRightRadius: index === 1 ? 10 : 2; bottomRightRadius: topRightRadius
            color: chosen ? "#303030" : hover.hovered || activeFocus ? "#262626" : "transparent"
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.label
            Accessible.checked: chosen
            Accessible.onPressAction: root.power = modelData.key
            Keys.onReturnPressed: root.power = modelData.key
            Keys.onSpacePressed: root.power = modelData.key
            Text {
              anchors.centerIn: parent
              text: segment.modelData.label; color: "white"
              opacity: hover.hovered ? 1 : 0.7
              font.family: Shell.Theme.fontFamily; font.pixelSize: 13
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.power = segment.modelData.key }
          }
        }
      }
    },
    MouseArea {
      anchors.fill: parent; visible: !!root.dropdownField
      onClicked: root.closeDropdown()
      onWheel: event => { event.accepted = true; }
    },
    Loader {
      id: dropdownLoader
      active: !!root.dropdownField
      x: root.width - width - 38
      y: Math.max(60, Math.min(root.dropdownCenter - height / 2, root.height - height - 24))
      sourceComponent: Component {
        Settings.Dropdown {
          objectName: "lockDropdown"
          width: 181
          maximumHeight: Math.max(56, root.height - 84)
          options: System.Idle.options
          currentValue: String(System.Idle.timeouts[root.power][root.dropdownField])
          onDismissed: root.closeDropdown()
          onSelected: value => { const key = root.dropdownField; root.closeDropdown(); System.Idle.set(root.power, key, Number(value)); }
        }
      }
    }
  ]
}
