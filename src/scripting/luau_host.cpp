#include "scripting/luau_host.h"

#include "compositors/compositor_platform.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/process.h"
#include "lua.h"
#include "luacode.h"
#include "lualib.h"
#include "notification/notifications.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {
  Logger kLog{"luau"};
  constexpr const char* kHostKey = "__noctalia_host";
  constexpr auto kDefaultCommandTimeout = std::chrono::milliseconds(5000);
  constexpr auto kMinCommandTimeout = std::chrono::milliseconds(50);
  constexpr auto kMaxCommandTimeout = std::chrono::milliseconds(60000);
  constexpr std::size_t kMaxAsyncCommandOutputBytes = 1024 * 1024;
  constexpr std::size_t kMaxAsyncCommandsPerHost = 8;
  constexpr int kMaxGlobalAsyncCommands = 32;

  std::uint64_t& nextHostId() {
    static std::uint64_t id = 1;
    return id;
  }

  std::unordered_map<std::uint64_t, LuauHost*>& liveHosts() {
    static std::unordered_map<std::uint64_t, LuauHost*> hosts;
    return hosts;
  }

  std::atomic<int>& inFlightAsyncCommands() {
    static std::atomic<int> count{0};
    return count;
  }

  LuauHost* findHost(std::uint64_t hostId) {
    const auto it = liveHosts().find(hostId);
    return it != liveHosts().end() ? it->second : nullptr;
  }

  std::chrono::milliseconds commandTimeoutFromLua(lua_State* L) {
    const double rawTimeout = luaL_optnumber(
        L, 3,
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(kDefaultCommandTimeout).count()));
    const double timeoutMs =
        std::isfinite(rawTimeout) ? rawTimeout : static_cast<double>(kDefaultCommandTimeout.count());
    const double bounded = std::clamp(timeoutMs, static_cast<double>(kMinCommandTimeout.count()),
                                      static_cast<double>(kMaxCommandTimeout.count()));
    return std::chrono::milliseconds(static_cast<int>(bounded));
  }

  void setTableInteger(lua_State* L, const char* key, int value) {
    lua_pushinteger(L, value);
    lua_setfield(L, -2, key);
  }

  void setTableString(lua_State* L, const char* key, const std::string& value) {
    lua_pushlstring(L, value.data(), value.size());
    lua_setfield(L, -2, key);
  }

  void setTableBool(lua_State* L, const char* key, bool value) {
    lua_pushboolean(L, value ? 1 : 0);
    lua_setfield(L, -2, key);
  }

  LuauHost* hostForState(lua_State* L) {
    lua_getglobal(L, kHostKey);
    auto* host = static_cast<LuauHost*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return host;
  }

  int luau_log(lua_State* L) {
    const char* msg = luaL_checkstring(L, 1);
    kLog.info("{}", msg);
    return 0;
  }

  int luau_runAsync(lua_State* L) {
    size_t len = 0;
    const char* cmd = luaL_checklstring(L, 1, &len);
    std::string command(cmd, len);

    if (lua_isnoneornil(L, 2)) {
      bool ok = process::runAsync(command);
      lua_pushboolean(L, ok ? 1 : 0);
      return 1;
    }

    luaL_checktype(L, 2, LUA_TFUNCTION);

    auto* host = hostForState(L);
    if (host == nullptr) {
      lua_pushboolean(L, 0);
      return 1;
    }

    const auto timeout = commandTimeoutFromLua(L);
    const int callbackRef = lua_ref(L, 2);
    bool ok = host->startAsyncCommand(std::move(command), callbackRef, timeout);
    if (!ok) {
      lua_unref(L, callbackRef);
    }
    lua_pushboolean(L, ok ? 1 : 0);
    return 1;
  }

  int luau_commandExists(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    lua_pushboolean(L, process::commandExists(name) ? 1 : 0);
    return 1;
  }

  int luau_flatpakAppInstalled(lua_State* L) {
    size_t len = 0;
    const char* appId = luaL_checklstring(L, 1, &len);
    lua_pushboolean(L, process::flatpakAppInstalled(std::string_view(appId, len)) ? 1 : 0);
    return 1;
  }

  int luau_portalAvailable(lua_State* L) {
    lua_pushboolean(L, process::desktopPortalAvailable() ? 1 : 0);
    return 1;
  }

  int luau_focusedOutputName(lua_State* L) {
    auto* host = hostForState(L);
    if (host == nullptr || host->platform() == nullptr) {
      lua_pushnil(L);
      return 1;
    }

    wl_output* output = host->platform()->preferredInteractiveOutput();
    const auto* info = host->platform()->findOutputByWl(output);
    if (info == nullptr || info->connectorName.empty()) {
      lua_pushnil(L);
      return 1;
    }

    lua_pushlstring(L, info->connectorName.data(), info->connectorName.size());
    return 1;
  }

  int luau_processMatches(lua_State* L) {
    const int count = lua_gettop(L);
    std::vector<std::string> needles;
    needles.reserve(static_cast<std::size_t>(count));
    for (int i = 1; i <= count; ++i) {
      size_t len = 0;
      const char* needle = luaL_checklstring(L, i, &len);
      needles.emplace_back(needle, len);
    }
    lua_pushboolean(L, process::commandLineMatchesAll(needles) ? 1 : 0);
    return 1;
  }

  int luau_notify(lua_State* L) {
    const char* title = luaL_checkstring(L, 1);
    const char* body = luaL_optstring(L, 2, "");
    notify::info("Noctalia", title, body);
    return 0;
  }

  int luau_notifyError(lua_State* L) {
    const char* title = luaL_checkstring(L, 1);
    const char* body = luaL_optstring(L, 2, "");
    notify::error("Noctalia", title, body);
    return 0;
  }

  int luau_getenv(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    const char* val = std::getenv(name);
    if (val)
      lua_pushstring(L, val);
    else
      lua_pushnil(L);
    return 1;
  }

  const luaL_Reg kNoctaliaBaseLib[] = {
      {"log", luau_log},
      {"runAsync", luau_runAsync},
      {"commandExists", luau_commandExists},
      {"processMatches", luau_processMatches},
      {"flatpakAppInstalled", luau_flatpakAppInstalled},
      {"portalAvailable", luau_portalAvailable},
      {"focusedOutputName", luau_focusedOutputName},
      {"notify", luau_notify},
      {"notifyError", luau_notifyError},
      {"getenv", luau_getenv},
      {nullptr, nullptr},
  };

  void registerNoctaliaLib(lua_State* L) {
    luaL_register(L, "noctalia", kNoctaliaBaseLib);
    lua_pop(L, 1);
  }
} // namespace

