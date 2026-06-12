#include "core/process.h"
#include "scripting/plugin_git.h"

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
      std::fprintf(stderr, "plugin_git_export_test: %s\n", message);
    }
    return condition;
  }

  std::filesystem::path makeTempDir() {
    std::string pattern = (std::filesystem::temp_directory_path() / "noctalia-plugin-git-export-XXXXXX").string();
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

  bool runGit(const std::vector<std::string>& args) {
    auto result = process::runSync(args);
    if (!result) {
      std::fprintf(stderr, "plugin_git_export_test: command failed:");
      for (const auto& arg : args) {
        std::fprintf(stderr, " %s", arg.c_str());
      }
      std::fprintf(stderr, "\n%s\n", result.err.c_str());
    }
    return result;
  }

} // namespace

int main() {
  const auto root = makeTempDir();
  if (!expect(!root.empty(), "failed to create temp dir")) {
    return 1;
  }

  const auto source = root / "source";
  const auto repo = root / "repo";
  const auto exported = root / "exported";

  bool ok = true;
  std::filesystem::create_directories(source);
  ok = runGit({"git", "-C", source.string(), "init", "-q"}) && ok;
  ok = writeText(source / "clock/plugin.toml", "id = \"noctalia/clock\"\nversion = \"1\"\nmin_noctalia = \"0\"\n")
      && ok;
  ok = writeText(source / "clock/main.luau", "barWidget.setText(\"ok\")\n") && ok;
  ok = runGit({"git", "-C", source.string(), "add", "clock/plugin.toml", "clock/main.luau"}) && ok;
  ok = runGit(
           {"git", "-C", source.string(), "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit",
            "-q", "-m", "init"}
       )
      && ok;

  const auto cloned = scripting::plugin_git::cloneBlobless(source.string(), repo);
  ok = expect(static_cast<bool>(cloned), "cloneBlobless failed") && ok;

  const auto exportResult = scripting::plugin_git::exportSubdir(repo, "HEAD", "clock", exported);
  ok = expect(static_cast<bool>(exportResult), "exportSubdir failed") && ok;
  ok = expect(std::filesystem::exists(exported / "clock/plugin.toml"), "exported manifest missing") && ok;
  ok = expect(!std::filesystem::exists(repo / "clock/plugin.toml"), "repo cache was checked out") && ok;

  std::error_code ec;
  std::filesystem::remove_all(root, ec);
  return ok ? 0 : 1;
}
