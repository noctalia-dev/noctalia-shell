import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs.Modules.Settings
import qs.Modules.ControlCenter
import qs.Commons
import qs.Services
import qs.Widgets

// Header card with avatar, user and quick actions
NBox {
  id: root

  property string uptimeText: "--"
  property real spacing: Style.marginS * scaling
  readonly property bool hasPP: PowerProfileService.available

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM * scaling

    // Profile, Uptime, Settings, SessionMenu, Close
    RowLayout {
      id: content

      spacing: root.spacing
      Layout.alignment: Qt.AlignVCenter

      NImageCircled {
        width: Style.baseWidgetSize * 1.25 * scaling
        height: Style.baseWidgetSize * 1.25 * scaling
        imagePath: Settings.data.general.avatarImage
        fallbackIcon: "person"
        borderColor: Color.mPrimary
        borderWidth: Math.max(1, Style.borderM * scaling)
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: Style.marginXS * scaling
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS * scaling
        NText {
          text: Quickshell.env("USER") || "user"
          font.weight: Style.fontWeightBold
          font.capitalization: Font.Capitalize
        }
        NText {
          text: I18n.tr("system.uptime", {
                          "uptime": uptimeText
                        })
          pointSize: Style.fontSizeS * scaling
          color: Color.mOnSurfaceVariant
        }
      }

      Item {
        Layout.fillWidth: true
      }

      RowLayout {
        spacing: root.spacing
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

        NIconButton {
          baseSize: Style.baseWidgetSize * 0.9
          icon: "settings"
          tooltipText: I18n.tr("tooltips.open-settings")
          onClicked: {
            settingsPanel.requestedTab = SettingsPanel.Tab.General
            settingsPanel.open()
          }
        }

        NIconButton {
          baseSize: Style.baseWidgetSize * 0.9
          icon: "power"
          tooltipText: I18n.tr("tooltips.session-menu")
          onClicked: {
            sessionMenuPanel.open()
            controlCenterPanel.close()
          }
        }

        NIconButton {
          baseSize: Style.baseWidgetSize * 0.9
          icon: "close"
          tooltipText: I18n.tr("tooltips.close")
          onClicked: {
            controlCenterPanel.close()
          }
        }
      }
    }

    RowLayout {
      id: utilitiesRow
      Layout.alignment: Qt.AlignVCenter
      Layout.topMargin: Style.marginM * scaling
      Layout.bottomMargin: Style.marginM * scaling
      Layout.fillWidth: true

      // Left group - Media & Display
      Rectangle {
        color: Color.mSurface
        radius: Style.radiusM * scaling
        Layout.preferredHeight: Style.baseWidgetSize * 1.2 * scaling
        Layout.preferredWidth: childrenRect.width + (Style.marginS * scaling * 2)

        RowLayout {
          anchors.centerIn: parent
          spacing: Style.marginM * scaling

          // Screen Recorder
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            icon: "camera-video"
            visible: ProgramCheckerService.gpuScreenRecorderAvailable
            tooltipText: ScreenRecorderService.isRecording ? I18n.tr("tooltips.stop-screen-recording") : I18n.tr("tooltips.start-screen-recording")
            colorBg: ScreenRecorderService.isRecording ? Color.mPrimary : Color.mSurfaceVariant
            colorFg: ScreenRecorderService.isRecording ? Color.mOnPrimary : Color.mPrimary
            onClicked: {
              ScreenRecorderService.toggleRecording()
              if (!ScreenRecorderService.isRecording) {
                var panel = PanelService.getPanel("controlCenterPanel")
                panel?.close()
              }
            }
          }

          // Wallpaper
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            visible: Settings.data.wallpaper.enabled
            icon: "wallpaper-selector"
            tooltipText: I18n.tr("tooltips.wallpaper-selector")
            onClicked: PanelService.getPanel("wallpaperPanel")?.toggle(this)
            onRightClicked: WallpaperService.setRandomWallpaper()
          }

          // Night Light
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            visible: ProgramCheckerService.wlsunsetAvailable
            colorBg: Settings.data.nightLight.forced ? Color.mPrimary : Color.transparent
            colorFg: Settings.data.nightLight.forced ? Color.mOnPrimary : Color.mPrimary
            icon: Settings.data.nightLight.enabled ? (Settings.data.nightLight.forced ? "nightlight-forced" : "nightlight-on") : "nightlight-off"
            tooltipText: Settings.data.nightLight.enabled ? (Settings.data.nightLight.forced ? I18n.tr("tooltips.night-light-forced") : I18n.tr("tooltips.night-light-enabled")) : I18n.tr("tooltips.night-light-disabled")
            onClicked: {
              if (!Settings.data.nightLight.enabled) {
                Settings.data.nightLight.enabled = true
                Settings.data.nightLight.forced = false
              } else if (Settings.data.nightLight.enabled && !Settings.data.nightLight.forced) {
                Settings.data.nightLight.forced = true
              } else {
                Settings.data.nightLight.enabled = false
                Settings.data.nightLight.forced = false
              }
            }

            onRightClicked: {
              var settingsPanel = PanelService.getPanel("settingsPanel")
              settingsPanel.requestedTab = SettingsPanel.Tab.Display
              settingsPanel.open()
            }
          }
        }
      }

      // Spacer
      Item {
        Layout.fillWidth: true
      }

      // Center group - Network & Caffeine
      Rectangle {
        color: Color.mSurface
        radius: Style.radiusM * scaling
        Layout.preferredHeight: Style.baseWidgetSize * 1.2 * scaling
        Layout.preferredWidth: childrenRect.width + (Style.marginS * scaling * 2)

        RowLayout {
          anchors.centerIn: parent
          spacing: Style.marginM * scaling

          // Wifi
          NIconButton {
            id: wifiButton
            baseSize: Style.baseWidgetSize * 0.9
            tooltipText: I18n.tr("tooltips.manage-wifi")
            icon: {
              try {
                if (NetworkService.ethernetConnected) {
                  return "ethernet"
                }
                let connected = false
                let signalStrength = 0
                for (const net in NetworkService.networks) {
                  if (NetworkService.networks[net].connected) {
                    connected = true
                    signalStrength = NetworkService.networks[net].signal
                    break
                  }
                }
                return connected ? NetworkService.signalIcon(signalStrength) : "wifi-off"
              } catch (error) {
                Logger.error("Wi-Fi", "Error getting icon:", error)
                return "signal_wifi_bad"
              }
            }
            onClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
            onRightClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
          }

          // Bluetooth
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            tooltipText: I18n.tr("tooltips.bluetooth-devices")
            icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
            onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
            onRightClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
          }

          // Caffeine (Keep Awake)
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
            tooltipText: IdleInhibitorService.isInhibited ? I18n.tr("tooltips.disable-keep-awake") : I18n.tr("tooltips.enable-keep-awake")
            colorBg: IdleInhibitorService.isInhibited ? Color.mPrimary : Color.mSurfaceVariant
            colorFg: IdleInhibitorService.isInhibited ? Color.mOnPrimary : Color.mPrimary
            onClicked: {
              IdleInhibitorService.manualToggle()
            }
          }
        }
      }

      // Spacer
      Item {
        Layout.fillWidth: true
      }

      // Right group - Power Profiles
      Rectangle {
        color: Color.mSurface
        radius: Style.radiusM * scaling
        Layout.preferredHeight: Style.baseWidgetSize * 1.2 * scaling
        Layout.preferredWidth: childrenRect.width + (Style.marginS * scaling * 2)

        RowLayout {
          anchors.centerIn: parent
          spacing: Style.marginM * scaling

          // Performance
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            icon: PowerProfileService.getIcon(PowerProfile.Performance)
            tooltipText: I18n.tr("tooltips.set-power-profile", {
                                   "profile": PowerProfileService.getName(PowerProfile.Performance)
                                 })
            enabled: hasPP
            opacity: enabled ? Style.opacityFull : Style.opacityMedium
            colorBg: (enabled && PowerProfileService.profile === PowerProfile.Performance) ? Color.mPrimary : Color.mSurfaceVariant
            colorFg: (enabled && PowerProfileService.profile === PowerProfile.Performance) ? Color.mOnPrimary : Color.mPrimary
            onClicked: PowerProfileService.setProfile(PowerProfile.Performance)
          }

          // Balanced
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            icon: PowerProfileService.getIcon(PowerProfile.Balanced)
            tooltipText: I18n.tr("tooltips.set-power-profile", {
                                   "profile": PowerProfileService.getName(PowerProfile.Balanced)
                                 })
            enabled: hasPP
            opacity: enabled ? Style.opacityFull : Style.opacityMedium
            colorBg: (enabled && PowerProfileService.profile === PowerProfile.Balanced) ? Color.mPrimary : Color.mSurfaceVariant
            colorFg: (enabled && PowerProfileService.profile === PowerProfile.Balanced) ? Color.mOnPrimary : Color.mPrimary
            onClicked: PowerProfileService.setProfile(PowerProfile.Balanced)
          }

          // Eco
          NIconButton {
            baseSize: Style.baseWidgetSize * 0.9
            icon: PowerProfileService.getIcon(PowerProfile.PowerSaver)
            tooltipText: I18n.tr("tooltips.set-power-profile", {
                                   "profile": PowerProfileService.getName(PowerProfile.PowerSaver)
                                 })
            enabled: hasPP
            opacity: enabled ? Style.opacityFull : Style.opacityMedium
            colorBg: (enabled && PowerProfileService.profile === PowerProfile.PowerSaver) ? Color.mPrimary : Color.mSurfaceVariant
            colorFg: (enabled && PowerProfileService.profile === PowerProfile.PowerSaver) ? Color.mOnPrimary : Color.mPrimary
            onClicked: PowerProfileService.setProfile(PowerProfile.PowerSaver)
          }
        }
      }
    }
  }

  // ----------------------------------
  // Uptime
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: uptimeProcess.running = true
  }

  Process {
    id: uptimeProcess
    command: ["cat", "/proc/uptime"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        var uptimeSeconds = parseFloat(this.text.trim().split(' ')[0])
        uptimeText = Time.formatVagueHumanReadableDuration(uptimeSeconds)
        uptimeProcess.running = false
      }
    }
  }

  function updateSystemInfo() {
    uptimeProcess.running = true
  }
}
