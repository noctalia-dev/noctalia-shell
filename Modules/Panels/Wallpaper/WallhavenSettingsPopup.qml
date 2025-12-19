import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Popup {
  id: root

  property ShellScreen screen
  property Item anchorItem: null

  width: Math.max(440, contentColumn.implicitWidth + (Style.marginL * 2))
  height: contentColumn.implicitHeight + (Style.marginL * 2)
  padding: Style.marginL
  modal: true
  dim: false
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  parent: anchorItem ? anchorItem.parent : Overlay.overlay

  x: {
    if (anchorItem) {
      var itemPos = anchorItem.mapToItem(parent, 0, 0);
      return itemPos.x - width + anchorItem.width;
    }
    return 0;
  }

  y: {
    if (anchorItem) {
      var itemPos = anchorItem.mapToItem(parent, 0, 0);
      return itemPos.y + anchorItem.height + Style.marginS;
    }
    return 0;
  }

  function showAt(item) {
    if (!item) {
      return;
    }
    anchorItem = item;
    open();
    Qt.callLater(() => {
                   // Try to focus the first input if available
                   if (resolutionWidthInput.inputItem) {
                     resolutionWidthInput.inputItem.forceActiveFocus();
                   }
                 });
  }

  onOpened: {
    Qt.callLater(() => {
                   if (resolutionWidthInput.inputItem) {
                     resolutionWidthInput.inputItem.forceActiveFocus();
                   }
                 });
  }

  function hide() {
    close();
  }

  function updateResolution(triggerSearch) {
    if (typeof WallhavenService === "undefined") {
      return;
    }

    var width = Settings.data.wallpaper.wallhavenResolutionWidth || "";
    var height = Settings.data.wallpaper.wallhavenResolutionHeight || "";
    var mode = Settings.data.wallpaper.wallhavenResolutionMode || "atleast";

    if (width && height) {
      var resolution = width + "x" + height;
      if (mode === "atleast") {
        WallhavenService.minResolution = resolution;
        WallhavenService.resolutions = "";
      } else {
        WallhavenService.minResolution = "";
        WallhavenService.resolutions = resolution;
      }
    } else {
      WallhavenService.minResolution = "";
      WallhavenService.resolutions = "";
    }

    // Trigger new search with updated resolution only if requested
    if (triggerSearch && Settings.data.wallpaper.useWallhaven) {
      WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);
    }
  }

  background: Rectangle {
    id: backgroundRect
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderM

    NDropShadow {
      source: backgroundRect
    }
  }

  contentItem: ColumnLayout {
    id: contentColumn
    spacing: Style.marginM

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NIcon {
        icon: "settings"
        pointSize: Style.fontSizeL
        color: Color.mPrimary
      }

      NText {
        text: I18n.tr("wallpaper.panel.wallhaven-settings.title")
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        tooltipText: I18n.tr("tooltips.close")
        baseSize: Style.baseWidgetSize * 0.8
        onClicked: root.hide()
      }
    }

    NDivider {
      Layout.fillWidth: true
    }

    // API Key
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: I18n.tr("wallpaper.panel.apikey.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
      }

      NTextInput {
        id: apiKeyInput
        Layout.fillWidth: true
        placeholderText: I18n.tr("wallpaper.panel.apikey.placeholder")
        text: Settings.data.wallpaper.wallhavenApiKey || ""
        
        // Fix for password echo mode
        Component.onCompleted: {
          if (apiKeyInput.inputItem) {
             apiKeyInput.inputItem.echoMode = TextInput.Password;
          }
        }

        onEditingFinished: {
          Settings.data.wallpaper.wallhavenApiKey = text;
        }
      }
      
      NText {
        text: I18n.tr("wallpaper.panel.apikey.help")
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Sorting
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("wallpaper.panel.sorting.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        Layout.preferredWidth: implicitWidth
      }

      NComboBox {
        id: sortingComboBox
        Layout.fillWidth: true
        Layout.minimumWidth: 200
        model: [
          {
            "key": "date_added",
            "name": I18n.tr("wallpaper.panel.sorting.date_added")
          },
          {
            "key": "relevance",
            "name": I18n.tr("wallpaper.panel.sorting.relevance")
          },
          {
            "key": "random",
            "name": I18n.tr("wallpaper.panel.sorting.random")
          },
          {
            "key": "views",
            "name": I18n.tr("wallpaper.panel.sorting.views")
          },
          {
            "key": "favorites",
            "name": I18n.tr("wallpaper.panel.sorting.favorites")
          },
          {
            "key": "toplist",
            "name": I18n.tr("wallpaper.panel.sorting.toplist")
          }
        ]
        currentKey: Settings.data.wallpaper.wallhavenSorting || "relevance"
        onSelected: key => {
                      Settings.data.wallpaper.wallhavenSorting = key;
                      if (typeof WallhavenService !== "undefined") {
                        WallhavenService.sorting = key;
                        WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);
                      }
                    }
      }
    }

    // Order
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM
      visible: sortingComboBox.currentKey !== "random"

      NText {
        text: I18n.tr("wallpaper.panel.order.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        Layout.preferredWidth: implicitWidth
      }

      NComboBox {
        id: orderComboBox
        Layout.fillWidth: true
        Layout.minimumWidth: 200
        model: [
          {
            "key": "desc",
            "name": I18n.tr("wallpaper.panel.order.desc")
          },
          {
            "key": "asc",
            "name": I18n.tr("wallpaper.panel.order.asc")
          }
        ]
        currentKey: Settings.data.wallpaper.wallhavenOrder || "desc"
        onSelected: key => {
                      Settings.data.wallpaper.wallhavenOrder = key;
                      if (typeof WallhavenService !== "undefined") {
                        WallhavenService.order = key;
                        WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);
                      }
                    }
      }
    }

    // Purity selector
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("wallpaper.panel.purity.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        Layout.preferredWidth: implicitWidth
      }

      Item {
        Layout.fillWidth: true
      }

      RowLayout {
        id: purityRow
        spacing: Style.marginL

        function getPurityValue(index) {
          var purity = Settings.data.wallpaper.wallhavenPurity || "100";
          return purity.length > index && purity.charAt(index) === "1";
        }

        function updatePurity(sfw, sketchy, nsfw) {
          var purity = (sfw ? "1" : "0") + (sketchy ? "1" : "0") + (nsfw ? "1" : "0");
          Settings.data.wallpaper.wallhavenPurity = purity;
          // Update checkboxes immediately
          sfwToggle.checked = sfw;
          sketchyToggle.checked = sketchy;
          nsfwToggle.checked = nsfw;
          if (typeof WallhavenService !== "undefined") {
            WallhavenService.purity = purity;
            WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);
          }
        }

        Connections {
          target: Settings.data.wallpaper
          function onWallhavenPurityChanged() {
            sfwToggle.checked = purityRow.getPurityValue(0);
            sketchyToggle.checked = purityRow.getPurityValue(1);
            nsfwToggle.checked = purityRow.getPurityValue(2);
          }
          function onWallhavenApiKeyChanged() {
            // If API key is removed, disable NSFW
            if (!Settings.data.wallpaper.wallhavenApiKey && nsfwToggle.checked) {
               nsfwToggle.toggled(false);
            }
          }
        }

        Component.onCompleted: {
          sfwToggle.checked = purityRow.getPurityValue(0);
          sketchyToggle.checked = purityRow.getPurityValue(1);
          nsfwToggle.checked = purityRow.getPurityValue(2);
        }

        // SFW checkbox
        Item {
          Layout.preferredWidth: sfwCheckboxRow.implicitWidth
          Layout.preferredHeight: sfwCheckboxRow.implicitHeight

          RowLayout {
            id: sfwCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.purity.sfw")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: sfwBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: sfwToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: sfwToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, sfwBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sfwToggle.toggled(!sfwToggle.checked)
              }
            }
          }
        }

        // Sketchy checkbox
        Item {
          Layout.preferredWidth: sketchyCheckboxRow.implicitWidth
          Layout.preferredHeight: sketchyCheckboxRow.implicitHeight

          RowLayout {
            id: sketchyCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.purity.sketchy")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: sketchyBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: sketchyToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: sketchyToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, sketchyBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sketchyToggle.toggled(!sketchyToggle.checked)
              }
            }
          }
        }

        // NSFW checkbox
        Item {
          Layout.preferredWidth: nsfwCheckboxRow.implicitWidth
          Layout.preferredHeight: nsfwCheckboxRow.implicitHeight
          visible: Settings.data.wallpaper.wallhavenApiKey !== ""

          RowLayout {
            id: nsfwCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.purity.nsfw")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: nsfwBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: nsfwToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: nsfwToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, nsfwBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: nsfwToggle.toggled(!nsfwToggle.checked)
              }
            }
          }
        }

        // Invisible objects for logic
        QtObject {
          id: sfwToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       purityRow.updatePurity(checked, purityRow.getPurityValue(1), purityRow.getPurityValue(2));
                     }
        }

        QtObject {
          id: sketchyToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       purityRow.updatePurity(purityRow.getPurityValue(0), checked, purityRow.getPurityValue(2));
                     }
        }

        QtObject {
          id: nsfwToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       purityRow.updatePurity(purityRow.getPurityValue(0), purityRow.getPurityValue(1), checked);
                     }
        }
      }
    }

    // Categories
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("wallpaper.panel.categories.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        Layout.preferredWidth: implicitWidth
      }

      Item {
        Layout.fillWidth: true
      }

      RowLayout {
        id: categoriesRow
        spacing: Style.marginL

        function getCategoryValue(index) {
          var cats = Settings.data.wallpaper.wallhavenCategories || "111";
          return cats.length > index && cats.charAt(index) === "1";
        }

        function updateCategories(general, anime, people) {
          var categories = (general ? "1" : "0") + (anime ? "1" : "0") + (people ? "1" : "0");
          Settings.data.wallpaper.wallhavenCategories = categories;
          // Update checkboxes immediately
          generalToggle.checked = general;
          animeToggle.checked = anime;
          peopleToggle.checked = people;
          if (typeof WallhavenService !== "undefined") {
            WallhavenService.categories = categories;
            WallhavenService.search(Settings.data.wallpaper.wallhavenQuery, 1);
          }
        }

        Connections {
          target: Settings.data.wallpaper
          function onWallhavenCategoriesChanged() {
            generalToggle.checked = categoriesRow.getCategoryValue(0);
            animeToggle.checked = categoriesRow.getCategoryValue(1);
            peopleToggle.checked = categoriesRow.getCategoryValue(2);
          }
        }

        Component.onCompleted: {
          generalToggle.checked = categoriesRow.getCategoryValue(0);
          animeToggle.checked = categoriesRow.getCategoryValue(1);
          peopleToggle.checked = categoriesRow.getCategoryValue(2);
        }

        // General checkbox
        Item {
          Layout.preferredWidth: generalCheckboxRow.implicitWidth
          Layout.preferredHeight: generalCheckboxRow.implicitHeight

          RowLayout {
            id: generalCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.categories.general")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: generalBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: generalToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: generalToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, generalBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: generalToggle.toggled(!generalToggle.checked)
              }
            }
          }
        }

        // Anime checkbox
        Item {
          Layout.preferredWidth: animeCheckboxRow.implicitWidth
          Layout.preferredHeight: animeCheckboxRow.implicitHeight

          RowLayout {
            id: animeCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.categories.anime")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: animeBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: animeToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: animeToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, animeBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: animeToggle.toggled(!animeToggle.checked)
              }
            }
          }
        }

        // People checkbox
        Item {
          Layout.preferredWidth: peopleCheckboxRow.implicitWidth
          Layout.preferredHeight: peopleCheckboxRow.implicitHeight

          RowLayout {
            id: peopleCheckboxRow
            anchors.fill: parent
            spacing: Style.marginS

            NText {
              text: I18n.tr("wallpaper.panel.categories.people")
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
            }

            Rectangle {
              id: peopleBox
              implicitWidth: Math.round(Style.baseWidgetSize * 0.7)
              implicitHeight: Math.round(Style.baseWidgetSize * 0.7)
              radius: Style.radiusXS
              color: peopleToggle.checked ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: peopleToggle.checked
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, peopleBox.width * 0.5)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: peopleToggle.toggled(!peopleToggle.checked)
              }
            }
          }
        }

        // Invisible checkboxes to maintain the signal handlers
        QtObject {
          id: generalToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       categoriesRow.updateCategories(checked, categoriesRow.getCategoryValue(1), categoriesRow.getCategoryValue(2));
                     }
        }

        QtObject {
          id: animeToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       categoriesRow.updateCategories(categoriesRow.getCategoryValue(0), checked, categoriesRow.getCategoryValue(2));
                     }
        }

        QtObject {
          id: peopleToggle
          property bool checked: false
          signal toggled(bool checked)
          onToggled: checked => {
                       categoriesRow.updateCategories(categoriesRow.getCategoryValue(0), categoriesRow.getCategoryValue(1), checked);
                     }
        }
      }
    }

    // Resolution filter
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: I18n.tr("wallpaper.panel.resolution.label")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: I18n.tr("wallpaper.panel.resolution.mode.label")
          color: Color.mOnSurface
          pointSize: Style.fontSizeM
          Layout.preferredWidth: implicitWidth
        }

        NComboBox {
          id: resolutionModeComboBox
          Layout.fillWidth: true
          Layout.minimumWidth: 200
          model: [
            {
              "key": "atleast",
              "name": I18n.tr("wallpaper.panel.resolution.atleast")
            },
            {
              "key": "exact",
              "name": I18n.tr("wallpaper.panel.resolution.exact")
            }
          ]
          currentKey: Settings.data.wallpaper.wallhavenResolutionMode || "atleast"

          Connections {
            target: Settings.data.wallpaper
            function onWallhavenResolutionModeChanged() {
              if (resolutionModeComboBox.currentKey !== Settings.data.wallpaper.wallhavenResolutionMode) {
                resolutionModeComboBox.currentKey = Settings.data.wallpaper.wallhavenResolutionMode || "atleast";
              }
            }
          }

          onSelected: key => {
                        Settings.data.wallpaper.wallhavenResolutionMode = key;
                        updateResolution(false);
                      }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTextInput {
          id: resolutionWidthInput
          Layout.preferredWidth: 80
          placeholderText: "Width"
          inputMethodHints: Qt.ImhDigitsOnly
          text: Settings.data.wallpaper.wallhavenResolutionWidth || ""

          Component.onCompleted: {
            if (resolutionWidthInput.inputItem) {
              resolutionWidthInput.inputItem.focusPolicy = Qt.StrongFocus;
              // Ensure the TextField can receive keyboard input
              resolutionWidthInput.inputItem.activeFocusOnPress = true;
            }
          }

          // Ensure focus when clicked
          onActiveFocusChanged: {
            if (activeFocus && resolutionWidthInput.inputItem) {
              resolutionWidthInput.inputItem.forceActiveFocus();
            }
          }

          Connections {
            target: Settings.data.wallpaper
            function onWallhavenResolutionWidthChanged() {
              if (resolutionWidthInput.text !== Settings.data.wallpaper.wallhavenResolutionWidth) {
                resolutionWidthInput.text = Settings.data.wallpaper.wallhavenResolutionWidth || "";
              }
            }
          }

          onEditingFinished: {
            Settings.data.wallpaper.wallhavenResolutionWidth = text;
            updateResolution(false);
          }
        }

        NText {
          text: "×"
          color: Color.mOnSurface
          pointSize: Style.fontSizeM
          Layout.preferredWidth: implicitWidth
        }

        NTextInput {
          id: resolutionHeightInput
          Layout.preferredWidth: 80
          placeholderText: "Height"
          inputMethodHints: Qt.ImhDigitsOnly
          text: Settings.data.wallpaper.wallhavenResolutionHeight || ""

          Component.onCompleted: {
            if (resolutionHeightInput.inputItem) {
              resolutionHeightInput.inputItem.focusPolicy = Qt.StrongFocus;
              resolutionHeightInput.inputItem.activeFocusOnPress = true;
            }
          }

          // Ensure focus when clicked
          onActiveFocusChanged: {
            if (activeFocus && resolutionHeightInput.inputItem) {
              resolutionHeightInput.inputItem.forceActiveFocus();
            }
          }

          Connections {
            target: Settings.data.wallpaper
            function onWallhavenResolutionHeightChanged() {
              if (resolutionHeightInput.text !== Settings.data.wallpaper.wallhavenResolutionHeight) {
                resolutionHeightInput.text = Settings.data.wallpaper.wallhavenResolutionHeight || "";
              }
            }
          }

          onEditingFinished: {
            Settings.data.wallpaper.wallhavenResolutionHeight = text;
            updateResolution(false);
          }
        }
      }
    }

    // Apply button
    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM
    }

    NButton {
      Layout.fillWidth: true
      text: I18n.tr("wallpaper.panel.wallhaven-settings.apply")
      onClicked: {
        // Ensure all settings are synced to the service
        if (typeof WallhavenService !== "undefined" && Settings.data.wallpaper.useWallhaven) {
          // Sync all settings to the service
          WallhavenService.categories = Settings.data.wallpaper.wallhavenCategories;
          WallhavenService.purity = Settings.data.wallpaper.wallhavenPurity;
          WallhavenService.sorting = Settings.data.wallpaper.wallhavenSorting;
          WallhavenService.order = Settings.data.wallpaper.wallhavenOrder;
          WallhavenService.apiKey = Settings.data.wallpaper.wallhavenApiKey;

          // Update resolution settings (without triggering search)
          updateResolution(false);

          // Refresh the wallpaper search with current settings
          WallhavenService.search(Settings.data.wallpaper.wallhavenQuery || "", 1);

          // Close the popup after applying (delay to prevent click propagation)
          Qt.callLater(() => {
                         root.hide();
                       });
        }
      }
    }
  }
}
