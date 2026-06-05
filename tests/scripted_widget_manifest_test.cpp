#include "lua.h"
#include "luacode.h"
#include "lualib.h"
#include "scripting/scripted_widget_bindings.h"

#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {

  bool expect(bool condition, const char* message) {
    if (!condition) {
      std::cerr << message << '\n';
    }
    return condition;
  }

  bool extractManifest(std::string_view source, scripting::ScriptWidgetManifest& manifest) {
    lua_State* L = luaL_newstate();
    if (L == nullptr) {
      std::cerr << "failed to create Lua state\n";
      return false;
    }
    luaL_openlibs(L);

    scripting::ScriptedWidgetBindingContext context;
    context.manifestExtractionMode = true;
    context.manifestOut = &manifest;
    scripting::registerScriptedWidgetBindings(L, &context);

    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source.data(), source.size(), nullptr, &bytecodeSize);
    if (bytecode == nullptr) {
      std::cerr << "luau_compile returned null\n";
      lua_close(L);
      return false;
    }

    const int loadResult = luau_load(L, "scripted_widget_manifest_test", bytecode, bytecodeSize, 0);
    std::free(bytecode);
    if (loadResult != 0) {
      const char* err = lua_tostring(L, -1);
      std::cerr << "luau_load failed: " << (err != nullptr ? err : "(no error)") << '\n';
      lua_close(L);
      return false;
    }

    (void)lua_pcall(L, 0, 0, 0);
    const bool defined = context.defineCalled;
    lua_close(L);
    return defined;
  }

} // namespace

int main() {
  scripting::ScriptWidgetManifest manifest;
  const std::string_view source = R"lua(
barWidget.define({
  label = "Fixture",
  version = "2.3.4",
  icon = "script",
  description = "Manifest parser test",
  settings = {
    { key = "image_path", type = "file", label = "Image", default = "/tmp/image.png",
      extensions = { ".png", ".jpg" } },
    { key = "output_dir", type = "folder", label = "Output", default = "/tmp/out" },
  },
})
error("manifest extraction should stop before side effects")
)lua";

  bool ok = expect(extractManifest(source, manifest), "manifest was not captured");
  ok = expect(manifest.label == "Fixture", "manifest label mismatch") && ok;
  ok = expect(manifest.version == "2.3.4", "manifest version mismatch") && ok;
  ok = expect(manifest.settings.size() == 2, "manifest setting count mismatch") && ok;
  if (manifest.settings.size() == 2) {
    const auto& file = manifest.settings[0];
    const auto& folder = manifest.settings[1];
    ok = expect(file.type == scripting::ManifestFieldType::File, "file setting type mismatch") && ok;
    ok = expect(file.stringDefault == "/tmp/image.png", "file default mismatch") && ok;
    ok = expect(file.extensions.size() == 2, "file extension count mismatch") && ok;
    if (file.extensions.size() == 2) {
      ok = expect(file.extensions[0] == ".png", "first file extension mismatch") && ok;
      ok = expect(file.extensions[1] == ".jpg", "second file extension mismatch") && ok;
    }
    ok = expect(folder.type == scripting::ManifestFieldType::Folder, "folder setting type mismatch") && ok;
    ok = expect(folder.stringDefault == "/tmp/out", "folder default mismatch") && ok;
  }

  return ok ? 0 : 1;
}
