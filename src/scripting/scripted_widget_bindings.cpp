#include "scripting/scripted_widget_bindings.h"

#include "lua.h"
#include "lualib.h"
#include "shell/bar/widgets/scripted_widget.h"

#include <variant>

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

  int luau_isVertical(lua_State* L) {
    auto* w = getWidget(L);
    lua_pushboolean(L, w && w->isVertical() ? 1 : 0);
    return 1;
  }

  int luau_setUpdateInterval(lua_State* L) {
    auto ms = static_cast<float>(luaL_checknumber(L, 1));
    if (auto* w = getWidget(L))
      w->luaSetUpdateInterval(ms);
    return 0;
  }

  int luau_setVisible(lua_State* L) {
    bool visible = lua_toboolean(L, 1) != 0;
    if (auto* w = getWidget(L))
      w->luaSetVisible(visible);
    return 0;
  }

  int luau_getConfig(lua_State* L) {
    const char* key = luaL_checkstring(L, 1);
    auto* w = getWidget(L);
    if (!w) {
      lua_pushnil(L);
      return 1;
    }

    auto it = w->settings().find(key);
    if (it == w->settings().end()) {
      if (lua_gettop(L) >= 2) {
        lua_pushvalue(L, 2);
        return 1;
      }
      lua_pushnil(L);
      return 1;
    }

    std::visit(
        [L](const auto& val) {
          using T = std::decay_t<decltype(val)>;
          if constexpr (std::is_same_v<T, bool>)
            lua_pushboolean(L, val ? 1 : 0);
          else if constexpr (std::is_same_v<T, std::int64_t>)
            lua_pushnumber(L, static_cast<double>(val));
          else if constexpr (std::is_same_v<T, double>)
            lua_pushnumber(L, val);
          else if constexpr (std::is_same_v<T, std::string>)
            lua_pushlstring(L, val.data(), val.size());
          else if constexpr (std::is_same_v<T, std::vector<std::string>>) {
            lua_createtable(L, static_cast<int>(val.size()), 0);
            for (size_t i = 0; i < val.size(); ++i) {
              lua_pushlstring(L, val[i].data(), val[i].size());
              lua_rawseti(L, -2, static_cast<int>(i + 1));
            }
          }
        },
        it->second);
    return 1;
  }

  const luaL_Reg kWidgetLib[] = {
      {"setText", luau_setText},
      {"setGlyph", luau_setGlyph},
      {"setGlyphCodepoint", luau_setGlyphCodepoint},
      {"setColor", luau_setColor},
      {"setGlyphColor", luau_setGlyphColor},
      {"isVertical", luau_isVertical},
      {"setUpdateInterval", luau_setUpdateInterval},
      {"setVisible", luau_setVisible},
      {"getConfig", luau_getConfig},
      {nullptr, nullptr},
  };

} // namespace

void registerScriptedWidgetBindings(lua_State* L, ScriptedWidget* widget) {
  lua_pushlightuserdata(L, widget);
  lua_setglobal(L, kWidgetKey);

  luaL_register(L, "barWidget", kWidgetLib);
  lua_pop(L, 1);
}
