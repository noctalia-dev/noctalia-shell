#include "scripting/scripted_widget_bindings.h"

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

  int luau_setText(lua_State* L) {
    const char* text = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetText(text);
    return 0;
  }

  int luau_setGlyph(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetGlyph(name);
    return 0;
  }

  int luau_setGlyphCodepoint(lua_State* L) {
    auto cp = static_cast<char32_t>(luaL_checknumber(L, 1));
    if (auto* w = getWidget(L))
      w->luaSetGlyphCodepoint(cp);
    return 0;
  }

  int luau_setColor(lua_State* L) {
    const char* role = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetColor(role);
    return 0;
  }

  int luau_setGlyphColor(lua_State* L) {
    const char* role = luaL_checkstring(L, 1);
    if (auto* w = getWidget(L))
      w->luaSetGlyphColor(role);
    return 0;
  }

  const luaL_Reg kWidgetLib[] = {
      {"setText", luau_setText},   {"setGlyph", luau_setGlyph},           {"setGlyphCodepoint", luau_setGlyphCodepoint},
      {"setColor", luau_setColor}, {"setGlyphColor", luau_setGlyphColor}, {nullptr, nullptr},
  };

} // namespace

void registerScriptedWidgetBindings(lua_State* L, ScriptedWidget* widget) {
  lua_pushlightuserdata(L, widget);
  lua_setglobal(L, kWidgetKey);

  luaL_register(L, "barWidget", kWidgetLib);
  lua_pop(L, 1);
}
