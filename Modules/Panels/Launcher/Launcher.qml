import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.MainScreen
import "Plugins"

SmartPanel {
  id: root

  // Panel configuration
  preferredWidth: 500 * Style.uiScaleRatio
  preferredHeight: 600 * Style.uiScaleRatio
  preferredWidthRatio: 0.3
  preferredHeightRatio: 0.5

  panelBackgroundColor: Qt.alpha(Color.mSurface, Settings.data.appLauncher.backgroundOpacity)

  // Positioning
  readonly property string panelPosition: {
    if (Settings.data.appLauncher.position === "follow_bar") {
      if (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") {
        return `center_${Settings.data.bar.position}`
      } else {
        return `${Settings.data.bar.position}_center`
      }
    } else {
      return Settings.data.appLauncher.position
    }
  }
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  // Core state
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var plugins: []
  property var activePlugin: null
  property bool resultsReady: false
  property bool ignoreMouseHover: false

  readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6)
  readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2)

  // Override keyboard handlers from SmartPanel for navigation
  function onTabPressed() {
    selectNextWrapped()
  }

  function onShiftTabPressed() {
    selectPreviousWrapped()
  }

  function onUpPressed() {
    selectPreviousWrapped()
  }

  function onDownPressed() {
    selectNextWrapped()
  }

  function onReturnPressed() {
    activate()
  }

  function onHomePressed() {
    selectFirst()
  }

  function onEndPressed() {
    selectLast()
  }

  function onPageUpPressed() {
    selectPreviousPage()
  }

  function onPageDownPressed() {
    selectNextPage()
  }

  function onCtrlJPressed() {
    selectNextWrapped()
  }

  function onCtrlKPressed() {
    selectPreviousWrapped()
  }

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
    resultsReady = false
    ignoreMouseHover = true

    // Notify plugins and update results
    // Use Qt.callLater to ensure plugins are registered (Component.onCompleted runs first)
    Qt.callLater(() => {
                   for (let plugin of plugins) {
                     if (plugin.onOpened)
                     plugin.onOpened()
                   }
                   updateResults()
                   resultsReady = true
                 })
  }

  onClosed: {
    // Reset search text
    searchText = ""
    ignoreMouseHover = true

    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onClosed)
        plugin.onClosed()
    }
  }

  // Plugin components - declared inline so imports work correctly
  ApplicationsPlugin {
    id: appsPlugin
    Component.onCompleted: {
      registerPlugin(this)
      Logger.d("Launcher", "Registered: ApplicationsPlugin")
    }
  }

  CalculatorPlugin {
    id: calcPlugin
    Component.onCompleted: {
      registerPlugin(this)
      Logger.d("Launcher", "Registered: CalculatorPlugin")
    }
  }

  ClipboardPlugin {
    id: clipPlugin
    Component.onCompleted: {
      if (Settings.data.appLauncher.enableClipboardHistory) {
        registerPlugin(this)
        Logger.d("Launcher", "Registered: ClipboardPlugin")
      }
    }
  }

  // Navigation functions
  function selectNextWrapped() {
    if (results.length > 0) {
      selectedIndex = (selectedIndex + 1) % results.length
    }
  }

  function selectPreviousWrapped() {
    if (results.length > 0) {
      selectedIndex = (((selectedIndex - 1) % results.length) + results.length) % results.length
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
      const page = Math.max(1, Math.floor(600 / entryHeight)) // Use approximate height
      selectedIndex = Math.min(selectedIndex + page, results.length - 1)
    }
  }

  function selectPreviousPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight)) // Use approximate height
      selectedIndex = Math.max(selectedIndex - page, 0)
    }
  }

  function activate() {
    if (results.length > 0 && results[selectedIndex]) {
      const item = results[selectedIndex]
      if (item.onActivate) {
        item.onActivate()
      }
    }
  }

  // UI
  panelContent: Rectangle {
    id: ui
    color: Color.transparent
    opacity: resultsReady ? 1.0 : 0.0

    // Global MouseArea to detect mouse movement
    MouseArea {
      id: mouseMovementDetector
      anchors.fill: parent
      z: -999
      hoverEnabled: true
      propagateComposedEvents: true
      acceptedButtons: Qt.NoButton

      property real lastX: 0
      property real lastY: 0
      property bool initialized: false

      onPositionChanged: mouse => {
                           // Store initial position
                           if (!initialized) {
                             lastX = mouse.x
                             lastY = mouse.y
                             initialized = true
                             return
                           }

                           // Check if mouse actually moved
                           const deltaX = Math.abs(mouse.x - lastX)
                           const deltaY = Math.abs(mouse.y - lastY)
                           if (deltaX > 1 || deltaY > 1) {
                             root.ignoreMouseHover = false
                             lastX = mouse.x
                             lastY = mouse.y
                           }
                         }

      // Reset when launcher opens
      Connections {
        target: root
        function onOpened() {
          mouseMovementDetector.initialized = false
        }
      }
    }

    // Focus management
    Connections {
      target: root
      function onOpened() {
        // Delay focus to ensure window has keyboard focus
        Qt.callLater(() => {
                       if (searchInput.inputItem) {
                         searchInput.inputItem.forceActiveFocus()
                       }
                     })
      }
    }

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      NTextInput {
        id: searchInput
        Layout.fillWidth: true

        fontSize: Style.fontSizeL
        fontWeight: Style.fontWeightSemiBold

        text: searchText
        placeholderText: I18n.tr("placeholders.search-launcher")

        onTextChanged: searchText = text

        Component.onCompleted: {
          if (searchInput.inputItem) {
            searchInput.inputItem.forceActiveFocus()
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
        spacing: Style.marginXXS
        model: results
        currentIndex: selectedIndex
        cacheBuffer: resultsList.height * 2
        onCurrentIndexChanged: {
          cancelFlick()
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain)
          }
        }
        onModelChanged: {

        }

        delegate: Rectangle {
          id: entry

          property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)
          // Accessor for app id
          property string appId: (modelData && modelData.appId) ? String(modelData.appId) : ""

          // Pin helpers
          function togglePin(appId) {
            if (!appId)
              return
            let arr = (Settings.data.dock.pinnedApps || []).slice()
            const idx = arr.indexOf(appId)
            if (idx >= 0)
              arr.splice(idx, 1)
            else
              arr.push(appId)
            Settings.data.dock.pinnedApps = arr
          }

          function isPinned(appId) {
            const arr = Settings.data.dock.pinnedApps || []
            return appId && arr.indexOf(appId) >= 0
          }

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

          width: resultsList.width - Style.marginS
          implicitHeight: entryHeight
          radius: Style.radiusM
          color: entry.isSelected ? Color.mHover : Color.mSurface

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCirc
            }
          }

          ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            // Top row - Main entry content with pin button
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              // Icon badge or Image preview
              Rectangle {
                Layout.preferredWidth: badgeSize
                Layout.preferredHeight: badgeSize
                radius: Style.radiusM
                color: Color.mSurfaceVariant

                // Image preview for clipboard images
                NImageRounded {
                  id: imagePreview
                  anchors.fill: parent
                  visible: modelData.isImage
                  imageRadius: Style.radiusM

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
                      width: Style.baseWidgetSize * 0.5
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
                  anchors.margins: Style.marginXS

                  visible: !modelData.isImage || imagePreview.status === Image.Error
                  active: visible

                  sourceComponent: Component {
                    IconImage {
                      anchors.fill: parent
                      source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
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
                  pointSize: Style.fontSizeXXL
                  font.weight: Style.fontWeightBold
                  color: Color.mOnPrimary
                }

                // Image type indicator overlay
                Rectangle {
                  visible: modelData.isImage && imagePreview.visible
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: 2
                  width: formatLabel.width + 6
                  height: formatLabel.height + 2
                  radius: Style.radiusM
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
                    pointSize: Style.fontSizeXXS
                    color: Color.mPrimary
                  }
                }
              }

              // Text content
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                NText {
                  text: modelData.name || "Unknown"
                  pointSize: Style.fontSizeL
                  font.weight: Style.fontWeightBold
                  color: entry.isSelected ? Color.mOnHover : Color.mOnSurface
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                NText {
                  text: modelData.description || ""
                  pointSize: Style.fontSizeS
                  color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  visible: text !== ""
                }
              }

              // Pin/Unpin action icon button
              NIconButton {
                visible: !!entry.appId && !modelData.isImage && entry.isSelected && (Settings.data.dock.monitors && Settings.data.dock.monitors.length > 0)
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                icon: entry.isPinned(entry.appId) ? "unpin" : "pin"
                tooltipText: entry.isPinned(entry.appId) ? I18n.tr("launcher.unpin") : I18n.tr("launcher.pin")
                onClicked: entry.togglePin(entry.appId)
              }
            }
          }

          MouseArea {
            id: mouseArea
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
              if (!root.ignoreMouseHover) {
                selectedIndex = index
              }
            }
            onClicked: mouse => {
                         if (mouse.button === Qt.LeftButton) {
                           selectedIndex = index
                           root.activate()
                           mouse.accepted = true
                         }
                       }
            acceptedButtons: Qt.LeftButton
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
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
