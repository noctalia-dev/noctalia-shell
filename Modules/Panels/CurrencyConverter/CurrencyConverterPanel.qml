import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  property var converterWidget: null
  
  preferredWidth: 400 * Style.uiScaleRatio
  preferredHeight: 500 * Style.uiScaleRatio
  preferredWidthRatio: 0.25
  preferredHeightRatio: 0.4

  // Positioning (follow bar)
  readonly property string panelPosition: {
    if (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") {
      return `center_${Settings.data.bar.position}`;
    } else {
      return `${Settings.data.bar.position}_center`;
    }
  }
  
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  // Local state
  property string fromCurrency: converterWidget ? converterWidget.fromCurrency : "USD"
  property string toCurrency: converterWidget ? converterWidget.toCurrency : "BRL"
  property real fromAmount: 1.0
  property real toAmount: 0.0
  property var availableRates: converterWidget ? converterWidget.allRates : ({})
  property var currencies: []

  Component.onCompleted: {
    // Build currency list from common currencies
    currencies = [
      "USD", "EUR", "BRL", "GBP", "JPY", "CNY", "CAD", "AUD", 
      "CHF", "INR", "MXN", "ARS", "CLP", "COP", "PEN", "UYU"
    ];
  }

  onFromAmountChanged: calculateConversion()
  onFromCurrencyChanged: calculateConversion()
  onToCurrencyChanged: calculateConversion()
  onAvailableRatesChanged: calculateConversion()

  function calculateConversion() {
    if (!availableRates || Object.keys(availableRates).length === 0) {
      toAmount = 0;
      return;
    }

    // Get rates relative to the base currency (converterWidget.fromCurrency)
    var baseRate = availableRates[fromCurrency] || 1;
    var targetRate = availableRates[toCurrency] || 1;
    
    // Calculate conversion
    var rate = targetRate / baseRate;
    toAmount = fromAmount * rate;
  }

  function swapCurrencies() {
    var temp = fromCurrency;
    fromCurrency = toCurrency;
    toCurrency = temp;
    calculateConversion();
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerContent.implicitHeight + Style.marginL * 2
        color: Color.mSurfaceVariant

        ColumnLayout {
          id: headerContent
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NIcon {
              icon: "currency-dollar"
              pointSize: Style.fontSizeXXL
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("currency-converter.title") || "Conversor de Moedas"
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "refresh"
              tooltipText: I18n.tr("currency-converter.refresh") || "Atualizar cotações"
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                if (converterWidget) {
                  converterWidget.fetchExchangeRate();
                }
              }
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("tooltips.close") || "Fechar"
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }
        }
      }

      // Converter content
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurface

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginL

          // From section
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: I18n.tr("currency-converter.from") || "De"
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NTextInput {
                id: fromAmountInput
                Layout.fillWidth: true
                Layout.preferredHeight: Style.baseWidgetSize
                text: fromAmount.toString()
                
                property var numberValidator: DoubleValidator {
                  bottom: 0
                  decimals: 2
                  notation: DoubleValidator.StandardNotation
                }
                
                Component.onCompleted: {
                  if (inputItem) {
                    inputItem.validator = numberValidator;
                  }
                }
                
                onTextChanged: {
                  var val = parseFloat(text);
                  if (!isNaN(val) && val >= 0) {
                    fromAmount = val;
                  }
                }
              }

              ComboBox {
                id: fromCurrencyCombo
                Layout.preferredWidth: 120 * Style.uiScaleRatio
                Layout.preferredHeight: Style.baseWidgetSize
                model: currencies
                currentIndex: currencies.indexOf(fromCurrency)
                
                onActivated: index => {
                  fromCurrency = currencies[index];
                }

                background: Rectangle {
                  color: Color.mSurface
                  border.color: Color.mOutline
                  border.width: Style.borderS
                  radius: Style.iRadiusM
                }

                contentItem: NText {
                  leftPadding: Style.marginM
                  rightPadding: Style.marginM
                  pointSize: Style.fontSizeM
                  verticalAlignment: Text.AlignVCenter
                  color: Color.mOnSurface
                  text: fromCurrencyCombo.displayText
                }

                indicator: NIcon {
                  x: fromCurrencyCombo.width - width - Style.marginS
                  y: fromCurrencyCombo.topPadding + (fromCurrencyCombo.availableHeight - height) / 2
                  icon: "caret-down"
                  pointSize: Style.fontSizeM
                }

                popup: Popup {
                  y: fromCurrencyCombo.height
                  implicitWidth: fromCurrencyCombo.width
                  implicitHeight: Math.min(300, fromCurrencyListView.contentHeight + Style.marginM * 2)
                  padding: Style.marginM

                  contentItem: ListView {
                    id: fromCurrencyListView
                    clip: true
                    model: fromCurrencyCombo.model
                    currentIndex: fromCurrencyCombo.highlightedIndex

                    delegate: Rectangle {
                      required property int index
                      required property string modelData
                      property bool isHighlighted: fromCurrencyListView.currentIndex === index

                      width: fromCurrencyListView.width
                      height: delegateText.implicitHeight + Style.marginS * 2
                      radius: Style.iRadiusS
                      color: isHighlighted ? Color.mHover : Color.transparent

                      NText {
                        id: delegateText
                        anchors.fill: parent
                        anchors.leftMargin: Style.marginM
                        anchors.rightMargin: Style.marginM
                        verticalAlignment: Text.AlignVCenter
                        pointSize: Style.fontSizeM
                        color: parent.isHighlighted ? Color.mOnHover : Color.mOnSurface
                        text: modelData
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                          if (containsMouse)
                            fromCurrencyListView.currentIndex = index;
                        }
                        onClicked: {
                          fromCurrencyCombo.currentIndex = index;
                          fromCurrencyCombo.activated(index);
                          fromCurrencyCombo.popup.close();
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
              }
            }
          }

          // Swap button
          NIconButton {
            Layout.alignment: Qt.AlignHCenter
            icon: "arrows-exchange"
            tooltipText: I18n.tr("currency-converter.swap") || "Trocar moedas"
            baseSize: Style.baseWidgetSize * 0.9
            colorBg: Color.mPrimary
            colorFg: Color.mOnPrimary
            onClicked: swapCurrencies()
          }

          // To section
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: I18n.tr("currency-converter.to") || "Para"
              color: Color.mOnSurface
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.baseWidgetSize
                color: Color.mSurfaceVariant
                border.color: Color.mOutline
                border.width: Style.borderS
                radius: Style.iRadiusM

                NText {
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginM
                  anchors.rightMargin: Style.marginM
                  verticalAlignment: Text.AlignVCenter
                  text: toAmount.toFixed(2)
                  color: Color.mPrimary
                  pointSize: Style.fontSizeL
                  font.weight: Style.fontWeightBold
                }
              }

              ComboBox {
                id: toCurrencyCombo
                Layout.preferredWidth: 120 * Style.uiScaleRatio
                Layout.preferredHeight: Style.baseWidgetSize
                model: currencies
                currentIndex: currencies.indexOf(toCurrency)
                
                onActivated: index => {
                  toCurrency = currencies[index];
                }

                background: Rectangle {
                  color: Color.mSurface
                  border.color: Color.mOutline
                  border.width: Style.borderS
                  radius: Style.iRadiusM
                }

                contentItem: NText {
                  leftPadding: Style.marginM
                  rightPadding: Style.marginM
                  pointSize: Style.fontSizeM
                  verticalAlignment: Text.AlignVCenter
                  color: Color.mOnSurface
                  text: toCurrencyCombo.displayText
                }

                indicator: NIcon {
                  x: toCurrencyCombo.width - width - Style.marginS
                  y: toCurrencyCombo.topPadding + (toCurrencyCombo.availableHeight - height) / 2
                  icon: "caret-down"
                  pointSize: Style.fontSizeM
                }

                popup: Popup {
                  y: toCurrencyCombo.height
                  implicitWidth: toCurrencyCombo.width
                  implicitHeight: Math.min(300, toCurrencyListView.contentHeight + Style.marginM * 2)
                  padding: Style.marginM

                  contentItem: ListView {
                    id: toCurrencyListView
                    clip: true
                    model: toCurrencyCombo.model
                    currentIndex: toCurrencyCombo.highlightedIndex

                    delegate: Rectangle {
                      required property int index
                      required property string modelData
                      property bool isHighlighted: toCurrencyListView.currentIndex === index

                      width: toCurrencyListView.width
                      height: toDelegateText.implicitHeight + Style.marginS * 2
                      radius: Style.iRadiusS
                      color: isHighlighted ? Color.mHover : Color.transparent

                      NText {
                        id: toDelegateText
                        anchors.fill: parent
                        anchors.leftMargin: Style.marginM
                        anchors.rightMargin: Style.marginM
                        verticalAlignment: Text.AlignVCenter
                        pointSize: Style.fontSizeM
                        color: parent.isHighlighted ? Color.mOnHover : Color.mOnSurface
                        text: modelData
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                          if (containsMouse)
                            toCurrencyListView.currentIndex = index;
                        }
                        onClicked: {
                          toCurrencyCombo.currentIndex = index;
                          toCurrencyCombo.activated(index);
                          toCurrencyCombo.popup.close();
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
              }
            }
          }

          Item {
            Layout.fillHeight: true
          }

          // Exchange rate info
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: rateInfoText.implicitHeight + Style.marginM * 2
            color: Color.mSurfaceVariant
            radius: Style.iRadiusM

            NText {
              id: rateInfoText
              anchors.fill: parent
              anchors.margins: Style.marginM
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              text: {
                if (!availableRates || Object.keys(availableRates).length === 0) {
                  return I18n.tr("currency-converter.no-data") || "Sem dados disponíveis";
                }
                var baseRate = availableRates[fromCurrency] || 1;
                var targetRate = availableRates[toCurrency] || 1;
                var rate = (targetRate / baseRate).toFixed(4);
                return `1 ${fromCurrency} = ${rate} ${toCurrency}`;
              }
            }
          }
        }
      }
    }
  }
}
