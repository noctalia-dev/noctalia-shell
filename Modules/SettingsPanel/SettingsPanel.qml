import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Modules.SettingsPanel.Tabs as Tabs
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: {
    var w = Math.round(Math.max(screen?.width * 0.4, 1000) * scaling)
    w = Math.min(w, screen?.width - Style.marginL * 2)
    return w
  }
  panelHeight: {
    var h = Math.round(Math.max(screen?.height * 0.75, 800) * scaling)
    h = Math.min(h, screen?.height - Style.barHeight * scaling - Style.marginL * 2)
    return h
  }
  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  panelKeyboardFocus: true

  // Tabs enumeration, order is NOT relevant
  enum Tab {
    About,
    Audio,
    Bar,
    Hooks,
    Launcher,
    Brightness,
    ColorScheme,
    Display,
    General,
    Network,
    ScreenRecorder,
    TimeWeather,
    Wallpaper,
    WallpaperSelector
  }

  property int requestedTab: SettingsPanel.Tab.General
  property int currentTabIndex: 0
  property var tabsModel: []
  property var activeScrollView: null

  Connections {
    target: Settings.data.wallpaper
    function onEnabledChanged() {
      updateTabsModel()
    }
  }

  Component.onCompleted: {
    updateTabsModel()
  }

  Component {
    id: generalTab
    Tabs.GeneralTab {}
  }
  Component {
    id: launcherTab
    Tabs.LauncherTab {}
  }
  Component {
    id: barTab
    Tabs.BarTab {}
  }

  Component {
    id: audioTab
    Tabs.AudioTab {}
  }
  Component {
    id: brightnessTab
    Tabs.BrightnessTab {}
  }
  Component {
    id: displayTab
    Tabs.DisplayTab {}
  }
  Component {
    id: networkTab
    Tabs.NetworkTab {}
  }
  Component {
    id: timeWeatherTab
    Tabs.TimeWeatherTab {}
  }
  Component {
    id: colorSchemeTab
    Tabs.ColorSchemeTab {}
  }
  Component {
    id: wallpaperTab
    Tabs.WallpaperTab {}
  }
  Component {
    id: wallpaperSelectorTab
    Tabs.WallpaperSelectorTab {}
  }
  Component {
    id: screenRecorderTab
    Tabs.ScreenRecorderTab {}
  }
  Component {
    id: aboutTab
    Tabs.AboutTab {}
  }
  Component {
    id: hooksTab
    Tabs.HooksTab {}
  }

  // Order *DOES* matter
  function updateTabsModel() {
    let newTabs = [{
                     "id": SettingsPanel.Tab.General,
                     "label": "General",
                     "icon": "tune",
                     "source": generalTab
                   }, {
                     "id": SettingsPanel.Tab.Bar,
                     "label": "Bar",
                     "icon": "web_asset",
                     "source": barTab
                   }, {
                     "id": SettingsPanel.Tab.Launcher,
                     "label": "Launcher",
                     "icon": "apps",
                     "source": launcherTab
                   }, {
                     "id": SettingsPanel.Tab.Audio,
                     "label": "Audio",
                     "icon": "volume_up",
                     "source": audioTab
                   }, {
                     "id": SettingsPanel.Tab.Display,
                     "label": "Display",
                     "icon": "monitor",
                     "source": displayTab
                   }, {
                     "id": SettingsPanel.Tab.Network,
                     "label": "Network",
                     "icon": "lan",
                     "source": networkTab
                   }, {
                     "id": SettingsPanel.Tab.Brightness,
                     "label": "Brightness",
                     "icon": "brightness_6",
                     "source": brightnessTab
                   }, {
                     "id": SettingsPanel.Tab.TimeWeather,
                     "label": "Time & Weather",
                     "icon": "schedule",
                     "source": timeWeatherTab
                   }, {
                     "id": SettingsPanel.Tab.ColorScheme,
                     "label": "Color Scheme",
                     "icon": "palette",
                     "source": colorSchemeTab
                   }, {
                     "id": SettingsPanel.Tab.Wallpaper,
                     "label": "Wallpaper",
                     "icon": "image",
                     "source": wallpaperTab
                   }]

    // Only add the Wallpaper Selector tab if the feature is enabled
    if (Settings.data.wallpaper.enabled) {
      newTabs.push({
                     "id": SettingsPanel.Tab.WallpaperSelector,
                     "label": "Wallpaper Selector",
                     "icon": "wallpaper_slideshow",
                     "source": wallpaperSelectorTab
                   })
    }

    newTabs.push({
                   "id": SettingsPanel.Tab.ScreenRecorder,
                   "label": "Screen Recorder",
                   "icon": "videocam",
                   "source": screenRecorderTab
                 }, {
                   "id": SettingsPanel.Tab.Hooks,
                   "label": "Hooks",
                   "icon": "cable",
                   "source": hooksTab
                 }, {
                   "id": SettingsPanel.Tab.About,
                   "label": "About",
                   "icon": "info",
                   "source": aboutTab
                 })

    root.tabsModel = newTabs // Assign the generated list to the model
  }
  // When the panel opens, choose the appropriate tab
  onOpened: {
    updateTabsModel()

    var initialIndex = SettingsPanel.Tab.General
    if (root.requestedTab !== null) {
      for (var i = 0; i < root.tabsModel.length; i++) {
        if (root.tabsModel[i].id === root.requestedTab) {
          initialIndex = i
          break
        }
      }
    }
    // Now that the UI is settled, set the current tab index.
    root.currentTabIndex = initialIndex
  }

  // Add scroll functions
  function scrollDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical
      const stepSize = activeScrollView.height * 0.1 // Scroll 10% of viewport
      scrollBar.position = Math.min(scrollBar.position + stepSize / activeScrollView.contentHeight,
                                    1.0 - scrollBar.size)
    }
  }

  function scrollUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical
      const stepSize = activeScrollView.height * 0.1 // Scroll 10% of viewport
      scrollBar.position = Math.max(scrollBar.position - stepSize / activeScrollView.contentHeight, 0)
    }
  }

  function scrollPageDown() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical
      const pageSize = activeScrollView.height * 0.9 // Scroll 90% of viewport
      scrollBar.position = Math.min(scrollBar.position + pageSize / activeScrollView.contentHeight,
                                    1.0 - scrollBar.size)
    }
  }

  function scrollPageUp() {
    if (activeScrollView && activeScrollView.ScrollBar.vertical) {
      const scrollBar = activeScrollView.ScrollBar.vertical
      const pageSize = activeScrollView.height * 0.9 // Scroll 90% of viewport
      scrollBar.position = Math.max(scrollBar.position - pageSize / activeScrollView.contentHeight, 0)
    }
  }

  // Add navigation functions
  function selectNextTab() {
    if (tabsModel.length > 0) {
      currentTabIndex = (currentTabIndex + 1) % tabsModel.length
    }
  }

  function selectPreviousTab() {
    if (tabsModel.length > 0) {
      currentTabIndex = (currentTabIndex - 1 + tabsModel.length) % tabsModel.length
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    // Main layout container that fills the panel
    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: 0

      // Keyboard shortcuts container
      Item {
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0

        // Scrolling via keyboard
        Shortcut {
          sequence: "Down"
          onActivated: root.scrollDown()
          enabled: root.opened
        }

        Shortcut {
          sequence: "Up"
          onActivated: root.scrollUp()
          enabled: root.opened
        }

        Shortcut {
          sequence: "Ctrl+J"
          onActivated: root.scrollDown()
          enabled: root.opened
        }

        Shortcut {
          sequence: "Ctrl+K"
          onActivated: root.scrollUp()
          enabled: root.opened
        }

        Shortcut {
          sequence: "PgDown"
          onActivated: root.scrollPageDown()
          enabled: root.opened
        }

        Shortcut {
          sequence: "PgUp"
          onActivated: root.scrollPageUp()
          enabled: root.opened
        }

        // Changing tab via keyboard
        Shortcut {
          sequence: "Tab"
          onActivated: root.selectNextTab()
          enabled: root.opened
        }

        Shortcut {
          sequence: "Shift+Tab"
          onActivated: root.selectPreviousTab()
          enabled: root.opened
        }
      }

      // Main content area
      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginM * scaling

        // Sidebar
        Rectangle {
          id: sidebar
          Layout.preferredWidth: 220 * scaling
          Layout.fillHeight: true
          Layout.alignment: Qt.AlignTop
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Math.max(1, Style.borderS * scaling)
          radius: Style.radiusM * scaling

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton // Don't interfere with clicks
            property int wheelAccumulator: 0
            onWheel: wheel => {
                       wheelAccumulator += wheel.angleDelta.y
                       if (wheelAccumulator >= 120) {
                         root.selectPreviousTab()
                         wheelAccumulator = 0
                       } else if (wheelAccumulator <= -120) {
                         root.selectNextTab()
                         wheelAccumulator = 0
                       }
                       wheel.accepted = true
                     }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS * scaling
            spacing: Style.marginXS * scaling

            Repeater {
              id: sections
              model: root.tabsModel
              delegate: Rectangle {
                id: tabItem
                Layout.fillWidth: true
                Layout.preferredHeight: tabEntryRow.implicitHeight + Style.marginS * scaling * 2
                radius: Style.radiusS * scaling
                color: selected ? Color.mPrimary : (tabItem.hovering ? Color.mTertiary : Color.transparent)
                readonly property bool selected: index === currentTabIndex
                property bool hovering: false
                property color tabTextColor: selected ? Color.mOnPrimary : (tabItem.hovering ? Color.mOnTertiary : Color.mOnSurface)

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                Behavior on tabTextColor {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }

                RowLayout {
                  id: tabEntryRow
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginS * scaling
                  anchors.rightMargin: Style.marginS * scaling
                  spacing: Style.marginS * scaling

                  // Tab icon
                  NIcon {
                    text: modelData.icon
                    color: tabTextColor
                    font.pointSize: Style.fontSizeL * scaling
                  }

                  // Tab label
                  NText {
                    text: modelData.label
                    color: tabTextColor
                    font.pointSize: Style.fontSizeM * scaling
                    font.weight: Style.fontWeightBold
                    Layout.fillWidth: true
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton
                  onEntered: tabItem.hovering = true
                  onExited: tabItem.hovering = false
                  onCanceled: tabItem.hovering = false
                  onClicked: currentTabIndex = index
                }
              }
            }

            Item {
              Layout.fillHeight: true
            }
          }
        }

        // Content pane
        Rectangle {
          id: contentPane
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.alignment: Qt.AlignTop
          radius: Style.radiusM * scaling
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Math.max(1, Style.borderS * scaling)
          clip: true

          ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: Style.marginL * scaling
            spacing: Style.marginS * scaling

            // Header row
            RowLayout {
              id: headerRow
              Layout.fillWidth: true
              spacing: Style.marginS * scaling

              // Tab title
              NText {
                text: root.tabsModel[currentTabIndex]?.label || ""
                font.pointSize: Style.fontSizeXL * scaling
                font.weight: Style.fontWeightBold
                color: Color.mPrimary
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              // Close button
              NIconButton {
                icon: "close"
                tooltipText: "Close"
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.close()
              }
            }

            // Divider
            NDivider {
              Layout.fillWidth: true
            }

            // Tab content area
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              color: Color.transparent

              Repeater {
                model: root.tabsModel
                delegate: Loader {
                  anchors.fill: parent
                  active: index === root.currentTabIndex

                  onStatusChanged: {
                    if (status === Loader.Ready && item) {
                      // Find and store reference to the ScrollView
                      const scrollView = item.children[0]
                      if (scrollView && scrollView.toString().includes("ScrollView")) {
                        root.activeScrollView = scrollView
                      }
                    }
                  }

                  sourceComponent: Flickable {
                    // Using a Flickable here with a pressDelay to fix conflict between
                    // ScrollView and NTextInput. This fixes the weird text selection issue.
                    id: flickable
                    anchors.fill: parent
                    pressDelay: 200

                    ScrollView {
                      id: scrollView
                      anchors.fill: parent
                      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                      ScrollBar.vertical.policy: ScrollBar.AsNeeded
                      padding: Style.marginL * scaling
                      clip: true

                      Component.onCompleted: {
                        root.activeScrollView = scrollView
                      }

                      Loader {
                        active: true
                        sourceComponent: root.tabsModel[index]?.source
                        width: scrollView.availableWidth
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
