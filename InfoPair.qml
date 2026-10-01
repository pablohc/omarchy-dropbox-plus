import QtQuick
import qs.Commons
import qs.Ui

// Label/value pair stretched to the full width, value flush right.
Row {
  id: root

  property string label: ""
  property string value: ""
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground

  width: parent.width
  spacing: Style.space(8)

  InfoLabel { text: root.label }
  Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
  InfoValue { text: root.value }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
