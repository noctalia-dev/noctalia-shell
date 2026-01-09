import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true
  Layout.fillHeight: true

  required property var cardsModel
  required property list<var> cardsDefault

  function saveCards() {
    var toSave = [];
    for (var i = 0; i < cardsModel.length; i++) {
      toSave.push({
        "id": cardsModel[i].id,
        "enabled": cardsModel[i].enabled
      });
    }
    Settings.data.controlCenter.cards = toSave;
  }

    NText {
      text: I18n.tr("panels.control-center.cards-desc")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      Connections {
        target: Settings.data.location
        function onWeatherEnabledChanged() {
          // Auto-disable weather card when weather is disabled
          var newModel = root.cardsModel.slice();
          for (var i = 0; i < newModel.length; i++) {
            if (newModel[i].id === "weather-card") {
              newModel[i] = Object.assign({}, newModel[i], {
                                            "enabled": Settings.data.location.weatherEnabled
                                          });
              root.cardsModel = newModel;
              saveCards();
              break;
            }
          }
        }
      }

      NReorderCheckboxes {
        Layout.fillWidth: true
        model: root.cardsModel
        disabledIds: Settings.data.location.weatherEnabled ? [] : ["weather-card"]
        onItemToggled: function (index, enabled) {
          var newModel = root.cardsModel.slice();
          newModel[index] = Object.assign({}, newModel[index], {
                                            "enabled": enabled
                                          });
          root.cardsModel = newModel;
          saveCards();
        }
        onItemsReordered: function (fromIndex, toIndex) {
          var newModel = root.cardsModel.slice();
          var item = newModel.splice(fromIndex, 1)[0];
          newModel.splice(toIndex, 0, item);
          root.cardsModel = newModel;
          saveCards();
        }
      }
    }
  }
