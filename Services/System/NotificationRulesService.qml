pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Configuration
  readonly property string rulesFile: Settings.configDir + "notification-rules.json"

  // State
  property bool isLoaded: false
  property var rules: []
  property string defaultAction: "show"

  // Statistics
  property int totalEvaluated: 0
  property int totalBlocked: 0
  property int totalMuted: 0

  readonly property var supportedActions: ["show", "block", "mute", "notoast", "snooze", "modify"]

  // Internal: compiled regex cache
  property var regexCache: ({})

  Component.onCompleted: {
    // Ensure config directory exists
    Quickshell.execDetached(["mkdir", "-p", Settings.configDir]);
  }

  FileView {
    id: rulesFileView
    path: Settings.directoriesCreated ? root.rulesFile : undefined
    printErrors: false
    watchChanges: true

    onPathChanged: {
      if (path !== undefined) {
        reload();
      }
    }

    onLoaded: {
      parseRulesFile();
    }

    onFileChanged: {
      Logger.i("NotificationRules", "Rules file changed, reloading...");
      reload();
    }

    onLoadFailed: function (error) {
      if (error === 2) {
        // File doesn't exist - use empty rules (no filtering)
        Logger.i("NotificationRules", "No rules file found, filtering disabled");
        root.rules = [];
        root.defaultAction = "show";
        root.isLoaded = true;
      } else {
        Logger.e("NotificationRules", "Failed to load rules file:", error);
      }
    }
  }

  function parseRulesFile() {
    try {
      const text = rulesFileView.text();
      const config = JSON.parse(text);

      // Validate version
      if (config.version !== 1) {
        Logger.w("NotificationRules", "Unknown config version:", config.version, "- expected 1");
      }

      root.defaultAction = config.defaultAction || "show";

      // Parse and validate rules
      const parsedRules = [];
      for (const rule of config.rules || []) {
        const validated = validateRule(rule);
        if (validated) {
          parsedRules.push(validated);
        }
      }

      // Sort by priority (higher first)
      parsedRules.sort((a, b) => (b.priority || 0) - (a.priority || 0));

      root.rules = parsedRules;
      root.regexCache = {}; // Clear regex cache on reload
      root.isLoaded = true;

      Logger.i("NotificationRules", "Loaded", parsedRules.length, "rules");
    } catch (e) {
      Logger.e("NotificationRules", "Failed to parse rules file:", e);
      root.rules = [];
      root.defaultAction = "show";
      root.isLoaded = true;
    }
  }

  function validateRule(rule) {
    if (!rule.id) {
      Logger.w("NotificationRules", "Rule missing id, skipping");
      return null;
    }

    if (!rule.action) {
      Logger.w("NotificationRules", "Rule", rule.id, "missing action, skipping");
      return null;
    }

    if (supportedActions.indexOf(rule.action) === -1) {
      Logger.w("NotificationRules", "Rule", rule.id, "has unknown action:", rule.action);
    }

    return {
      id: rule.id,
      name: rule.name || rule.id,
      enabled: rule.enabled !== false // Default to true
               ,
      priority: rule.priority || 0,
      match: rule.match || {},
      action: rule.action,
      snooze_minutes: rule.snooze_minutes,
      modify: rule.modify
    };
  }

  function evaluate(notification) {
    if (!isLoaded || rules.length === 0) {
      return {
        action: defaultAction
      };
    }

    totalEvaluated++;

    for (const rule of rules) {
      if (!rule.enabled) {
        continue;
      }

      if (matchesRule(notification, rule)) {
        Logger.d("NotificationRules", "Notification matched rule:", rule.name);

        // Update statistics
        if (rule.action === "block") {
          totalBlocked++;
        } else if (rule.action === "mute") {
          totalMuted++;
        }

        return {
          action: rule.action,
          rule: rule,
          snooze_minutes: rule.snooze_minutes,
          modify: rule.modify
        };
      }
    }

    // No rule matched - use default action
    return {
      action: defaultAction
    };
  }

  function matchesRule(notification, rule) {
    const match = rule.match;
    if (!match || Object.keys(match).length === 0) {
      // Empty match = matches everything
      return true;
    }

    // All conditions must match (AND logic)

    // app_name: exact match (case-insensitive)
    if (match.app_name !== undefined) {
      const matchLower = match.app_name.toLowerCase();
      const transformedMatch = notification.appName.toLowerCase() === matchLower;
      const rawMatch = (notification.appNameRaw || "").toLowerCase() === matchLower;
      if (!transformedMatch && !rawMatch) {
        return false;
      }
    }

    // app_pattern: regex match
    if (match.app_pattern !== undefined) {
      const transformedMatch = matchRegex(notification.appName, match.app_pattern, rule.id + "_app");
      const rawMatch = matchRegex(notification.appNameRaw || "", match.app_pattern, rule.id + "_app_raw");
      if (!transformedMatch && !rawMatch) {
        return false;
      }
    }

    // summary_pattern: regex match
    if (match.summary_pattern !== undefined) {
      if (!matchRegex(notification.summary, match.summary_pattern, rule.id + "_summary")) {
        return false;
      }
    }

    // body_pattern: regex match
    if (match.body_pattern !== undefined) {
      if (!matchRegex(notification.body, match.body_pattern, rule.id + "_body")) {
        return false;
      }
    }

    // body_contains: any word matches (case-insensitive)
    if (match.body_contains !== undefined && Array.isArray(match.body_contains)) {
      const bodyLower = (notification.body || "").toLowerCase();
      const found = match.body_contains.some(word => bodyLower.includes(word.toLowerCase()));
      if (!found) {
        return false;
      }
    }

    // urgency: object with comparators
    if (match.urgency !== undefined) {
      if (!matchUrgency(notification.urgency, match.urgency)) {
        return false;
      }
    }

    // category: exact match
    if (match.category !== undefined) {
      if (notification.category !== match.category) {
        return false;
      }
    }

    return true;
  }

  function matchRegex(text, pattern, cacheKey) {
    try {
      let regex = regexCache[cacheKey];
      if (!regex) {
        regex = new RegExp(pattern, "i"); // Case-insensitive
        regexCache[cacheKey] = regex;
      }
      return regex.test(text || "");
    } catch (e) {
      Logger.e("NotificationRules", "Invalid regex in rule", cacheKey, ":", pattern, e);
      return false;
    }
  }

  function matchUrgency(urgency, condition) {
    // urgency: 0=low, 1=normal, 2=critical

    if (condition.eq !== undefined) {
      return urgency === condition.eq;
    }

    if (condition.lt !== undefined) {
      if (!(urgency < condition.lt))
        return false;
    }

    if (condition.lte !== undefined) {
      if (!(urgency <= condition.lte))
        return false;
    }

    if (condition.gt !== undefined) {
      if (!(urgency > condition.gt))
        return false;
    }

    if (condition.gte !== undefined) {
      if (!(urgency >= condition.gte))
        return false;
    }

    if (condition.in !== undefined && Array.isArray(condition.in)) {
      return condition.in.includes(urgency);
    }

    return true;
  }

  function isActionImplemented(action) {
    return action === "show" || action === "block";
  }

  // Reset statistics
  function resetStats() {
    totalEvaluated = 0;
    totalBlocked = 0;
    totalMuted = 0;
  }
}
