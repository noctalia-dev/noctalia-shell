import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 700

  property var widgetData: null
  property var widgetMetadata: null

  property string valueFromCurrency: (widgetData && widgetData.fromCurrency) ? widgetData.fromCurrency : ((widgetMetadata && widgetMetadata.fromCurrency) ? widgetMetadata.fromCurrency : "USD")
  property string valueToCurrency: (widgetData && widgetData.toCurrency) ? widgetData.toCurrency : ((widgetMetadata && widgetMetadata.toCurrency) ? widgetMetadata.toCurrency : "BRL")
  property int valueUpdateInterval: (widgetData && widgetData.updateInterval !== undefined) ? widgetData.updateInterval : ((widgetMetadata && widgetMetadata.updateInterval !== undefined) ? widgetMetadata.updateInterval : 30)
  property string valueDisplayMode: (widgetData && widgetData.displayMode) ? widgetData.displayMode : ((widgetMetadata && widgetMetadata.displayMode) ? widgetMetadata.displayMode : "both")

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.fromCurrency = valueFromCurrency;
    settings.toCurrency = valueToCurrency;
    settings.updateInterval = valueUpdateInterval;
    settings.displayMode = valueDisplayMode;
    return settings;
  }

  property var currencies: [
    "USD", "EUR", "BRL", "GBP", "JPY", "CNY", "CAD", "AUD",
    "CHF", "INR", "MXN", "ARS", "CLP", "COP", "PEN", "UYU"
  ]

  property var currencyNames: ({
    "USD": "Dólar Americano (USD)",
    "EUR": "Euro (EUR)",
    "BRL": "Real Brasileiro (BRL)",
    "GBP": "Libra Esterlina (GBP)",
    "JPY": "Iene Japonês (JPY)",
    "CNY": "Yuan Chinês (CNY)",
    "CAD": "Dólar Canadense (CAD)",
    "AUD": "Dólar Australiano (AUD)",
    "CHF": "Franco Suíço (CHF)",
    "INR": "Rúpia Indiana (INR)",
    "MXN": "Peso Mexicano (MXN)",
    "ARS": "Peso Argentino (ARS)",
    "CLP": "Peso Chileno (CLP)",
    "COP": "Peso Colombiano (COP)",
    "PEN": "Sol Peruano (PEN)",
    "UYU": "Peso Uruguaio (UYU)"
  })

  property var currencyModel: {
    var model = [];
    for (var i = 0; i < currencies.length; i++) {
      model.push({
        "key": currencies[i],
        "name": currencyNames[currencies[i]] || currencies[i]
      });
    }
    return model;
  }

  Text {
    text: "Configurações do Conversor de Moedas"
    font.pointSize: 14
    font.weight: Font.Bold
    color: "#FFFFFF"
    Layout.fillWidth: true
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.currency-converter.from-currency.label")
    description: I18n.tr("bar.widget-settings.currency-converter.from-currency.description")
    Layout.fillWidth: true
    model: currencyModel
    currentKey: valueFromCurrency
    onSelected: key => {
      valueFromCurrency = key;
    }
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.currency-converter.to-currency.label")
    description: I18n.tr("bar.widget-settings.currency-converter.to-currency.description")
    Layout.fillWidth: true
    model: currencyModel
    currentKey: valueToCurrency
    onSelected: key => {
      valueToCurrency = key;
    }
  }

  NSpinBox {
    label: I18n.tr("bar.widget-settings.currency-converter.update-interval.label")
    description: I18n.tr("bar.widget-settings.currency-converter.update-interval.description")
    Layout.fillWidth: true
    from: 5
    to: 1440
    stepSize: 5
    value: valueUpdateInterval
    suffix: " min"
    onValueChanged: valueUpdateInterval = value
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.currency-converter.display-mode.label")
    description: I18n.tr("bar.widget-settings.currency-converter.display-mode.description")
    Layout.fillWidth: true
    model: [
      {
        "key": "both",
        "name": I18n.tr("bar.widget-settings.currency-converter.display-mode.both")
      },
      {
        "key": "icon",
        "name": I18n.tr("bar.widget-settings.currency-converter.display-mode.icon")
      },
      {
        "key": "text",
        "name": I18n.tr("bar.widget-settings.currency-converter.display-mode.text")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
      valueDisplayMode = key;
    }
  }

  Item {
    Layout.fillHeight: true
  }
}

