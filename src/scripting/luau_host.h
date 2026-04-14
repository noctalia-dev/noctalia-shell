#pragma once

#include <optional>
#include <string>
#include <string_view>

struct lua_State;

class LuauHost {
public:
  LuauHost();
  ~LuauHost();

  LuauHost(const LuauHost&) = delete;
  LuauHost& operator=(const LuauHost&) = delete;

  // Compile and load `source` as a chunk named `chunkName`. The chunk is left
  // on the Lua stack as a callable; call run() to execute it.
  // Returns true on success; on failure the error is logged.
  bool loadString(std::string_view chunkName, std::string_view source);

  // Pop the chunk from loadString() and pcall it with no args / no results.
  bool run();

  // Convenience: loadString + run.
  bool exec(std::string_view chunkName, std::string_view source) { return loadString(chunkName, source) && run(); }

  // Look up a global function by name and pcall it with no args.
  // If the function returns a string, it is returned; otherwise nullopt.
  std::optional<std::string> callGlobalReturningString(const char* name);

  lua_State* state() { return m_T; }

private:
  lua_State* m_L = nullptr;  // main state, frozen by luaL_sandbox
  lua_State* m_T = nullptr;  // sandboxed thread; user code runs here
  int m_threadRef = -1;      // registry ref pinning m_T against the GC
};
