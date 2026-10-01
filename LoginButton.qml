import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Pre-authentication row: "Login to Dropbox" (or a CLI-missing notice) with a
// launch button. Emits activated() for the action and cursorClaimed() when
// hovered, so the panel can route its keyboard cursor here.
CursorSurface {
  id: root

  property bool installed: false
  property bool busy: false
  property string fontFamily: Style.font.family
  property color dim: Qt.darker(foreground, 1.55)
  signal activated()
  signal cursorClaimed()

  implicitHeight: loginRow.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.installed && !root.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.installed && !root.busy
    onEntered: root.cursorClaimed()
    onClicked: root.activated()
  }

  RowLayout {
    id: loginRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)

    Text {
      text: ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.installed ? "Login to Dropbox" : "Dropbox CLI is not installed"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.installed ? "Start the authentication flow" : "Install Dropbox from the service menu"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      iconText: "󰌋"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: root.installed && !root.busy
      Layout.alignment: Qt.AlignVCenter
      onClicked: root.activated()
    }
  }
}
