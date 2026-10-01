import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One tappable action row: glyph + title + hint. The owner decides what
// "activated" means (mouse click or keyboard Enter on the claimed row) and
// binds hasCursor to highlight the row under the keyboard cursor.
CursorSurface {
  id: root

  property string iconGlyph: ""
  property string actionText: ""
  property string actionHint: ""
  property bool rowEnabled: true
  property string fontFamily: Style.font.family
  property color dim: Qt.darker(foreground, 1.55)
  signal activated()
  signal cursorClaimed()

  implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX
  opacity: rowEnabled ? 1.0 : 0.45

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.rowEnabled
    onEntered: root.cursorClaimed()
    onClicked: root.activated()
  }

  RowLayout {
    id: actionContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(16)
    spacing: Style.space(8)

    Text {
      text: root.iconGlyph
      visible: root.iconGlyph !== ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.actionText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: root.actionHint !== ""
        text: root.actionHint
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
