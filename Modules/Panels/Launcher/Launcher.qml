import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../Helpers/AdvancedMath.js" as AdvancedMath
import "../../../Helpers/FuzzySort.js" as Fuzzysort

import "Plugins"
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Keyboard
import qs.Widgets

SmartPanel {
  id: root

  readonly property bool previewActive: !!(searchText && searchText.startsWith(">clip") && Settings.data.appLauncher.enableClipPreview && ClipboardService.items && ClipboardService.items.length > 0 && selectedIndex >= 0 && results && results[selectedIndex] && results[selectedIndex].clipboardId)

  // Panel configuration
  readonly property int listPanelWidth: Math.round(500 * Style.uiScaleRatio)
  readonly property int previewPanelWidth: Math.round(400 * Style.uiScaleRatio)
  readonly property int totalBaseWidth: listPanelWidth + (Style.marginL * 2)

  preferredWidth: totalBaseWidth
  preferredHeight: Math.round(600 * Style.uiScaleRatio)
  preferredWidthRatio: 0.3
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
  property var plugins: []
  property var activePlugin: null
  property bool resultsReady: false
  property bool ignoreMouseHover: Settings.data.appLauncher.ignoreMouseInput

  readonly property int badgeSize: Math.round(Style.baseWidgetSize * 1.6 * Style.uiScaleRatio)
  readonly property int entryHeight: Math.round(badgeSize + Style.marginM * 2)
  readonly property bool isGridView: {
    // Always use list view for clipboard and calculator to better display content
    if (searchText.startsWith(">clip") || searchText.startsWith(">calc")) {
      return false;
    }
    if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
      return true;
    }
    return Settings.data.appLauncher.viewMode === "grid";
  }

  // Target columns, but actual columns may vary based on available width
  // Account for NTabBar margins to match category tabs width
  readonly property int targetGridColumns: 5
  readonly property int gridContentWidth: listPanelWidth - (2 * Style.marginXS)
  readonly property int gridCellSize: Math.floor((gridContentWidth - ((targetGridColumns - 1) * Style.marginS)) / targetGridColumns)

  // Actual columns that fit in the GridView
  // This gets updated dynamically by the GridView when its actual width is known
  property int gridColumns: 5

  // Override keyboard handlers from SmartPanel for navigation.
  // Launcher specific: onTabPressed() and onBackTabPressed() are special here.
  // They are not coming from SmartPanelWindow as they are consumed by the search field before reaching the panel.
  // They are instead being forwared from the search field NTextInput below.
  function onTabPressed() {
    // In emoji browsing mode, Tab navigates between categories
    if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
      var currentIndex = emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
      var nextIndex = (currentIndex + 1) % emojiPlugin.categories.length;
      emojiPlugin.selectCategory(emojiPlugin.categories[nextIndex]);
    } else if ((activePlugin === null || activePlugin === appsPlugin) && appsPlugin.isBrowsingMode && !root.searchText.startsWith(">") && Settings.data.appLauncher.showCategories) {
      // In apps browsing mode (no search), Tab navigates between categories
      var availableCategories = appsPlugin.availableCategories || ["all"];
      var currentIndex = availableCategories.indexOf(appsPlugin.selectedCategory);
      var nextIndex = (currentIndex + 1) % availableCategories.length;
      appsPlugin.selectCategory(availableCategories[nextIndex]);
    } else {
      selectNextWrapped();
    }
  }

  function onBackTabPressed() {
    if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
      var currentIndex = emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
      var previousIndex = ((currentIndex - 1) % emojiPlugin.categories.length + emojiPlugin.categories.length) % emojiPlugin.categories.length;
      emojiPlugin.selectCategory(emojiPlugin.categories[previousIndex]);
    } else if ((activePlugin === null || activePlugin === appsPlugin) && appsPlugin.isBrowsingMode && !root.searchText.startsWith(">") && Settings.data.appLauncher.showCategories) {
      var availableCategories = appsPlugin.availableCategories || ["all"];
      var currentIndex = availableCategories.indexOf(appsPlugin.selectedCategory);
      var previousIndex = ((currentIndex - 1) % availableCategories.length + availableCategories.length) % availableCategories.length;
      appsPlugin.selectCategory(availableCategories[previousIndex]);
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
    // Delete clipboard entry if one is selected
    if (selectedIndex >= 0 && results && results[selectedIndex] && results[selectedIndex].clipboardId) {
      const clipboardId = results[selectedIndex].clipboardId;
      clipPlugin.gotResults = false;
      clipPlugin.isWaitingForData = true;
      clipPlugin.lastSearchText = root.searchText;
      ClipboardService.deleteById(String(clipboardId));
    }
  }

  // Public API for plugins
  function setSearchText(text) {
    searchText = text;
  }

  // Plugin registration
  function registerPlugin(plugin) {
    plugins.push(plugin);
    plugin.launcher = root;
    if (plugin.init)
      plugin.init();
  }

  // Caclualtor handling
  function isMathExpression(expr) {
    // Allow: digits, operators, parentheses, decimal points, whitespace, letters (for functions), commas
    if (!/^[\d\s\+\-\*\/\(\)\.\%\^a-zA-Z,]+$/.test(expr)) {
      return false;
    }

    // Must contain at least one operator OR a function call (letter followed by parenthesis)
    if (!/[+\-*/%\^]/.test(expr) && !/[a-zA-Z]\s*\(/.test(expr)) {
      return false;
    }

    // Reject if ends with an operator (incomplete expression)
    if (/[+\-*/%\^]\s*$/.test(expr)) {
      return false;
    }

    // Reject if it's just letters (would match app names)
    if (/^[a-zA-Z\s]+$/.test(expr)) {
      return false;
    }

    return true;
  }

  function getInlineCalculatorResult(query) {
    const trimmed = query.trim();
    if (!trimmed || !isMathExpression(trimmed)) {
      return null;
    }

    try {
      const result = AdvancedMath.evaluate(trimmed);
      const iconMode = Settings.data.appLauncher.iconMode;
      return {
        "name": AdvancedMath.formatResult(result),
        "description": `${trimmed} = ${result}`,
        "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
        "isTablerIcon": true,
        "isImage": false,
        "onActivate": function () {
          // TODO: copy entry to clipboard via ClipHist
          root.close();
        }
      };
    } catch (error) {
      return null;
    }
  }

  // Search handling
  function updateResults() {
    results = [];
    activePlugin = null;

    // Check for command mode
    if (searchText.startsWith(">")) {
      // Find plugin that handles this command
      for (let plugin of plugins) {
        if (plugin.handleCommand && plugin.handleCommand(searchText)) {
          activePlugin = plugin;
          results = plugin.getResults(searchText);
          break;
        }
      }

      // Show available commands if just ">" or filter commands if partial match
      if (!activePlugin) {
        // Collect all commands from all plugins
        let allCommands = [];
        for (let plugin of plugins) {
          if (plugin.commands) {
            allCommands = allCommands.concat(plugin.commands());
          }
        }

        if (searchText === ">") {
          // Show all commands when just ">"
          results = allCommands;
        } else if (searchText.length > 1) {
          // Filter commands using fuzzy search when typing partial command
          const query = searchText.substring(1); // Remove the ">" prefix

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
      // Regular search - let plugins contribute results
      for (let plugin of plugins) {
        if (plugin.handleSearch) {
          const pluginResults = plugin.getResults(searchText);
          results = results.concat(pluginResults);
        }
      }

      // Inline calculator - append result if query is a valid math expression
      const inlineResult = getInlineCalculatorResult(searchText);
      if (inlineResult) {
        results = results.concat([inlineResult]);
      }
    }

    selectedIndex = 0;
  }

  onSearchTextChanged: updateResults()

  // Lifecycle
  onOpened: {
    resultsReady = false;
    ignoreMouseHover = true;

    // Notify plugins and update results
    // Use Qt.callLater to ensure plugins are registered (Component.onCompleted runs first)
    Qt.callLater(() => {
                   for (let plugin of plugins) {
                     if (plugin.onOpened)
                     plugin.onOpened();
                   }
                   updateResults();
                   resultsReady = true;
                 });
  }

  onClosed: {
    // Reset search text
    searchText = "";
    ignoreMouseHover = true;

    // Notify plugins
    for (let plugin of plugins) {
      if (plugin.onClosed)
        plugin.onClosed();
    }
  }

  // Plugin components - declared inline so imports work correctly
  ApplicationsPlugin {
    id: appsPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: ApplicationsPlugin");
    }
  }

  CalculatorPlugin {
    id: calcPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: CalculatorPlugin");
    }
  }

  ClipboardPlugin {
    id: clipPlugin
    Component.onCompleted: {
      if (Settings.data.appLauncher.enableClipboardHistory) {
        registerPlugin(this);
        Logger.d("Launcher", "Registered: ClipboardPlugin");
      }
    }
  }

  CommandPlugin {
    id: cmdPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: CommandPlugin");
    }
  }

  EmojiPlugin {
    id: emojiPlugin
    Component.onCompleted: {
      registerPlugin(this);
      Logger.d("Launcher", "Registered: EmojiPlugin");
    }
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
      const page = Math.max(1, Math.floor(600 / entryHeight)); // Use approximate height
      selectedIndex = Math.min(selectedIndex + page, results.length - 1);
    }
  }

  function selectPreviousPage() {
    if (results.length > 0) {
      const page = Math.max(1, Math.floor(600 / entryHeight)); // Use approximate height
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
      if (item.onActivate) {
        item.onActivate();
      }
    }
  }

  panelContent: Rectangle {
    id: ui
    color: Color.transparent
    opacity: resultsReady ? 1.0 : 0.0

    // Preview Panel (external)
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

      Loader {
        id: clipboardPreviewLoader
        anchors.fill: parent
        active: root.previewActive
        source: active ? "./ClipboardPreview.qml" : ""

        onLoaded: {
          if (selectedIndex >= 0 && results[selectedIndex] && item) {
            item.currentItem = results[selectedIndex];
          }
        }

        onItemChanged: {
          if (item && selectedIndex >= 0 && results[selectedIndex]) {
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
            visible: root.activePlugin === null || root.activePlugin === appsPlugin
            icon: Settings.data.appLauncher.viewMode === "grid" ? "layout-list" : "layout-grid"
            tooltipText: Settings.data.appLauncher.viewMode === "grid" ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
            Layout.preferredWidth: searchInput.height
            Layout.preferredHeight: searchInput.height
            onClicked: {
              Settings.data.appLauncher.viewMode = Settings.data.appLauncher.viewMode === "grid" ? "list" : "grid";
            }
          }
        }

        // Emoji category tabs (shown when in browsing mode)
        NTabBar {
          id: emojiCategoryTabs
          visible: root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode
          Layout.fillWidth: true
          margins: Style.marginM
          property int computedCurrentIndex: {
            if (visible && emojiPlugin.categories) {
              return emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
            }
            return 0;
          }
          currentIndex: computedCurrentIndex

          Repeater {
            model: emojiPlugin.categories
            NIconTabButton {
              required property string modelData
              required property int index
              icon: emojiPlugin.categoryIcons[modelData] || "star"
              tooltipText: emojiPlugin.getCategoryName ? emojiPlugin.getCategoryName(modelData) : modelData
              tabIndex: index
              checked: emojiCategoryTabs.currentIndex === index
              onClicked: {
                emojiPlugin.selectCategory(modelData);
              }
            }
          }
        }

        Connections {
          target: emojiPlugin
          enabled: emojiCategoryTabs.visible
          function onSelectedCategoryChanged() {
            // Force update of currentIndex when selectedCategory changes
            Qt.callLater(() => {
                           if (emojiCategoryTabs.visible && emojiPlugin.categories) {
                             const newIndex = emojiPlugin.categories.indexOf(emojiPlugin.selectedCategory);
                             if (newIndex >= 0 && emojiCategoryTabs.currentIndex !== newIndex) {
                               emojiCategoryTabs.currentIndex = newIndex;
                             }
                           }
                         });
          }
        }

        // App category tabs (shown when browsing apps without search)
        NTabBar {
          id: appCategoryTabs
          visible: (root.activePlugin === null || root.activePlugin === appsPlugin) && appsPlugin.isBrowsingMode && !root.searchText.startsWith(">") && Settings.data.appLauncher.showCategories
          Layout.fillWidth: true
          margins: Style.marginM
          property int computedCurrentIndex: {
            if (visible && appsPlugin.availableCategories) {
              return appsPlugin.availableCategories.indexOf(appsPlugin.selectedCategory);
            }
            return 0;
          }
          currentIndex: computedCurrentIndex

          Repeater {
            model: appsPlugin.availableCategories || []
            NIconTabButton {
              required property string modelData
              required property int index
              icon: appsPlugin.categoryIcons[modelData] || "apps"
              tooltipText: appsPlugin.getCategoryName ? appsPlugin.getCategoryName(modelData) : modelData
              tabIndex: index
              checked: appCategoryTabs.currentIndex === index
              onClicked: {
                appsPlugin.selectCategory(modelData);
              }
            }
          }
        }

        Connections {
          target: appsPlugin
          enabled: appCategoryTabs.visible
          function onSelectedCategoryChanged() {
            // Force update of currentIndex when selectedCategory changes
            Qt.callLater(() => {
                           if (appCategoryTabs.visible && appsPlugin.availableCategories) {
                             const newIndex = appsPlugin.availableCategories.indexOf(appsPlugin.selectedCategory);
                             if (newIndex >= 0 && appCategoryTabs.currentIndex !== newIndex) {
                               appCategoryTabs.currentIndex = newIndex;
                             }
                           }
                         });
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
            verticalPolicy: ScrollBar.AsNeeded

            width: parent.width
            height: parent.height
            spacing: Style.marginXXS
            model: results
            currentIndex: selectedIndex
            cacheBuffer: resultsList.height * 2
            interactive: !Settings.data.appLauncher.ignoreMouseInput
            onCurrentIndexChanged: {
              cancelFlick();
              if (currentIndex >= 0) {
                positionViewAtIndex(currentIndex, ListView.Contain);
              }
              if (clipboardPreviewLoader.item) {
                clipboardPreviewLoader.item.currentItem = results[currentIndex] || null;
              }
            }
            onModelChanged: {}

            delegate: Rectangle {
              id: entry

              property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)
              property string appId: (modelData && modelData.appId) ? String(modelData.appId) : ""

              // Helper function to normalize app IDs for case-insensitive matching
              function normalizeAppId(appId) {
                if (!appId || typeof appId !== 'string')
                  return "";
                return appId.toLowerCase().trim();
              }

              // Pin helpers
              function togglePin(appId) {
                if (!appId)
                  return;
                const normalizedId = normalizeAppId(appId);
                let arr = (Settings.data.dock.pinnedApps || []).slice();
                const idx = arr.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
                if (idx >= 0)
                  arr.splice(idx, 1);
                else
                  arr.push(appId);
                Settings.data.dock.pinnedApps = arr;
              }

              function isPinned(appId) {
                if (!appId)
                  return false;
                const arr = Settings.data.dock.pinnedApps || [];
                const normalizedId = normalizeAppId(appId);
                return arr.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
              }

              // Property to reliably track the current item's ID.
              // This changes whenever the delegate is recycled for a new item.
              property var currentClipboardId: modelData.isImage ? modelData.clipboardId : ""

              // When this delegate is assigned a new image item, trigger the decode.
              onCurrentClipboardIdChanged: {
                // Check if it's a valid ID and if the data isn't already cached.
                if (currentClipboardId && !ClipboardService.getImageData(currentClipboardId)) {
                  ClipboardService.decodeToDataUrl(currentClipboardId, modelData.mime, null);
                }
              }

              width: resultsList.width - Style.marginS
              implicitHeight: entryHeight
              radius: Style.radiusM
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
                  Rectangle {
                    Layout.preferredWidth: badgeSize
                    Layout.preferredHeight: badgeSize
                    radius: 0
                    color: Color.mSurfaceVariant

                    // Image preview for clipboard images
                    NImageRounded {
                      id: imagePreview
                      anchors.fill: parent
                      visible: modelData.isImage && !modelData.emojiChar
                      radius: Style.radiusM

                      // This property creates a dependency on the service's revision counter
                      readonly property int _rev: ClipboardService.revision

                      // Fetches from the service's cache.
                      // The dependency on `_rev` ensures this binding is re-evaluated when the cache is updated.
                      imagePath: {
                        _rev;
                        return ClipboardService.getImageData(modelData.clipboardId) || "";
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

                      visible: !modelData.isImage && !modelData.emojiChar || (modelData.isImage && imagePreview.status === Image.Error)
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
                          visible: modelData.icon && !modelData.emojiChar
                        }
                      }

                      Component {
                        id: systemIconComponent
                        IconImage {
                          anchors.fill: parent
                          source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                          visible: modelData.icon && source !== "" && !modelData.emojiChar
                          asynchronous: true
                        }
                      }
                    }

                    // Emoji display - takes precedence when emojiChar is present
                    NText {
                      id: emojiDisplay
                      anchors.centerIn: parent
                      visible: modelData.emojiChar || (!imagePreview.visible && !iconLoader.visible)
                      text: modelData.emojiChar ? modelData.emojiChar : modelData.name.charAt(0).toUpperCase()
                      pointSize: modelData.emojiChar ? Style.fontSizeXXXL : Style.fontSizeXXL  // Larger font for emojis
                      font.weight: Style.fontWeightBold
                      color: modelData.emojiChar ? Color.mOnSurface : Color.mOnPrimary  // Different color for emojis
                    }

                    // Image type indicator overlay
                    Rectangle {
                      visible: modelData.isImage && imagePreview.visible
                      anchors.bottom: parent.bottom
                      anchors.right: parent.right
                      anchors.margins: 2
                      width: formatLabel.width + 6
                      height: formatLabel.height + 2
                      radius: Style.radiusM
                      color: Color.mSurfaceVariant

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
                        color: Color.mPrimary
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
                      Layout.fillWidth: true
                    }

                    NText {
                      text: modelData.description || ""
                      pointSize: Style.fontSizeS
                      color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant
                      wrapMode: Text.WordWrap
                      Layout.fillWidth: true
                      visible: text !== ""
                    }
                  }

                  // Action buttons row
                  RowLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: Style.marginXS
                    visible: (!!entry.appId && entry.isSelected) || (!!modelData.clipboardId && entry.isSelected)

                    // Pin/Unpin action icon button
                    NIconButton {
                      visible: !!entry.appId && !modelData.isImage && entry.isSelected
                      icon: entry.isPinned(entry.appId) ? "unpin" : "pin"
                      tooltipText: entry.isPinned(entry.appId) ? I18n.tr("launcher.unpin") : I18n.tr("launcher.pin")
                      onClicked: entry.togglePin(entry.appId)
                    }

                    // open an annotation tool for images
                    NIconButton {
                      visible: !!modelData.clipboardId && entry.isSelected && modelData.isImage && Settings.data.appLauncher.screenshotAnnotationTool !== ""
                      icon: "pencil"
                      tooltipText: I18n.tr("tooltips.open-annotation-tool")
                      z: 1
                      onClicked: {
                        var tool = Settings.data.appLauncher.screenshotAnnotationTool;
                        if (modelData.clipboardId) {
                          Quickshell.execDetached(["sh", "-c", "cliphist decode " + modelData.clipboardId + " | " + tool]);
                          root.close();
                        }
                      }
                    }

                    // Delete action icon button for clipboard entries
                    NIconButton {
                      visible: !!modelData.clipboardId && entry.isSelected
                      icon: "trash"
                      tooltipText: I18n.tr("plugins.clipboard-delete")
                      z: 1
                      onClicked: {
                        if (modelData.clipboardId) {
                          // Set plugin state before deletion so refresh works
                          clipPlugin.gotResults = false;
                          clipPlugin.isWaitingForData = true;
                          clipPlugin.lastSearchText = root.searchText;
                          // Delete the item - deleteById now uses Process and will refresh automatically
                          ClipboardService.deleteById(String(modelData.clipboardId));
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
            verticalPolicy: ScrollBar.AsNeeded

            width: parent.width
            height: parent.height
            cellWidth: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return parent.width / root.targetGridColumns;
              }
              // Make cells fit exactly like the tab bar
              // Cell width scales automatically as parent.width scales with uiScaleRatio
              return parent.width / root.targetGridColumns;
            }
            cellHeight: {
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                return (parent.width / root.targetGridColumns) * 1.2;
              }
              // Cell height scales automatically as parent.width scales with uiScaleRatio
              // Content (badge, text) scales via badgeSize which now uses uiScaleRatio
              return parent.width / root.targetGridColumns;
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
              // Update gridColumns based on actual GridView width
              // This ensures navigation works correctly regardless of panel size
              if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
                // Always 5 columns for emoji browsing mode
                root.gridColumns = 5;
              } else {
                // Since cellWidth = width / targetGridColumns, the number of columns is always targetGridColumns
                // Just use targetGridColumns directly
                root.gridColumns = root.targetGridColumns;
              }
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

            // Update gridColumns when entering/exiting emoji browsing mode
            Connections {
              target: emojiPlugin
              function onIsBrowsingModeChanged() {
                if (emojiPlugin.isBrowsingMode) {
                  root.gridColumns = 5;
                }
              }
            }

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
                if (clipboardPreviewLoader.item && root.selectedIndex >= 0) {
                  clipboardPreviewLoader.item.currentItem = results[root.selectedIndex] || null;
                }
              }
            }

            delegate: Rectangle {
              id: gridEntry

              property bool isSelected: (!root.ignoreMouseHover && mouseArea.containsMouse) || (index === selectedIndex)
              property string appId: (modelData && modelData.appId) ? String(modelData.appId) : ""

              // Helper function to normalize app IDs for case-insensitive matching
              function normalizeAppId(appId) {
                if (!appId || typeof appId !== 'string')
                  return "";
                return appId.toLowerCase().trim();
              }

              // Pin helpers
              function togglePin(appId) {
                if (!appId)
                  return;
                const normalizedId = normalizeAppId(appId);
                let arr = (Settings.data.dock.pinnedApps || []).slice();
                const idx = arr.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
                if (idx >= 0)
                  arr.splice(idx, 1);
                else
                  arr.push(appId);
                Settings.data.dock.pinnedApps = arr;
              }

              function isPinned(appId) {
                if (!appId)
                  return false;
                const arr = Settings.data.dock.pinnedApps || [];
                const normalizedId = normalizeAppId(appId);
                return arr.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
              }

              width: resultsGrid.cellWidth
              height: resultsGrid.cellHeight
              radius: Style.radiusM
              color: gridEntry.isSelected ? Color.mHover : Color.mSurface

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCirc
                }
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) ? 4 : Style.marginM
                anchors.bottomMargin: (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) ? Style.marginL : Style.marginM
                spacing: Style.marginS

                // Icon badge or Image preview or Emoji
                Rectangle {
                  Layout.preferredWidth: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return gridEntry.width - 8;
                    }
                    // Scale badge relative to cell size for proper scaling on all resolutions
                    // Use 60% of cell width, ensuring it scales down on low res and up on high res
                    return Math.round(gridEntry.width * 0.6);
                  }
                  Layout.preferredHeight: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return gridEntry.width - 8;
                    }
                    // Scale badge relative to cell size for proper scaling on all resolutions
                    // Use 60% of cell width, ensuring it scales down on low res and up on high res
                    return Math.round(gridEntry.width * 0.6);
                  }
                  Layout.alignment: Qt.AlignHCenter
                  radius: Style.radiusM
                  color: Color.mSurfaceVariant

                  // Image preview for clipboard images
                  NImageRounded {
                    id: gridImagePreview
                    anchors.fill: parent
                    visible: modelData.isImage && !modelData.emojiChar
                    radius: Style.radiusM

                    readonly property int _rev: ClipboardService.revision

                    imagePath: {
                      _rev;
                      return ClipboardService.getImageData(modelData.clipboardId) || "";
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

                    visible: !modelData.isImage && !modelData.emojiChar || (modelData.isImage && gridImagePreview.status === Image.Error)
                    active: visible

                    sourceComponent: Component {
                      Loader {
                        anchors.fill: parent
                        sourceComponent: Settings.data.appLauncher.iconMode === "tabler" && modelData.isTablerIcon ? gridTablerIconComponent : gridSystemIconComponent
                      }
                    }

                    Component {
                      id: gridTablerIconComponent
                      NIcon {
                        icon: modelData.icon
                        pointSize: Style.fontSizeXXXL
                        visible: modelData.icon && !modelData.emojiChar
                      }
                    }

                    Component {
                      id: gridSystemIconComponent
                      IconImage {
                        anchors.fill: parent
                        source: modelData.icon ? ThemeIcons.iconFromName(modelData.icon, "application-x-executable") : ""
                        visible: modelData.icon && source !== "" && !modelData.emojiChar
                        asynchronous: true
                      }
                    }
                  }

                  // Emoji display
                  NText {
                    id: gridEmojiDisplay
                    anchors.centerIn: parent
                    visible: modelData.emojiChar || (!gridImagePreview.visible && !gridIconLoader.visible)
                    text: modelData.emojiChar ? modelData.emojiChar : modelData.name.charAt(0).toUpperCase()
                    pointSize: {
                      if (modelData.emojiChar) {
                        if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode) {
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
                    color: modelData.emojiChar ? Color.mOnSurface : Color.mOnPrimary
                  }
                }

                // Text content
                NText {
                  text: modelData.name || "Unknown"
                  pointSize: {
                    if (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) {
                      return Style.fontSizeS * Style.uiScaleRatio;
                    }
                    // Scale font size relative to cell width for low res, but cap at maximum
                    const cellBasedSize = gridEntry.width * 0.12;
                    const baseSize = Style.fontSizeS * Style.uiScaleRatio;
                    const maxSize = Style.fontSizeM * Style.uiScaleRatio;
                    return Math.min(Math.max(cellBasedSize, baseSize), maxSize);
                  }
                  font.weight: Style.fontWeightSemiBold
                  color: gridEntry.isSelected ? Color.mOnHover : Color.mOnSurface
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  Layout.maximumWidth: gridEntry.width - 8
                  Layout.leftMargin: (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) ? Style.marginS : 0
                  Layout.rightMargin: (root.activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && modelData.emojiChar) ? Style.marginS : 0
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.NoWrap
                  maximumLineCount: 1
                }
              }

              // Action buttons (overlay in top-right corner)
              Row {
                visible: (!!gridEntry.appId && gridEntry.isSelected) || (!!modelData.clipboardId && gridEntry.isSelected)
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.marginXS
                z: 10
                spacing: Style.marginXXS

                // Pin/Unpin action icon button
                NIconButton {
                  visible: !!gridEntry.appId && !modelData.isImage && gridEntry.isSelected
                  icon: gridEntry.isPinned(gridEntry.appId) ? "unpin" : "pin"
                  tooltipText: gridEntry.isPinned(gridEntry.appId) ? I18n.tr("launcher.unpin") : I18n.tr("launcher.pin")
                  onClicked: gridEntry.togglePin(gridEntry.appId)
                }

                // Delete action icon button for clipboard entries
                NIconButton {
                  visible: !!modelData.clipboardId && gridEntry.isSelected
                  icon: "trash"
                  tooltipText: I18n.tr("plugins.clipboard-delete")
                  z: 11
                  onClicked: {
                    if (modelData.clipboardId) {
                      // Set plugin state before deletion so refresh works
                      clipPlugin.gotResults = false;
                      clipPlugin.isWaitingForData = true;
                      clipPlugin.lastSearchText = root.searchText;
                      // Delete the item - deleteById now uses Process and will refresh automatically
                      ClipboardService.deleteById(String(modelData.clipboardId));
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
                return "No results";
              } else if (activePlugin === emojiPlugin && emojiPlugin.isBrowsingMode && emojiPlugin.selectedCategory === "recent") {
                return "No recently used emoji";
              }
              return "";
            }
            var prefix = activePlugin && activePlugin.name ? activePlugin.name + ": " : "";
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
