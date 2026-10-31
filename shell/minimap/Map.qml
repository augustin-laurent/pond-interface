import QtQuick
import "." as Minimap

// The sidebar shares workspace modes, badges, tooltips and drag behavior with
// the bottom bar, while keeping its vertically stacked workspace presentation.
Minimap.HorizontalMap {
  vertical: true
}
