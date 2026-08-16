import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest?.id || "yordanbuilds.jot"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/yordanbuilds.jot"

  property bool opened: false
  property string text: ""
  property string fontFamily: Style.font.menuFamily

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(
    contentMargin * 2 + Math.max(headerHeight, contentText.contentHeight + Style.spacing.controlPaddingY * 2),
    panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function submit() {
    var captured = root.text
    root.dismiss()
    if (!captured.trim()) return
    Quickshell.execDetached([root.pluginDir + "/bin/jot-append", captured])
  }

  // First-load omakase setup (config, keybinding, menu rows). Idempotent.
  Process {
    id: setupProcess
    command: [root.pluginDir + "/bin/jot-setup"]
  }
  Component.onCompleted: setupProcess.running = true

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var isEnter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (isEnter && (event.modifiers & Qt.ShiftModifier)) {
            root.text = root.text + "\n"
            event.accepted = true
          } else if (isEnter) {
            root.submit()
            event.accepted = true
          } else if (Util.editsFilter(event, root.text)) {
            root.text = Util.editedFilter(event, root.text)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.text = root.text + event.text
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: contentText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.text || "Jot something down…"
          color: root.foreground
          opacity: root.text ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
