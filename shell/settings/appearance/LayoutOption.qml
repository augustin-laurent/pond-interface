import QtQuick
import "../.." as Shell

Rectangle {
  id: root
  property string label
  property string description
  property bool selected: false
  signal clicked
  implicitHeight: 64
  z: selected ? 1 : 0
  radius: 12
  color: hover.hovered || activeFocus ? "#303030" : selected ? "#333333" : "transparent"
  border.width: 1
  border.color: selected ? "#cba6f7" : hover.hovered || activeFocus ? "#444444" : "#3d3d3d"
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: label
  Accessible.checked: selected
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Accessible.onPressAction: clicked()
  Behavior on color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }
  Behavior on border.color { ColorAnimation { duration: 170; easing.type: Easing.OutCubic } }
  Text {
    x: 20; y: 15
    text: root.label
    color: "white"; font.family: Shell.Theme.fontFamily; font.pixelSize: 13
  }
  Text {
    x: 20; y: 32
    text: root.description
    color: "#80ffffff"; font.family: Shell.Theme.fontFamily; font.pixelSize: 13
  }
  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
