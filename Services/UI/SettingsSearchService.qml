pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Power
import qs.Services.System

Singleton {
  id: root

  property var searchIndex: []

  FileView {
    path: Quickshell.shellDir + "/Assets/settings-search-index.json"
    watchChanges: false
    printErrors: false

    onLoaded: {
      try {
        root.searchIndex = JSON.parse(text());
      } catch (e) {
        root.searchIndex = [];
      }
    }
  }

  readonly property var _roots: ({
                                   "CompositorService": CompositorService,
                                   "Settings": Settings,
                                   "Quickshell": Quickshell,
                                   "IdleService": IdleService,
                                   "SystemStatService": SystemStatService,
                                   "SoundService": SoundService
                                 })

  function isEntryVisible(entry) {
    if (!entry.visibleWhen || entry.visibleWhen.length === 0)
      return true;
    for (let i = 0; i < entry.visibleWhen.length; i++) {
      if (!_evalCondition(entry.visibleWhen[i]))
        return false;
    }
    return true;
  }

  function _resolveValue(path) {
    const parts = path.split(".");
    const rootObj = _roots[parts[0]];
    if (rootObj === undefined)
      return undefined;

    let obj = rootObj;
    for (let i = 1; i < parts.length; i++) {
      if (obj === undefined || obj === null)
        return undefined;
      let key = parts[i];
      if (key.endsWith("?"))
        key = key.slice(0, -1);
      obj = obj[key];
    }
    return obj;
  }

  function _splitAnd(expr) {
    const parts = [];
    let depth = 0;
    let current = "";
    for (let i = 0; i < expr.length; i++) {
      const ch = expr[i];
      if (ch === "(")
        depth++;
      else if (ch === ")")
        depth--;
      else if (depth === 0 && ch === "&" && i + 1 < expr.length && expr[i + 1] === "&") {
        parts.push(current);
        current = "";
        i++;
        continue;
      }
      current += ch;
    }
    parts.push(current);
    return parts;
  }

  function _evalCondition(expr) {
    expr = expr.trim();

    // Strip outer parentheses
    if (expr.startsWith("(") && expr.endsWith(")")) {
      let depth = 0;
      let allWrapped = true;
      for (let i = 0; i < expr.length - 1; i++) {
        if (expr[i] === "(")
          depth++;
        else if (expr[i] === ")")
          depth--;
        if (depth === 0) {
          allWrapped = false;
          break;
        }
      }
      if (allWrapped)
        return _evalCondition(expr.slice(1, -1));
    }

    // AND: all parts must be true
    if (expr.includes("&&")) {
      const parts = _splitAnd(expr);
      if (parts.length > 1) {
        for (let i = 0; i < parts.length; i++) {
          if (!_evalCondition(parts[i]))
            return false;
        }
        return true;
      }
    }

    // Negation
    if (expr.startsWith("!"))
      return !_evalCondition(expr.slice(1).trim());

    // Literal false
    if (expr === "false")
      return false;

    // Strip nullish coalescing fallback
    const nullishMatch = expr.match(/^(.+?)\s*\?\?\s*(?:false|true)\s*$/);
    if (nullishMatch)
      return _evalCondition(nullishMatch[1]);

    // === comparison
    let m = expr.match(/^(.+?)\s*===\s*"([^"]*)"\s*$/);
    if (m)
      return _resolveValue(m[1].trim()) === m[2];

    // !== comparison
    m = expr.match(/^(.+?)\s*!==\s*"([^"]*)"\s*$/);
    if (m)
      return _resolveValue(m[1].trim()) !== m[2];

    // > comparison
    m = expr.match(/^(.+?)\s*>\s*(\d+)\s*$/);
    if (m)
      return _resolveValue(m[1].trim()) > parseInt(m[2]);

    // Simple property path — resolve and return truthiness
    const val = _resolveValue(expr);
    if (val !== undefined)
      return !!val;

    // Unrecognized expression — assume visible
    return true;
  }
}
