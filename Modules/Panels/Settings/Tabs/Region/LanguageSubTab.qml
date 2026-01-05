import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.general.language.section.label")
    description: I18n.tr("settings.general.language.section.description")
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.general.language.select.label")
    description: I18n.tr("settings.general.language.select.description")
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.language")
    model: [
      {
        "key": "",
        "name": I18n.tr("settings.general.language.select.auto-detect") + " (" + I18n.systemDetectedLangCode + ")"
      }
    ].concat(I18n.availableLanguages.map(function (langCode) {
      return {
        "key": langCode,
        "name": langCode
      };
    }))
    currentKey: Settings.data.general.language
    settingsPath: "general.language"
    onSelected: key => {
                  // Need to change language on next frame using "callLater" or it will pull the rug below our feet: the NComboBox would be rebuilt immediately before it can close properly.
                  Qt.callLater(() => {
                                 Settings.data.general.language = key;
                                 if (key === "") {
                                   I18n.detectLanguage(); // Re-detect system language if "Automatic" is selected
                                 } else {
                                   I18n.setLanguage(key); // Set specific language
                                 }
                               });
                }
  }
}