LuauHost::LuauHost(CompositorPlatform* platform) : m_platform(platform) {
  m_hostId = nextHostId()++;
  liveHosts()[m_hostId] = this;

  m_L = luaL_newstate();
  luaL_openlibs(m_L);
  registerNoctaliaLib(m_L);
  // Freeze main state's stdlib + globals. The thread we create next inherits
  // reads from this frozen table but gets its own writable globals, so the
  // user script can define `function update()` without touching the parent.
  luaL_sandbox(m_L);

  m_T = lua_newthread(m_L);
  luaL_sandboxthread(m_T);
  lua_pushlightuserdata(m_T, this);
  lua_setglobal(m_T, kHostKey);
  // lua_newthread leaves the thread on the main stack; pin it in the registry
  // so the GC can't collect it, then drop the stack reference.
  m_threadRef = lua_ref(m_L, -1);
  lua_pop(m_L, 1);
}

LuauHost::~LuauHost() {
  if (m_hostId != 0) {
    const auto it = liveHosts().find(m_hostId);
    if (it != liveHosts().end() && it->second == this) {
      liveHosts().erase(it);
    }
  }

  if (m_L) {
    if (m_T != nullptr) {
      for (int callbackRef : m_asyncCommandCallbackRefs) {
        lua_unref(m_T, callbackRef);
      }
      m_asyncCommandCallbackRefs.clear();
    }
    if (m_threadRef != -1)
      lua_unref(m_L, m_threadRef);
    lua_close(m_L);
  }
}

