# Luau (vendored)

Source: https://github.com/luau-lang/luau
Tag: `0.716`
License: MIT (see `LICENSE.txt`, plus `lua_LICENSE.txt` for upstream Lua)

## Pruned

Only the components needed to compile and execute Luau scripts are kept:
- `VM/` — bytecode interpreter
- `Compiler/` — Luau → bytecode
- `Ast/` — parser/lexer (Compiler depends on it)
- `Common/` — shared headers + StringUtils

Removed: `Analysis/`, `CodeGen/`, `CLI/`, `Config/`, `Require/`, `extern/`,
`bench/`, `fuzz/`, `tests/`, `tools/`, `Sources.cmake`, `CMakeLists.txt`,
`Makefile`. CodeGen (native JIT) can be added later if profiling demands it.
