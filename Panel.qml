import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dropbox bar widget + panel: hero with sync switch, storage usage, quick
// actions, account entries fired through dropboxd's SNI DBus menu, and the
// collapsible recent-files section.
//
// Layout lives in RecentsSection/ActionRow/LoginButton/InfoPair; SNI menu
// firing lives in SniMenu. This file keeps state (keyboard cursor, focus
// section) and wiring.
Panel {
  id: root
  moduleName: "pablohc.dropbox"
  ipcTarget: "pablohc.dropbox"
  manageIpc: false

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string focusSection: "login"
  property int fileIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  // Keyboard cursor order and per-section row counts. "header" = the hero
  // switch; "actions"/"account" are the ActionRow groups; "files" is the
  // recent-files list.
  readonly property var navOrder: dropbox.authenticated
    ? ["header", "actions", "account", "files"]
    : ["login"]
  readonly property var navSizes: ({
    "login": 1,
    "header": 1,
    "actions": 3,
    "account": 4,
    "files": dropbox.files.length
  })

  readonly property var activePhrases: [
    "Filing files",
    "Distributing data",
    "Shuffling folders",
    "Boxing bytes",
    "Sorting stuff",
    "Syncing secrets",
    "Packing packets",
    "Moving memories",
    "Wrangling revisions",
    "Cataloging chaos"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: dropbox.authenticated && dropbox.active ? foreground : dim
  readonly property string toggleHint: dropbox.active ? "Pause syncing" : "Resume syncing"
  readonly property color barIconColor: dropbox.authenticated && dropbox.active ? barForeground : Qt.darker(barForeground, 1.55)
  // Only claim the header cursor when the switch is actually on screen —
  // "header" stays navigable, but an absent CLI leaves nothing to highlight.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && dropbox.installed

  function ensureCursor() {
    if (!dropbox.authenticated) {
      focusSection = "login"
      fileIndex = 0
      actionIndex = 0
      return
    }
    if (navOrder.indexOf(focusSection) < 0) focusSection = "header"
    if (focusSection === "files") {
      if (dropbox.files.length === 0) {
        focusSection = "header"
      } else if (fileIndex >= dropbox.files.length) {
        fileIndex = Math.max(0, dropbox.files.length - 1)
      }
    } else if (focusSection !== "header") {
      actionIndex = Math.max(0, Math.min(navSizes[focusSection] - 1, actionIndex))
    }
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    var i = navOrder.indexOf(focusSection)
    var row = focusSection === "files" ? fileIndex : actionIndex
    row += dy
    // Walk into the neighbouring section when crossing a boundary.
    while (row < 0 && i > 0) {
      i--
      row = navSizes[navOrder[i]] - 1
    }
    while (row > navSizes[navOrder[i]] - 1 && i < navOrder.length - 1) {
      i++
      row = 0
    }
    row = Math.max(0, Math.min(navSizes[navOrder[i]] - 1, row))
    focusSection = navOrder[i]
    applyCursorRow(row)
  }

  function applyCursorRow(row) {
    if (focusSection === "files") {
      fileIndex = row
      scrollCursorIntoView()
    } else {
      actionIndex = row
      if (focusSection === "header" && panelFlick) panelFlick.contentY = 0
    }
  }

  // Hover entry for ActionRow groups: highlight only — the list never moves
  // under a stationary pointer.
  function claimActionRow(section, index) {
    cursorActive = true
    focusSection = section
    actionIndex = index
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
  }

  function scrollCursorIntoView() {
    if (focusSection === "files") recents.revealRow(fileIndex)
  }

  function toggleRunning() {
    if (dropbox.installed && !dropbox.busy) dropbox.toggleRunning()
  }

  // Single source of truth for the action rows: mouse clicks (onActivated)
  // and keyboard Enter (activateCursor) both land here.
  function runRowAction(section, index) {
    if (section === "actions") {
      if (index === 0) dropbox.openFolder()
      else if (index === 1) dropbox.openWebsite()
      else if (index === 2 && !dropbox.busy) dropbox.refresh()
    } else if (section === "account") {
      if (index === 0) sniMenu.trigger("preferences")
      else if (index === 1) sniMenu.trigger("snooze")
      else if (index === 2) sniMenu.trigger("space")
      else if (index === 3) sniMenu.trigger("help")
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "login") dropbox.login()
    else if (focusSection === "header") toggleRunning()
    else if (focusSection === "actions" || focusSection === "account") runRowAction(focusSection, actionIndex)
    else if (focusSection === "files") dropbox.openFile(selectedFile())
  }

  function selectedFile() {
    if (dropbox.files.length === 0) return null
    return dropbox.files[Math.max(0, Math.min(fileIndex, dropbox.files.length - 1))]
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    dropbox.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: dropbox
    settings: root.settings
    omarchyPath: root.omarchyPath
  }

  SniMenu {
    id: sniMenu
    onFinished: function(kind, ok) {
      dropbox.notifyStatus(ok ? actionFeedback(kind) : "Could not trigger: " + kind)
    }
  }

  // Friendly status-line text for a fired SNI menu action kind.
  function actionFeedback(kind) {
    if (kind === "preferences") return "Opened Dropbox preferences"
    if (kind === "snooze") return "Notifications snoozed for 30 minutes"
    if (kind === "space") return "Opened Dropbox plans"
    if (kind === "help") return "Opened Dropbox Help Center"
    return kind
  }

  Connections {
    target: dropbox
    function onAuthenticatedChanged() { root.ensureCursor() }
    function onFilesChanged() {
      root.ensureCursor()
      // Files re-order on every sync; a stale contentY clips the first row
      // under the panel's bottom edge. Snap back to the top.
      if (panelFlick) panelFlick.contentY = 0
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { dropbox.refresh(); return "ok" }
    function login(): string { dropbox.login(); return "ok" }
    function status(): string { return dropbox.statusText }
    function menu(): string { return sniMenu.dump() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        DropboxIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: dropbox.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      // Left opens/closes the panel, middle logs in. Right click is ignored —
      // the base button surfaces a native menu there, which duplicated the
      // panel.
      if (buttonCode === Qt.MiddleButton) dropbox.login()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // pinnedHeader sits Style.space(6) below the card's top inset, and the
    // flickable hangs off its bottom edge — so the margin must be part of the
    // desired height. Omitting it shaved exactly that much off the block
    // below: with the section collapsed it sliced the RECENT FILES header
    // right through the text.
    contentHeight: panel.fittedContentHeight(Style.space(6) + pinnedHeader.implicitHeight + contentColumn.implicitHeight, Style.space(812))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") dropbox.refresh()
        else if (t === "l" || t === "L") dropbox.login()
        else if (t === "p" || t === "P") root.toggleRunning()
      }
    }

    // Pinned header (hero + Stored): stays visible while RECENT FILES scrolls.
    Column {
      id: pinnedHeader
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.space(6)
      spacing: Style.space(10)

      Column {
        id: header
        visible: dropbox.authenticated
        width: parent.width
        spacing: Style.space(12)
        // Exposed for the hero's trailingControl, whose `root` resolves to
        // PanelHero (not this Panel) — reach panel state via `header`.
        readonly property bool ringVisible: root.headerHasCursor
        function focusHero() { root.setHeaderCursor() }

        PanelHero {
          id: hero
          width: parent.width
          height: Style.space(56)
          title: "Dropbox"
          meta: dropbox.active ? root.heroPhraseText : "Syncing paused"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: dropbox.active ? 1.0 : 0.5
          // Status only — the switch owns toggling, mouse and keyboard alike.
          iconComponent: Component {
            DropboxIcon {
              iconSize: Style.font.display
              color: root.iconColor
            }
          }

          // Compact on/off switch on the trailing edge of the hero, and the
          // header's only cursor target. The service already flips `active`
          // optimistically, so the knob throws the instant you click it.
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: dropbox.installed
              checked: dropbox.active
              busy: dropbox.busy
              hasCursor: header.ringVisible
              foreground: hero.foreground
              onHovered: function(on) { if (on) header.focusHero() }
              onToggled: root.toggleRunning()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Column {
          visible: dropbox.authenticated
          width: parent.width
          spacing: Style.spacing.labelGap

          Column {
            width: parent.width - Style.space(16)
            spacing: Style.spacing.labelGap
            InfoPair { label: "Stored"; value: Model.usageText(dropbox.usedBytes, dropbox.quotaBytes, dropbox.quotaKnown, dropbox.usagePercent); foreground: root.foreground; fontFamily: root.fontFamily }
          }
        }
      }
    }

    Flickable {
      id: panelFlick
      anchors.top: pinnedHeader.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      contentWidth: width
      // The recent-files viewport owns scrolling; the panel itself never
      // scrolls — sections always fit, so any drift here is pure noise.
      contentHeight: height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: false
      // Clamp any residual sub-pixel drift so content stays flush with the frame.
      onContentYChanged: {
        if (contentY < 0) contentY = 0
        var maxY = Math.max(0, contentHeight - height)
        if (contentY > maxY) contentY = maxY
      }
      // Scrollbar hidden: AsNeeded kept a dark strip pinned to the right edge
      // even at exactly-fit heights (rounding). Wheel scrolling still works.
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

      Column {
        id: contentColumn
        width: panelFlick.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          visible: dropbox.actionStatus !== "" || dropbox.lastError !== ""
          width: parent.width
          text: dropbox.actionStatus !== "" ? dropbox.actionStatus : dropbox.lastError
          color: dropbox.lastError !== "" && dropbox.actionStatus === "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        LoginButton {
          visible: !dropbox.authenticated
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
          installed: dropbox.installed
          busy: dropbox.busy
          hasCursor: root.cursorActive && root.focusSection === "login"
          onActivated: dropbox.login()
          onCursorClaimed: {
            root.cursorActive = true
            root.focusSection = "login"
          }
        }

        PanelSeparator {
          visible: dropbox.authenticated
          foreground: root.foreground
        }

        Column {
          visible: dropbox.authenticated
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "ACTIONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\uF07B"
            actionText: "Open Dropbox folder"
            actionHint: "Browse synced files in the file manager"
            hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 0
            onCursorClaimed: root.claimActionRow("actions", 0)
            onActivated: root.runRowAction("actions", 0)
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\uF0AC"
            actionText: "Open dropbox.com"
            actionHint: "Web interface — manage sharing and account settings"
            hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 1
            onCursorClaimed: root.claimActionRow("actions", 1)
            onActivated: root.runRowAction("actions", 1)
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\u{F0450}"
            actionText: "Refresh status"
            actionHint: "Re-check sync state now"
            rowEnabled: !dropbox.busy
            hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === 2
            onCursorClaimed: root.claimActionRow("actions", 2)
            onActivated: root.runRowAction("actions", 2)
          }
        }

        PanelSeparator {
          visible: dropbox.authenticated
          foreground: root.foreground
        }

        Column {
          visible: dropbox.authenticated
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "ACCOUNT & SETTINGS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\u{F0493}"
            actionText: "Preferences"
            actionHint: "Language, bandwidth, proxies, selective sync"
            hasCursor: root.cursorActive && root.focusSection === "account" && root.actionIndex === 0
            onCursorClaimed: root.claimActionRow("account", 0)
            onActivated: root.runRowAction("account", 0)
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\uF0F3"
            actionText: "Snooze notifications"
            actionHint: "Pause Dropbox alerts for 30 minutes"
            hasCursor: root.cursorActive && root.focusSection === "account" && root.actionIndex === 1
            onCursorClaimed: root.claimActionRow("account", 1)
            onActivated: root.runRowAction("account", 1)
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\uF07A"
            actionText: "Get more space"
            actionHint: "Upgrade your Dropbox plan"
            hasCursor: root.cursorActive && root.focusSection === "account" && root.actionIndex === 2
            onCursorClaimed: root.claimActionRow("account", 2)
            onActivated: root.runRowAction("account", 2)
          }

          ActionRow {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconGlyph: "\uF059"
            actionText: "Help Center"
            actionHint: "Documentation and support"
            hasCursor: root.cursorActive && root.focusSection === "account" && root.actionIndex === 3
            onCursorClaimed: root.claimActionRow("account", 3)
            onActivated: root.runRowAction("account", 3)
          }
        }

        RecentsSection {
          id: recents
          visible: dropbox.authenticated
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
          files: dropbox.files
          activeRow: root.cursorActive && root.focusSection === "files" ? root.fileIndex : -1
          onRowHovered: function(index) { root.setFileCursor(index) }
          onFileActivated: function(file) { dropbox.openFile(file) }
          onShareLinkRequested: function(file) { dropbox.copyShareLink(file) }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && dropbox.authenticated && dropbox.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }
}
