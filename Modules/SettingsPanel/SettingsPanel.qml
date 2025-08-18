import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Modules.SettingsPanel.Tabs as Tabs
import qs.Commons
import qs.Services
import qs.Widgets

NLoader {
  id: root

  // Tabs enumeration, order is NOT relevant
  enum Tab {
    About,
    AudioService,
    Bar,
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

  content: Component {
    NPanel {
      id: panel

      property int currentTabIndex: 0

      // Override hide function to animate first
      function hide() {
        // Start hide animation
        bgRect.scaleValue = 0.8
        bgRect.opacityValue = 0.0
        // Hide after animation completes
        hideTimer.start()
      }

      // Connect to NPanel's dismissed signal to handle external close events
      Connections {
        target: panel
        function onDismissed() {
          hide()
        }
      }

      // Timer to hide panel after animation
      Timer {
        id: hideTimer
        interval: Style.animationSlow
        repeat: false
        onTriggered: {
          panel.visible = false
          panel.dismissed()
        }
      }

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      Component {
        id: generalTab
        Tabs.GeneralTab {}
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

      // Order *DOES* matter
      property var tabsModel: [{
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
          "id": SettingsPanel.Tab.AudioService,
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
        }, {
          "id": SettingsPanel.Tab.WallpaperSelector,
          "label": "Wallpaper Selector",
          "icon": "wallpaper_slideshow",
          "source": wallpaperSelectorTab
        }, {
          "id": SettingsPanel.Tab.ScreenRecorder,
          "label": "Screen Recorder",
          "icon": "videocam",
          "source": screenRecorderTab
        }, {
          "id": SettingsPanel.Tab.About,
          "label": "About",
          "icon": "info",
          "source": aboutTab
        }]

      Component.onCompleted: {
        var initialIndex = 0
        if (root.requestedTab !== null) {
          for (var i = 0; i < panel.tabsModel.length; i++) {
            if (panel.tabsModel[i].id === root.requestedTab) {
              initialIndex = i
              break
            }
          }
        }
        // Now that the UI is settled, set the current tab index.
        panel.currentTabIndex = initialIndex
        show()
      }

      onVisibleChanged: {
        if (!visible && (bgRect.opacityValue > 0)) {
          hide()
        }
      }

      Rectangle {
        id: bgRect
        color: Color.mSurface
        radius: Style.radiusLarge * scaling
        border.color: Color.mOutlineVariant
        border.width: Math.max(1, Style.borderThin * scaling)
        layer.enabled: true
        width: Math.max(screen.width * 0.5, 1280) * scaling
        height: Math.max(screen.height * 0.5, 720) * scaling
        anchors.centerIn: parent

        // Animation properties
        property real scaleValue: 0.8
        property real opacityValue: 0.0

        scale: scaleValue
        opacity: opacityValue

        // Animate in when component is completed
        Component.onCompleted: {
          scaleValue = 1.0
          opacityValue = 1.0
        }

        MouseArea {
          anchors.fill: parent
        }

        Behavior on scale {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.OutExpo
          }
        }
        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginLarge * scaling
          spacing: Style.marginLarge * scaling

          Rectangle {
            id: sidebar
            Layout.preferredWidth: Style.sliderWidth * 1.3 * scaling
            Layout.fillHeight: true
            color: Color.mSurfaceVariant
            border.color: Color.mOutlineVariant
            border.width: Math.max(1, Style.borderThin * scaling)
            radius: Style.radiusMedium * scaling

            Column {
              anchors.fill: parent
              anchors.margins: Style.marginSmall * scaling
              spacing: Style.marginTiny * 1.5 * scaling

              Repeater {
                id: sections
                model: panel.tabsModel
                delegate: Rectangle {
                  id: tabItem
                  width: parent.width
                  height: 32 * scaling
                  radius: Style.radiusSmall * scaling
                  color: selected ? Color.mPrimary : (tabItem.hovering ? Color.mTertiary : Color.transparent)
                  readonly property bool selected: index === currentTabIndex
                  property bool hovering: false
                  property color tabTextColor: selected ? Color.mOnPrimary : (tabItem.hovering ? Color.mOnTertiary : Color.mOnSurface)
                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.marginSmall * scaling
                    anchors.rightMargin: Style.marginSmall * scaling
                    spacing: Style.marginSmall * scaling
                    // Tab icon on the left side
                    NIcon {
                      text: modelData.icon
                      color: tabTextColor
                      font.pointSize: Style.fontSizeLarge * scaling
                    }
                    // Tab label on the left side
                    NText {
                      text: modelData.label
                      color: tabTextColor
                      font.pointSize: Style.fontSizeMedium * scaling
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
            }
          }

          // Content
          Rectangle {
            id: contentPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.radiusMedium * scaling
            color: Color.mSurfaceVariant
            border.color: Color.mOutlineVariant
            border.width: Math.max(1, Style.borderThin * scaling)
            clip: true

            ColumnLayout {
              id: contentLayout
              anchors.fill: parent
              anchors.margins: Style.marginLarge * scaling
              spacing: Style.marginSmall * scaling

              RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Style.marginSmall * scaling

                // Tab label on the main right side
                NText {
                  text: panel.tabsModel[currentTabIndex].label
                  font.pointSize: Style.fontSizeLarge * scaling
                  font.weight: Style.fontWeightBold
                  color: Color.mPrimary
                  Layout.fillWidth: true
                }
                NIconButton {
                  icon: "close"
                  tooltipText: "Close"
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: panel.hide()
                }
              }

              NDivider {
                Layout.fillWidth: true
              }

              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Repeater {
                  model: panel.tabsModel

                  onItemAdded: function (index, item) {
                    item.sourceComponent = panel.tabsModel[index].source
                  }

                  delegate: Loader {
                    // All loaders will occupy the same space, stacked on top of each other.
                    anchors.fill: parent
                    visible: index === panel.currentTabIndex
                    // The loader is only active (and uses memory) when its page is visible.
                    active: visible
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
