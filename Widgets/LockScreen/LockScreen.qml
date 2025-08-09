import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io
import Quickshell.Widgets
import qs.Components
import qs.Settings
import qs.Services
import qs.Widgets.LockScreen
import "../../Helpers/Weather.js" as WeatherHelper

WlSessionLock {
    id: lock

    property string errorMessage: ""
    property bool authenticating: false
    property string password: ""
    property bool pamAvailable: typeof PamContext !== "undefined"
    property string weatherCity: Settings.settings.weatherCity
    property var weatherData: null
    property string weatherError: ""
    property string weatherInfo: ""
    property string weatherIcon: ""
    property double currentTemp: 0
    locked: false

    // Request to fetch weather with a little delay to ensure weatherCity is properly loaded.
    Component.onCompleted: {
        Qt.callLater(function () {
            fetchWeatherData();
        });
    }

    function fetchWeatherData() {
        WeatherHelper.fetchCityWeather(weatherCity, function (result) {
            weatherData = result.weather;
            weatherError = "";
        }, function (err) {
            weatherError = err;
        });
    }

    function materialSymbolForCode(code) {
        if (code === 0)
            return "sunny";
        if (code === 1 || code === 2)
            return "partly_cloudy_day";
        if (code === 3)
            return "cloud";
        if (code >= 45 && code <= 48)
            return "foggy";
        if (code >= 51 && code <= 67)
            return "rainy";
        if (code >= 71 && code <= 77)
            return "weather_snowy";
        if (code >= 80 && code <= 82)
            return "rainy";
        if (code >= 95 && code <= 99)
            return "thunderstorm";
        return "cloud";
    }

    function unlockAttempt() {
        console.log("Unlock attempt started");
        if (!pamAvailable) {
            lock.errorMessage = "PAM authentication not available.";
            console.log("PAM not available");
            return;
        }
        if (!lock.password) {
            lock.errorMessage = "Password required.";
            console.log("No password entered");
            return;
        }
        console.log("Starting PAM authentication...");
        lock.authenticating = true;
        lock.errorMessage = "";

        console.log("[LockScreen] About to create PAM context with userName:", Quickshell.env("USER"));
        var pam = Qt.createQmlObject('import Quickshell.Services.Pam; PamContext { config: "login"; user: "' + Quickshell.env("USER") + '" }', lock);
        console.log("PamContext created", pam);

        pam.onCompleted.connect(function (result) {
            console.log("PAM completed with result:", result);
            lock.authenticating = false;
            if (result === PamResult.Success) {
                console.log("Authentication successful, unlocking...");
                lock.locked = false;
                lock.password = "";
                lock.errorMessage = "";
            } else {
                console.log("Authentication failed");
                lock.errorMessage = "Authentication failed.";
                lock.password = "";
            }
            pam.destroy();
        });

        pam.onError.connect(function (error) {
            console.log("PAM error:", error);
            lock.authenticating = false;
            lock.errorMessage = pam.message || "Authentication error.";
            lock.password = "";
            pam.destroy();
        });

        pam.onPamMessage.connect(function () {
            console.log("PAM message:", pam.message, "isError:", pam.messageIsError);
            if (pam.messageIsError) {
                lock.errorMessage = pam.message;
            }
        });

        pam.onResponseRequiredChanged.connect(function () {
            console.log("PAM response required:", pam.responseRequired);
            if (pam.responseRequired && lock.authenticating) {
                console.log("Responding to PAM with password");
                pam.respond(lock.password);
            }
        });

        var started = pam.start();
        console.log("PAM start result:", started);
    }

    WlSessionLockSurface {
        // Wallpaper image to blur
        Image {
            id: lockBgImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: WallpaperManager.currentWallpaper !== "" ? WallpaperManager.currentWallpaper : ""
            cache: true
            smooth: true
            mipmap: false
        }

        MultiEffect {
            id: lockBgBlur
            anchors.fill: parent
            source: lockBgImage
            blurEnabled: true
            blur: 0.48   // controls blur strength (0 to 1)
            blurMax: 128 // max blur radius in pixels
            // transparentBorder: true
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 30
            width: Math.min(parent.width * 0.8, 400 * Theme.scale(Screen))

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 80 * Theme.scale(Screen)
                height: 80 * Theme.scale(Screen)
                radius: 40
                color: Theme.accentPrimary

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: 40
                    border.color: Theme.accentPrimary
                    border.width: 3 * Theme.scale(Screen)
                    z: 2
                }

                Avatar {}

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Theme.accentPrimary
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Quickshell.env("USER")
                font.family: Theme.fontFamily
                font.pixelSize: 24 * Theme.scale(Screen)
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Rectangle {
                Layout.fillWidth: true
                height: 50 * Theme.scale(Screen)
                radius: 25
                color: Theme.surface
                opacity: passwordInput.activeFocus ? 0.8 : 0.3
                border.color: passwordInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 2 * Theme.scale(Screen)

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.margins: 15 * Theme.scale(Screen)
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: 16 * Theme.scale(Screen)
                    color: Theme.textPrimary
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    passwordMaskDelay: 0

                    text: lock.password
                    onTextChanged: lock.password = text

                    Text {
                        anchors.centerIn: parent
                        text: "Enter password..."
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16 * Theme.scale(Screen)
                        visible: !passwordInput.text && !passwordInput.activeFocus
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            lock.unlockAttempt();
                        }
                    }

                    Component.onCompleted: {
                        forceActiveFocus();
                    }
                }
            }

            Rectangle {
                id: errorMessageRect
                Layout.alignment: Qt.AlignHCenter
                width: parent.width * 0.8
                height: 44 * Theme.scale(Screen)
                color: Theme.overlay
                radius: 18
                visible: lock.errorMessage !== ""

                Text {
                    anchors.centerIn: parent
                    text: lock.errorMessage
                    color: Theme.error
                    font.family: Theme.fontFamily
                    font.pixelSize: 14 * Theme.scale(Screen)
                    opacity: 1
                    visible: lock.errorMessage !== ""
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 120 * Theme.scale(Screen)
                height: 44 * Theme.scale(Screen)
                radius: 18
                opacity: unlockButtonArea.containsMouse ? 0.8 : 0.5
                color: unlockButtonArea.containsMouse ? Theme.accentPrimary : Theme.surface
                border.color: Theme.accentPrimary
                border.width: 2 * Theme.scale(Screen)
                enabled: !lock.authenticating

                Text {
                    id: unlockButtonText
                    anchors.centerIn: parent
                    text: lock.authenticating ? "..." : "Unlock"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16 * Theme.scale(Screen)
                    font.bold: true
                    color: unlockButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                }

                MouseArea {
                    id: unlockButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!lock.authenticating) {
                            lock.unlockAttempt();
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
        }

        Rectangle {
            width: infoColumn.width + 32 * Theme.scale(Screen)
            height: infoColumn.height + 8 * Theme.scale(Screen)
            color: (Theme.backgroundPrimary !== undefined && Theme.backgroundPrimary !== null) ? Theme.backgroundPrimary : "#222"
            anchors.horizontalCenter: parent.horizontalCenter
            bottomLeftRadius: 20 * Theme.scale(Screen)
            bottomRightRadius: 20 * Theme.scale(Screen)

            ColumnLayout {
                id: infoColumn
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                spacing: 8

                Text {
                    id: timeText
                    text: Qt.formatDateTime(new Date(), "HH:mm")
                    font.family: Theme.fontFamily
                    font.pixelSize: 48 * Theme.scale(Screen)
                    font.bold: true
                    color: Theme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    id: dateText
                    text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                    font.family: Theme.fontFamily
                    font.pixelSize: 16 * Theme.scale(Screen)
                    color: Theme.textSecondary
                    opacity: 0.8
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                }

                RowLayout {
                    spacing: 6
                    Layout.alignment: Qt.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: weatherData && weatherData.current_weather

                    Text {
                        text: weatherData && weatherData.current_weather ? materialSymbolForCode(weatherData.current_weather.weathercode) : "cloud"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 28 * Theme.scale(Screen)
                        color: Theme.accentPrimary
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: weatherData && weatherData.current_weather ? ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? `${Math.round(weatherData.current_weather.temperature * 9 / 5 + 32)}°F` : `${Math.round(weatherData.current_weather.temperature)}°C`) : ((Settings.settings.useFahrenheit !== undefined ? Settings.settings.useFahrenheit : false) ? "--°F" : "--°C")
                        font.family: Theme.fontFamily
                        font.pixelSize: 18 * Theme.scale(Screen)
                        color: Theme.textSecondary
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    text: weatherError
                    color: Theme.error
                    visible: weatherError !== ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 10 * Theme.scale(Screen)
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: {
                timeText.text = Qt.formatDateTime(new Date(), "HH:mm");
                dateText.text = Qt.formatDateTime(new Date(), "dddd, MMMM d");
            }
        }

        Timer {
            interval: 600000 // 10 minutes
            running: true
            repeat: true
            onTriggered: {
                fetchWeatherData();
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 32
            spacing: 12

            BatteryCharge {}
        }

        ColumnLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 32
            spacing: 12

            Rectangle {
                width: 48 * Theme.scale(Screen)
                height: 48 * Theme.scale(Screen)
                radius: 24
                color: shutdownArea.containsMouse ? Theme.error : "transparent"
                border.color: Theme.error
                border.width: 1 * Theme.scale(Screen)

                MouseArea {
                    id: shutdownArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Qt.createQmlObject('import Quickshell.Io; Process { command: ["shutdown", "-h", "now"]; running: true }', lock);
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24 * Theme.scale(Screen)
                    color: shutdownArea.containsMouse ? Theme.onAccent : Theme.error
                }
            }

            Rectangle {
                width: 48 * Theme.scale(Screen)
                height: 48 * Theme.scale(Screen)
                radius: 24
                color: rebootArea.containsMouse ? Theme.accentPrimary : "transparent"
                border.color: Theme.accentPrimary
                border.width: 1 * Theme.scale(Screen)

                MouseArea {
                    id: rebootArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Qt.createQmlObject('import Quickshell.Io; Process { command: ["reboot"]; running: true }', lock);
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "refresh"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24 * Theme.scale(Screen)
                    color: rebootArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                }
            }

            Rectangle {
                width: 48 * Theme.scale(Screen)
                height: 48 * Theme.scale(Screen)
                radius: 24
                color: logoutArea.containsMouse ? Theme.accentSecondary : "transparent"
                border.color: Theme.accentSecondary
                border.width: 1 * Theme.scale(Screen)

                MouseArea {
                    id: logoutArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Qt.createQmlObject('import Quickshell.Io; Process { command: ["loginctl", "terminate-user", "' + Quickshell.env("USER") + '"]; running: true }', lock);
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "exit_to_app"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24 * Theme.scale(Screen)
                    color: logoutArea.containsMouse ? Theme.onAccent : Theme.accentSecondary
                }
            }
        }
    }
}
