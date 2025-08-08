import QtQuick
import Quickshell
import Quickshell.Services.UPower
import QtQuick.Layouts
import qs.Components
import qs.Settings

Item {

    property bool testMode: false
    property int testPercent: 49
    property bool testCharging: true

    property var battery: UPower.displayDevice
    property bool isReady: testMode ? true : (battery && battery.ready && battery.isLaptopBattery && battery.isPresent)
    property real percent: testMode ? testPercent : (isReady ? (battery.percentage * 100) : 0)
    property bool charging: testMode ? testCharging : (isReady ? battery.state === UPowerDeviceState.Charging : false)
    property bool show: isReady && percent > 0

    width: row.width
    height: row.height
    visible: testMode || (isReady && battery.isLaptopBattery)


    function batteryIcon() {
        if (!show)
            return "";

        if (charging)
            return "battery_android_bolt";

        if (percent >= 95)
            return "battery_android_full";

    
        if (percent >= 85)
            return "battery_android_6";
        if (percent >= 70)
            return "battery_android_5";
        if (percent >= 55)
            return "battery_android_4";
        if (percent >= 40)
            return "battery_android_3";
        if (percent >= 25)
            return "battery_android_2";
        if (percent >= 10)
            return "battery_android_1";
        if (percent >= 0)
            return "battery_android_0";
    }

    RowLayout {
        id: row
        spacing: 6
        Layout.alignment: Qt.AlignHCenter
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
            text: batteryIcon()
            font.family: "Material Symbols Outlined"
            font.pixelSize: 28 * Theme.scale(Screen)
            color: charging ? Theme.accentPrimary : Theme.textPrimary
            verticalAlignment: Text.AlignVBottom
        }

        Text {
            text: Math.round(percent) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 18 * Theme.scale(Screen)
            color: Theme.textPrimary
            verticalAlignment: Text.AlignVBottom
        }
    }
}
