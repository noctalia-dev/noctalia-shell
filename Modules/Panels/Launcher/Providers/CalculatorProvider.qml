import QtQuick
import Quickshell
import "../../../../Helpers/AdvancedMath.js" as AdvancedMath
import qs.Commons
import qs.Services.Keyboard
import qs.Services.UI

Item {
  id: root

  // Provider metadata
  property string name: I18n.tr("launcher.providers.calculator")
  property var launcher: null
  property string iconMode: Settings.data.appLauncher.iconMode
  property bool handleSearch: true // Contribute to regular search
  property string supportedLayouts: "list"

  // Initialize provider
  function init() {
    Logger.d("CalculatorProvider", "Initialized");
  }

  // Get search results - evaluates math expressions inline
  function getResults(query) {
    if (!query)
      return [];

    const trimmed = query.trim();
    if (!trimmed || !isMathExpression(trimmed))
      return [];

    try {
      const result = AdvancedMath.evaluate(trimmed);
      const formattedResult = AdvancedMath.formatResult(result);
      return [
            {
              "name": formattedResult,
              "description": I18n.tr("launcher.providers.calculator-press-enter-to-copy"),
              "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
              "isTablerIcon": true,
              "isImage": false,
              "provider": root,
              "onActivate": function () {
                // Copy result to clipboard via xclip
                Quickshell.execDetached(["bash", "-c", "echo -n '" + formattedResult.replace(/'/g, "'\\''") + "' | wl-copy"]);
                ToastService.showNotice("Copied", formattedResult);
                if (launcher)
                  launcher.close();
              }
            }
          ];
    } catch (error) {
      return [];
    }
  }

  // Check if a string is a valid math expression
  function isMathExpression(expr) {
    // Allow: digits, operators, parentheses, decimal points, whitespace, letters (for functions), commas
    if (!/^[\d\s\+\-\*\/\(\)\.\%\^a-zA-Z,]+$/.test(expr))
      return false;

    // Must contain at least one operator OR a function call (letter followed by parenthesis)
    if (!/[+\-*/%\^]/.test(expr) && !/[a-zA-Z]\s*\(/.test(expr))
      return false;

    // Reject if ends with an operator (incomplete expression)
    if (/[+\-*/%\^]\s*$/.test(expr))
      return false;

    // Reject if it's just letters (would match app names)
    if (/^[a-zA-Z\s]+$/.test(expr))
      return false;

    return true;
  }
}
