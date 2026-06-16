#include "scripting/plugin_manifest.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

namespace {

  bool expect(bool condition, const char* message) {
    if (!condition) {
      std::fprintf(stderr, "plugin_manifest_test: %s\n", message);
    }
    return condition;
  }

  bool expectEq(std::string_view actual, std::string_view expected, const char* message) {
    if (actual != expected) {
      std::fprintf(
          stderr, "plugin_manifest_test: %s\n  actual:   %.*s\n  expected: %.*s\n", message,
          static_cast<int>(actual.size()), actual.data(), static_cast<int>(expected.size()), expected.data()
      );
      return false;
    }
    return true;
  }

  std::filesystem::path makeTempDir() {
    std::string pattern = (std::filesystem::temp_directory_path() / "noctalia-plugin-manifest-XXXXXX").string();
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    char* result = ::mkdtemp(buffer.data());
    return result != nullptr ? std::filesystem::path(result) : std::filesystem::path{};
  }

  bool writeText(const std::filesystem::path& path, std::string_view text) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
      return false;
    }
    out << text;
    return out.good();
  }

} // namespace

int main() {
  const auto root = makeTempDir();
  if (!expect(!root.empty(), "failed to create temp dir")) {
    return 1;
  }

  bool ok = true;
  const auto defaultManifestPath = root / "defaults/plugin.toml";
  ok = writeText(defaultManifestPath, "id = \"me/defaults\"\nname = \"Defaults\"\nmin_noctalia = \"5.0.0\"\n") && ok;

  std::string error;
  const auto defaults = scripting::parsePluginManifest(defaultManifestPath, &error);
  ok = expect(defaults.has_value(), error.empty() ? "failed to parse default manifest" : error.c_str()) && ok;
  if (defaults.has_value()) {
    ok = expectEq(defaults->license, "MIT", "license should default to MIT") && ok;
    ok = expect(!defaults->deprecated, "deprecated should default to false") && ok;
  }

  const auto explicitManifestPath = root / "explicit/plugin.toml";
  ok = writeText(
           explicitManifestPath,
           "id = \"me/explicit\"\n"
           "name = \"Explicit\"\n"
           "min_noctalia = \"5.0.0\"\n"
           "license = \"Apache-2.0\"\n"
           "deprecated = true\n"
       )
      && ok;

  error.clear();
  const auto explicitManifest = scripting::parsePluginManifest(explicitManifestPath, &error);
  ok = expect(explicitManifest.has_value(), error.empty() ? "failed to parse explicit manifest" : error.c_str()) && ok;
  if (explicitManifest.has_value()) {
    ok = expectEq(explicitManifest->license, "Apache-2.0", "license should parse explicit value") && ok;
    ok = expect(explicitManifest->deprecated, "deprecated should parse explicit value") && ok;
  }

  const auto launcherManifestPath = root / "launcher/plugin.toml";
  ok = writeText(
           launcherManifestPath,
           "id = \"me/launcher\"\n"
           "name = \"Launcher\"\n"
           "min_noctalia = \"5.0.0\"\n"
           "[[launcher_provider]]\n"
           "id = \"translate\"\n"
           "entry = \"translate.luau\"\n"
           "prefix = \":tr\"\n"
           "glyph = \"language\"\n"
           "include_in_global_search = true\n"
           "debounce_ms = 300\n"
           "[[launcher_provider.category]]\n"
           "label = \"Languages\"\n"
           "glyph = \"world\"\n"
       )
      && ok;
  error.clear();
  const auto launcherManifest = scripting::parsePluginManifest(launcherManifestPath, &error);
  ok = expect(launcherManifest.has_value(), error.empty() ? "failed to parse launcher manifest" : error.c_str()) && ok;
  if (launcherManifest.has_value() && expect(launcherManifest->entries.size() == 1, "one launcher entry expected")) {
    const auto& entry = launcherManifest->entries.front();
    ok = expect(entry.kind == scripting::PluginEntryKind::LauncherProvider, "entry kind should be LauncherProvider")
        && ok;
    ok = expectEq(entry.launcherPrefix, ":tr", "launcher prefix should parse") && ok;
    ok = expectEq(entry.launcherGlyph, "language", "launcher glyph should parse") && ok;
    ok = expect(entry.launcherGlobalSearch, "include_in_global_search should parse true") && ok;
    ok = expect(entry.launcherDebounceMs == 300, "debounce_ms should parse") && ok;
    ok = expect(entry.launcherCategories.size() == 1, "one launcher category expected") && ok;
    if (!entry.launcherCategories.empty()) {
      ok = expectEq(entry.launcherCategories.front().label, "Languages", "category label should parse") && ok;
      ok = expectEq(entry.launcherCategories.front().glyph, "world", "category glyph should parse") && ok;
    }
  }

  const auto missingNameManifestPath = root / "missing-name/plugin.toml";
  ok = writeText(missingNameManifestPath, "id = \"me/missing-name\"\nmin_noctalia = \"5.0.0\"\n") && ok;
  error.clear();
  const auto missingName = scripting::parsePluginManifest(missingNameManifestPath, &error);
  ok = expect(!missingName.has_value(), "manifest without name should fail") && ok;
  ok = expectEq(error, "missing mandatory key 'name'", "missing name error") && ok;

  std::error_code ec;
  std::filesystem::remove_all(root, ec);
  return ok ? 0 : 1;
}
