import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../Helpers/FuzzySort.js" as Fuzzysort

import "Providers"
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Keyboard
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

SmartPanel {
    id: root

    // Generic preview support - active when current provider has preview and item is selected
    readonly property bool previewActive: {
        var provider = activeProvider;
        if (!provider || !provider.hasPreview)
            return false;
        if (!Settings.data.appLauncher.enableClipPreview)
            return false;
        return selectedIndex >= 0 && results && !!results[selectedIndex];
    }

    // Panel configuration
    readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
    readonly property int previewPanelWidth: Math.round(400 * Style.uiScaleRatio)
    readonly property int totalBaseWidth: listPanelWidth + (Style.marginL * 2)

    preferredWidth: totalBaseWidth
    preferredHeight: Math.round(600 * Style.uiScaleRatio)
    preferredWidthRatio: 0.25
    preferredHeightRatio: 0.5

    // Positioning
    readonly property string panelPosition: {
        if (Settings.data.appLauncher.position === "follow_bar") {
            if (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") {
                return `center_${Settings.data.bar.position}`;
            } else {
                return `${Settings.data.bar.position}_center`;
            }
        } else {
            return Settings.data.appLauncher.position;
        }
    }
    panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
    panelAnchorVerticalCenter: panelPosition === "center"
    panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
    panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
    panelAnchorBottom: panelPosition.startsWith("bottom_")
    panelAnchorTop: panelPosition.startsWith("top_")

    // Core state
    property string searchText: ""
    property int selectedIndex: 0
    property var results: []
    property var providers: []
    property var activeProvider: null
    property bool resultsReady: false
    property var pluginProviderInstances: ({}) // Track plugin provider instances
    property bool ignoreMouseHover: Settings.data.appLauncher.ignoreMouseInput

    // Default provider for regular search (applications)
    readonly property var defaultProvider: appsProvider
    // Current provider - either active command provider or default
    readonly property var currentProvider: activeProvider || defaultProvider

    readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6 * Style.uiScaleRatio)
    readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2)
    // Whether current provider is showing categorized view (vs filtered search results)
    readonly property bool providerShowsCategories: {
        return currentProvider.showsCategories === true;
    }

    // Get categories for the current provider (uses availableCategories if present, falls back to categories)
    readonly property var providerCategories: {
        if (currentProvider.availableCategories && currentProvider.availableCategories.length > 0) {
            return currentProvider.availableCategories;
        }
        return currentProvider.categories || [];
    }

    // Check if category tabs should be shown
    readonly property bool showProviderCategories: {
        if (!providerShowsCategories || providerCategories.length === 0) {
            return false;
        }
        // For default apps provider, respect the showCategories setting
        if (currentProvider === defaultProvider) {
            return Settings.data.appLauncher.showCategories;
        }
        return true;
    }

    // Check if results have displayString (emoji/kaomoji style)
    readonly property bool providerHasDisplayString: {
        return results.length > 0 && !!results[0].displayString;
    }

    // Get supported layouts - check active provider first, then first result's provider
    readonly property string providerSupportedLayouts: {
        // Active command provider takes priority
        if (activeProvider && activeProvider.supportedLayouts) {
            return activeProvider.supportedLayouts;
        }
        // Check first result's provider (for mixed search results)
        if (results.length > 0 && results[0].provider && results[0].provider.supportedLayouts) {
            return results[0].provider.supportedLayouts;
        }
        // Fall back to default provider
        if (defaultProvider && defaultProvider.supportedLayouts) {
            return defaultProvider.supportedLayouts;
        }
        return "both";
    }

    // Whether to show the layout toggle button
    readonly property bool showLayoutToggle: {
        // Hide toggle when provider has displayString (forces grid)
        if (providerHasDisplayString) {
            return false;
        }
        // Only show toggle when provider supports both layouts
        return providerSupportedLayouts === "both";
    }

    readonly property bool isGridView: {
        // Command picker always in list view
        if (searchText === ">") {
            return false;
        }
        // Respect provider's layout preference
        if (providerSupportedLayouts === "grid") {
            return true;
        }
        if (providerSupportedLayouts === "list") {
            return false;
        }
        // Provider supports both - use user preference or displayString hint
        if (providerHasDisplayString) {
            return true;
        }
        return Settings.data.appLauncher.viewMode === "grid";
    }

    // Target columns - use provider preference if available, otherwise default to 5
    readonly property int targetGridColumns: {
        if (currentProvider && currentProvider.preferredGridColumns) {
            return currentProvider.preferredGridColumns;
        }
        return 5;
    }
    readonly property int gridContentWidth: listPanelWidth - (2 * Style.marginXS)
    readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

    // Actual columns that fit in the GridView
    // This gets updated dynamically by the GridView when its actual width is known
    property int gridColumns: 5

    // Listen for plugin provider registry changes
    Connections {
        target: LauncherProviderRegistry
        function onPluginProviderRegistryUpdated() {
            root.syncPluginProviders();
        }
    }

    onSearchTextChanged: updateResults()

    // Lifecycle
    onOpened: {
        resultsReady = false;
        ignoreMouseHover = true;

        // Sync plugin providers first
        syncPluginProviders();

        // Notify providers and update results
        // Use Qt.callLater to ensure providers are registered (Component.onCompleted runs first)
        Qt.callLater(() => {
            for (let provider of providers) {
                if (provider.onOpened)
                    provider.onOpened();
            }
            updateResults();
            resultsReady = true;
        });
    }

    onClosed: {
        // Reset search text
        searchText = "";
        ignoreMouseHover = true;

        // Notify providers
        for (let provider of providers) {
            if (provider.onClosed)
                provider.onClosed();
        }
    }

    // Override keyboard handlers from SmartPanel for navigation.
    // Launcher specific: onTabPressed() and onBackTabPressed() are special here.
    // They are not coming from SmartPanelWindow as they are consumed by the search field before reaching the panel.
    // They are instead being forwared from the search field NTextInput below.
    function onTabPressed() {
        // In browsing mode with categories, Tab navigates between categories
        if (showProviderCategories) {
            var categories = providerCategories;
            var catIndex = categories.indexOf(currentProvider.selectedCategory);
            var nextIndex = (catIndex + 1) % categories.length;
            currentProvider.selectCategory(categories[nextIndex]);
        } else {
            selectNextWrapped();
        }
    }

    function onBackTabPressed() {
        // In browsing mode with categories, Shift+Tab navigates between categories
        if (showProviderCategories) {
            var categories = providerCategories;
            var catIndex = categories.indexOf(currentProvider.selectedCategory);
            var previousIndex = ((catIndex - 1) % categories.length + categories.length) % categories.length;
            currentProvider.selectCategory(categories[previousIndex]);
        } else {
            selectPreviousWrapped();
        }
    }

    function onUpPressed() {
        if (isGridView) {
            selectPreviousRow();
        } else {
            selectPreviousWrapped();
        }
    }

    function onDownPressed() {
        if (isGridView) {
            selectNextRow();
        } else {
            selectNextWrapped();
        }
    }

    function onLeftPressed() {
        if (isGridView) {
            selectPreviousColumn();
        } else {
            // In list view, left = previous item
            selectPreviousWrapped();
        }
    }

    function onRightPressed() {
        if (isGridView) {
            selectNextColumn();
        } else {
            // In list view, right = next item
            selectNextWrapped();
        }
    }

    function onReturnPressed() {
        activate();
    }

    function onHomePressed() {
        selectFirst();
    }

    function onEndPressed() {
        selectLast();
    }

    function onPageUpPressed() {
        selectPreviousPage();
    }

    function onPageDownPressed() {
        selectNextPage();
    }

    function onCtrlJPressed() {
        selectNextWrapped();
    }

    function onCtrlKPressed() {
        selectPreviousWrapped();
    }

    function onCtrlNPressed() {
        selectNextWrapped();
    }

    function onCtrlPPressed() {
        selectPreviousWrapped();
    }

    function onDeletePressed() {
        // Generic delete handling - ask provider if item can be deleted
        if (selectedIndex < 0 || !results || !results[selectedIndex])
            return;
        var item = results[selectedIndex];
        var provider = item.provider || currentProvider;

        if (provider && provider.canDeleteItem && provider.canDeleteItem(item)) {
            provider.deleteItem(item);
        }
    }

    // Public API for providers
    function setSearchText(text) {
        searchText = text;
    }

    // Provider registration
    function registerProvider(provider) {
        providers.push(provider);
        provider.launcher = root;
        if (provider.init)
            provider.init();
    }

    // Plugin provider sync - loads providers from LauncherProviderRegistry
    function syncPluginProviders() {
        var registeredIds = LauncherProviderRegistry.getPluginProviders();

        // Remove providers that are no longer registered
        for (var existingId in pluginProviderInstances) {
            if (registeredIds.indexOf(existingId) === -1) {
                // Unregister and destroy
                var idx = providers.indexOf(pluginProviderInstances[existingId]);
                if (idx >= 0) {
                    providers.splice(idx, 1);
                }
                pluginProviderInstances[existingId].destroy();
                delete pluginProviderInstances[existingId];
                Logger.d("Launcher", "Removed plugin provider:", existingId);
            }
        }

        // Add new providers
        for (var i = 0; i < registeredIds.length; i++) {
            var providerId = registeredIds[i];
            if (!pluginProviderInstances[providerId]) {
                var component = LauncherProviderRegistry.getProviderComponent(providerId);
                var pluginId = providerId.substring(7);
                // Remove "plugin:" prefix
                var pluginApi = PluginService.getPluginAPI(pluginId);

                if (component && pluginApi) {
                    var instance = component.createObject(root, {
                        "pluginApi": pluginApi
                    });
                    if (instance) {
                        pluginProviderInstances[providerId] = instance;
                        registerProvider(instance);
                        Logger.d("Launcher", "Registered plugin provider:", providerId);
                    }
                }
            }
        }

        // Update results if launcher is open
        if (root.isPanelOpen) {
            updateResults();
        }
    }

    // Search handling
    function updateResults() {
        results = [];
        var newActiveProvider = null;

        // Check for command mode
        if (searchText.startsWith(">")) {
            // Find provider that handles this command
            for (let provider of providers) {
                if (provider.handleCommand && provider.handleCommand(searchText)) {
                    newActiveProvider = provider;
                    results = provider.getResults(searchText);
                    break;
                }
            }

            // Show available commands if just ">" or filter commands if partial match
            if (!newActiveProvider) {
                // Collect all commands from all providers
                let allCommands = [];
                for (let provider of providers) {
                    if (provider.commands) {
                        allCommands = allCommands.concat(provider.commands());
                    }
                }

                if (searchText === ">") {
                    // Show all commands when just ">"
                    results = allCommands;
                } else if (searchText.length > 1) {
                    // Filter commands using fuzzy search when typing partial command
                    const query = searchText.substring(1);

                    // Remove the ">" prefix
                    if (typeof Fuzzysort !== 'undefined') {
                        // Use fuzzy search to filter commands
                        const fuzzyResults = Fuzzysort.go(query, allCommands, {
                            "keys": ["name"],
                            "threshold": -1000,
                            "limit": 50
                        });

                        // Convert fuzzy results back to command objects
                        results = fuzzyResults.map(result => result.obj);
                    } else {
                        // Fallback to simple substring matching
                        const queryLower = query.toLowerCase();
                        results = allCommands.filter(cmd => {
                            const cmdName = (cmd.name || "").toLowerCase();
                            return cmdName.includes(queryLower);
                        });
                    }
                }
            }
        } else {
            // Regular search - let providers contribute results
            for (let provider of providers) {
                if (provider.handleSearch) {
                    const providerResults = provider.getResults(searchText);
                    results = results.concat(providerResults);
                }
            }
        }

        // Update activeProvider only after computing new state to avoid UI flicker
        activeProvider = newActiveProvider;
        selectedIndex = 0;
    }

    // Navigation functions
    function selectNextWrapped() {
        if (results.length > 0) {
            selectedIndex = (selectedIndex + 1) % results.length;
        }
    }

    function selectPreviousWrapped() {
        if (results.length > 0) {
            selectedIndex = (((selectedIndex - 1) % results.length) + results.length) % results.length;
        }
    }

    function selectFirst() {
        selectedIndex = 0;
    }

    function selectLast() {
        if (results.length > 0) {
            selectedIndex = results.length - 1;
        } else {
            selectedIndex = 0;
        }
    }

    function selectNextPage() {
        if (results.length > 0) {
            const page = Math.max(1, Math.floor(600 / entryHeight));
            // Use approximate height
            selectedIndex = Math.min(selectedIndex + page, results.length - 1);
        }
    }

    function selectPreviousPage() {
        if (results.length > 0) {
            const page = Math.max(1, Math.floor(600 / entryHeight));
            // Use approximate height
            selectedIndex = Math.max(selectedIndex - page, 0);
        }
    }

    // Grid view navigation functions
    function selectPreviousRow() {
        if (results.length > 0 && isGridView && gridColumns > 0) {
            const currentRow = Math.floor(selectedIndex / gridColumns);
            const currentCol = selectedIndex % gridColumns;

            if (currentRow > 0) {
                // Move to previous row, same column
                const targetRow = currentRow - 1;
                const targetIndex = targetRow * gridColumns + currentCol;
                // Check if target column exists in target row
                const itemsInTargetRow = Math.min(gridColumns, results.length - targetRow * gridColumns);
                if (currentCol < itemsInTargetRow) {
                    selectedIndex = targetIndex;
                } else {
                    // Target column doesn't exist, go to last item in target row
                    selectedIndex = targetRow * gridColumns + itemsInTargetRow - 1;
                }
            } else {
                // Wrap to last row, same column
                const totalRows = Math.ceil(results.length / gridColumns);
                const lastRow = totalRows - 1;
                const itemsInLastRow = Math.min(gridColumns, results.length - lastRow * gridColumns);
                if (currentCol < itemsInLastRow) {
                    selectedIndex = lastRow * gridColumns + currentCol;
                } else {
                    selectedIndex = results.length - 1;
                }
            }
        }
    }

    function selectNextRow() {
        if (results.length > 0 && isGridView && gridColumns > 0) {
            const currentRow = Math.floor(selectedIndex / gridColumns);
            const currentCol = selectedIndex % gridColumns;
            const totalRows = Math.ceil(results.length / gridColumns);

            if (currentRow < totalRows - 1) {
                // Move to next row, same column
                const targetRow = currentRow + 1;
                const targetIndex = targetRow * gridColumns + currentCol;

                // Check if target index is valid
                if (targetIndex < results.length) {
                    selectedIndex = targetIndex;
                } else {
                    // Target column doesn't exist in target row, go to last item in target row
                    const itemsInTargetRow = results.length - targetRow * gridColumns;
                    if (itemsInTargetRow > 0) {
                        selectedIndex = targetRow * gridColumns + itemsInTargetRow - 1;
                    } else {
                        // Target row is empty, wrap to first row
                        selectedIndex = Math.min(currentCol, results.length - 1);
                    }
                }
            } else {
                // Wrap to first row, same column
                selectedIndex = Math.min(currentCol, results.length - 1);
            }
        }
    }

    function selectPreviousColumn() {
        if (results.length > 0 && isGridView) {
            const currentRow = Math.floor(selectedIndex / gridColumns);
            const currentCol = selectedIndex % gridColumns;
            if (currentCol > 0) {
                // Move left in same row
                selectedIndex = currentRow * gridColumns + (currentCol - 1);
            } else {
                // Wrap to last column of previous row
                if (currentRow > 0) {
                    selectedIndex = (currentRow - 1) * gridColumns + (gridColumns - 1);
                } else {
                    // Wrap to last column of last row
                    const totalRows = Math.ceil(results.length / gridColumns);
                    const lastRowIndex = (totalRows - 1) * gridColumns + (gridColumns - 1);
                    selectedIndex = Math.min(lastRowIndex, results.length - 1);
                }
            }
        }
    }

    function selectNextColumn() {
        if (results.length > 0 && isGridView) {
            const currentRow = Math.floor(selectedIndex / gridColumns);
            const currentCol = selectedIndex % gridColumns;
            const itemsInCurrentRow = Math.min(gridColumns, results.length - currentRow * gridColumns);

            if (currentCol < itemsInCurrentRow - 1) {
                // Move right in same row
                selectedIndex = currentRow * gridColumns + (currentCol + 1);
            } else {
                // Wrap to first column of next row
                const totalRows = Math.ceil(results.length / gridColumns);
                if (currentRow < totalRows - 1) {
                    selectedIndex = (currentRow + 1) * gridColumns;
                } else {
                    // Wrap to first item
                    selectedIndex = 0;
                }
            }
        }
    }

    function activate() {
        if (results.length > 0 && results[selectedIndex]) {
            const item = results[selectedIndex];
            const provider = item.provider || currentProvider;

            // Check if auto-paste is enabled and provider/item supports it
            if (Settings.data.appLauncher.autoPasteClipboard && provider && provider.supportsAutoPaste && item.autoPasteText) {
                // Call optional pre-paste callback (e.g., to record usage)
                if (item.onAutoPaste) {
                    item.onAutoPaste();
                }
                root.closeImmediately();
                Qt.callLater(() => {
                    ClipboardService.pasteText(item.autoPasteText);
                });
                return;
            }

            if (item.onActivate) {
                item.onActivate();
            }
        }
    }

    // -----------------------
    // Provider components
    // -----------------------
    ApplicationsProvider {
        id: appsProvider
        Component.onCompleted: {
            registerProvider(this);
            Logger.d("Launcher", "Registered: ApplicationsProvider");
        }
    }

    ClipboardProvider {
        id: clipProvider
        Component.onCompleted: {
            if (Settings.data.appLauncher.enableClipboardHistory) {
                registerProvider(this);
                Logger.d("Launcher", "Registered: ClipboardProvider");
            }
        }
    }

    CommandProvider {
        id: cmdProvider
        Component.onCompleted: {
            registerProvider(this);
            Logger.d("Launcher", "Registered: CommandProvider");
        }
    }

    EmojiProvider {
        id: emojiProvider
        Component.onCompleted: {
            registerProvider(this);
            Logger.d("Launcher", "Registered: EmojiProvider");
        }
    }

    CalculatorProvider {
        id: calcProvider
        Component.onCompleted: {
            registerProvider(this);
            Logger.d("Launcher", "Registered: CalculatorProvider");
        }
    }

    WebSearchProvider {
        id: webSearchProvider
        Component.onCompleted: {
            registerProvider(this);
            Logger.d("Launcher", "Registered: WebSearchProvider");
        }
    }

    // ---------------------------------------------------
    panelContent: Rectangle {
        id: ui
        color: "transparent"
        opacity: resultsReady ? 1.0 : 0.0

        // Preview Panel (external) - uses provider's preview component
        NBox {
            id: previewBox
            visible: root.previewActive
            width: root.previewPanelWidth
            height: Math.round(400 * Style.uiScaleRatio)
            x: ui.width + Style.marginM
            y: {
                if (!resultsViewLoader.item)
                    return Style.marginL;
                const view = resultsViewLoader.item;
                const row = root.isGridView ? Math.floor(root.selectedIndex / root.gridColumns) : root.selectedIndex;
                const itemHeight = root.isGridView ? (root.gridCellSize + Style.marginXXS) : (root.entryHeight + view.spacing);
                const yPos = row * itemHeight - view.contentY;
                const mapped = view.mapToItem(ui, 0, yPos);
                return Math.max(Style.marginL, Math.min(mapped.y, ui.height - previewBox.height - Style.marginL));
            }
            z: -1 // Draw behind main panel content if it ever overlaps

            opacity: visible ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: Style.animationFast
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: Style.animationFast
                    easing.type: Easing.OutCubic
                }
            }

            Loader {
                id: previewLoader
                anchors.fill: parent
                active: root.previewActive
                source: {
                    if (!active)
                        return "";
                    var provider = root.activeProvider;
                    if (provider && provider.previewComponentPath)
                        return provider.previewComponentPath;
                    return "";
                }

                onLoaded: {
                    updatePreviewItem();
                }

                onItemChanged: {
                    updatePreviewItem();
                }

                function updatePreviewItem() {
                    if (!item || selectedIndex < 0 || !results[selectedIndex])
                        return;
                    var provider = root.activeProvider;
                    if (provider && provider.getPreviewData) {
                        item.currentItem = provider.getPreviewData(results[selectedIndex]);
                    } else {
                        item.currentItem = results[selectedIndex];
                    }
                }
            }
        }

        MouseArea {
            id: mouseMovementDetector
            anchors.fill: parent
            z: -999
            hoverEnabled: true
            propagateComposedEvents: true
            acceptedButtons: Qt.NoButton
            enabled: !Settings.data.appLauncher.ignoreMouseInput

            property real lastX: 0
            property real lastY: 0
            property bool initialized: false

            onPositionChanged: mouse => {
                if (!initialized) {
                    lastX = mouse.x;
                    lastY = mouse.y;
                    initialized = true;
                    return;
                }

                const deltaX = Math.abs(mouse.x - lastX);
                const deltaY = Math.abs(mouse.y - lastY);
                if (deltaX > 1 || deltaY > 1) {
                    root.ignoreMouseHover = false;
                    lastX = mouse.x;
                    lastY = mouse.y;
                }
            }

            Connections {
                target: root
                function onOpened() {
                    mouseMovementDetector.initialized = false;
                }
            }
        }

        // Focus management
        Connections {
            target: root
            function onOpened() {
                // Delay focus to ensure window has keyboard focus
                Qt.callLater(() => {
                    if (searchInput.inputItem) {
                        searchInput.inputItem.forceActiveFocus();
                    }
                });
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Style.animationFast
                easing.type: Easing.OutCirc
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL // Apply overall margins here
            spacing: Style.marginM // Apply spacing between elements here

            // Left Pane
            ColumnLayout {
                id: leftPane
                Layout.fillHeight: true
                Layout.preferredWidth: root.listPanelWidth
                spacing: Style.marginM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NTextInput {
                        id: searchInput
                        Layout.fillWidth: true

                        text: searchText
                        placeholderText: I18n.tr("placeholders.search-launcher")
                        fontSize: Style.fontSizeM

                        onTextChanged: searchText = text

                        Component.onCompleted: {
                            if (searchInput.inputItem) {
                                searchInput.inputItem.forceActiveFocus();
                                // Intercept keys before TextField handles them
                                searchInput.inputItem.Keys.onPressed.connect(function (event) {
                                    if (event.key === Qt.Key_Tab) {
                                        root.onTabPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Backtab) {
                                        root.onBackTabPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Left) {
                                        root.onLeftPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Right) {
                                        root.onRightPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up) {
                                        root.onUpPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down) {
                                        root.onDownPressed();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Enter) {
                                        root.activate();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Delete) {
                                        root.onDeletePressed();
                                        event.accepted = true;
                                    }
                                });
                            }
                        }
                    }

                    NIconButton {
                        visible: root.showLayoutToggle
                        icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
                        tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
                        Layout.preferredWidth: searchInput.height
                        Layout.preferredHeight: searchInput.height
                        onClicked: {
                            Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid";
                        }
                    }
                }

                // Unified category tabs (works with any provider that has categories)
                NTabBar {
                    id: categoryTabs
                    visible: root.showProviderCategories
                    Layout.fillWidth: true
                    margins: Style.marginM
                    border.color: Style.boxBorderColor
                    border.width: Style.borderS

                    property int computedCurrentIndex: {
                        if (visible && root.providerCategories.length > 0) {
                            return root.providerCategories.indexOf(root.currentProvider.selectedCategory);
                        }
                        return 0;
                    }
                    currentIndex: computedCurrentIndex

                    Repeater {
                        model: root.providerCategories
                        NIconTabButton {
                            required property string modelData
                            required property int index
                            icon: root.currentProvider.categoryIcons ? (root.currentProvider.categoryIcons[modelData] || "star") : "star"
                            tooltipText: root.currentProvider.getCategoryName ? root.currentProvider.getCategoryName(modelData) : modelData
                            tabIndex: index
                            checked: categoryTabs.currentIndex === index
                            onClicked: {
                                root.currentProvider.selectCategory(modelData);
                            }
                        }
                    }
                }

                Loader {
                    id: resultsViewLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: root.isGridView ? gridViewComponent : listViewComponent
                }

                Component {
                    id: listViewComponent
                    NListView {
                        id: resultsList

                        horizontalPolicy: ScrollBar.AlwaysOff
                        verticalPolicy: ScrollBar.AlwaysOff

                        width: parent.width
                        height: parent.height
                        spacing: Style.marginXS
                        model: results
                        currentIndex: selectedIndex
                        cacheBuffer: resultsList.height * 2
                        interactive: !Settings.data.appLauncher.ignoreMouseInput
                        onCurrentIndexChanged: {
                            cancelFlick();
                            if (currentIndex >= 0) {
                                positionViewAtIndex(currentIndex, ListView.Contain);
                            }
                            if (previewLoader.item) {
                                previewLoader.updatePreviewItem();
                            }
                        }
                        onModelChanged: {}

                        delegate: NBox {
                            id: entry

                            property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)

                            // Prepare item when it becomes visible (e.g., decode images)
                            Component.onCompleted: {
                                var provider = modelData.provider;
                                if (provider && provider.prepareItem) {
                                    provider.prepareItem(modelData);
                                }
                            }

                            width: resultsList.width
                            implicitHeight: entryHeight
                            clip: true
                            color: entry.isSelected ? Color.mHover : Color.mSurface

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.animationFast
                                    easing.type: Easing.OutCirc
                                }
                            }

                            ColumnLayout {
                                id: contentLayout
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginM

                                // Top row - Main entry content with pin button
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.marginM

                                    // Icon badge or Image preview or Emoji
                                    Item {
                                        visible: !modelData.hideIcon
                                        Layout.preferredWidth: modelData.hideIcon ? 0 : badgeSize
                                        Layout.preferredHeight: modelData.hideIcon ? 0 : badgeSize

                                        // Icon background
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Style.radiusM
                                            color: Color.mSurfaceVariant
                                            visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
                                        }

                                        // Image preview - uses provider's getImageUrl if available
                                        NImageRounded {
                                            id: imagePreview
                                            anchors.fill: parent
                                            visible: modelData.isImage && !modelData.displayString
                                            radius: Style.radiusXS
                                            borderColor: Color.mOnSurface
                                            borderWidth: Style.borderM
                                            imageFillMode: Image.PreserveAspectCrop

                                            // Use provider's image revision for reactive updates
                                            readonly property int _rev: modelData.provider && modelData.provider.imageRevision ? modelData.provider.imageRevision : 0

                                            // Get image URL from provider
                                            imagePath: {
                                                _rev;
                                                var provider = modelData.provider;
                                                if (provider && provider.getImageUrl) {
                                                    return provider.getImageUrl(modelData);
                                                }
                                                return "";
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                visible: parent.status === Image.Loading
                                                color: Color.mSurfaceVariant

                                                BusyIndicator {
                                                    anchors.centerIn: parent
                                                    running: true
                                                    width: Style.baseWidgetSize * 0.5
                                                    height: width
                                                }
                                            }

                                            onStatusChanged: status => {
                                                if (status === Image.Error) {
                                                    iconLoader.visible = true;
                                                    imagePreview.visible = false;
                                                }
                                            }
                                        }

                                        Loader {
                                            id: iconLoader
                                            anchors.fill: parent
                                            anchors.margins: Style.marginXS

                                            visible: (!modelData.isImage && !modelData.displayString) || (modelData.isImage && imagePreview.status === Image.Error)
                                            active: visible

                                            sourceComponent: Component {
                                                Loader {
                                                    anchors.fill: parent
                                                    sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? tablerIconComponent : systemIconComponent
                                                }
                                            }

                                            Component {
                                                id: tablerIconComponent
                                                NIcon {
                                                    icon: modelData.icon
                                                    pointSize: Style.fontSizeXXXL
                                                    visible: modelData.icon && !modelData.displayString
                                                }
                                            }

                                            Component {
                                                id: systemIconComponent
                                                IconImage {
                                                    anchors.fill: parent
                                                    source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                                                    visible: modelData.icon && source !== "" && !modelData.displayString
                                                    asynchronous: true
                                                }
                                            }
                                        }

                                        // String display - takes precedence when displayString is present
                                        NText {
                                            id: stringDisplay
                                            anchors.centerIn: parent
                                            visible: modelData.displayString || (!imagePreview.visible && !iconLoader.visible)
                                            text: modelData.displayString ? modelData.displayString : modelData.name.charAt(0).toUpperCase()
                                            pointSize: modelData.displayString ? (modelData.displayStringSize || Style.fontSizeXXXL) : Style.fontSizeXXL
                                            font.weight: Style.fontWeightBold
                                            color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
                                        }

                                        // Image type indicator overlay
                                        Rectangle {
                                            visible: modelData.isImage && imagePreview.visible
                                            anchors.bottom: parent.bottom
                                            anchors.right: parent.right
                                            anchors.margins: 2
                                            width: formatLabel.width + Style.marginXXS * 2
                                            height: formatLabel.height + Style.marginXXS
                                            color: Color.mSurfaceVariant
                                            radius: Style.radiusXXS
                                            NText {
                                                id: formatLabel
                                                anchors.centerIn: parent
                                                text: {
                                                    if (!modelData.isImage)
                                                        return "";
                                                    const desc = modelData.description || "";
                                                    const parts = desc.split(" • ");
                                                    return parts[0] || "IMG";
                                                }
                                                pointSize: Style.fontSizeXXS
                                                color: Color.mOnSurfaceVariant
                                            }
                                        }
                                    }

                                    // Text content
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        NText {
                                            text: modelData.name || "Unknown"
                                            pointSize: Style.fontSizeL
                                            font.weight: Style.fontWeightBold
                                            color: entry.isSelected ? Color.mOnHover : Color.mOnSurface
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            wrapMode: Text.Wrap
                                            clip: true
                                            Layout.fillWidth: true
                                        }

                                        NText {
                                            text: modelData.description || ""
                                            pointSize: Style.fontSizeS
                                            color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                        }
                                    }

                                    // Action buttons row - dynamically populated from provider
                                    RowLayout {
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        spacing: Style.marginXS
                                        visible: entry.isSelected && itemActions.length > 0

                                        property var itemActions: {
                                            if (!entry.isSelected)
                                                return [];
                                            var provider = modelData.provider || root.currentProvider;
                                            if (provider && provider.getItemActions) {
                                                return provider.getItemActions(modelData);
                                            }
                                            return [];
                                        }

                                        Repeater {
                                            model: parent.itemActions
                                            NIconButton {
                                                icon: modelData.icon
                                                tooltipText: modelData.tooltip
                                                z: 1
                                                onClicked: {
                                                    if (modelData.action) {
                                                        modelData.action();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                z: -1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !Settings.data.appLauncher.ignoreMouseInput
                                onEntered: {
                                    if (!root.ignoreMouseHover) {
                                        selectedIndex = index;
                                    }
                                }
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        selectedIndex = index;
                                        root.activate();
                                        mouse.accepted = true;
                                    }
                                }
                                acceptedButtons: Qt.LeftButton
                            }
                        }
                    }
                }

                Component {
                    id: gridViewComponent
                    NGridView {
                        id: resultsGrid

                        horizontalPolicy: ScrollBar.AlwaysOff
                        verticalPolicy: ScrollBar.AlwaysOff

                        width: parent.width
                        height: parent.height
                        cellWidth: parent.width / root.targetGridColumns
                        cellHeight: {
                            var cellWidth = parent.width / root.targetGridColumns;
                            // Use provider's preferred ratio if available
                            if (root.currentProvider && root.currentProvider.preferredGridCellRatio) {
                                return cellWidth * root.currentProvider.preferredGridCellRatio;
                            }
                            return cellWidth;
                        }
                        leftMargin: 0
                        rightMargin: 0
                        topMargin: 0
                        bottomMargin: 0
                        model: results
                        cacheBuffer: resultsGrid.height * 2
                        keyNavigationEnabled: false
                        focus: false
                        interactive: !Settings.data.appLauncher.ignoreMouseInput

                        Component.onCompleted: {
                            // Initialize gridColumns when grid view is created
                            updateGridColumns();
                        }

                        function updateGridColumns() {
                            // Since cellWidth = width / targetGridColumns, the number of columns is always targetGridColumns
                            root.gridColumns = root.targetGridColumns;
                        }

                        onWidthChanged: {
                            updateGridColumns();
                        }

                        // Completely disable GridView key handling
                        Keys.enabled: false

                        // Don't sync selectedIndex to GridView's currentIndex
                        // The visual selection is handled by the delegate based on selectedIndex
                        // We only need to position the view to show the selected item
                        onModelChanged: {}

                        // Handle scrolling to show selected item when it changes
                        Connections {
                            target: root
                            enabled: root.isGridView
                            function onSelectedIndexChanged() {
                                // Only process if we're still in grid view and component exists
                                if (!root.isGridView || root.selectedIndex < 0 || !resultsGrid) {
                                    return;
                                }

                                Qt.callLater(() => {
                                    // Double-check we're still in grid view mode
                                    if (root.isGridView && resultsGrid && resultsGrid.cancelFlick) {
                                        resultsGrid.cancelFlick();
                                        resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                                    }
                                });

                                // Update preview
                                if (previewLoader.item && root.selectedIndex >= 0) {
                                    previewLoader.updatePreviewItem();
                                }
                            }
                        }

                        delegate: Item {
                            id: gridEntryContainer
                            width: resultsGrid.cellWidth
                            height: resultsGrid.cellHeight

                            property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)

                            // Prepare item when it becomes visible (e.g., decode images)
                            Component.onCompleted: {
                                var provider = modelData.provider;
                                if (provider && provider.prepareItem) {
                                    provider.prepareItem(modelData);
                                }
                            }

                            NBox {
                                id: gridEntry
                                anchors.fill: parent
                                anchors.margins: Style.marginXXS
                                color: gridEntryContainer.isSelected ? Color.mHover : Color.mSurface

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.animationFast
                                        easing.type: Easing.OutCirc
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Style.marginS
                                    anchors.bottomMargin: Style.marginS
                                    spacing: Style.marginXXS

                                    // Icon badge or Image preview or Emoji
                                    Item {
                                        // Use consistent 65% sizing for all items
                                        Layout.preferredWidth: Math.round(gridEntry.width * 0.65)
                                        Layout.preferredHeight: Math.round(gridEntry.width * 0.65)
                                        Layout.alignment: Qt.AlignHCenter

                                        // Icon background
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Style.radiusM
                                            color: Color.mSurfaceVariant
                                            visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
                                        }

                                        // Image preview - uses provider's getImageUrl if available
                                        NImageRounded {
                                            id: gridImagePreview
                                            anchors.fill: parent
                                            visible: modelData.isImage && !modelData.displayString
                                            radius: Style.radiusM

                                            // Use provider's image revision for reactive updates
                                            readonly property int _rev: modelData.provider && modelData.provider.imageRevision ? modelData.provider.imageRevision : 0

                                            // Get image URL from provider
                                            imagePath: {
                                                _rev;
                                                var provider = modelData.provider;
                                                if (provider && provider.getImageUrl) {
                                                    return provider.getImageUrl(modelData);
                                                }
                                                return "";
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                visible: parent.status === Image.Loading
                                                color: Color.mSurfaceVariant

                                                BusyIndicator {
                                                    anchors.centerIn: parent
                                                    running: true
                                                    width: Style.baseWidgetSize * 0.5
                                                    height: width
                                                }
                                            }

                                            onStatusChanged: status => {
                                                if (status === Image.Error) {
                                                    gridIconLoader.visible = true;
                                                    gridImagePreview.visible = false;
                                                }
                                            }
                                        }

                                        Loader {
                                            id: gridIconLoader
                                            anchors.fill: parent
                                            anchors.margins: Style.marginXS

                                            visible: (!modelData.isImage && !modelData.displayString) || (modelData.isImage && gridImagePreview.status === Image.Error)
                                            active: visible

                                            sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? gridTablerIconComponent : gridSystemIconComponent

                                            Component {
                                                id: gridTablerIconComponent
                                                NIcon {
                                                    icon: modelData.icon
                                                    pointSize: Style.fontSizeXXXL
                                                    visible: modelData.icon && !modelData.displayString
                                                }
                                            }

                                            Component {
                                                id: gridSystemIconComponent
                                                IconImage {
                                                    anchors.fill: parent
                                                    source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                                                    visible: modelData.icon && source !== "" && !modelData.displayString
                                                    asynchronous: true
                                                }
                                            }
                                        }

                                        // String display
                                        NText {
                                            id: gridStringDisplay
                                            anchors.centerIn: parent
                                            visible: modelData.displayString || (!gridImagePreview.visible && !gridIconLoader.visible)
                                            text: modelData.displayString ? modelData.displayString : modelData.name.charAt(0).toUpperCase()
                                            pointSize: {
                                                if (modelData.displayString) {
                                                    // Use custom size if provided, otherwise default scaling
                                                    if (modelData.displayStringSize) {
                                                        return modelData.displayStringSize * Style.uiScaleRatio;
                                                    }
                                                    if (root.providerHasDisplayString) {
                                                        // Scale with cell width but cap at reasonable maximum
                                                        const cellBasedSize = gridEntry.width * 0.4;
                                                        const maxSize = Style.fontSizeXXXL * Style.uiScaleRatio;
                                                        return Math.min(cellBasedSize, maxSize);
                                                    }
                                                    return Style.fontSizeXXL * 2 * Style.uiScaleRatio;
                                                }
                                                // Scale font size relative to cell width for low res, but cap at maximum
                                                const cellBasedSize = gridEntry.width * 0.25;
                                                const baseSize = Style.fontSizeXL * Style.uiScaleRatio;
                                                const maxSize = Style.fontSizeXXL * Style.uiScaleRatio;
                                                return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
                                            }
                                            font.weight: Style.fontWeightBold
                                            color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
                                        }
                                    }

                                    // Text content (hidden when hideLabel is true)
                                    NText {
                                        visible: !modelData.hideLabel
                                        text: modelData.name || "Unknown"
                                        pointSize: {
                                            if (root.providerHasDisplayString && modelData.displayString) {
                                                return Style.fontSizeS * Style.uiScaleRatio;
                                            }
                                            // Scale font size relative to cell width for low res, but cap at maximum
                                            const cellBasedSize = gridEntry.width * 0.12;
                                            const baseSize = Style.fontSizeS * Style.uiScaleRatio;
                                            const maxSize = Style.fontSizeM * Style.uiScaleRatio;
                                            return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
                                        }
                                        font.weight: Style.fontWeightSemiBold
                                        color: gridEntryContainer.isSelected ? Color.mOnHover : Color.mOnSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: gridEntry.width - 8
                                        Layout.leftMargin: (root.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
                                        Layout.rightMargin: (root.providerHasDisplayString && modelData.displayString) ? Style.marginS : 0
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.NoWrap
                                        maximumLineCount: 1
                                    }
                                }

                                // Action buttons (overlay in top-right corner) - dynamically populated from provider
                                Row {
                                    visible: gridEntryContainer.isSelected && gridItemActions.length > 0
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Style.marginXS
                                    z: 10
                                    spacing: Style.marginXXS

                                    property var gridItemActions: {
                                        if (!gridEntryContainer.isSelected)
                                            return [];
                                        var provider = modelData.provider || root.currentProvider;
                                        if (provider && provider.getItemActions) {
                                            return provider.getItemActions(modelData);
                                        }
                                        return [];
                                    }

                                    Repeater {
                                        model: parent.gridItemActions
                                        NIconButton {
                                            icon: modelData.icon
                                            tooltipText: modelData.tooltip
                                            z: 11
                                            onClicked: {
                                                if (modelData.action) {
                                                    modelData.action();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                z: -1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !Settings.data.appLauncher.ignoreMouseInput
                                onEntered: {
                                    root.ignoreMouseHover = false;
                                    selectedIndex = index;
                                }
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        selectedIndex = index;
                                        root.activate();
                                        mouse.accepted = true;
                                    }
                                }
                                acceptedButtons: Qt.LeftButton
                            }
                        }
                    }
                }

                NDivider {
                    Layout.fillWidth: true
                }

                NText {
                    Layout.fillWidth: true
                    text: {
                        if (results.length === 0) {
                            if (searchText) {
                                return I18n.tr("launcher.no-results");
                            }
                            // Use provider's empty browsing message if available
                            var provider = root.currentProvider;
                            if (provider && provider.emptyBrowsingMessage) {
                                return provider.emptyBrowsingMessage;
                            }
                            return "";
                        }
                        var prefix = activeProvider && activeProvider.name ? activeProvider.name + ": " : "";
                        return prefix + results.length + " result" + (results.length !== 1 ? 's' : '');
                    }
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    horizontalAlignment: Text.AlignCenter
                }
            }
        }
    }
}
