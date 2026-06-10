#pragma once

#include "scripting/scripted_widget_types.h"

#include <string>
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

    // Entry id ("author/plugin:entry") for diagnostics, e.g. an undeclared getConfig.
    std::string ownerId;

    void beginCall(ScriptWidgetSnapshot nextSnapshot) {
      snapshot = std::move(nextSnapshot);
      patch = {};
      sideEffects.clear();
    }
  };

  void registerScriptedWidgetBindings(lua_State* L, ScriptedWidgetBindingContext* context);

  // getConfig(key) binding — reads the runtime's seeded settings. Registered under
  // both barWidget.* and noctalia.* so every entry kind (widget/shortcut/service)
  // can read settings uniformly.
  int luau_getConfig(lua_State* L);

} // namespace scripting
