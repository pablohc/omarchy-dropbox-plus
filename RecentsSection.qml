import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Collapsible RECENT FILES section: toggle header, empty-state text, and a
// ~4-row viewport whose internal scroll reaches every recent file. Expanding
// reserves the block; nothing else in the panel moves.
Column {
  id: root

  property bool collapsed: false
  property var files: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // Keyboard cursor row, already resolved by the panel (-1 = elsewhere).
  property int activeRow: -1

  signal rowHovered(int index)
  signal fileActivated(var file)
  signal shareLinkRequested(var file)

  // Live height of the first row, reported by the delegate. Fallback stride
  // 48.76 = measured default (1219px / 25 rows at stock font scale); the live
  // measure keeps the 4-row window exact if fonts rescale.
  property real firstRowHeight: 0
  readonly property real listSpacing: Style.space(6)
  readonly property real rowStride: firstRowHeight > 0 ? firstRowHeight + listSpacing : 48.76
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool empty: !files || files.length === 0

  spacing: Style.space(10)

  // Keyboard cursor support: bring the row into the viewport only when it is
  // genuinely clipped (ε test, not margin). Margin-based tests re-aligned
  // fully visible rows — the flush last row crossed
  // `bottom > viewBottom - margin` on every hover, the alignment clipped the
  // first row and exposed a sliver of the next, and the list ping-ponged as
  // the pointer travelled between first and last row.
  function revealRow(index) {
    if (!flick || index < 0) return
    var item = rowsRepeater.itemAt(index)
    if (!item) return
    Qt.callLater(function() {
      if (!item || !flick) return
      var eps = 0.5
      var margin = Style.space(6)
      var top = item.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      if (top >= viewTop - eps && bottom <= viewBottom + eps) return
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < viewTop - eps) {
        flick.contentY = Math.max(0, top - margin)
        return
      }
      var land = bottom + margin - flick.height
      // Never land low enough to expose a sliver of the next row — a sliver
      // under a stationary cursor invites another alignment.
      var next = rowsRepeater.itemAt(index + 1)
      if (next) land = Math.min(land, next.y - flick.height)
      flick.contentY = Math.max(0, Math.min(land, maxY))
    })
  }

  function resetScroll() {
    if (flick) flick.contentY = 0
    // After the expand transition the viewport has real height: queue a
    // second reset so the top row starts whole.
    Qt.callLater(function() { if (flick) flick.contentY = 0 })
  }

  // Collapsible section header: click toggles RECENT FILES visibility.
  Item {
    width: parent.width
    implicitHeight: recentsHeader.implicitHeight

    MouseArea {
      id: recentsToggle
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.collapsed = !root.collapsed
        root.resetScroll()
      }
    }

    Row {
      id: recentsHeader
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        text: "RECENT FILES"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      // Collapsed points right, expanded rotates down — mirrors the toggle.
      Text {
        textFormat: Text.PlainText
        text: "\u203A"
        color: root.foreground
        opacity: 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
        rotation: root.collapsed ? 0 : 90
        Behavior on rotation {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.collapsed ? "show" : "hide"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  Text {
    visible: root.empty && !root.collapsed
    width: parent.width
    text: "No synced files found."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
  }

  Item {
    id: viewport
    visible: !root.empty && !root.collapsed
    width: parent.width
    // Exactly 4 rows (4 heights + 3 gaps). Any extra bottom padding exposes a
    // sliver of the next row: hovering it fired onEntered on an offscreen row
    // and yanked the list a full stride down.
    height: (root.collapsed || root.empty) ? 0 : Math.min(4 * root.rowStride - root.listSpacing, flick.contentHeight || 9999)

    Flickable {
      id: flick
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: recentsList.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      onVisibleChanged: if (visible) contentY = 0
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: recentsList
        width: flick.width
        spacing: root.listSpacing

        Repeater {
          id: rowsRepeater
          model: root.files
          FileRow { }
        }
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    required property var modelData
    required property int index
    readonly property string fileName: modelData ? String(modelData.name || "Untitled") : "Untitled"

    width: recentsList.width
    hasCursor: root.activeRow === index
    foreground: root.foreground

    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    Component.onCompleted: if (index === 0) root.firstRowHeight = height
    onHeightChanged: if (index === 0) root.firstRowHeight = height

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onEntered: root.rowHovered(fileRow.index)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.shareLinkRequested(fileRow.modelData)
        else root.fileActivated(fileRow.modelData)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: fileRow.fileName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.modelData)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
