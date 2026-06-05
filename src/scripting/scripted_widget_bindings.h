#pragma once

#include "scripting/scripted_widget_manifest.h"
#include "scripting/scripted_widget_types.h"

#include <vector>

struct lua_State;
class LuauHost;

namespace scripting {

  struct ScriptedWidgetBindingContext {
    const ScriptWidgetSettings* settings = nullptr;
    LuauHost* host = nullptr;
    ScriptWidgetSnapshot snapshot;
    ScriptWidgetPatch patch;
    std::vector<ScriptWidgetSideEffect> sideEffects;

    // Manifest extraction: when `manifestExtractionMode` is set, `barWidget.define`
    // captures its table into `manifestOut`, flips `defineCalled`, then aborts the
    // chunk so no later top-level side effects run.
    bool manifestExtractionMode = false;
    bool defineCalled = false;
    ScriptWidgetManifest* manifestOut = nullptr;

    void beginCall(ScriptWidgetSnapshot nextSnapshot) {
      snapshot = std::move(nextSnapshot);
      patch = {};
      sideEffects.clear();
    }
  };

  void registerScriptedWidgetBindings(lua_State* L, ScriptedWidgetBindingContext* context);

} // namespace scripting