bool LuauHost::startAsyncCommand(std::string command, int callbackRef, std::chrono::milliseconds timeout) {
  if (command.empty() || callbackRef <= LUA_REFNIL || m_asyncCommandCallbackRefs.size() >= kMaxAsyncCommandsPerHost) {
    return false;
  }

  auto& globalInFlight = inFlightAsyncCommands();
  int current = globalInFlight.load(std::memory_order_relaxed);
  while (current < kMaxGlobalAsyncCommands) {
    if (globalInFlight.compare_exchange_weak(current, current + 1, std::memory_order_relaxed)) {
      break;
    }
  }
  if (current >= kMaxGlobalAsyncCommands) {
    return false;
  }

  m_asyncCommandCallbackRefs.insert(callbackRef);
  try {
    std::thread([hostId = m_hostId, callbackRef, command = std::move(command), timeout]() mutable {
      auto result =
          process::runSyncWithTimeoutAndOutputLimit({"/bin/sh", "-lc", command}, timeout, kMaxAsyncCommandOutputBytes);
      inFlightAsyncCommands().fetch_sub(1, std::memory_order_relaxed);
      DeferredCall::callLater([hostId, callbackRef, result = std::move(result)]() mutable {
        auto* host = findHost(hostId);
        if (host != nullptr) {
          host->deliverAsyncCommandResult(callbackRef, std::move(result));
        }
      });
    }).detach();
  } catch (...) {
    m_asyncCommandCallbackRefs.erase(callbackRef);
    globalInFlight.fetch_sub(1, std::memory_order_relaxed);
    return false;
  }

  return true;
}

void LuauHost::deliverAsyncCommandResult(int callbackRef, process::RunResult result) {
  if (m_T == nullptr) {
    return;
  }
  const auto it = m_asyncCommandCallbackRefs.find(callbackRef);
  if (it == m_asyncCommandCallbackRefs.end()) {
    return;
  }
  m_asyncCommandCallbackRefs.erase(it);

  lua_getref(m_T, callbackRef);
  lua_unref(m_T, callbackRef);
  if (!lua_isfunction(m_T, -1)) {
    lua_pop(m_T, 1);
    return;
  }

  lua_createtable(m_T, 0, 6);
  setTableInteger(m_T, "exitCode", result.exitCode);
  setTableString(m_T, "stdout", result.out);
  setTableString(m_T, "stderr", result.err);
  setTableBool(m_T, "timedOut", result.timedOut);
  setTableBool(m_T, "stdoutTruncated", result.outTruncated);
  setTableBool(m_T, "stderrTruncated", result.errTruncated);

  int rc = lua_pcall(m_T, 1, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("async command callback failed: {}", err ? err : "(no error)");
    lua_pop(m_T, 1);
  }
}

bool LuauHost::loadString(std::string_view chunkName, std::string_view source) {
  size_t bytecodeSize = 0;
  char* bytecode = luau_compile(source.data(), source.size(), nullptr, &bytecodeSize);
  if (!bytecode) {
    kLog.error("luau_compile returned null for chunk '{}'", std::string(chunkName));
    return false;
  }
  std::string name(chunkName);
  int loadResult = luau_load(m_T, name.c_str(), bytecode, bytecodeSize, 0);
  std::free(bytecode);
  if (loadResult != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("luau_load failed for '{}': {}", name, err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

bool LuauHost::run() {
  int rc = lua_pcall(m_T, 0, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("lua_pcall failed: {}", err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

bool LuauHost::hasGlobal(const char* name) {
  lua_getglobal(m_T, name);
  bool exists = lua_isfunction(m_T, -1);
  lua_pop(m_T, 1);
  return exists;
}

bool LuauHost::callGlobal(const char* name) {
  lua_getglobal(m_T, name);
  if (!lua_isfunction(m_T, -1)) {
    lua_pop(m_T, 1);
    return false;
  }
  int rc = lua_pcall(m_T, 0, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("call to '{}' failed: {}", name, err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

bool LuauHost::callGlobalWithBool(const char* name, bool value) {
  lua_getglobal(m_T, name);
  if (!lua_isfunction(m_T, -1)) {
    lua_pop(m_T, 1);
    return false;
  }
  lua_pushboolean(m_T, value ? 1 : 0);
  int rc = lua_pcall(m_T, 1, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("call to '{}' failed: {}", name, err ? err : "(no error)");
    lua_pop(m_T, 1);
    return false;
  }
  return true;
}

bool LuauHost::callGlobalWithStrings(const char* name, std::string_view first, std::string_view second) {
  lua_getglobal(m_T, name);
  if (!lua_isfunction(m_T, -1)) {
    lua_pop(m_T, 1);
    return false;
  }
  lua_pushlstring(m_T, first.data(), first.size());
  lua_pushlstring(m_T, second.data(), second.size());
  int rc = lua_pcall(m_T, 2, 0, 0);
  if (rc != 0) {
    const char* err = lua_tostring(m_T, -1);
    kLog.error("call to '{}' failed: {}", name, err ? err : "(no error)");
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
    kLog.error("call to '{}' failed: {}", name, err ? err : "(no error)");
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
