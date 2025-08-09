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
    Timer {
        id: clipboardTimer
        interval: 1000
        repeat: true
        running: appLauncherPanel.visible
        onTriggered: {
            updateClipboardHistory();
        }
    }

    property var clipboardHistory: []
    property bool clipboardInitialized: false

    Process {
        id: clipboardTypeProcess
        property bool isLoading: false
        property var currentTypes: []

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                currentTypes = String(stdout.text).trim().split('\n').filter(t => t);

                const imageType = currentTypes.find(t => t.startsWith('image/'));
                if (imageType) {
                    clipboardImageProcess.mimeType = imageType;
                    clipboardImageProcess.command = ["sh", "-c", `wl-paste -n -t "${imageType}" | base64 -w 0`];
                    clipboardImageProcess.running = true;
                } else {

                    clipboardHistoryProcess.command = ["wl-paste", "-n", "--type", "text/plain"];
                    clipboardHistoryProcess.running = true;
                }
            } else {

                clipboardTypeProcess.isLoading = false;
            }
        }

        stdout: StdioCollector {}
    }

    Process {
        id: clipboardImageProcess
        property string mimeType: ""

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                const base64 = stdout.text.trim();
                if (base64) {
                    const entry = {
                        type: 'image',
                        mimeType: mimeType,
                        data: `data:${mimeType};base64,${base64}`,
                        timestamp: new Date().getTime()
                    };
                    
    
                    const exists = clipboardHistory.find(item => 
                        item.type === 'image' && item.data === entry.data
                    );

                    if (!exists) {
                        clipboardHistory = [entry, ...clipboardHistory].slice(0, 20);
                        root.updateFilter();
                    }
                }
            }
            
            if (!clipboardHistoryProcess.isLoading) {
                clipboardInitialized = true;
            }
            clipboardTypeProcess.isLoading = false;
        }

        stdout: StdioCollector {}
    }

    Process {
        id: clipboardHistoryProcess
        property bool isLoading: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                const content = String(stdout.text).trim();
                // Only filter out self path to avoid capturing this file
                const isSelfPath = content.indexOf("/home/lysec/.config/quickshell/Bar/Modules/Applauncher.qml") !== -1;
                if (content && !isSelfPath) {
                    const entry = {
                        type: 'text',
                        content: content,
                        timestamp: new Date().getTime()
                    };

    
                    const exists = clipboardHistory.find(item => {
                        if (item.type === 'text') {
                            return item.content === content;
                        }
        
                        return item === content;
                    });

                    if (!exists) {
        
                        const newHistory = clipboardHistory.map(item => {
                            if (typeof item === 'string') {
                                return {
                                    type: 'text',
                                    content: item,
                                    timestamp: new Date().getTime()
                                };
                            }
                            return item;
                        });
                        
                        clipboardHistory = [entry, ...newHistory].slice(0, 20);
                    }
                }
            } else {

                clipboardHistoryProcess.isLoading = false;
            }
            clipboardInitialized = true;
            clipboardTypeProcess.isLoading = false;
            root.updateFilter();
        }

        stdout: StdioCollector {}
    }

    Process {
        id: clipboardImageCopyProcess
        property string mimeType: ""
        property string pendingBase64: ""
        // Simple FIFO queue for repeated copy requests
        property var queue: []
        stdinEnabled: true

        command: [
            "sh",
            "-c",
            "base64 -d | wl-copy -t '" + mimeType + "'"
        ]
        function copyBase64(mime, base64) {
            // If a copy is in progress or pending, queue the next request
            if (running || (pendingBase64 && pendingBase64.length > 0)) {
                var q = queue.slice();
                q.push({ mime: mime, base64: base64 });
                queue = q;
                return;
            }
            mimeType = mime;
            pendingBase64 = base64;
            running = true;
        }
        onStarted: {
            // ensure stdin is open for each new run
            stdinEnabled = true;
            if (pendingBase64 && pendingBase64.length > 0) {
                write(pendingBase64);
            }
            // Close stdin to signal EOF so base64 exits
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            pendingBase64 = "";
            // re-open stdin for the next run so we can copy repeatedly
            stdinEnabled = true;
            if (queue.length > 0) {
                var next = queue[0];
                // pop front
                var q2 = queue.slice(1);
                queue = q2;
                mimeType = next.mime;
                pendingBase64 = next.base64;
                running = true;
            }
        }
        stdout: StdioCollector {}
    }

    // Process to copy arbitrary text via stdin to avoid quoting/ARG_MAX issues
    Process {
        id: clipboardTextCopyProcess
        property string pendingText: ""
        property var queue: []
        stdinEnabled: true

        command: [
            "sh",
            "-c",
            "cat | wl-copy -t text/plain;charset=utf-8"
        ]

        function copyText(text) {
            if (running || (pendingText && pendingText.length > 0)) {
                var q = queue.slice();
                q.push(text);
                queue = q;
                return;
            }
            pendingText = text;
            running = true;
        }

        onStarted: {
            stdinEnabled = true;
            if (pendingText && pendingText.length > 0) {
                write(pendingText);
            }
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            pendingText = "";
            stdinEnabled = true;
            if (queue.length > 0) {
                var next = queue[0];
                queue = queue.slice(1);
                pendingText = next;
                running = true;
            }
        }
        stdout: StdioCollector {}
    }

    

    function updateClipboardHistory() {
        if (!clipboardTypeProcess.isLoading && !clipboardHistoryProcess.isLoading) {
            clipboardTypeProcess.isLoading = true;
            clipboardTypeProcess.command = ["wl-paste", "-l"];
            clipboardTypeProcess.running = true;
        }
    }

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
            // Start clipboard refresh immediately on open so >clip is ready
            updateClipboardHistory();
        }

        function hidePanel() {
            shouldBeVisible = false;
            searchField.text = "";
            root.selectedIndex = 0;
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
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
                

                if (query === ">") {
                    results.push({
                        isCommand: true,
                        name: ">calc",
                        content: "Calculator - evaluate mathematical expressions",
                        icon: "calculate",
                        execute: function() {
                            searchField.text = ">calc ";
                            searchField.cursorPosition = searchField.text.length;
                        }
                    });
                    
                    results.push({
                        isCommand: true,
                        name: ">clip",
                        content: "Clipboard history - browse and restore clipboard items",
                        icon: "content_paste",
                        execute: function() {
                            searchField.text = ">clip ";
                            searchField.cursorPosition = searchField.text.length;
                        }
                    });
                    
                    root.filteredApps = results;
                    return;
                }
                

                if (query.startsWith(">clip")) {
                    if (!clipboardInitialized) {
                        updateClipboardHistory();
                    }
                    const searchTerm = query.slice(5).trim();
                    
                    clipboardHistory.forEach(function(clip, index) {
                        let searchContent = clip.type === 'image' ? 
                            clip.mimeType : 
                            clip.content || clip;  // Support both new object format and old string format
                            
                        if (!searchTerm || searchContent.toLowerCase().includes(searchTerm)) {
                            let entry;
                            if (clip.type === 'image') {
                                entry = {
                                    isClipboard: true,
                                    name: "Image from " + new Date(clip.timestamp).toLocaleTimeString(),
                                    content: "Image: " + clip.mimeType,
                                    icon: "image",
                                    type: 'image',
                                    data: clip.data,
                                    execute: function() {
                                        // Restore image via stdin to avoid command-length limits
                                        const base64Data = clip.data.split(',')[1];
                                        clipboardImageCopyProcess.copyBase64(clip.mimeType, base64Data);
                                        Quickshell.execDetached(["notify-send", "Clipboard", "Image copied: " + clip.mimeType]);
                                    }
                                };
                            } else {
                                const textContent = clip.content || clip;  // Support both new object format and old string format
                                let displayContent = textContent;
                                let previewContent = "";
                                
                                // Clean up whitespace for display
                                displayContent = displayContent.replace(/\s+/g, ' ').trim();
                                
                                // Truncate long content and show preview
                                if (displayContent.length > 50) {
                                    previewContent = displayContent;
                                    // Show first line or first 50 characters as title
                                    displayContent = displayContent.split('\n')[0].substring(0, 50) + "...";
                                }
                                
                                entry = {
                                    isClipboard: true,
                                    name: displayContent,
                                    content: previewContent || textContent,
                                    icon: "content_paste",
                                    execute: function() {
                                        // Set Quickshell clipboard as primary path; also stream to wl-copy for system clipboard
                                        Quickshell.clipboardText = String(textContent);
                                        clipboardTextCopyProcess.copyText(String(textContent));
                                        var preview = (textContent.length > 50) ? textContent.slice(0,50) + "…" : textContent;
                                        Quickshell.execDetached(["notify-send", "Clipboard", "Text copied: " + preview]);
                                    }
                                };
                            }
                            results.push(entry);
                        }
                    });
                    
                    if (results.length === 0) {
                        results.push({
                            isClipboard: true,
                            name: "No clipboard history",
                            content: "No matching clipboard entries found",
                            icon: "content_paste_off"
                        });
                    }
                    
                    root.filteredApps = results;
                    return;
                }
                

                if (query.startsWith(">calc")) {
                    var expr = searchField.text.slice(5).trim();
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
                    // Sort pinned apps alphabetically for consistent display
                    pinned.sort(function(a, b) {
                        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
                    });
                    root.filteredApps = pinned.concat(unpinned);
                    root.selectedIndex = 0;
                    return;
                }
                if (!query) {
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
                } else if (modelData.isCommand) {
    
                    modelData.execute();
                    return;
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

            RowLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 18

        
                Rectangle {
                    id: previewPanel
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    color: Theme.surface
                    radius: 20
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 16
                        color: "transparent"
                        clip: true

                        Image {
                            id: previewImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            smooth: true
                        }
                    }
                }

        
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 18

            
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

                            Text {
                                text: "search"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: Theme.fontSizeHeader * Theme.scale(screen)
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
                                font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
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

                                Keys.onDownPressed: root.selectNext()
                                Keys.onUpPressed: root.selectPrev()
                                Keys.onEnterPressed: root.activateSelected()
                                Keys.onReturnPressed: root.activateSelected()
                                Keys.onEscapePressed: appLauncherPanel.hidePanel()
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

            
                    Rectangle {
                        color: Theme.surface
                        radius: 20
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        property int innerPadding: 16

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
                                height: (modelData.isClipboard || modelData.isCommand) ? 64 : 48
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
                                        property bool iconLoaded: !modelData.isCalculator && !modelData.isClipboard && !modelData.isCommand && iconImg.status === Image.Ready && iconImg.source !== "" && iconImg.status !== Image.Error
                                        
                                        Image {
                                            id: clipboardImage
                                            anchors.fill: parent
                                            visible: modelData.type === 'image'
                                            source: modelData.data || ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                propagateComposedEvents: true
                                                onContainsMouseChanged: {
                                                    if (containsMouse && modelData.type === 'image') {
                                                        previewImage.source = modelData.data;
                                                        previewPanel.visible = true;
                                                    } else {
                                                        previewPanel.visible = false;
                                                    }
                                                }
                                                onMouseXChanged: mouse.accepted = false
                                                onMouseYChanged: mouse.accepted = false
                                                onClicked: mouse.accepted = false
                                            }
                                        }

                                        IconImage {
                                            id: iconImg
                                            anchors.fill: parent
                                            asynchronous: true
                                            source: modelData.isCalculator ? "qrc:/icons/calculate.svg" : 
                                                    modelData.isClipboard ? "qrc:/icons/" + modelData.icon + ".svg" :
                                                    modelData.isCommand ? "qrc:/icons/" + modelData.icon + ".svg" :
                                                    Quickshell.iconPath(modelData.icon, "application-x-executable")
                                            visible: (modelData.isCalculator || modelData.isClipboard || modelData.isCommand || parent.iconLoaded) && modelData.type !== 'image'
                                        }
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !modelData.isCalculator && !modelData.isClipboard && !modelData.isCommand && !parent.iconLoaded && modelData.type !== 'image'
                                            text: "broken_image"
                                            font.family: "Material Symbols Outlined"
                                            font.pixelSize: Theme.fontSizeHeader * Theme.scale(screen)
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
                                            font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
                                            font.bold: hovered || isSelected
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: modelData.isCalculator ? (modelData.expr + " = " + modelData.result) : 
                                                  modelData.isClipboard ? modelData.content :
                                                  modelData.isCommand ? modelData.content :
                                                  (modelData.comment || modelData.genericName || "No description available")
                                            color: (hovered || isSelected) ? Theme.onAccent : (appLauncherPanel.isPinned(modelData) ? Theme.textSecondary : Theme.textSecondary)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeCaption * Theme.scale(screen)
                                            font.italic: !(modelData.comment || modelData.genericName)
                                            opacity: modelData.isClipboard ? 0.8 : modelData.isCommand ? 0.9 : ((modelData.comment || modelData.genericName) ? 1.0 : 0.6)
                                            elide: Text.ElideRight
                                            maximumLineCount: (modelData.isClipboard || modelData.isCommand) ? 2 : 1
                                            wrapMode: (modelData.isClipboard || modelData.isCommand) ? Text.WordWrap : Text.NoWrap
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: (modelData.isClipboard || modelData.isCommand) ? implicitHeight : contentHeight
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.isCalculator ? "content_copy" : "chevron_right"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
                                        color: (hovered || isSelected)
                                            ? Theme.onAccent
                                            : (appLauncherPanel.isPinned(modelData) ? Theme.textPrimary : Theme.textSecondary)
                                        verticalAlignment: Text.AlignVCenter
                                        Layout.rightMargin: 8
                                    }

            
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
                                    height: Math.max(1, 1 * Theme.scale(screen))
                                    color: Theme.outline
                                    opacity: index === appList.count - 1 ? 0 : 0.10
                                }

        
                                Item {
                                    id: pinArea
                                    width: 28; height: 28
                                    z: 100
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
                                        font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
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
        }
    }
}