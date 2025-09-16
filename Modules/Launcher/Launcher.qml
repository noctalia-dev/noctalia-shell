import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  // Panel configuration
  preferredWidth: 500
  preferredWidthRatio: 0.3
  preferredHeight: 600
  preferredHeightRatio: 0.5

  panelKeyboardFocus: false
  panelBackgroundColor: Qt.alpha(Color.mSurface, Settings.data.appLauncher.backgroundOpacity)

  // Positioning
  readonly property string launcherPosition: Settings.data.appLauncher.position
  panelAnchorHorizontalCenter: launcherPosition === "center" || launcherPosition.endsWith("_center")
  panelAnchorVerticalCenter: launcherPosition === "center"
  panelAnchorLeft: launcherPosition !== "center" && launcherPosition.endsWith("_left")
  panelAnchorRight: launcherPosition !== "center" && launcherPosition.endsWith("_right")
  panelAnchorBottom: launcherPosition.startsWith("bottom_")
  panelAnchorTop: launcherPosition.startsWith("top_")

  // Core state
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var plugins: []
  property var activePlugin: null

  readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6 * scaling)
  readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2 * scaling)

  // Public API for plugins
  function setSearchText(text) {
    searchText = text
  }

  // Plugin registration
  function registerPlugin(plugin) {
    plugins.push(plugin)
    plugin.launcher = root
    if (plugin.init)
      plugin.init()
  }

  // Search handling
  function updateResults() {
    results = []
    activePlugin = null

    // Check for command mode
    if (searchText.startsWith(">")) {
      // Find plugin that handles this command
      for (let plugin of plugins) {
        if (plugin.handleCommand && plugin.handleCommand(searchText)) {
          activePlugin = plugin
          results = plugin.getResults(searchText)
          break
        }
      }

      // Show available commands if just ">"
      if (searchText === ">" && !activePlugin) {
        for (let plugin of plugins) {
          if (plugin.commands) {
            results = results.concat(plugin.commands())
          }
        }
      }
    } else {
      // Regular search - let plugins contribute results
      for (let plugin of plugins) {
        if (plugin.handleSearch) {
          const pluginResults = plugin.getResults(searchText)
          results = results.concat(pluginResults)
        }
      }
    }

    selectedIndex = 0
  }

  onSearchTextChanged: updateResults()

  // Lifecycle
  onOpened: {
    root.panelKeyboardFocus = true
    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onOpened)
        plugin.onOpened()
    }
    updateResults()
  }

  onClosed: {
    // Reset search text
    searchText = ""

    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onClosed)
        plugin.onClosed()
    }
  }

  // Load plugins
  Component.onCompleted: {
    // Load applications plugin
    const appsPlugin = Qt.createComponent("Plugins/ApplicationsPlugin.qml").createObject(this)
    if (appsPlugin) {
      registerPlugin(appsPlugin)
      Logger.log("Launcher", "Registered: ApplicationsPlugin")
    } else {
      Logger.error("Launcher", "Failed to load ApplicationsPlugin")
    }

    // Load calculator plugin
    const calcPlugin = Qt.createComponent("Plugins/CalculatorPlugin.qml").createObject(this)
    if (calcPlugin) {
      registerPlugin(calcPlugin)
      Logger.log("Launcher", "Registered: CalculatorPlugin")
    } else {
      Logger.error("Launcher", "Failed to load CalculatorPlugin")
    }

    // Load clipboard history plugin
    const clipboardPlugin = Qt.createComponent("Plugins/ClipboardPlugin.qml").createObject(this)
    if (clipboardPlugin) {
      registerPlugin(clipboardPlugin)
      Logger.log("Launcher", "Registered: ClipboardPlugin")
    } else {
      Logger.error("Launcher", "Failed to load ClipboardPlugin")
    }
  }

  // UI
  panelContent: Rectangle {
    id: ui
    color: Color.transparent

    // ---------------------
    // Navigation
    function selectNext() {
      if (results.length > 0) {
        // Clamp the index to not exceed the last item
        selectedIndex = Math.min(selectedIndex + 1, results.length - 1)
      }
    }

    function selectPrevious() {
      if (results.length > 0) {
        // Clamp the index to not go below the first item (0)
        selectedIndex = Math.max(selectedIndex - 1, 0)
      }
    }

    function selectFirst() {
      selectedIndex = 0
    }

    function selectLast() {
      if (results.length > 0) {
        selectedIndex = results.length - 1
      } else {
        selectedIndex = 0
      }
    }

    function selectNextPage() {
      if (results.length > 0) {
        const page = Math.max(1, Math.floor(resultsList.height / entryHeight))
        selectedIndex = Math.min(selectedIndex + page, results.length - 1)
      }
    }
    function selectPreviousPage() {
      if (results.length > 0) {
        const page = Math.max(1, Math.floor(resultsList.height / entryHeight))
        selectedIndex = Math.max(selectedIndex - page, 0)
      }
    }

    function activate() {
      root.panelKeyboardFocus = false
      if (results.length > 0 && results[selectedIndex]) {
        const item = results[selectedIndex]
        if (item.onActivate) {
          item.onActivate()
        }
      }
    }

    Shortcut {
      sequence: "Ctrl+K"
      onActivated: ui.selectPrevious()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    Shortcut {
      sequence: "Ctrl+J"
      onActivated: ui.selectNext()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    Shortcut {
      sequence: "PgDown" // or "PageDown"
      onActivated: ui.selectNextPage()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    Shortcut {
      sequence: "PgUp" // or "PageUp"
      onActivated: ui.selectPreviousPage()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    Shortcut {
      sequence: "Home"
      onActivated: ui.selectFirst()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    Shortcut {
      sequence: "End"
      onActivated: ui.selectLast()
      enabled: root.opened && searchInput.inputItem && searchInput.inputItem.activeFocus
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      NTextInput {
        id: searchInput
        Layout.fillWidth: true

        fontSize: Style.fontSizeL * scaling
        fontWeight: Style.fontWeightSemiBold

        text: searchText
        placeholderText: "Search entries... or use > for commands"

        onTextChanged: searchText = text

        Component.onCompleted: {
          if (searchInput.inputItem && searchInput.inputItem.visible) {
            searchInput.inputItem.forceActiveFocus()

            // Override the TextField's default Home/End behavior
            searchInput.inputItem.Keys.priority = Keys.BeforeItem
            searchInput.inputItem.Keys.onPressed.connect(function (event) {
              // Intercept Home and End BEFORE the TextField handles them
              if (event.key === Qt.Key_Home) {
                ui.selectFirst()
                event.accepted = true
                return
              } else if (event.key === Qt.Key_End) {
                ui.selectLast()
                event.accepted = true
                return
              }
            })
            searchInput.inputItem.Keys.onDownPressed.connect(function (event) {
              ui.selectNext()
            })
            searchInput.inputItem.Keys.onUpPressed.connect(function (event) {
              ui.selectPrevious()
            })
            searchInput.inputItem.Keys.onReturnPressed.connect(function (event) {
              ui.activate()
            })
          }
        }
      }

      // Results list
      NListView {
        id: resultsList

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginXXS * scaling

        model: results
        currentIndex: selectedIndex

        clip: true
        cacheBuffer: resultsList.height * 2
        onCurrentIndexChanged: {
          cancelFlick()
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain)
          }
        }

        delegate: Rectangle {
          id: entry

          property bool isSelected: mouseArea.containsMouse || (index === selectedIndex)

          // Property to reliably track the current item's ID.
          // This changes whenever the delegate is recycled for a new item.
          property var currentClipboardId: modelData.isImage ? modelData.clipboardId : ""

          // When this delegate is assigned a new image item, trigger the decode.
          onCurrentClipboardIdChanged: {
            // Check if it's a valid ID and if the data isn't already cached.
            if (currentClipboardId && !ClipboardService.getImageData(currentClipboardId)) {
              ClipboardService.decodeToDataUrl(currentClipboardId, modelData.mime, null)
            }
          }

          width: resultsList.width - Style.marginS * scaling
          height: entryHeight
          radius: Style.radiusM * scaling
          color: entry.isSelected ? Color.mTertiary : Color.mSurface

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCirc
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginM * scaling

            // Icon badge or Image preview
            Rectangle {
              Layout.preferredWidth: badgeSize
              Layout.preferredHeight: badgeSize
              radius: Style.radiusM * scaling
              color: Color.mSurfaceVariant
              clip: true

              // Image preview for clipboard images
              NImageRounded {
                id: imagePreview
                anchors.fill: parent
                visible: modelData.isImage
                imageRadius: Style.radiusM * scaling

                // This property creates a dependency on the service's revision counter
                readonly property int _rev: ClipboardService.revision

                // Fetches from the service's cache.
                // The dependency on `_rev` ensures this binding is re-evaluated when the cache is updated.
                imagePath: {
                  _rev
                  return ClipboardService.getImageData(modelData.clipboardId) || ""
                }

                // Loading indicator
                Rectangle {
                  anchors.fill: parent
                  visible: parent.status === Image.Loading
                  color: Color.mSurfaceVariant

                  BusyIndicator {
                    anchors.centerIn: parent
                    running: true
                    width: Style.baseWidgetSize * 0.5 * scaling
                    height: width
                  }
                }

                // Error fallback
                onStatusChanged: status => {
                                   if (status === Image.Error) {
                                     iconLoader.visible = true
                                     imagePreview.visible = false
                                   }
                                 }
              }

              // Icon fallback
              Loader {
                id: iconLoader
                anchors.fill: parent
                anchors.margins: Style.marginXS * scaling

                visible: !modelData.isImage || imagePreview.status === Image.Error
                active: visible

                sourceComponent: Component {
                  IconImage {
                    anchors.fill: parent
                    source: modelData.icon ? AppIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                    visible: modelData.icon && source !== ""
                    asynchronous: true
                  }
                }
              }

              // Fallback text if no icon and no image
              NText {
                anchors.centerIn: parent
                visible: !imagePreview.visible && !iconLoader.visible
                text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                font.pointSize: Style.fontSizeXXL * scaling
                font.weight: Style.fontWeightBold
                color: Color.mOnPrimary
              }

              // Image type indicator overlay
              Rectangle {
                visible: modelData.isImage && imagePreview.visible
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 2 * scaling
                width: formatLabel.width + 6 * scaling
                height: formatLabel.height + 2 * scaling
                radius: Style.radiusM * scaling
                color: Color.mSurfaceVariant

                NText {
                  id: formatLabel
                  anchors.centerIn: parent
                  text: {
                    if (!modelData.isImage)
                      return ""
                    const desc = modelData.description || ""
                    const parts = desc.split(" • ")
                    return parts[0] || "IMG"
                  }
                  font.pointSize: Style.fontSizeXXS * scaling
                  color: Color.mPrimary
                }
              }
            }

            // Text content
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0 * scaling

              NText {
                text: modelData.name || "Unknown"
                font.pointSize: Style.fontSizeL * scaling
                font.weight: Style.fontWeightBold
                color: entry.isSelected ? Color.mOnTertiary : Color.mOnSurface
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              NText {
                text: modelData.description || ""
                font.pointSize: Style.fontSizeS * scaling
                color: entry.isSelected ? Color.mOnTertiary : Color.mOnSurfaceVariant
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
              }
            }
          }

          MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              selectedIndex = index
              ui.activate()
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Status
      NText {
        Layout.fillWidth: true
        text: {
          if (results.length === 0)
            return searchText ? "No results" : ""
          const prefix = activePlugin?.name ? `${activePlugin.name}: ` : ""
          return prefix + `${results.length} result${results.length !== 1 ? 's' : ''}`
        }
        font.pointSize: Style.fontSizeXS * scaling
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
