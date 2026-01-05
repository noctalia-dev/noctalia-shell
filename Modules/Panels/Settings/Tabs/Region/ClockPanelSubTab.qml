import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property list<var> cardsModel: []
  property list<var> cardsDefault: [
    {
      "id": "calendar-header-card",
      "text": I18n.tr("settings.location.calendar.header.label"),
      "enabled": true,
      "required": true
    },
    {
      "id": "calendar-month-card",
      "text": I18n.tr("settings.location.calendar.month.label"),
      "enabled": true,
      "required": false
    },
    {
      "id": "timer-card",
      "text": I18n.tr("calendar.timer.title"),
      "enabled": true,
      "required": false
    },
    {
      "id": "weather-card",
      "text": I18n.tr("settings.location.weather.section.label"),
      "enabled": true,
      "required": false
    }
  ]

  function saveCards() {
    var toSave = [];
    for (var i = 0; i < cardsModel.length; i++) {
      toSave.push({
                    "id": cardsModel[i].id,
                    "enabled": cardsModel[i].enabled
                  });
    }
    Settings.data.calendar.cards = toSave;
  }

  Component.onCompleted: {
    // Starts empty
    cardsModel = [];

    // Add the cards available in settings
    for (var i = 0; i < Settings.data.calendar.cards.length; i++) {
      const settingCard = Settings.data.calendar.cards[i];

      for (var j = 0; j < cardsDefault.length; j++) {
        if (settingCard.id === cardsDefault[j].id) {
          var card = cardsDefault[j];
          card.enabled = settingCard.enabled;
          // Auto-disable weather card if weather is disabled
          if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
            card.enabled = false;
          }
          cardsModel.push(card);
        }
      }
    }

    // Add any missing cards from default
    for (var i = 0; i < cardsDefault.length; i++) {
      var found = false;
      for (var j = 0; j < cardsModel.length; j++) {
        if (cardsModel[j].id === cardsDefault[i].id) {
          found = true;
          break;
        }
      }

      if (!found) {
        var card = cardsDefault[i];
        // Auto-disable weather card if weather is disabled
        if (card.id === "weather-card" && !Settings.data.location.weatherEnabled) {
          card.enabled = false;
        }
        cardsModel.push(card);
      }
    }

    saveCards();
  }

  // Clock style section
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.region.clock-panel.section.label")
      description: I18n.tr("settings.region.clock-panel.section.description")
    }

    NToggle {
      label: I18n.tr("settings.location.date-time.use-analog.label")
      description: I18n.tr("settings.location.date-time.use-analog.description")
      checked: Settings.data.location.analogClockInCalendar
      onToggled: checked => Settings.data.location.analogClockInCalendar = checked
    }

    NToggle {
      label: I18n.tr("settings.location.date-time.week-numbers.label")
      description: I18n.tr("settings.location.date-time.week-numbers.description")
      checked: Settings.data.location.showWeekNumberInCalendar
      onToggled: checked => Settings.data.location.showWeekNumberInCalendar = checked
    }

    NToggle {
      label: I18n.tr("settings.location.date-time.show-events.label")
      description: I18n.tr("settings.location.date-time.show-events.description")
      checked: Settings.data.location.showCalendarEvents
      onToggled: checked => Settings.data.location.showCalendarEvents = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Calendar Cards Management Section
  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.location.calendar.cards.section.label")
      description: I18n.tr("settings.location.calendar.cards.section.description")
    }

    Connections {
      target: Settings.data.location
      function onWeatherEnabledChanged() {
        // Auto-disable weather card when weather is disabled
        var newModel = cardsModel.slice();
        for (var i = 0; i < newModel.length; i++) {
          if (newModel[i].id === "weather-card") {
            newModel[i] = Object.assign({}, newModel[i], {
                                          "enabled": Settings.data.location.weatherEnabled
                                        });
            cardsModel = newModel;
            saveCards();
            break;
          }
        }
      }
    }

    NReorderCheckboxes {
      Layout.fillWidth: true
      model: cardsModel
      disabledIds: Settings.data.location.weatherEnabled ? [] : ["weather-card"]
      onItemToggled: function (index, enabled) {
        var newModel = cardsModel.slice();
        newModel[index] = Object.assign({}, newModel[index], {
                                          "enabled": enabled
                                        });
        cardsModel = newModel;
        saveCards();
      }
      onItemsReordered: function (fromIndex, toIndex) {
        var newModel = cardsModel.slice();
        var item = newModel.splice(fromIndex, 1)[0];
        newModel.splice(toIndex, 0, item);
        cardsModel = newModel;
        saveCards();
      }
    }
  }
}
