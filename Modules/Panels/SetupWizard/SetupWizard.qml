import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  // When true, only shows step 0 with modified text for returning users (telemetry notification)
  property bool telemetryOnlyMode: false

  signal telemetryWizardCompleted

  preferredWidth: Math.round(preferredWidthRatio * 2560 * Style.uiScaleRatio)
  preferredHeight: Math.round(preferredHeightRatio * 1440 * Style.uiScaleRatio)
  preferredWidthRatio: 0.4
  preferredHeightRatio: root.telemetryOnlyMode ? 0.45 : 0.6

  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  closeWithEscape: false

  panelContent: Item {
    id: panelContent

    // Wizard state (lazy-loaded with panelContent)
    property int currentStep: 0
    readonly property int totalSteps: root.telemetryOnlyMode ? 1 : 5
    property bool isCompleting: false

    // Setup wizard data
    property string selectedWallpaperDirectory: Settings.defaultWallpapersDirectory
    property string selectedWallpaper: ""
    property real selectedScaleRatio: 1.0
    property string selectedBarPosition: "top"

    Component.onCompleted: {
      selectedScaleRatio = Settings.data.general.scaleRatio;
      selectedBarPosition = Settings.data.bar.position;
      selectedWallpaperDirectory = Settings.data.wallpaper.directory || Settings.defaultWallpapersDirectory;
    }

    Connections {
      target: Settings
      function onSettingsSaved() {
        if (panelContent.isCompleting) {
          Logger.i("SetupWizard", "Settings saved, closing panel");
          panelContent.isCompleting = false;
          root.close();
        }
      }
    }

    Timer {
      id: closeTimer
      interval: 2000
      onTriggered: {
        if (panelContent.isCompleting) {
          Logger.w("SetupWizard", "Settings save timeout, closing panel anyway");
          panelContent.isCompleting = false;
          root.close();
        }
      }
    }

    function completeSetup() {
      if (isCompleting) {
        Logger.w("SetupWizard", "completeSetup() called while already completing, ignoring");
        return;
      }

      try {
        Logger.i("SetupWizard", root.telemetryOnlyMode ? "Completing telemetry wizard" : "Completing setup with selected options");
        isCompleting = true;

        // In telemetry-only mode, we only need to save the telemetry setting
        if (!root.telemetryOnlyMode) {
          if (typeof WallpaperService !== "undefined" && WallpaperService.refreshWallpapersList) {
            if (selectedWallpaperDirectory !== Settings.data.wallpaper.directory) {
              Settings.data.wallpaper.directory = selectedWallpaperDirectory;
              WallpaperService.refreshWallpapersList();
            }

            if (selectedWallpaper !== "") {
              WallpaperService.changeWallpaper(selectedWallpaper, undefined);
            }
          }

          Settings.data.general.scaleRatio = selectedScaleRatio;
          Settings.data.bar.position = selectedBarPosition;
        }

        // Mark the current version as seen to prevent telemetry wizard on next startup
        // (only for full setup wizard - telemetry wizard lets changelog mark it seen)
        if (!root.telemetryOnlyMode) {
          UpdateService.markChangelogSeen(UpdateService.currentVersion);
        }

        // Initialize telemetry now that user has made their choice
        TelemetryService.init();

        // Save settings immediately and wait for settingsSaved signal before closing
        Settings.saveImmediate();
        Logger.i("SetupWizard", "Setup completed successfully, waiting for settings save confirmation");

        // Emit signal for telemetry wizard completion (shell.qml will show changelog)
        if (root.telemetryOnlyMode) {
          root.telemetryWizardCompleted();
        }

        // Fallback: if settingsSaved signal doesn't fire within 2 seconds, close anyway
        closeTimer.start();
      } catch (error) {
        Logger.e("SetupWizard", "Error completing setup:", error);
        isCompleting = false;
      }
    }

    function applyWallpaperSettings() {
      if (typeof WallpaperService !== "undefined" && WallpaperService.refreshWallpapersList) {
        if (selectedWallpaperDirectory !== Settings.data.wallpaper.directory) {
          Settings.data.wallpaper.directory = selectedWallpaperDirectory;
          WallpaperService.refreshWallpapersList();
        }

        if (selectedWallpaper !== "") {
          WallpaperService.changeWallpaper(selectedWallpaper, undefined);
        }
      }
    }

    function applyUISettings() {
      Settings.data.general.scaleRatio = selectedScaleRatio;
      Settings.data.bar.position = selectedBarPosition;
    }

    ColumnLayout {
      id: wizardContent
      anchors.fill: parent
      anchors.margins: Style.marginXL
      spacing: Style.marginL

      // Step content - takes most of the space
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Math.round(300 * Style.uiScaleRatio)

        StackLayout {
          id: stepStack
          anchors.fill: parent
          currentIndex: currentStep

          // Step 0: Welcome - Beautiful centered design
          Item {
            ColumnLayout {
              anchors.centerIn: parent
              width: Math.round(Math.max(parent.width * 0.5, 420))
              spacing: Style.marginXL

              // Logo with subtle glow effect
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                  anchors.centerIn: parent
                  width: 120
                  height: 120
                  radius: width / 2
                  color: Color.mPrimary
                  opacity: 0.08
                  scale: 1.3
                }

                Image {
                  anchors.centerIn: parent
                  width: 110
                  height: 110
                  source: Qt.resolvedUrl(Quickshell.shellDir + "/Assets/noctalia.svg")
                  fillMode: Image.PreserveAspectFit
                  smooth: true

                  Rectangle {
                    anchors.fill: parent
                    color: Color.mSurfaceVariant
                    radius: width / 2
                    border.color: Color.mOutline
                    border.width: Style.borderM
                    visible: parent.status === Image.Error

                    NIcon {
                      icon: "sparkles"
                      pointSize: Style.fontSizeXXL * 1.5
                      color: Color.mPrimary
                      anchors.centerIn: parent
                    }
                  }

                  // Subtle pulse animation
                  SequentialAnimation on scale {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation {
                      from: 1.0
                      to: 1.05
                      duration: 2000
                      easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                      from: 1.05
                      to: 1.0
                      duration: 2000
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }

              // Welcome text with gradient feel
              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.marginM

                NText {
                  text: root.telemetryOnlyMode ? I18n.tr("setup.telemetry-wizard-title") : I18n.tr("setup.welcome-title")
                  pointSize: Style.fontSizeXXL * 1.4
                  font.weight: Style.fontWeightBold
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignHCenter
                }

                NText {
                  text: root.telemetryOnlyMode ? I18n.tr("setup.telemetry-wizard-subtitle") : I18n.tr("setup.welcome-subtitle")
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }

                // Friendly subtext
                Rectangle {
                  Layout.fillWidth: true
                  Layout.topMargin: Style.marginL
                  Layout.preferredHeight: childrenRect.height + Style.margin2M
                  color: Color.mSurfaceVariant
                  radius: Style.radiusL

                  NText {
                    anchors.centerIn: parent
                    width: parent.width - Style.marginL * 2
                    text: root.telemetryOnlyMode ? I18n.tr("setup.telemetry-wizard-note") : I18n.tr("setup.welcome-note")
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }

                // Telemetry toggle
                NToggle {
                  Layout.fillWidth: true
                  Layout.topMargin: Style.marginM
                  label: I18n.tr("panels.about.telemetry-enabled")
                  description: I18n.tr("panels.about.telemetry-desc")
                  checked: Settings.data.general.telemetryEnabled
                  onToggled: checked => Settings.data.general.telemetryEnabled = checked
                }
              }
            }
          }

          // Step 1: Wallpaper Setup
          SetupWallpaperStep {
            id: step1
            selectedDirectory: panelContent.selectedWallpaperDirectory
            selectedWallpaper: panelContent.selectedWallpaper
            onDirectoryChanged: function (directory) {
              panelContent.selectedWallpaperDirectory = directory;
              panelContent.applyWallpaperSettings();
            }
            onWallpaperChanged: function (wallpaper) {
              panelContent.selectedWallpaper = wallpaper;
              panelContent.applyWallpaperSettings();
            }
          }

          // Step 2: Appearance - Dark mode and color source
          SetupAppearanceStep {
            id: step3
          }

          // Step 3: UI Configuration
          SetupCustomizeStep {
            id: step2
            selectedScaleRatio: panelContent.selectedScaleRatio
            selectedBarPosition: panelContent.selectedBarPosition
            onScaleRatioChanged: function (ratio) {
              panelContent.selectedScaleRatio = ratio;
              panelContent.applyUISettings();
            }
            onBarPositionChanged: function (position) {
              panelContent.selectedBarPosition = position;
              panelContent.applyUISettings();
            }
          }

          // Step 4: Dock Setup
          SetupDockStep {
            id: stepDock
          }
        }
      }

      // Elegant divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
        visible: !root.telemetryOnlyMode
      }

      // Modern progress indicator with labels
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        visible: !root.telemetryOnlyMode

        RowLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          Repeater {
            model: [
              {
                "icon": "sparkles",
                "label": "Welcome"
              },
              {
                "icon": "image",
                "label": "Wallpaper"
              },
              {
                "icon": "palette",
                "label": "Appearance"
              },
              {
                "icon": "settings",
                "label": "Customize"
              },
              {
                "icon": "device-desktop",
                "label": "Dock"
              }
            ]
            delegate: RowLayout {
              spacing: Style.marginS

              Rectangle {
                width: 24
                height: 24
                radius: width / 2
                color: index <= currentStep ? Color.mPrimary : Color.mSurfaceVariant
                border.color: index === currentStep ? Color.mPrimary : "transparent"
                border.width: index === currentStep ? 2 : 0

                NIcon {
                  icon: modelData.icon
                  pointSize: Style.fontSizeS
                  color: index <= currentStep ? Color.mOnPrimary : Color.mOnSurfaceVariant
                  anchors.centerIn: parent
                }

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                  }
                }
              }

              NText {
                text: modelData.label
                pointSize: Style.fontSizeS
                color: index <= currentStep ? Color.mPrimary : Color.mOnSurfaceVariant
                font.weight: index === currentStep ? Style.fontWeightBold : Style.fontWeightRegular

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                  }
                }
              }

              // Connector line
              Rectangle {
                width: 40
                height: 2
                radius: 1
                color: index < currentStep ? Color.mPrimary : Color.mSurfaceVariant
                visible: index < totalSteps - 1

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                  }
                }
              }
            }
          }
        }
      }

      // Smooth navigation buttons
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        Layout.topMargin: Style.marginS

        RowLayout {
          anchors.fill: parent
          spacing: Style.marginM

          NButton {
            text: I18n.tr("setup.skip-setup")
            outlined: true
            visible: !root.telemetryOnlyMode
            Layout.preferredHeight: 44
            onClicked: {
              panelContent.completeSetup();
            }
          }

          Item {
            Layout.fillWidth: true
          }

          NButton {
            text: "← " + I18n.tr("common.back")
            outlined: true
            visible: currentStep > 0 && !root.telemetryOnlyMode
            Layout.preferredHeight: 44
            onClicked: {
              if (currentStep > 0) {
                currentStep--;
              }
            }
          }

          NButton {
            text: root.telemetryOnlyMode ? I18n.tr("setup.telemetry-wizard-done") : (currentStep === totalSteps - 1 ? I18n.tr("setup.all-done") : I18n.tr("common.continue") + " →")
            Layout.preferredHeight: 44
            onClicked: {
              if (currentStep < totalSteps - 1) {
                currentStep++;
              } else {
                panelContent.completeSetup();
              }
            }
          }
        }
      }
    }
  }
}
