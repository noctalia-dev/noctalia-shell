#pragma once

struct lua_State;
class ScriptedWidget;

void registerScriptedWidgetBindings(lua_State* L, ScriptedWidget* widget);
