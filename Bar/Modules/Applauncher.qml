import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Components
import qs.Settings

import "../../Helpers/Fuzzysort.js" as Fuzzysort

PanelWithOverlay {
    id: appLauncherPanel
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    
    function isPinned(app) {
        return app && app.execString && Settings.settings.pinnedExecs.indexOf(app.execString) !== -1;
    }
    function togglePin(app) {
        if (!app || !app.execString) return;
        var arr = Settings.settings.pinnedExecs ? Settings.settings.pinnedExecs.slice() : [];
        var idx = arr.indexOf(app.execString);
        if (idx === -1) {
            arr.push(app.execString);
        } else {
            arr.splice(idx, 1);
        }
        Settings.settings.pinnedExecs = arr;
        root.updateFilter();
    }
    
    function showAt() {
        appLauncherPanelRect.showAt();
    }

    function hidePanel() {
        appLauncherPanelRect.hidePanel();
    }

    function show() {
        appLauncherPanelRect.showAt();
    }

    function dismiss() {
        appLauncherPanelRect.hidePanel();
    }

    Rectangle {
        id: appLauncherPanelRect
        implicitWidth: 460
        implicitHeight: 640
        color: "transparent"
        visible: parent.visible
        property bool shouldBeVisible: false
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        function showAt() {
            appLauncherPanel.visible = true;
            shouldBeVisible = true;
            searchField.forceActiveFocus();
            root.selectedIndex = 0;
            root.appModel = DesktopEntries.applications.values;
            root.updateFilter();
        }

        function hidePanel() {
            shouldBeVisible = false;
            searchField.text = "";
            root.selectedIndex = 0;
        }

        Rectangle {
            id: root
            width: 460
            height: 640
            x: (parent.width - width) / 2
            color: Theme.backgroundPrimary
            bottomLeftRadius: 28
            bottomRightRadius: 28

            property var appModel: DesktopEntries.applications.values
            property var filteredApps: []
            property int selectedIndex: 0
            property int targetY: (parent.height - height) / 2
            y: appLauncherPanelRect.shouldBeVisible ? targetY : -height
            Behavior on y {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            scale: appLauncherPanelRect.shouldBeVisible ? 1 : 0
            Behavior on scale {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutCubic
                }
            }
            onScaleChanged: {
                if (scale === 0 && !appLauncherPanelRect.shouldBeVisible) {
                    appLauncherPanel.visible = false;
                }
            }
            function isMathExpression(str) {
                return /^[-+*/().0-9\s]+$/.test(str);
            }
            function safeEval(expr) {
                try {
                    return Function('return (' + expr + ')')();
                } catch (e) {
                    return undefined;
                }
            }
            function updateFilter() {
                var query = searchField.text ? searchField.text.toLowerCase() : "";
                var apps = root.appModel.slice();
                var results = [];
                // Calculator mode: starts with '='
                if (query.startsWith("=")) {
                    var expr = searchField.text.slice(1).trim();
                    if (expr && isMathExpression(expr)) {
                        var value = safeEval(expr);
                        if (value !== undefined && value !== null && value !== "") {
                            results.push({
                                isCalculator: true,
                                name: `Calculator: ${expr} = ${value}`,
                                result: value,
                                expr: expr,
                                icon: "calculate"
                            });
                        }
                    }
                }
                if (!query || query.startsWith("=")) {
                    results = results.concat(apps.sort(function (a, b) {
                        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
                    }));
                } else {
                    var fuzzyResults = Fuzzysort.go(query, apps, {
                        keys: ["name", "comment", "genericName"]
                    });
                    results = results.concat(fuzzyResults.map(function (r) {
                        return r.obj;
                    }));
                }
                // Pinning logic: split into pinned and unpinned
                var pinned = [];
                var unpinned = [];
                for (var i = 0; i < results.length; ++i) {
                    var app = results[i];
                    if (app.execString && Settings.settings.pinnedExecs.indexOf(app.execString) !== -1) {
                        pinned.push(app);
                    } else {
                        unpinned.push(app);
                    }
                }
                // Sort pinned alphabetically
                pinned.sort(function(a, b) {
                    return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
                });
                root.filteredApps = pinned.concat(unpinned);
                root.selectedIndex = 0;
            }
            function selectNext() {
                if (filteredApps.length > 0)
                    selectedIndex = Math.min(selectedIndex + 1, filteredApps.length - 1);
            }
            function selectPrev() {
                if (filteredApps.length > 0)
                    selectedIndex = Math.max(selectedIndex - 1, 0);
            }
            function selectNextPage() {
                if (filteredApps.length > 0)
                    selectedIndex = Math.min(selectedIndex + 10, filteredApps.length - 1);
            }
            function selectPrevPage() {
                if (filteredApps.length > 0)
                    selectedIndex = Math.max(selectedIndex - 10, 0);
            }

            function activateSelected() {
                if (filteredApps.length === 0)
                    return;

                var modelData = filteredApps[selectedIndex];
                const termEmu = Quickshell.env("TERMINAL") || Quickshell.env("TERM_PROGRAM") || "";

                if (modelData.isCalculator) {
                    Qt.callLater(function () {
                        Quickshell.clipboardText = String(modelData.result);
                        Quickshell.execDetached(["notify-send", "Calculator Result", `${modelData.expr} = ${modelData.result} (copied to clipboard)`]);
                    });
                } else if (modelData.runInTerminal && termEmu){
                    Quickshell.execDetached([termEmu, "-e", modelData.execString.trim()]);
                } else if (modelData.execute) {
                    modelData.execute();
                } else {
                    var execCmd = modelData.execString || modelData.exec || "";
                    if (execCmd) {
                        execCmd = execCmd.replace(/\s?%[fFuUdDnNiCkvm]/g, '');
                        Quickshell.execDetached(["sh", "-c", execCmd.trim()]);
                    }
                }

                appLauncherPanel.hidePanel();
                searchField.text = "";
            }

            Component.onCompleted: updateFilter()

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 32
                spacing: 18

                // Search Bar
                Rectangle {
                    id: searchBar
                    color: Theme.surfaceVariant
                    radius: 20
                    height: 48
                    Layout.fillWidth: true
                    border.color: searchField.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: searchField.activeFocus ? 2 : 1

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Keys.onDownPressed: root.selectNext()
                        Keys.onUpPressed: root.selectPrev()
                        Keys.onEnterPressed: root.activateSelected()
                        Keys.onReturnPressed: root.activateSelected()
                        Keys.onEscapePressed: appLauncherPanel.hidePanel()
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_PageDown) {
                                root.selectNextPage()
                                event.accepted = true; 
                            } 
                            else if (event.key === Qt.Key_PageUp) {
                                root.selectPrevPage()
                                event.accepted = true;
                            }
                        }
                        
                        Text {
                            text: "search"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: Theme.fontSizeHeader
                            color: searchField.activeFocus ? Theme.accentPrimary : Theme.textSecondary
                            verticalAlignment: Text.AlignVCenter
                            Layout.alignment: Qt.AlignVCenter
                        }
                        TextField {
                            id: searchField
                            placeholderText: "Search apps..."
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textSecondary
                            background: null
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            onTextChanged: root.updateFilter()
                            selectedTextColor: Theme.onAccent
                            selectionColor: Theme.accentPrimary
                            padding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            font.bold: true
                            Component.onCompleted: contentItem.cursorColor = Theme.textPrimary
                            onActiveFocusChanged: contentItem.cursorColor = Theme.textPrimary
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 120
                        }
                    }
                    Behavior on border.width {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }

                // App List Card
                Rectangle {
                    color: Theme.surface
                    radius: 20
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    property int innerPadding: 16

                    Item {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: parent.innerPadding
                        visible: false
                    }

                    ListView {
                        id: appList
                        anchors.fill: parent
                        anchors.margins: parent.innerPadding
                        spacing: 2
                        model: root.filteredApps
                        currentIndex: root.selectedIndex
                        delegate: Item {
                            id: appDelegate
                            width: appList.width
                            height: 48
                            property bool hovered: mouseArea.containsMouse
                            property bool isSelected: index === root.selectedIndex

                            Rectangle {
                                anchors.fill: parent
                                color: (hovered || isSelected)
                                    ? Theme.accentPrimary
                                    : (appLauncherPanel.isPinned(modelData) ? Theme.surfaceVariant : "transparent")
                                radius: 12
                                border.color: appLauncherPanel.isPinned(modelData)
                                    ? "transparent"
                                    : (hovered || isSelected ? Theme.accentPrimary : "transparent")
                                border.width: appLauncherPanel.isPinned(modelData) ? 0 : (hovered || isSelected ? 2 : 0)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                                Behavior on border.color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                                Behavior on border.width {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                Item {
                                    width: 28
                                    height: 28
                                    property bool iconLoaded: !modelData.isCalculator && iconImg.status === Image.Ready && iconImg.source !== "" && iconImg.status !== Image.Error
                                    IconImage {
                                        id: iconImg
                                        anchors.fill: parent
                                        asynchronous: true
                                        source: modelData.isCalculator ? "qrc:/icons/calculate.svg" : Quickshell.iconPath(modelData.icon, "application-x-executable")
                                        visible: modelData.isCalculator || parent.iconLoaded
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !modelData.isCalculator && !parent.iconLoaded
                                        text: "broken_image"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: Theme.fontSizeHeader
                                        color: Theme.accentPrimary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: modelData.name
                                        color: (hovered || isSelected) ? Theme.onAccent : (appLauncherPanel.isPinned(modelData) ? Theme.textPrimary : Theme.textPrimary)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: hovered || isSelected
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.isCalculator ? (modelData.expr + " = " + modelData.result) : (modelData.comment || modelData.genericName || "No description available")
                                        color: (hovered || isSelected) ? Theme.onAccent : (appLauncherPanel.isPinned(modelData) ? Theme.textSecondary : Theme.textSecondary)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.italic: !(modelData.comment || modelData.genericName)
                                        opacity: (modelData.comment || modelData.genericName) ? 1.0 : 0.6
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.isCalculator ? "content_copy" : "chevron_right"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: Theme.fontSizeBody
                                    color: (hovered || isSelected)
                                        ? Theme.onAccent
                                        : (appLauncherPanel.isPinned(modelData) ? Theme.textPrimary : Theme.textSecondary)
                                    verticalAlignment: Text.AlignVCenter
                                    Layout.rightMargin: 8 // Add margin to separate from star
                                }
                                // Add a spacing item between chevron and star
                                Item { width: 8; height: 1 }
                            }

                            Rectangle {
                                id: ripple
                                anchors.fill: parent
                                color: Theme.onAccent
                                opacity: 0.0
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: {
                                    // Prevent app launch if click is inside pinArea
                                    if (pinArea.containsMouse) return;
                                    if (mouse.button === Qt.RightButton) {
                                        appLauncherPanel.togglePin(modelData);
                                        return;
                                    }
                                    ripple.opacity = 0.18;
                                    rippleNumberAnimation.start();
                                    root.selectedIndex = index;
                                    root.activateSelected();
                                }
                                cursorShape: Qt.PointingHandCursor
                                onPressed: ripple.opacity = 0.18
                                onReleased: ripple.opacity = 0.0
                            }

                            NumberAnimation {
                                id: rippleNumberAnimation
                                target: ripple
                                property: "opacity"
                                to: 0.0
                                duration: 320
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.outline
                                opacity: index === appList.count - 1 ? 0 : 0.10
                            }
                            // Pin/Unpin button (move to last child for stacking)
                            Item {
                                id: pinArea
                                width: 28; height: 28
                                z: 100 // Ensure above everything else
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true
                                    z: 100
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    propagateComposedEvents: false
                                    onClicked: {
                                        appLauncherPanel.togglePin(modelData);
                                        event.accepted = true;
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "star"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: (parent.MouseArea.containsMouse || hovered || isSelected)
                                        ? Theme.onAccent
                                        : (appLauncherPanel.isPinned(modelData) ? Theme.textPrimary : Theme.textDisabled)
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }

        Corners {
            id: launcherCornerRight
            position: "bottomleft"
            size: 1.1
            fillColor: Theme.backgroundPrimary
            anchors.top: root.top
            offsetX: 416
            offsetY: 0
        }

        Corners {
            id: launcherCornerLeft
            position: "bottomright"
            size: 1.1
            fillColor: Theme.backgroundPrimary
            anchors.top: root.top
            offsetX: -416
            offsetY: 0
        }
    }
}
