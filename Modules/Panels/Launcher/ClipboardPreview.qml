import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../Helpers/TextFormatter.js" as TextFormatter
import qs.Commons
import qs.Services.Keyboard
import qs.Widgets

Item {
  id: previewPanel

  property var currentItem: null
  property string fullContent: ""
  property string imageDataUrl: ""
  property bool loadingFullContent: false
  property bool isImageContent: false

  implicitHeight: contentColumn.implicitHeight + Style.marginL * 2

  Connections {
    target: previewPanel
    function onCurrentItemChanged() {
      fullContent = "";
      imageDataUrl = "";
      loadingFullContent = false;
      isImageContent = currentItem && currentItem.isImage;

      if (currentItem && currentItem.clipboardId) {
        if (isImageContent) {
          imageDataUrl = ClipboardService.getImageData(currentItem.clipboardId) || "";
          loadingFullContent = !imageDataUrl;

          if (!imageDataUrl && currentItem.mime) {
            ClipboardService.decodeToDataUrl(currentItem.clipboardId, currentItem.mime, null);
          }
        } else {
          loadingFullContent = true;
          ClipboardService.decode(currentItem.clipboardId, function (content) {
            fullContent = TextFormatter.wrapTextForDisplay(content);
            loadingFullContent = false;
          });
        }
      }
    }
  }

  readonly property int _rev: ClipboardService.revision

  Timer {
    id: imageUpdateTimer
    interval: 200
    running: currentItem && currentItem.isImage && imageDataUrl === ""
    repeat: currentItem && currentItem.isImage && imageDataUrl === ""

    onTriggered: {
      if (currentItem && currentItem.clipboardId) {
        const newData = ClipboardService.getImageData(currentItem.clipboardId) || "";
        if (newData !== imageDataUrl) {
          imageDataUrl = newData;
          if (newData) {
            loadingFullContent = false;
          }
        }
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface || "#f5f5f5"
    border.color: Color.mOutlineVariant || "#cccccc"
    border.width: 1
    radius: Style.radiusM

    ColumnLayout {
      id: contentColumn
      anchors.fill: parent
      anchors.margins: Style.marginS
      spacing: Style.marginS

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant || "#e0e0e0"
        border.color: Color.mOutline || "#aaaaaa"
        border.width: 1
        radius: Style.radiusS

        BusyIndicator {
          anchors.centerIn: parent
          running: loadingFullContent
          visible: loadingFullContent
          width: Style.baseWidgetSize
          height: width
        }

        Item {
          anchors.fill: parent
          anchors.margins: Style.marginS

          NImageRounded {
            anchors.fill: parent
            imagePath: imageDataUrl
            visible: isImageContent && !loadingFullContent && imageDataUrl !== ""
            radius: Style.radiusS
            imageFillMode: Image.PreserveAspectFit
          }

          ScrollView {
            anchors.fill: parent
            clip: true
            visible: !isImageContent && !loadingFullContent

            TextArea {
              text: fullContent
              readOnly: true
              wrapMode: Text.Wrap
              textFormat: TextArea.RichText // Enable HTML rendering
              font.pointSize: Style.fontSizeM // Adjust font size for readability
              color: Color.mOnSurface // Consistent text color
              background: Rectangle {
                color: Color.mSurfaceVariant || "#e0e0e0"
              }
            }
          }
        }
      }
    }
  }
}
