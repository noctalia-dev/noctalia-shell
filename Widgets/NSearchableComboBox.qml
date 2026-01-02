import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Helpers/FuzzySort.js" as Fuzzysort
import qs.Commons
import qs.Widgets

RowLayout {
  id: root

  property real minimumWidth: 280
  property real popupHeight: 180

  property string label: ""
  property string description: ""
  property ListModel model: {}
  property string currentKey: ""
  property string placeholder: ""
  property string searchPlaceholder: I18n.tr("placeholders.search")
  property Component delegate: null
  property bool isSettings: false
  property var defaultValue: ""
  property string settingsPath: ""

  readonly property real preferredHeight: Math.round(Style.baseWidgetSize * 1.1)

  signal selected(string key)

  spacing: Style.marginL
  Layout.fillWidth: true

  readonly property bool isValueChanged: isSettings && (currentKey !== defaultValue)
  readonly property string indicatorTooltip: {
    if (!isSettings)
      return "";
    var displayValue = "";
    if (defaultValue === "") {
      // Try to find the display name for empty key in the model
      if (model && model.count > 0) {
        for (var i = 0; i < model.count; i++) {
          var item = model.get(i);
          if (item && item.key === "") {
            displayValue = item.name || I18n.tr("settings.indicator.system-default");
            break;
          }
        }
        // If not found in model, show "System Default" instead of "(empty)"
        if (displayValue === "") {
          displayValue = I18n.tr("settings.indicator.system-default");
        }
      } else {
        displayValue = I18n.tr("settings.indicator.system-default");
      }
    } else {
      // Try to find the display name for the default key in the model
      if (model && model.count > 0) {
        for (var i = 0; i < model.count; i++) {
          var item = model.get(i);
          if (item && item.key === defaultValue) {
            displayValue = item.name || String(defaultValue);
            break;
          }
        }
        if (displayValue === "") {
          displayValue = String(defaultValue);
        }
      } else {
        displayValue = String(defaultValue);
      }
    }
    return I18n.tr("settings.indicator.default-value", {
                     "value": displayValue
                   });
  }

  // Filtered model for search results
  property ListModel filteredModel: ListModel {}
  property string searchText: ""

  function findIndexByKey(key) {
    if (!root.model)
      return -1;
    for (var i = 0; i < root.model.count; i++) {
      if (root.model.get(i).key === key) {
        return i;
      }
    }
    return -1;
  }

  // The active model used for the popup list (source model or filtered results)
  readonly property var activeModel: isFiltered ? filteredModel : root.model

  function findIndexInActiveModel(key) {
    if (!activeModel || activeModel.count === undefined)
      return -1;
    for (var i = 0; i < activeModel.count; i++) {
      if (activeModel.get(i).key === key) {
        return i;
      }
    }
    return -1;
  }

  // Whether we're using filtered results or the source model directly
  property bool isFiltered: false

  function filterModel() {
    // Check if model exists and has items
    if (!root.model || root.model.count === undefined || root.model.count === 0) {
      filteredModel.clear();
      isFiltered = false;
      return;
    }

    var query = searchText.trim();
    if (query === "") {
      // No search text - use source model directly, don't copy
      filteredModel.clear();
      isFiltered = false;
      return;
    }

    // We have search text - need to filter
    isFiltered = true;
    filteredModel.clear();

    // Convert ListModel to array for fuzzy search
    var items = [];
    for (var i = 0; i < root.model.count; i++) {
      items.push(root.model.get(i));
    }

    // Use fuzzy search if available, fallback to simple search
    if (typeof Fuzzysort !== 'undefined') {
      var fuzzyResults = Fuzzysort.go(query, items, {
                                        "key": "name",
                                        "threshold": -1000,
                                        "limit": 50
                                      });

      // Add results in order of relevance
      for (var j = 0; j < fuzzyResults.length; j++) {
        filteredModel.append(fuzzyResults[j].obj);
      }
    } else {
      // Fallback to simple search
      var searchLower = query.toLowerCase();
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (item.name.toLowerCase().includes(searchLower)) {
          filteredModel.append(item);
        }
      }
    }
  }

  onSearchTextChanged: filterModel()

  NLabel {
    label: root.label
    description: root.description
    showIndicator: root.isSettings && root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  Item {
    Layout.fillWidth: true
  }

  ComboBox {
    id: combo

    Layout.minimumWidth: Math.round(root.minimumWidth * Style.uiScaleRatio)
    Layout.preferredHeight: Math.round(root.preferredHeight * Style.uiScaleRatio)
    implicitWidth: Layout.minimumWidth
    model: root.activeModel
    currentIndex: findIndexInActiveModel(currentKey)
    onActivated: {
      if (combo.currentIndex >= 0 && root.activeModel && combo.currentIndex < root.activeModel.count) {
        root.selected(root.activeModel.get(combo.currentIndex).key);
      }
    }

    background: Rectangle {
      implicitWidth: Math.round(Style.baseWidgetSize * 3.75 * Style.uiScaleRatio)
      implicitHeight: Math.round(root.preferredHeight * Style.uiScaleRatio)
      color: Color.mSurface
      border.color: combo.activeFocus ? Color.mSecondary : Color.mOutline
      border.width: Style.borderS
      radius: Style.iRadiusM

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }
    }

    contentItem: NText {
      leftPadding: Style.marginL
      rightPadding: combo.indicator.width + Style.marginL
      pointSize: Style.fontSizeM
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight

      // Look up current selection directly in source model by key
      readonly property int sourceIndex: root.findIndexByKey(root.currentKey)
      readonly property bool hasSelection: root.model && sourceIndex >= 0 && sourceIndex < root.model.count

      color: hasSelection ? Color.mOnSurface : Color.mOnSurfaceVariant
      text: hasSelection ? root.model.get(sourceIndex).name : root.placeholder
    }

    indicator: NIcon {
      x: combo.width - width - Style.marginM
      y: combo.topPadding + (combo.availableHeight - height) / 2
      icon: "caret-down"
      pointSize: Style.fontSizeL
    }

    popup: Popup {
      y: combo.height
      width: combo.width
      height: Math.round((root.popupHeight + 60) * Style.uiScaleRatio)
      padding: Style.marginM

      contentItem: ColumnLayout {
        spacing: Style.marginS

        // Search input
        NTextInput {
          id: searchInput
          inputIconName: "search"
          Layout.fillWidth: true
          placeholderText: root.searchPlaceholder
          text: root.searchText
          onTextChanged: root.searchText = text
          fontSize: Style.fontSizeS
        }

        NListView {
          id: listView
          Layout.fillWidth: true
          Layout.fillHeight: true
          // Use activeModel (source model when not filtering, filtered results when searching)
          model: combo.popup.visible ? root.activeModel : null
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded

          delegate: root.delegate ? root.delegate : defaultDelegate

          Component {
            id: defaultDelegate
            ItemDelegate {
              id: delegateRoot
              width: listView.width
              leftPadding: Style.marginM
              rightPadding: Style.marginM
              topPadding: Style.marginS
              bottomPadding: Style.marginS
              hoverEnabled: true
              highlighted: ListView.view.currentIndex === index

              onHoveredChanged: {
                if (hovered) {
                  ListView.view.currentIndex = index;
                }
              }

              onClicked: {
                var selectedKey = listView.model.get(index).key;
                root.selected(selectedKey);
                combo.popup.close();
              }

              contentItem: RowLayout {
                width: delegateRoot.width - delegateRoot.leftPadding - delegateRoot.rightPadding
                spacing: Style.marginM

                NText {
                  text: name
                  pointSize: Style.fontSizeM
                  color: highlighted ? Color.mOnHover : Color.mOnSurface
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  Behavior on color {
                    ColorAnimation {
                      duration: Style.animationFast
                    }
                  }
                }

                RowLayout {
                  spacing: Style.marginXXS
                  Layout.alignment: Qt.AlignRight

                  // Generic badge renderer
                  Repeater {
                    model: {
                      if (typeof badges === 'undefined' || badges === null)
                        return 0;
                      // Handle both arrays and ListModels
                      if (typeof badges.length !== 'undefined')
                        return badges.length;
                      if (typeof badges.count !== 'undefined')
                        return badges.count;
                      return 0;
                    }

                    delegate: NIcon {
                      required property int index
                      readonly property var badgeData: {
                        if (typeof badges === 'undefined' || badges === null)
                          return null;
                        // Handle both arrays and ListModels
                        if (typeof badges.length !== 'undefined')
                          return badges[index];
                        if (typeof badges.get !== 'undefined')
                          return badges.get(index);
                        return null;
                      }

                      icon: badgeData && badgeData.icon ? badgeData.icon : ""
                      pointSize: {
                        if (!badgeData || !badgeData.size)
                          return Style.fontSizeXS;
                        if (badgeData.size === "xsmall")
                          return Style.fontSizeXXS;
                        else if (badgeData.size === "medium")
                          return Style.fontSizeM;
                        else
                          return Style.fontSizeXS;
                      }
                      color: highlighted ? Color.mOnHover : (badgeData && badgeData.color ? badgeData.color : Color.mOnSurface)
                      Layout.preferredWidth: Math.round(Style.baseWidgetSize * 0.6)
                      Layout.preferredHeight: Math.round(Style.baseWidgetSize * 0.6)
                      visible: badgeData && badgeData.icon !== undefined && badgeData.icon !== ""
                    }
                  }
                }
              }
              background: Rectangle {
                anchors.fill: parent
                color: highlighted ? Color.mHover : Color.transparent
                radius: Style.iRadiusS
                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationFast
                  }
                }
              }
            }
          }
        }
      }

      background: Rectangle {
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Style.borderS
        radius: Style.iRadiusM
      }
    }

    // Update the currentIndex if the currentKey is changed externally
    Connections {
      target: root
      function onCurrentKeyChanged() {
        combo.currentIndex = root.findIndexInActiveModel(root.currentKey);
      }
    }

    // Focus search input when popup opens and ensure model is filtered
    Connections {
      target: combo.popup
      function onVisibleChanged() {
        if (combo.popup.visible) {
          // Ensure the model is filtered when popup opens
          filterModel();
          // Small delay to ensure the popup is fully rendered
          Qt.callLater(() => {
                         if (searchInput && searchInput.inputItem) {
                           searchInput.inputItem.forceActiveFocus();
                         }
                       });
        }
      }
    }
  }
}
