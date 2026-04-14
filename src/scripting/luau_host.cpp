#include "scripting/luau_host.h"

#include "core/log.h"

#include "lua.h"
#include "luacode.h"
#include "lualib.h"

#include <cstdlib>
#include <string>

namespace {
  Logger log{"luau"};

  int luau_log(lua_State* L) {
    const char* msg = luaL_checkstring(L, 1);
    log.info("{}", msg);
    return 0;
  }

  void registerNoctaLib(lua_State* L) {
    lua_newtable(L);
    lua_pushcfunction(L, luau_log, "log");
    lua_setfield(L, -2, "log");
    lua_setglobal(L, "nocta");
  }
} // namespace

LuauHost::LuauHost() {
  m_L = luaL_newstate();
  luaL_openlibs(m_L);
  registerNoctaLib(m_L);
  // Freeze main state's stdlib + globals. The thread we create next inherits
  // reads from this frozen table but gets its own writable globals, so the
  // user script can define `function update()` without touching the parent.
  luaL_sandbox(m_L);

  m_T = lua_newthread(m_L);
  luaL_sandboxthread(m_T);
  // lua_newthread leaves the thread on the main stack; pin it in the registry
  // so the GC can't collect it, then drop the stack reference.
  m_threadRef = lua_ref(m_L, -1);
  lua_pop(m_L, 1);
}

LuauHost::~LuauHost() {
  if (m_L) {
    if (m_threadRef != -1) lua_unref(m_L, m_threadRef);
    lua_close(m_L);
  }
}

bool LuauHost::loadString(std::string_view chunkName, std::string_view source) {
  size_t bytecodeSize = 0;
  char* bytecode = luau_compile(source.data(), source.size(), nullptr, &bytecodeSize);
  if (!bytecode) {
    log.error("luau_compile returned null for chunk '{}'", std::string(chunkName));
    return false;
  }
  std::string name(chunkName);
  int loadResult = luau_load(m_T, name.c_str(), bytecode, bytecodeSize, 0);
  std::free(bytecode);
  if (loadResult != 0) {
    const char* err = lua_tostring(m_T, -1);
    log.error("luau_load failed for '{}': {}", name, err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

bool LuauHost::run() {
  int rc = lua_pcall(m_T, 0, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    log.error("lua_pcall failed: {}", err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

std::optional<std::string> LuauHost::callGlobalReturningString(const char* name) {
  lua_getglobal(m_T, name);
  if (!lua_isfunction(m_T, -1)) {
    lua_pop(m_T, 1);
    return std::nullopt;
  }
  int rc = lua_pcall(m_T, 0, 1, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    log.error("call to '{}' failed: {}", name, err ? err : "(no error)");
    lua_pop(m_T, 1);
    return std::nullopt;
  }
  std::optional<std::string> result;
  if (lua_isstring(m_T, -1)) {
    size_t len = 0;
    const char* s = lua_tolstring(m_T, -1, &len);
    result = std::string(s, len);
  }
  lua_pop(m_T, 1);
  return result;
}
