import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

import qs.Commons
import qs.Widgets

Item {
  id: gridEntryContainer

  required property var modelData
  required property int index
  required property var launcher

  width: GridView.view.cellWidth
  height: GridView.view.cellHeight

  property bool isSelected: (!launcher.ignoreMouseHover && mouseArea.containsMouse) || (index === launcher.selectedIndex)

  // Prepare item when it becomes visible (e.g., decode images)
  Component.onCompleted: {
    var provider = modelData.provider;
    if (provider && provider.prepareItem) {
      provider.prepareItem(modelData);
    }
  }

  NBox {
    id: gridEntry
    anchors.fill: parent
    anchors.margins: Style.marginXXS
    color: gridEntryContainer.isSelected ? Color.mHover : Color.mSurfaceVariant
    forceOpaque: gridEntryContainer.isSelected

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCirc
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: launcher.isCompactDensity ? Style.marginXS : Style.marginS
      anchors.bottomMargin: launcher.isCompactDensity ? Style.marginXS : Style.marginS
      spacing: launcher.isCompactDensity ? 0 : Style.marginXXS

      // Icon badge or Image preview or Emoji
      Item {
        // Size image at 65% of cell dimensions.
        Layout.preferredWidth: Math.round(gridEntry.width * 0.65)
        Layout.preferredHeight: Math.round(gridEntry.height * 0.65)
        Layout.alignment: Qt.AlignHCenter

        // Icon background
        Rectangle {
          anchors.fill: parent
          radius: Style.radiusM
          color: Color.mSurface
          visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
        }

        // Image preview - uses provider's getImageUrl if available
        NImageRounded {
          id: gridImagePreview
          anchors.fill: parent
          visible: !!modelData.isImage && !modelData.displayString
          radius: Style.radiusM

          // Use provider's image revision for reactive updates
          readonly property int _rev: modelData.provider && modelData.provider.imageRevision ? modelData.provider.imageRevision : 0

          // Get image URL from provider
          imagePath: {
            _rev;
            var provider = modelData.provider;
            if (provider && provider.getImageUrl) {
              return provider.getImageUrl(modelData);
            }
            return "";
          }

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

          onStatusChanged: status => {
                             if (status === Image.Error) {
                               gridIconLoader.visible = true;
                               gridImagePreview.visible = false;
                             }
                           }
        }

        Loader {
          id: gridIconLoader
          anchors.fill: parent
          anchors.margins: Style.marginXS

          visible: (!modelData.isImage && !modelData.displayString) || (!!modelData.isImage && gridImagePreview.status === Image.Error)
          active: visible

          sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? gridTablerIconComponent : gridSystemIconComponent

          Component {
            id: gridTablerIconComponent
            NIcon {
              icon: modelData.icon
              pointSize: Style.fontSizeXXXL
              visible: modelData.icon && !modelData.displayString
              color: (gridEntryContainer.isSelected && !Settings.data.appLauncher.showIconBackground) ? Color.mOnHover : Color.mOnSurface
            }
          }

          Component {
            id: gridSystemIconComponent
            IconImage {
              anchors.fill: parent
              source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
              visible: modelData.icon && source !== "" && !modelData.displayString
              asynchronous: true
            }
          }
        }

        // String display
        NText {
          id: gridStringDisplay
          anchors.centerIn: parent
          visible: !!modelData.displayString || (!gridImagePreview.visible && !gridIconLoader.visible)
          text: modelData.displayString ? modelData.displayString : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
          pointSize: {
            if (modelData.displayString) {
              // Use custom size if provided, otherwise default scaling
              if (modelData.displayStringSize) {
                return modelData.displayStringSize * Style.uiScaleRatio;
              }
              if (launcher.providerHasDisplayString) {
                // Scale with cell width but cap at reasonable maximum
                const cellBasedSize = gridEntry.width * 0.4;
                const maxSize = Style.fontSizeXXXL * Style.uiScaleRatio;
                return Math.min(cellBasedSize, maxSize);
              }
              return Style.fontSizeXXL * 2 * Style.uiScaleRatio;
            }
            // Scale font size relative to cell width for low res, but cap at maximum
            const cellBasedSize = gridEntry.width * 0.25;
            const baseSize = Style.fontSizeXL * Style.uiScaleRatio;
            const maxSize = Style.fontSizeXXL * Style.uiScaleRatio;
            return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
          }
          font.weight: Style.fontWeightBold
          color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
        }

        // Badge icon overlay (generic indicator for any provider)
        Rectangle {
          visible: !!modelData.badgeIcon
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.margins: 2
          width: height
          height: Style.fontSizeM + Style.marginXS
          color: Color.mSurfaceVariant
          radius: Style.radiusXXS
          NIcon {
            anchors.centerIn: parent
            icon: modelData.badgeIcon || ""
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
        }
      }

      // Text content (hidden when hideLabel is true)
      NText {
        visible: !modelData.hideLabel
        text: modelData.name || "Unknown"
        pointSize: {
          if (launcher.providerHasDisplayString && modelData.displayString) {
            return Style.fontSizeS * Style.uiScaleRatio;
          }
          // Scale font size relative to cell width for low res, but cap at maximum
          const cellBasedSize = gridEntry.width * 0.1;
          const baseSize = Style.fontSizeXS * Style.uiScaleRatio;
          const maxSize = Style.fontSizeS * Style.uiScaleRatio;
          return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
        }
        font.weight: Style.fontWeightSemiBold
        color: gridEntryContainer.isSelected ? Color.mOnHover : Color.mOnSurface
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.maximumWidth: gridEntry.width - 8
        Layout.leftMargin: (launcher.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
        Layout.rightMargin: (launcher.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.NoWrap
        maximumLineCount: 1
      }
    }

    // Action buttons (overlay in top-right corner) - dynamically populated from provider
    Row {
      visible: gridEntryContainer.isSelected && gridItemActions.length > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.marginXS
      z: 10
      spacing: Style.marginXXS

      property var gridItemActions: {
        if (!gridEntryContainer.isSelected)
          return [];
        var provider = modelData.provider || launcher.currentProvider;
        if (provider && provider.getItemActions) {
          return provider.getItemActions(modelData);
        }
        return [];
      }

      Repeater {
        model: parent.gridItemActions
        NIconButton {
          required property var modelData
          icon: modelData.icon
          baseSize: Style.baseWidgetSize * 0.75
          tooltipText: modelData.tooltip
          z: 11
          handleWheel: true
          onClicked: {
            if (modelData.action) {
              modelData.action();
            }
          }
        }
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: !Settings.data.appLauncher.ignoreMouseInput

    onEntered: {
      if (!launcher.ignoreMouseHover) {
        launcher.selectedIndex = gridEntryContainer.index;
      }
    }
    onClicked: mouse => {
                 if (mouse.button === Qt.LeftButton) {
                   launcher.selectedIndex = gridEntryContainer.index;
                   launcher.activate();
                   mouse.accepted = true;
                 }
               }
    acceptedButtons: Qt.LeftButton
  }
}
