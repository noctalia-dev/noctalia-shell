import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."
import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: 0

  // Time dropdown options (00:00 .. 23:30)
  ListModel {
    id: timeOptions
  }

  property var screen

  function populateTimeOptions() {
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        var hh = ("0" + h).slice(-2);
        var mm = ("0" + m).slice(-2);
        var key = hh + ":" + mm;
        timeOptions.append({
                             "key": key,
                             "name": key
                           });
      }
    }
  }

  Component.onCompleted: {
    Qt.callLater(populateTimeOptions);
  }

  // Download popup
  Loader {
    id: downloadPopupLoader
    active: false
    sourceComponent: SchemeDownloader {
      parent: Overlay.overlay
    }

    property bool pendingOpen: false

    function open() {
      pendingOpen = true;
      active = true;
      if (item) {
        item.open();
        pendingOpen = false;
      }
    }

    onItemChanged: {
      if (item && pendingOpen) {
        item.open();
        pendingOpen = false;
      }
    }
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("common.colors")
      tabIndex: 0
      checked: subTabBar.currentIndex === 0
    }
    NTabButton {
      text: I18n.tr("common.templates")
      tabIndex: 1
      checked: subTabBar.currentIndex === 1
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.marginL
  }

  NTabView {
    id: tabView
    currentIndex: subTabBar.currentIndex

    ColorsSubTab {
      screen: root.screen
      timeOptions: timeOptions
      onOpenDownloadPopup: downloadPopupLoader.open()
    }
    TemplatesSubTab {}
  }
}
