pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  readonly property string rulesFilePath: Settings.configDir + "notification-rules.json"

  property var rules: []

  property FileView rulesFileView: FileView {
    id: rulesFileView
    path: root.rulesFilePath
    watchChanges: true
    printErrors: false

    adapter: JsonAdapter {
      id: rulesAdapter
      property var rules: []
    }

    onLoaded: {
      try {
        const parsed = JSON.parse(rulesFileView.text());
        const raw = Array.isArray(parsed.rules) ? parsed.rules : [];
        root.rules = raw.filter(r => (r.pattern || "").trim() !== "");
      } catch (e) {
        root.rules = [];
      }
    }

    onLoadFailed: function (error) {
      root.rules = [];
    }
  }

  function init() {
  }

  function save() {
    Quickshell.execDetached(["mkdir", "-p", Settings.configDir]);
    root.rules = root.rules.filter(r => (r.pattern || "").trim() !== "");
    rulesAdapter.rules = root.rules;
    rulesFileView.writeAdapter();
  }

  function evaluate(appName, summary, body) {
    const haystack = [appName || "", summary || "", body || ""].join(" ");
    for (let i = 0; i < root.rules.length; i++) {
      const r = root.rules[i];
      const pattern = (r.pattern || "").trim();
      if (pattern === "")
        continue;
      let matched = false;
      if (pattern.length >= 3 && pattern.startsWith("/") && pattern.endsWith("/")) {
        try {
          matched = new RegExp(pattern.slice(1, -1)).test(haystack);
        } catch (e) {
          Logger.w("NotificationRulesService", "Invalid regex:", pattern, e);
        }
      } else if (pattern.includes("*")) {
        try {
          const reStr = pattern.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
          matched = new RegExp(reStr, "i").test(haystack);
        } catch (e) {
          matched = haystack.toLowerCase().includes(pattern.toLowerCase());
        }
      } else {
        matched = haystack.toLowerCase().includes(pattern.toLowerCase());
      }
      if (matched) {
        const a = (r.action || "block").toLowerCase();
        if (a === "mute" || a === "hide")
          return a;
        if (a === "silence")
          return "hide";
        return "block";
      }
    }
    return null;
  }
}
