#include "scripting/scripted_widget_bindings.h"

#include "lua.h"
#include "lualib.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <variant>

namespace {

  constexpr const char* kWidgetKey = "__scripted_widget";

  scripting::ScriptedWidgetBindingContext* getContext(lua_State* L) {
    lua_getglobal(L, kWidgetKey);
    auto* context = static_cast<scripting::ScriptedWidgetBindingContext*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return context;
  }

  std::string_view optionalStringArg(lua_State* L, int index) {
    if (lua_gettop(L) < index || lua_isnil(L, index)) {
      return {};
    }
    return luaL_checkstring(L, index);
  }

  int luau_setText(lua_State* L) {
    size_t len = 0;
    const char* text = luaL_checklstring(L, 1, &len);
    if (auto* context = getContext(L)) {
      context->patch.text = std::string(text, len);
    }
    return 0;
  }

  int luau_setGlyph(lua_State* L) {
    size_t len = 0;
    const char* name = luaL_checklstring(L, 1, &len);
    if (auto* context = getContext(L)) {
      context->patch.glyph = std::string(name, len);
    }
    return 0;
  }

  int luau_setColor(lua_State* L) {
    size_t len = 0;
    const char* role = luaL_checklstring(L, 1, &len);
    if (auto* context = getContext(L)) {
      context->patch.textColor = scripting::ScriptWidgetColorPatch{.role = std::string(role, len),
                                                                   .mode = std::string(optionalStringArg(L, 2))};
    }
    return 0;
  }

  int luau_setGlyphColor(lua_State* L) {
    size_t len = 0;
    const char* role = luaL_checklstring(L, 1, &len);
    if (auto* context = getContext(L)) {
      context->patch.glyphColor = scripting::ScriptWidgetColorPatch{.role = std::string(role, len),
                                                                    .mode = std::string(optionalStringArg(L, 2))};
    }
    return 0;
  }

  int luau_isVertical(lua_State* L) {
    auto* context = getContext(L);
    lua_pushboolean(L, context != nullptr && context->snapshot.isVertical ? 1 : 0);
    return 1;
  }

  int luau_setUpdateInterval(lua_State* L) {
    auto ms = static_cast<float>(luaL_checknumber(L, 1));
    if (auto* context = getContext(L)) {
      context->patch.updateIntervalMs = std::max(16, static_cast<int>(ms));
    }
    return 0;
  }

  int luau_setVisible(lua_State* L) {
    bool visible = lua_toboolean(L, 1) != 0;
    if (auto* context = getContext(L)) {
      context->patch.visible = visible;
    }
    return 0;
  }

  int luau_getConfig(lua_State* L) {
    const char* key = luaL_checkstring(L, 1);
    auto* context = getContext(L);
    if (context == nullptr || context->settings == nullptr) {
      lua_pushnil(L);
      return 1;
    }

    auto it = context->settings->find(key);
    if (it == context->settings->end()) {
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
      {"setColor", luau_setColor},
      {"setGlyphColor", luau_setGlyphColor},
      {"isVertical", luau_isVertical},
      {"setUpdateInterval", luau_setUpdateInterval},
      {"setVisible", luau_setVisible},
      {"getConfig", luau_getConfig},
      {nullptr, nullptr},
  };

} // namespace

namespace scripting {

  void registerScriptedWidgetBindings(lua_State* L, ScriptedWidgetBindingContext* context) {
    lua_pushlightuserdata(L, context);
    lua_setglobal(L, kWidgetKey);

    luaL_register(L, "barWidget", kWidgetLib);
    lua_pop(L, 1);
  }

} // namespace scripting
