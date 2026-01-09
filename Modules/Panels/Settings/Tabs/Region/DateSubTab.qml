import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("panels.location.date-time-12hour-format-label")
    description: I18n.tr("panels.location.date-time-12hour-format-description")
    checked: Settings.data.location.use12hourFormat
    onToggled: checked => Settings.data.location.use12hourFormat = checked
  }

  NComboBox {
    label: I18n.tr("panels.location.date-time-first-day-of-week-label")
    description: I18n.tr("panels.location.date-time-first-day-of-week-description")
    currentKey: Settings.data.location.firstDayOfWeek.toString()
    minimumWidth: 260 * Style.uiScaleRatio
    model: [
      {
        "key": "-1",
        "name": I18n.tr("panels.location.date-time-first-day-of-week-automatic")
      },
      {
        "key": "6",
        "name": I18n.locale.dayName(6, Locale.LongFormat).trim()
      } // Saturday
      ,
      {
        "key": "0",
        "name": I18n.locale.dayName(0, Locale.LongFormat).trim()
      } // Sunday
      ,
      {
        "key": "1",
        "name": I18n.locale.dayName(1, Locale.LongFormat).trim()
      } // Monday
    ]
    onSelected: key => Settings.data.location.firstDayOfWeek = parseInt(key)
  }
}
