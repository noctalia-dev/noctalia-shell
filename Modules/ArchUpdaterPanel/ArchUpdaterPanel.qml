import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root
  panelWidth: 380 * scaling
  panelHeight: 500 * scaling
  panelAnchorRight: true

  // Auto-refresh when service updates
  Connections {
    target: ArchUpdaterService
    function onUpdatePackagesChanged() {
      // Force UI update when packages change
      if (root.visible) {
        // Small delay to ensure data is fully updated
        Qt.callLater(() => {
                       // Force a UI update by triggering a property change
                       ArchUpdaterService.updatePackages = ArchUpdaterService.updatePackages
                     }, 100)
      }
    }
  }

  panelContent: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL * scaling

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          text: "system_update"
          font.pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        Text {
          text: "System Updates"
          font.pointSize: Style.fontSizeL * scaling
          font.family: Settings.data.ui.fontDefault
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: "Close"
          sizeMultiplier: 0.8
          onClicked: root.close()
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Update summary
      Text {
        text: ArchUpdaterService.updatePackages.length + " package" + (ArchUpdaterService.updatePackages.length
                                                                       !== 1 ? "s" : "") + " can be updated"
        font.pointSize: Style.fontSizeL * scaling
        font.family: Settings.data.ui.fontDefault
        font.weight: Style.fontWeightMedium
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      // Package selection info
      Text {
        text: ArchUpdaterService.selectedPackagesCount + " of " + ArchUpdaterService.updatePackages.length + " packages selected"
        font.pointSize: Style.fontSizeS * scaling
        font.family: Settings.data.ui.fontDefault
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
      }

      // Package list
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusM * scaling

        ListView {
          id: packageListView
          anchors.fill: parent
          anchors.margins: Style.marginS * scaling
          clip: true
          model: ArchUpdaterService.updatePackages
          spacing: Style.marginXS * scaling

          delegate: Rectangle {
            width: packageListView.width
            height: 50 * scaling
            color: Color.transparent
            radius: Style.radiusS * scaling

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.marginS * scaling
              spacing: Style.marginS * scaling

              // Checkbox for selection
              NIconButton {
                id: checkbox
                icon: "check_box_outline_blank"
                onClicked: {
                  const isSelected = ArchUpdaterService.isPackageSelected(modelData.name)
                  if (isSelected) {
                    ArchUpdaterService.togglePackageSelection(modelData.name)
                    icon = "check_box_outline_blank"
                    colorFg = Color.mOnSurfaceVariant
                  } else {
                    ArchUpdaterService.togglePackageSelection(modelData.name)
                    icon = "check_box"
                    colorFg = Color.mPrimary
                  }
                }
                colorBg: Color.transparent
                colorFg: Color.mOnSurfaceVariant
                Layout.preferredWidth: 30 * scaling
                Layout.preferredHeight: 30 * scaling

                Component.onCompleted: {
                  // Set initial state
                  if (ArchUpdaterService.isPackageSelected(modelData.name)) {
                    icon = "check_box"
                    colorFg = Color.mPrimary
                  }
                }
              }

              // Package info
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS * scaling

                Text {
                  text: modelData.name
                  font.pointSize: Style.fontSizeM * scaling
                  font.family: Settings.data.ui.fontDefault
                  font.weight: Style.fontWeightMedium
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                }

                Text {
                  text: modelData.oldVersion + " → " + modelData.newVersion
                  font.pointSize: Style.fontSizeS * scaling
                  font.family: Settings.data.ui.fontDefault
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                }
              }
            }
          }

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }
        }
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS * scaling

        NIconButton {
          icon: "refresh"
          tooltipText: "Check for updates"
          onClicked: {
            ArchUpdaterService.doPoll()
          }
          colorBg: Color.mSurfaceVariant
          colorFg: Color.mOnSurface
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "system_update"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update all packages"
          enabled: !ArchUpdaterService.updateInProgress
          onClicked: {
            ArchUpdaterService.runUpdate()
            root.close()
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : Color.mPrimary
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : Color.mOnPrimary
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }

        NIconButton {
          icon: ArchUpdaterService.updateInProgress ? "hourglass_empty" : "settings"
          tooltipText: ArchUpdaterService.updateInProgress ? "Update in progress..." : "Update selected packages"
          enabled: !ArchUpdaterService.updateInProgress && ArchUpdaterService.selectedPackagesCount > 0
          onClicked: {
            if (ArchUpdaterService.selectedPackagesCount > 0) {
              ArchUpdaterService.runSelectiveUpdate()
              root.close()
            }
          }
          colorBg: ArchUpdaterService.updateInProgress ? Color.mSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                  > 0 ? Color.mSecondary : Color.mSurfaceVariant)
          colorFg: ArchUpdaterService.updateInProgress ? Color.mOnSurfaceVariant : (ArchUpdaterService.selectedPackagesCount
                                                                                    > 0 ? Color.mOnSecondary : Color.mOnSurfaceVariant)
          Layout.fillWidth: true
          Layout.preferredHeight: 35 * scaling
        }
      }
    }
  }
}
