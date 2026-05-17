#pragma once

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

    void beginCall(ScriptWidgetSnapshot nextSnapshot) {
      snapshot = std::move(nextSnapshot);
      patch = {};
      sideEffects.clear();
    }
  };

  void registerScriptedWidgetBindings(lua_State* L, ScriptedWidgetBindingContext* context);

} // namespace scripting
