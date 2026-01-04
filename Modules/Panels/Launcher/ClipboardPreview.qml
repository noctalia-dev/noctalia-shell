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

  implicitHeight: contentArea.implicitHeight + Style.marginL * 2

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

  Item {
    id: contentArea
    anchors.fill: parent
    anchors.margins: Style.marginS

    BusyIndicator {
      anchors.centerIn: parent
      running: loadingFullContent
      visible: loadingFullContent
      width: Style.baseWidgetSize
      height: width
    }

    Image {
      anchors.fill: parent
      anchors.margins: Style.marginS
      source: imageDataUrl
      visible: isImageContent && !loadingFullContent && imageDataUrl !== ""
      fillMode: Image.PreserveAspectFit
    }

    ScrollView {
      anchors.fill: parent
      anchors.margins: Style.marginS
      clip: true
      visible: !isImageContent && !loadingFullContent

      TextArea {
        text: fullContent
        readOnly: true
        wrapMode: Text.Wrap
        textFormat: TextArea.RichText
        font.pointSize: Style.fontSizeM
        color: Color.mOnSurface
        background: Rectangle {
          color: Color.mSurfaceVariant || "#e0e0e0"
        }
      }
    }
  }
}
