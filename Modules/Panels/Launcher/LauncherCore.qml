import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import "Providers"
import qs.Commons
import qs.Services.Keyboard
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

// Core launcher logic and UI - shared between SmartPanel (Launcher.qml) and overlay (LauncherOverlayWindow.qml)
Rectangle {
  id: root
  color: "transparent"

  // External interface - set by parent
  property var screen: null
  property bool isOpen: false
  signal requestClose
  signal requestCloseImmediately

  function closeImmediately() {
    requestCloseImmediately();
  }

  // Expose for preview panel positioning
  readonly property var resultsView: resultsViewLoader.item

  // State
  property string searchText: ""
  property int selectedIndex: 0
  property var results: []
  property var providers: []
  property var activeProvider: null
  property bool resultsReady: false
  property var pluginProviderInstances: ({})
  property bool ignoreMouseHover: true // Transient flag, should always be true on init

  // Global mouse tracking for movement detection across delegates
  property real globalLastMouseX: 0
  property real globalLastMouseY: 0
  property bool globalMouseInitialized: false
  property bool mouseTrackingReady: false // Delay tracking until panel is settled

  Timer {
    id: mouseTrackingDelayTimer
    interval: Style.animationNormal + 50 // Wait for panel animation to complete + safety margin
    repeat: false
    onTriggered: {
      root.mouseTrackingReady = true;
      root.globalMouseInitialized = false; // Reset so we get fresh initial position
    }
  }

  readonly property var defaultProvider: appsProvider
  readonly property var currentProvider: activeProvider || defaultProvider

  readonly property string launcherDensity: (currentProvider && currentProvider.ignoreDensity === false) ? (Settings.data.appLauncher.density || "default") : "comfortable"
  readonly property int effectiveIconSize: launcherDensity === "comfortable" ? 48 : (launcherDensity === "default" ? 36 : 24)
  readonly property int badgeSize: Math.round(effectiveIconSize * Style.uiScaleRatio)
  readonly property int entryHeight: Math.round(badgeSize + (launcherDensity === "compact" ? (Style.marginL + Style.marginXXS) : (Style.marginXL + Style.marginS)))

  readonly property bool providerShowsCategories: currentProvider.showsCategories === true

  readonly property var providerCategories: {
    if (currentProvider.availableCategories && currentProvider.availableCategories.length > 0) {
      return currentProvider.availableCategories;
    }
    return currentProvider.categories || [];
  }

  readonly property bool showProviderCategories: {
    if (!providerShowsCategories || providerCategories.length === 0)
      return false;
    if (currentProvider === defaultProvider)
      return Settings.data.appLauncher.showCategories;
    return true;
  }

  readonly property bool providerHasDisplayString: results.length > 0 && !!results[0].displayString

  readonly property string providerSupportedLayouts: {
    if (activeProvider && activeProvider.supportedLayouts)
      return activeProvider.supportedLayouts;
    if (results.length > 0 && results[0].provider && results[0].provider.supportedLayouts)
      return results[0].provider.supportedLayouts;
    if (defaultProvider && defaultProvider.supportedLayouts)
      return defaultProvider.supportedLayouts;
    return "both";
  }

  readonly property bool showLayoutToggle: !providerHasDisplayString && providerSupportedLayouts === "both"

  readonly property string layoutMode: {
    if (searchText === ">")
      return "list";
    if (providerSupportedLayouts === "grid")
      return "grid";
    if (providerSupportedLayouts === "list")
      return "list";
    if (providerSupportedLayouts === "single")
      return "single";
    if (providerHasDisplayString)
      return "grid";
    return Settings.data.appLauncher.viewMode;
  }

  readonly property bool isGridView: layoutMode === "grid"
  readonly property bool isSingleView: layoutMode === "single"
  readonly property bool isCompactDensity: launcherDensity === "compact"

  readonly property int targetGridColumns: {
    let base = 5;
    if (launcherDensity === "comfortable")
      base = 4;
    else if (launcherDensity === "compact")
      base = 6;

    if (!activeProvider || activeProvider === defaultProvider)
      return base;

    if (activeProvider.preferredGridColumns) {
      let multiplier = base / 5.0;
      return Math.max(1, Math.round(activeProvider.preferredGridColumns * multiplier));
    }

    return base;
  }
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int gridContentWidth: listPanelWidth - (2 * Style.marginXS)
  readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

  property int gridColumns: 5

  // Check if current provider allows wrap navigation (default true)
  readonly property bool allowWrapNavigation: {
    var provider = activeProvider || currentProvider;
    return provider && provider.wrapNavigation !== undefined ? provider.wrapNavigation : true;
  }

  // Listen for plugin provider registry changes
  Connections {
    target: LauncherProviderRegistry
    function onPluginProviderRegistryUpdated() {
      root.syncPluginProviders();
    }
  }

  // Lifecycle
  onIsOpenChanged: {
    if (isOpen) {
      onOpened();
    } else {
      onClosed();
    }
  }

  function onOpened() {
    resultsReady = false;
    ignoreMouseHover = true;
    globalMouseInitialized = false;
    mouseTrackingReady = false;
    mouseTrackingDelayTimer.restart();
    syncPluginProviders();
    Qt.callLater(() => {
                   for (let provider of providers) {
                     if (provider.onOpened)
                     provider.onOpened();
                   }
                   updateResults();
                   resultsReady = true;
                   focusSearchInput();
                 });
  }

  function onClosed() {
    searchText = "";
    ignoreMouseHover = true;
    for (let provider of providers) {
      if (provider.onClosed)
        provider.onClosed();
    }
  }

  onSearchTextChanged: {
    if (isOpen)
      updateResults();
  }

  function close() {
    requestClose();
  }

  // Public API
  function setSearchText(text) {
    searchText = text;
  }

  function focusSearchInput() {
    if (searchInput.inputItem) {
      searchInput.inputItem.forceActiveFocus();
    }
  }

  // Provider registration
  function registerProvider(provider) {
    providers.push(provider);
    provider.launcher = root;
    if (provider.init)
      provider.init();
  }

  function syncPluginProviders() {
    var registeredIds = LauncherProviderRegistry.getPluginProviders();

    // Remove providers that are no longer registered
    for (var existingId in pluginProviderInstances) {
      if (registeredIds.indexOf(existingId) === -1) {
        var idx = providers.indexOf(pluginProviderInstances[existingId]);
        if (idx >= 0)
          providers.splice(idx, 1);
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
        var pluginId = providerId.substring(7); // Remove "plugin:" prefix
        var pluginApi = PluginService.getPluginAPI(pluginId);
        if (component && pluginApi) {
          var instance = component.createObject(root, {
                                                  pluginApi: pluginApi
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
    if (root.isOpen) {
      updateResults();
    }
  }

  // Search handling
  function updateResults() {
    results = [];
    var newActiveProvider = null;

    // Check for command mode
    if (searchText.startsWith(">")) {
      for (let provider of providers) {
        if (provider.handleCommand && provider.handleCommand(searchText)) {
          newActiveProvider = provider;
          results = provider.getResults(searchText);
          break;
        }
      }

      // Show available commands if just ">" or filter commands if partial match
      if (!newActiveProvider) {
        let allCommands = [];
        for (let provider of providers) {
          if (provider.commands)
            allCommands = allCommands.concat(provider.commands());
        }
        if (searchText === ">") {
          results = allCommands;
        } else if (searchText.length > 1) {
          const query = searchText.substring(1);
          if (typeof FuzzySort !== 'undefined') {
            const fuzzyResults = FuzzySort.go(query, allCommands, {
                                                "keys": ["name"],
                                                "limit": 50
                                              });
            results = fuzzyResults.map(result => result.obj);
          } else {
            const queryLower = query.toLowerCase();
            results = allCommands.filter(cmd => (cmd.name || "").toLowerCase().includes(queryLower));
          }
        }
      }
    } else {
      // Regular search - let providers contribute results
      let allResults = [];
      for (let provider of providers) {
        if (provider.handleSearch) {
          const providerResults = provider.getResults(searchText);
          allResults = allResults.concat(providerResults);
        }
      }

      // Sort by _score (higher = better match), items without _score go first
      if (searchText.trim() !== "") {
        allResults.sort((a, b) => {
                          const sa = a._score !== undefined ? a._score : 0;
                          const sb = b._score !== undefined ? b._score : 0;
                          return sb - sa;
                        });
      }
      results = allResults;
    }

    // Update activeProvider only after computing new state to avoid UI flicker
    activeProvider = newActiveProvider;
    selectedIndex = 0;
  }

  // Navigation functions
  function selectNext() {
    if (results.length > 0 && selectedIndex < results.length - 1) {
      selectedIndex++;
    }
  }

  function selectPrevious() {
    if (results.length > 0 && selectedIndex > 0) {
      selectedIndex--;
    }
  }

  function selectNextWrapped() {
    if (results.length > 0) {
      if (allowWrapNavigation) {
        selectedIndex = (selectedIndex + 1) % results.length;
      } else {
        selectNext();
      }
    }
  }

  function selectPreviousWrapped() {
    if (results.length > 0) {
      if (allowWrapNavigation) {
        selectedIndex = (((selectedIndex - 1) % results.length) + results.length) % results.length;
      } else {
        selectPrevious();
      }
    }
  }

  function selectFirst() {
    selectedIndex = 0;
  }

  function selectLast() {
    selectedIndex = results.length > 0 ? results.length - 1 : 0;
  }

  function selectNextPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight));
      selectedIndex = Math.min(selectedIndex + page, results.length - 1);
    }
  }

  function selectPreviousPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight));
      selectedIndex = Math.max(selectedIndex - page, 0);
    }
  }

  // Grid view navigation functions
  function selectPreviousRow() {
    if (results.length > 0 && isGridView && gridColumns > 0) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;

      if (currentRow > 0) {
        const targetRow = currentRow - 1;
        const targetIndex = targetRow * gridColumns + currentCol;
        const itemsInTargetRow = Math.min(gridColumns, results.length - targetRow * gridColumns);
        if (currentCol < itemsInTargetRow) {
          selectedIndex = targetIndex;
        } else {
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
        const targetRow = currentRow + 1;
        const targetIndex = targetRow * gridColumns + currentCol;
        if (targetIndex < results.length) {
          selectedIndex = targetIndex;
        } else {
          const itemsInTargetRow = results.length - targetRow * gridColumns;
          if (itemsInTargetRow > 0) {
            selectedIndex = targetRow * gridColumns + itemsInTargetRow - 1;
          } else {
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
        selectedIndex = currentRow * gridColumns + (currentCol - 1);
      } else if (currentRow > 0) {
        selectedIndex = (currentRow - 1) * gridColumns + (gridColumns - 1);
      } else {
        const totalRows = Math.ceil(results.length / gridColumns);
        const lastRowIndex = (totalRows - 1) * gridColumns + (gridColumns - 1);
        selectedIndex = Math.min(lastRowIndex, results.length - 1);
      }
    }
  }

  function selectNextColumn() {
    if (results.length > 0 && isGridView) {
      const currentRow = Math.floor(selectedIndex / gridColumns);
      const currentCol = selectedIndex % gridColumns;
      const itemsInCurrentRow = Math.min(gridColumns, results.length - currentRow * gridColumns);

      if (currentCol < itemsInCurrentRow - 1) {
        selectedIndex = currentRow * gridColumns + (currentCol + 1);
      } else {
        const totalRows = Math.ceil(results.length / gridColumns);
        if (currentRow < totalRows - 1) {
          selectedIndex = (currentRow + 1) * gridColumns;
        } else {
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
        if (item.onAutoPaste)
          item.onAutoPaste();
        closeImmediately();
        Qt.callLater(() => {
                       ClipboardService.pasteText(item.autoPasteText);
                     });
        return;
      }

      if (item.onActivate)
        item.onActivate();
    }
  }

  function checkKey(event, settingName) {
    return Keybinds.checkKey(event, settingName, Settings);
  }

  // Keyboard handler
  function handleKeyPress(event) {
    if (checkKey(event, 'escape')) {
      close();
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'enter')) {
      activate();
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'up')) {
      if (!isSingleView) {
        isGridView ? selectPreviousRow() : selectPreviousWrapped();
      }
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'down')) {
      if (!isSingleView) {
        isGridView ? selectNextRow() : selectNextWrapped();
      }
      event.accepted = true;
      return;
    }

    if (checkKey(event, 'left')) {
      if (isGridView) {
        selectPreviousColumn();
        event.accepted = true;
        return;
      }
    }

    if (checkKey(event, 'right')) {
      if (isGridView) {
        selectNextColumn();
        event.accepted = true;
        return;
      }
    }

    // Static bindings
    switch (event.key) {
    case Qt.Key_Tab:
      if (showProviderCategories) {
        var cats = providerCategories;
        var idx = cats.indexOf(currentProvider.selectedCategory);
        currentProvider.selectCategory(cats[(idx + 1) % cats.length]);
      } else {
        selectNextWrapped();
      }
      event.accepted = true;
      break;
    case Qt.Key_Backtab:
      if (showProviderCategories) {
        var cats2 = providerCategories;
        var idx2 = cats2.indexOf(currentProvider.selectedCategory);
        currentProvider.selectCategory(cats2[((idx2 - 1) % cats2.length + cats2.length) % cats2.length]);
      } else {
        selectPreviousWrapped();
      }
      event.accepted = true;
      break;
    case Qt.Key_Home:
      selectFirst();
      event.accepted = true;
      break;
    case Qt.Key_End:
      selectLast();
      event.accepted = true;
      break;
    case Qt.Key_PageUp:
      selectPreviousPage();
      event.accepted = true;
      break;
    case Qt.Key_PageDown:
      selectNextPage();
      event.accepted = true;
      break;
    case Qt.Key_Delete:
      if (selectedIndex >= 0 && results && results[selectedIndex]) {
        var item = results[selectedIndex];
        var provider = item.provider || currentProvider;
        if (provider && provider.canDeleteItem && provider.canDeleteItem(item))
          provider.deleteItem(item);
      }
      event.accepted = true;
      break;
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

  SettingsProvider {
    id: settingsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SettingsProvider");
    }
  }

  SessionProvider {
    id: sessionProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: SessionProvider");
    }
  }

  WindowsProvider {
    id: windowsProvider
    Component.onCompleted: {
      registerProvider(this);
      Logger.d("Launcher", "Registered: WindowsProvider");
    }
  }

  // ==================== UI Content ====================

  opacity: resultsReady ? 1.0 : 0.0

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCirc
    }
  }

  HoverHandler {
    id: globalHoverHandler
    enabled: !Settings.data.appLauncher.ignoreMouseInput

    onPointChanged: {
      if (!root.mouseTrackingReady) {
        return;
      }

      if (!root.globalMouseInitialized) {
        root.globalLastMouseX = point.position.x;
        root.globalLastMouseY = point.position.y;
        root.globalMouseInitialized = true;
        return;
      }

      const deltaX = Math.abs(point.position.x - root.globalLastMouseX);
      const deltaY = Math.abs(point.position.y - root.globalLastMouseY);
      if (deltaX + deltaY >= 5) {
        root.ignoreMouseHover = false;
        root.globalLastMouseX = point.position.x;
        root.globalLastMouseY = point.position.y;
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: Style.marginL
    anchors.bottomMargin: Style.marginL
    spacing: Style.marginL

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      spacing: Style.marginS

      NTextInput {
        id: searchInput
        Layout.fillWidth: true
        radius: Style.iRadiusM
        text: root.searchText
        placeholderText: I18n.tr("placeholders.search-launcher")
        fontSize: Style.fontSizeM
        onTextChanged: root.searchText = text

        Component.onCompleted: {
          if (searchInput.inputItem) {
            searchInput.inputItem.forceActiveFocus();
            searchInput.inputItem.Keys.onPressed.connect(function (event) {
              root.handleKeyPress(event);
            });
          }
        }
      }

      NIconButton {
        visible: root.showLayoutToggle
        icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
        tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
        customRadius: Style.iRadiusM
        Layout.preferredWidth: searchInput.height
        Layout.preferredHeight: searchInput.height
        onClicked: Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid"
      }
    }

    // Unified category tabs (works with any provider that has categories)
    NTabBar {
      id: categoryTabs
      visible: root.showProviderCategories
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      margins: 0
      border.color: Style.boxBorderColor
      border.width: Style.borderS

      property int computedCurrentIndex: visible && root.providerCategories.length > 0 ? root.providerCategories.indexOf(root.currentProvider.selectedCategory) : 0
      currentIndex: computedCurrentIndex

      Repeater {
        model: root.providerCategories
        NTabButton {
          required property string modelData
          required property int index
          icon: root.currentProvider.categoryIcons ? (root.currentProvider.categoryIcons[modelData] || "star") : "star"
          tooltipText: root.currentProvider.getCategoryName ? root.currentProvider.getCategoryName(modelData) : modelData
          tabIndex: index
          checked: categoryTabs.currentIndex === index
          onClicked: root.currentProvider.selectCategory(modelData)
        }
      }
    }

    // Results view
    Loader {
      id: resultsViewLoader
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL
      Layout.fillHeight: true
      sourceComponent: root.isSingleView ? singleViewComponent : (root.isGridView ? gridViewComponent : listViewComponent)
    }

    // --------------------------
    // LIST VIEW
    Component {
      id: listViewComponent
      NListView {
        id: resultsList

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Color.mSurfaceVariant
        wheelScrollMultiplier: 4.0

        width: parent.width
        height: parent.height
        spacing: Style.marginS
        model: root.results
        currentIndex: root.selectedIndex
        cacheBuffer: resultsList.height * 2
        interactive: !Settings.data.appLauncher.ignoreMouseInput
        onCurrentIndexChanged: {
          cancelFlick();
          if (currentIndex >= 0) {
            positionViewAtIndex(currentIndex, ListView.Contain);
          }
        }
        onModelChanged: {}

        delegate: NBox {
          id: entry

          property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === root.selectedIndex)

          // Prepare item when it becomes visible (e.g., decode images)
          Component.onCompleted: {
            var provider = modelData.provider;
            if (provider && provider.prepareItem) {
              provider.prepareItem(modelData);
            }
          }

          width: resultsList.availableWidth
          implicitHeight: root.entryHeight
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
            anchors.margins: root.isCompactDensity ? Style.marginXS : Style.marginM
            spacing: root.isCompactDensity ? Style.marginXS : Style.marginM

            // Top row - Main entry content with action buttons
            RowLayout {
              Layout.fillWidth: true
              spacing: root.isCompactDensity ? Style.marginS : Style.marginM

              // Icon badge or Image preview or Emoji
              Item {
                visible: !modelData.hideIcon
                Layout.preferredWidth: modelData.hideIcon ? 0 : root.badgeSize
                Layout.preferredHeight: modelData.hideIcon ? 0 : root.badgeSize

                // Icon background
                Rectangle {
                  anchors.fill: parent
                  radius: Style.radiusXS
                  color: Color.mSurfaceVariant
                  visible: Settings.data.appLauncher.showIconBackground && !modelData.isImage
                }

                // Image preview - uses provider's getImageUrl if available
                NImageRounded {
                  id: imagePreview
                  anchors.fill: parent
                  visible: !!modelData.isImage && !modelData.displayString
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

                  visible: (!modelData.isImage && !modelData.displayString) || (!!modelData.isImage && imagePreview.status === Image.Error)
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
                      color: (entry.isSelected && !Settings.data.appLauncher.showIconBackground) ? Color.mOnHover : Color.mOnSurface
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
                  visible: !!modelData.displayString || (!imagePreview.visible && !iconLoader.visible)
                  text: modelData.displayString ? modelData.displayString : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
                  pointSize: modelData.displayString ? (modelData.displayStringSize || Style.fontSizeXXXL) : Style.fontSizeXXL
                  font.weight: Style.fontWeightBold
                  color: modelData.displayString ? Color.mOnSurface : Color.mOnPrimary
                }

                // Image type indicator overlay
                Rectangle {
                  visible: !!modelData.isImage && imagePreview.visible
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: 2
                  width: formatLabel.width + Style.marginXS
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
                      const parts = desc.split(" \u2022 ");
                      return parts[0] || "IMG";
                    }
                    pointSize: Style.fontSizeXXS
                    color: Color.mOnSurfaceVariant
                  }
                }

                // Badge icon overlay (generic indicator for any provider)
                Rectangle {
                  visible: !!modelData.badgeIcon
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: 2
                  width: height
                  height: Style.fontSizeM + Style.marginXS
                  color: Color.mSurfaceVariant
                  radius: Style.radiusXXS
                  NIcon {
                    anchors.centerIn: parent
                    icon: modelData.badgeIcon || ""
                    pointSize: Style.fontSizeS
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
                  visible: text !== "" && !root.isCompactDensity
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
                    baseSize: Style.baseWidgetSize * 0.75
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
                root.selectedIndex = index;
              }
            }
            onClicked: mouse => {
                         if (mouse.button === Qt.LeftButton) {
                           root.selectedIndex = index;
                           root.activate();
                           mouse.accepted = true;
                         }
                       }
            acceptedButtons: Qt.LeftButton
          }
        }
      }
    }

    // --------------------------
    // SINGLE ITEM VIEW
    Component {
      id: singleViewComponent

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        NBox {
          anchors.fill: parent
          color: Color.mSurfaceVariant
          Layout.fillWidth: true
          Layout.fillHeight: true

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              NText {
                text: root.results.length > 0 ? root.results[0].name : ""
                pointSize: Style.fontSizeL
                font.weight: Font.Bold
                color: Color.mPrimary
              }
            }

            NScrollView {
              id: descriptionScrollView
              Layout.alignment: Qt.AlignTop | Qt.AlignLeft
              Layout.topMargin: Style.fontSizeL + Style.marginXL
              Layout.fillWidth: true
              Layout.fillHeight: true
              horizontalPolicy: ScrollBar.AlwaysOff
              reserveScrollbarSpace: false

              NText {
                width: descriptionScrollView.availableWidth
                text: root.results.length > 0 ? root.results[0].description : ""
                pointSize: Style.fontSizeM
                font.weight: Font.Bold
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHLeft
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                markdownTextEnabled: true
              }
            }
          }
        }
      }
    }

    // --------------------------
    // GRID VIEW
    Component {
      id: gridViewComponent
      NGridView {
        id: resultsGrid

        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AlwaysOff
        reserveScrollbarSpace: false
        gradientColor: Color.mSurfaceVariant
        wheelScrollMultiplier: 4.0
        trackedSelectionIndex: root.selectedIndex

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
        model: root.results
        cacheBuffer: resultsGrid.height * 2
        keyNavigationEnabled: false
        focus: false
        interactive: !Settings.data.appLauncher.ignoreMouseInput

        // Completely disable GridView key handling
        Keys.enabled: false

        Component.onCompleted: root.gridColumns = root.targetGridColumns
        onWidthChanged: root.gridColumns = root.targetGridColumns
        onModelChanged: {}

        // Handle scrolling to show selected item when it changes
        Connections {
          target: root
          enabled: root.isGridView
          function onSelectedIndexChanged() {
            if (!root.isGridView || root.selectedIndex < 0 || !resultsGrid) {
              return;
            }

            Qt.callLater(() => {
                           if (root.isGridView && resultsGrid && resultsGrid.cancelFlick) {
                             resultsGrid.cancelFlick();
                             resultsGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                           }
                         });
          }
        }

        delegate: Item {
          id: gridEntryContainer
          width: resultsGrid.cellWidth
          height: resultsGrid.cellHeight

          property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === root.selectedIndex)

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
              anchors.margins: root.isCompactDensity ? Style.marginXS : Style.marginS
              anchors.bottomMargin: root.isCompactDensity ? Style.marginXS : Style.marginS
              spacing: root.isCompactDensity ? 0 : Style.marginXXS

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
                  visible: !!modelData.isImage && !modelData.displayString
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

                  visible: (!modelData.isImage && !modelData.displayString) || (!!modelData.isImage && gridImagePreview.status === Image.Error)
                  active: visible

                  sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? gridTablerIconComponent : gridSystemIconComponent

                  Component {
                    id: gridTablerIconComponent
                    NIcon {
                      icon: modelData.icon
                      pointSize: Style.fontSizeXXXL
                      visible: modelData.icon && !modelData.displayString
                      color: (gridEntryContainer.isSelected && !Settings.data.appLauncher.showIconBackground) ? Color.mOnHover : Color.mOnSurface
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
                  visible: !!modelData.displayString || (!gridImagePreview.visible && !gridIconLoader.visible)
                  text: modelData.displayString ? modelData.displayString : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
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

                // Badge icon overlay (generic indicator for any provider)
                Rectangle {
                  visible: !!modelData.badgeIcon
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: 2
                  width: height
                  height: Style.fontSizeM + Style.marginXS
                  color: Color.mSurfaceVariant
                  radius: Style.radiusXXS
                  NIcon {
                    anchors.centerIn: parent
                    icon: modelData.badgeIcon || ""
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                  }
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
                  baseSize: Style.baseWidgetSize * 0.75
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
              if (!root.ignoreMouseHover) {
                root.selectedIndex = index;
              }
            }
            onClicked: mouse => {
                         if (mouse.button === Qt.LeftButton) {
                           root.selectedIndex = index;
                           root.activate();
                           mouse.accepted = true;
                         }
                       }
            acceptedButtons: Qt.LeftButton
          }
        }
      }
    }

    ColumnLayout {
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginL

      NDivider {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
      }

      NText {
        Layout.fillWidth: true
        text: {
          if (root.results.length === 0) {
            if (root.searchText) {
              return I18n.tr("common.no-results");
            }
            // Use provider's empty browsing message if available
            var provider = root.currentProvider;
            if (provider && provider.emptyBrowsingMessage) {
              return provider.emptyBrowsingMessage;
            }
            return "";
          }
          var prefix = root.activeProvider && root.activeProvider.name ? root.activeProvider.name + ": " : "";
          return prefix + I18n.trp("common.result-count", root.results.length);
        }
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignCenter
      }
    }
  }
}
