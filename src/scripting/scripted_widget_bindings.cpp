#include "scripting/scripted_widget_bindings.h"

#include "core/process.h"
#include "lua.h"
#include "lualib.h"
#include "shell/bar/widgets/scripted_widget.h"

namespace {

  constexpr const char* kWidgetKey = "__scripted_widget";

  ScriptedWidget* getWidget(lua_State* L) {
    lua_getglobal(L, kWidgetKey);
    auto* w = static_cast<ScriptedWidget*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return w;
  }

  int nocta_setText(lua_State* L) {
    const char* text = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetText(text);
    return 0;
  }

  int nocta_setGlyph(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetGlyph(name);
    return 0;
  }

  int nocta_setGlyphCodepoint(lua_State* L) {
    auto cp = static_cast<char32_t>(luaL_checknumber(L, 1));
    if (auto* w = getWidget(L))
      w->luaSetGlyphCodepoint(cp);
    return 0;
  }

  int nocta_setColor(lua_State* L) {
    const char* role = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetColor(role);
    return 0;
  }

  int nocta_setGlyphColor(lua_State* L) {
    const char* role = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetGlyphColor(role);
    return 0;
  }

  int nocta_runAsync(lua_State* L) {
    const char* cmd = luaL_checkstring(L, 1);
    bool ok = process::runAsync(std::string(cmd));
    lua_pushboolean(L, ok ? 1 : 0);
    return 1;
  }

  int nocta_runSync(lua_State* L) {
    const char* cmd = luaL_checkstring(L, 1);
    bool ok = process::runSync(std::string(cmd));
    lua_pushboolean(L, ok ? 1 : 0);
    return 1;
  }

} // namespace

void registerScriptedWidgetBindings(lua_State* L, ScriptedWidget* widget) {
  lua_pushlightuserdata(L, widget);
  lua_setglobal(L, kWidgetKey);

  // The inherited "nocta" table is frozen by luaL_sandbox on the parent state.
  // Create a fresh table that copies "log" from the original and adds the
  // widget-specific bindings.
  lua_newtable(L);

  lua_getglobal(L, "nocta");
  if (lua_istable(L, -1)) {
    lua_getfield(L, -1, "log");
    lua_setfield(L, -3, "log");
  }
  lua_pop(L, 1);

  lua_pushcfunction(L, nocta_setText, "setText");
  lua_setfield(L, -2, "setText");

  lua_pushcfunction(L, nocta_setGlyph, "setGlyph");
  lua_setfield(L, -2, "setGlyph");

  lua_pushcfunction(L, nocta_setGlyphCodepoint, "setGlyphCodepoint");
  lua_setfield(L, -2, "setGlyphCodepoint");

  lua_pushcfunction(L, nocta_setColor, "setColor");
  lua_setfield(L, -2, "setColor");

  lua_pushcfunction(L, nocta_setGlyphColor, "setGlyphColor");
  lua_setfield(L, -2, "setGlyphColor");

  lua_pushcfunction(L, nocta_runAsync, "runAsync");
  lua_setfield(L, -2, "runAsync");

  lua_pushcfunction(L, nocta_runSync, "runSync");
  lua_setfield(L, -2, "runSync");

  lua_setglobal(L, "nocta");
}
