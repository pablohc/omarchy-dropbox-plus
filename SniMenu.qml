import Quickshell
import Quickshell.Services.SystemTray

// Fires dropboxd's SNI DBus menu entries (Preferences, Snooze, …) without
// showing any menu.
//
// Entries are resolved STRUCTURALLY first — the menu tail is
// [..., Preferences, Help Center, Export Debug Logs, ---, Quit] in every
// locale, and the snooze entry is the last submenu — so the actions keep
// working when the daemon language changes ("Preferences..." /
// "Preferencias..."). Label matching stays as a fallback.
//
// History: an earlier version iterated the opener's children with .length
// and [i], but QsMenuOpener.children is an ObjectModel — the entries live in
// its `values` array.
QsMenuOpener {
  id: root

  // Pending lookup, retried on layout updates (bounded) because the DBus
  // layout may arrive incrementally after the menu is attached.
  property string pendingKind: ""
  property int fireAttempts: 0

  // Nested opener for submenu targets (Snooze → duration entries).
  property QsMenuOpener nestedOpener: QsMenuOpener {
    onChildrenChanged: root.nestedChildrenChanged()
  }
  property bool nestedPending: false
  property int nestedAttempts: 0

  // Emitted once a trigger attempt settles: ok=true when the DBus entry
  // fired, false when it could not be resolved. Drives the status line.
  signal finished(string kind, bool ok)

  onChildrenChanged: {
    if (root.pendingKind !== "" && root.fireAttempts < 5) {
      root.fireAttempts++
      root.tryFire()
    }
  }

  function nestedChildrenChanged() {
    if (root.nestedPending && root.nestedAttempts < 5) {
      root.nestedAttempts++
      root.tryFireNested()
    }
  }

  function entriesList() {
    var v = root.children.values
    return v ? v : []
  }

  function sane(e) {
    return e && !e.isSeparator && !e.hasChildren && e.enabled ? e : null
  }

  function firstSubmenuIndex(entries) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].hasChildren && !entries[i].isSeparator) return i
    }
    return -1
  }

  function lastSubmenu(entries) {
    var found = null
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].hasChildren && !entries[i].isSeparator) found = entries[i]
    }
    return found
  }

  // Resolves an action kind to a live menu entry, or null.
  function resolve(kind) {
    var entries = entriesList()
    var n = entries.length
    if (n === 0) return null

    // Tail block is locale-independent:
    // [..., Preferences, Help Center, Export Debug Logs, ---, Quit]
    if (kind === "preferences" && n >= 5) return sane(entries[n - 5])
    if (kind === "help" && n >= 4) return sane(entries[n - 4])

    if (kind === "space") {
      // The entry right after the separator that follows the first submenu
      // ("Recently Changed Files" → --- → Get More Space).
      var first = firstSubmenuIndex(entries)
      for (var i = first + 1; i < n && first >= 0; i++) {
        if (entries[i] && entries[i].isSeparator) {
          for (var j = i + 1; j < n; j++) {
            if (sane(entries[j])) return entries[j]
          }
        }
      }
      return null
    }

    if (kind === "snooze") {
      // The snooze entry is the menu's last submenu; its label varies with
      // state ("Snooze Notifications" / "Snoozing … until 3:42 PM").
      var last = lastSubmenu(entries)
      if (last) {
        var idx = entries.indexOf(last)
        if (idx > 0 && idx < n - 3) return last
      }
      return null
    }
    return null
  }

  // Label fallback for when a future dropboxd release reshuffles positions.
  function normalize(s) {
    return String(s || "").toLowerCase().replace(/[._\u2026\-\s]/g, "")
  }

  function findByLabel(kind) {
    var wanted = { "preferences": "Preferences", "space": "Get More Space", "help": "Help Center" }
    var entries = entriesList()
    var want = normalize(wanted[kind] || "")
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && normalize(entries[i].text) === want) return entries[i]
    }
    if (kind === "snooze") {
      for (var j = 0; j < entries.length; j++) {
        var e = entries[j]
        if (e && e.hasChildren && normalize(e.text).indexOf("snoo") === 0) return e
      }
    }
    return null
  }

  function tryFire() {
    var kind = root.pendingKind
    var entry = resolve(kind)
    if (!entry) entry = findByLabel(kind)
    if (!entry) {
      console.log("[pablohc.dropbox] SNI entry not resolvable:", kind,
                  "— menu has:", availableLabels())
      if (entriesList().length > 0 || root.fireAttempts >= 5) {
        root.finished(kind, false)
        root.clearPending()
      }
      return
    }
    if (kind === "snooze") {
      // Submenu target: fire the first duration entry inside it ("For the
      // next 30 minutes" — first enabled non-separator child in any locale).
      nestedOpener.menu = entry
      root.nestedPending = true
      root.nestedAttempts = 0
      root.tryFireNested()
      return
    }
    console.log("[pablohc.dropbox] triggering SNI entry:", kind, "→", String(entry.text))
    entry.triggered()
    root.finished(kind, true)
    root.clearPending()
  }

  function tryFireNested() {
    if (!root.nestedPending) return
    var entries = nestedOpener.children.values || []
    var entry = null
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && !entries[i].isSeparator && entries[i].enabled) {
        entry = entries[i]
        break
      }
    }
    if (!entry) {
      console.log("[pablohc.dropbox] SNI submenu duration entry not found")
      if (entries.length > 0 || root.nestedAttempts >= 5) {
        root.finished(root.pendingKind, false)
        root.clearPending()
      }
      return
    }
    console.log("[pablohc.dropbox] triggering SNI snooze duration:", String(entry.text))
    entry.triggered()
    root.finished(root.pendingKind, true)
    root.clearPending()
  }

  function clearPending() {
    root.pendingKind = ""
    root.fireAttempts = 0
    root.nestedPending = false
    root.nestedAttempts = 0
    nestedOpener.menu = null
  }

  function trigger(kind) {
    var item = findDropboxItem()
    if (!item || !item.menu) {
      console.log("[pablohc.dropbox] SNI dropbox item NOT found")
      root.finished(kind, false)
      return
    }
    root.clearPending()
    root.pendingKind = kind
    if (root.menu !== item.menu) {
      // First attach: children arrive asynchronously — retry on layout update.
      root.fireAttempts = 0
      root.menu = item.menu
      return
    }
    root.fireAttempts++
    root.tryFire()
  }

  // Diagnostics: attach the menu and return its current entry labels. The
  // first call right after a (re)attach may return an empty list while the
  // DBus layout round-trip completes; call again.
  function dump() {
    var item = findDropboxItem()
    if (!item || !item.menu) return "no dropbox SNI item found"
    root.menu = item.menu
    var entries = entriesList()
    if (entries.length === 0) return "(menu empty — children still populating, call again)"
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      out.push(i + ": [" + String(e ? e.text : "?") + "]" + (e && e.hasChildren ? " *" : "") + (e && e.isSeparator ? " ---" : ""))
    }
    return out.join("\n")
  }

  function availableLabels() {
    var out = []
    var entries = entriesList()
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      out.push(String(e ? e.text : "?") + (e && e.hasChildren ? "*" : ""))
    }
    return out.join(" | ")
  }

  function findDropboxItem() {
    var values = SystemTray.items.values
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      var hay = (String(item.id || "") + " " + String(item.title || "")).toLowerCase()
      if (hay.indexOf("dropbox") !== -1) return item
    }
    return null
  }
}
