#include "system/icon_resolver.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <set>
#include <string_view>
#include <utility>

namespace fs = std::filesystem;

namespace {

  struct IconThemePlan {
    std::vector<std::string> baseDirs;
    std::vector<std::string> searchDirs;
    std::vector<std::string> pixmapDirs;
    std::string activeTheme;
    std::string signature;
  };

  struct IconThemeState {
    bool initialized = false;
    std::uint64_t generation = 1;
    IconThemePlan plan;
  };

  IconThemeState& iconThemeState() {
    static IconThemeState state;
    return state;
  }

  std::string trim(std::string_view value) {
    while (!value.empty() && (value.front() == '\'' || value.front() == '"' || value.front() == ' ' ||
                              value.front() == '\t' || value.front() == '\r' || value.front() == '\n')) {
      value = value.substr(1);
    }
    while (!value.empty() && (value.back() == '\'' || value.back() == '"' || value.back() == ' ' ||
                              value.back() == '\t' || value.back() == '\r' || value.back() == '\n')) {
      value = value.substr(0, value.size() - 1);
    }
    return std::string(value);
  }

  void pushUnique(std::vector<std::string>& values, std::string value) {
    if (value.empty()) {
      return;
    }
    if (std::find(values.begin(), values.end(), value) == values.end()) {
      values.push_back(std::move(value));
    }
  }

  std::vector<std::string> splitList(std::string_view value, char separator) {
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (start <= value.size()) {
      const auto next = value.find(separator, start);
      const auto part = next == std::string_view::npos ? value.substr(start) : value.substr(start, next - start);
      const std::string trimmed = trim(part);
      if (!trimmed.empty()) {
        parts.push_back(trimmed);
      }
      if (next == std::string_view::npos) {
        break;
      }
      start = next + 1;
    }
    return parts;
  }

  std::vector<std::string> xdgDataDirs() {
    std::vector<std::string> dirs;

    const char* dataHome = std::getenv("XDG_DATA_HOME");
    if (dataHome != nullptr && dataHome[0] != '\0') {
      pushUnique(dirs, dataHome);
    } else if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
      pushUnique(dirs, std::string(home) + "/.local/share");
    }

    const char* dataDirs = std::getenv("XDG_DATA_DIRS");
    if (dataDirs != nullptr && dataDirs[0] != '\0') {
      for (auto dir : splitList(dataDirs, ':')) {
        pushUnique(dirs, std::move(dir));
      }
    } else {
      pushUnique(dirs, "/usr/local/share");
      pushUnique(dirs, "/usr/share");
    }

    return dirs;
  }

  std::vector<std::string> iconBaseDirs(const std::vector<std::string>& dataDirs) {
    std::vector<std::string> roots;
    if (!dataDirs.empty()) {
      pushUnique(roots, dataDirs.front() + "/icons");
    }
    if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
      pushUnique(roots, std::string(home) + "/.icons");
    }
    for (std::size_t i = dataDirs.empty() ? 0 : 1; i < dataDirs.size(); ++i) {
      pushUnique(roots, dataDirs[i] + "/icons");
    }
    return roots;
  }

  std::vector<std::string> pixmapDirs(const std::vector<std::string>& dataDirs) {
    std::vector<std::string> roots;
    for (const auto& dataDir : dataDirs) {
      pushUnique(roots, dataDir + "/pixmaps");
      pushUnique(roots, dataDir + "/pixmaps/distribution-logos");
    }
    return roots;
  }

  std::string signatureFor(const IconThemePlan& plan) {
    std::string signature = plan.activeTheme;
    signature += '\n';
    for (const auto& root : plan.baseDirs) {
      signature += "root:";
      signature += root;
      signature += '\n';
    }
    for (const auto& dir : plan.searchDirs) {
      signature += "theme:";
      signature += dir;
      signature += '\n';
    }
    for (const auto& dir : plan.pixmapDirs) {
      signature += "pixmap:";
      signature += dir;
      signature += '\n';
    }
    return signature;
  }

  // Returns theme name candidates in priority order:
  //   1. GSettings (the canonical source used by compositors and other launchers)
  //   2. GTK3 ini file (reliable fallback)
  //   3. GTK4 ini file (may be stale)
  std::vector<std::string> readGtkThemeCandidates() {
    std::vector<std::string> candidates;

    // 1. GSettings via CLI — most reliable, matches what fuzzel and other tools use
    if (FILE* pipe = popen("gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null", "r")) {
      char buf[256] = {};
      if (fgets(buf, sizeof(buf), pipe) != nullptr) {
        std::string value = trim(buf);
        if (!value.empty()) {
          candidates.emplace_back(std::move(value));
        }
      }
      pclose(pipe);
    }

    // 2. GTK ini files
    const char* home = std::getenv("HOME");
    if (home != nullptr) {
      for (const char* cfg : {"/.config/gtk-3.0/settings.ini", "/.config/gtk-4.0/settings.ini"}) {
        std::ifstream file(std::string(home) + cfg);
        if (!file.is_open()) {
          continue;
        }
        std::string line;
        while (std::getline(file, line)) {
          if (!line.starts_with("gtk-icon-theme-name")) {
            continue;
          }
          auto eq = line.find('=');
          if (eq == std::string::npos) {
            continue;
          }
          std::string value = trim(std::string_view(line.data() + eq + 1, line.size() - eq - 1));
          if (!value.empty()) {
            candidates.emplace_back(std::move(value));
          }
        }
      }
    }

    return candidates;
  }

  // Parse index.theme and return (subdir paths sorted by preference, parent theme names).
  // Preference: scalable/large dirs first so we get crisp icons at any size.
  std::pair<std::vector<std::string>, std::vector<std::string>> parseIndexTheme(const std::string& themeRoot) {
    std::ifstream file(themeRoot + "/index.theme");
    if (!file.is_open()) {
      return {};
    }

    struct DirEntry {
      std::string path;
      int size = 0;
      bool scalable = false;
    };

    std::vector<std::string> dirNames;
    std::vector<std::string> inherits;
    std::unordered_map<std::string, DirEntry> dirMap;

    std::string currentSection;
    std::string line;
    while (std::getline(file, line)) {
      while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
        line.pop_back();
      }
      if (line.empty() || line[0] == '#') {
        continue;
      }
      if (line[0] == '[') {
        currentSection = line.substr(1, line.size() - 2);
        continue;
      }
      auto eq = line.find('=');
      if (eq == std::string::npos) {
        continue;
      }
      std::string_view key(line.data(), eq);
      std::string_view value(line.data() + eq + 1, line.size() - eq - 1);

      if (currentSection == "Icon Theme") {
        if (key == "Directories") {
          for (auto name : splitList(value, ',')) {
            dirNames.emplace_back(name);
            dirMap[std::move(name)].path = dirNames.back();
          }
        } else if (key == "Inherits") {
          for (auto name : splitList(value, ',')) {
            inherits.emplace_back(std::move(name));
          }
        }
      } else if (!currentSection.empty() && dirMap.count(currentSection)) {
        auto& entry = dirMap[currentSection];
        if (key == "Size") {
          try {
            entry.size = std::stoi(std::string(value));
          } catch (...) {
          }
        } else if (key == "Type") {
          entry.scalable = (value == "Scalable" || value == "Threshold");
        } else if (key == "MaxSize") {
          // For threshold/scalable dirs, MaxSize gives a better sense of actual size
          int maxSize = 0;
          try {
            maxSize = std::stoi(std::string(value));
          } catch (...) {
          }
          if (maxSize > entry.size)
            entry.size = maxSize;
        }
      }
    }

    // Sort dirs: scalable first, then by size descending
    std::stable_sort(dirNames.begin(), dirNames.end(), [&](const std::string& a, const std::string& b) {
      const auto& da = dirMap[a];
      const auto& db = dirMap[b];
      if (da.scalable != db.scalable)
        return da.scalable > db.scalable;
      return da.size > db.size;
    });

    std::vector<std::string> sortedPaths;
    sortedPaths.reserve(dirNames.size());
    for (const auto& name : dirNames) {
      sortedPaths.push_back(name);
    }

    return {sortedPaths, inherits};
  }

  void buildThemeSearchPaths(const std::string& themeName, const std::vector<std::string>& baseDirs,
                             std::set<std::string>& visited, std::vector<std::string>& searchDirs) {
    if (visited.count(themeName)) {
      return;
    }
    visited.insert(themeName);

    for (const auto& base : baseDirs) {
      const std::string themeRoot = base + "/" + themeName;
      if (!fs::is_directory(themeRoot)) {
        continue;
      }

      auto [dirs, inherits] = parseIndexTheme(themeRoot);

      if (dirs.empty()) {
        // No index.theme — fall back to common paths so the theme isn't silently skipped
        for (const char* path :
             {"/scalable/apps/", "/48x48/apps/", "/64x64/apps/", "/128x128/apps/", "/256x256/apps/", "/32x32/apps/"}) {
          pushUnique(searchDirs, themeRoot + path);
        }
      } else {
        for (const auto& dir : dirs) {
          pushUnique(searchDirs, themeRoot + "/" + dir + "/");
        }
      }

      for (const auto& parent : inherits) {
        buildThemeSearchPaths(parent, baseDirs, visited, searchDirs);
      }
    }
  }

  IconThemePlan buildThemePlan() {
    IconThemePlan plan;
    const auto dataDirs = xdgDataDirs();
    plan.baseDirs = iconBaseDirs(dataDirs);
    plan.pixmapDirs = pixmapDirs(dataDirs);

    std::set<std::string> visited;

    // Use the first candidate theme that actually exists on disk
    for (const auto& candidate : readGtkThemeCandidates()) {
      bool exists = false;
      for (const auto& base : plan.baseDirs) {
        if (fs::is_directory(base + "/" + candidate)) {
          exists = true;
          break;
        }
      }
      if (exists) {
        plan.activeTheme = candidate;
        buildThemeSearchPaths(candidate, plan.baseDirs, visited, plan.searchDirs);
        break;
      }
    }

    // hicolor is the mandatory base theme — always include it last
    buildThemeSearchPaths("hicolor", plan.baseDirs, visited, plan.searchDirs);
    plan.signature = signatureFor(plan);
    return plan;
  }

  void ensureThemeState() {
    auto& state = iconThemeState();
    if (!state.initialized) {
      state.plan = buildThemePlan();
      state.initialized = true;
    }
  }

} // namespace

IconResolver::IconResolver() { rebuild(); }

bool IconResolver::checkThemeChanged() {
  auto& state = iconThemeState();
  IconThemePlan next = buildThemePlan();
  if (!state.initialized) {
    state.plan = std::move(next);
    state.initialized = true;
    return false;
  }
  if (next.signature == state.plan.signature) {
    return false;
  }

  state.plan = std::move(next);
  ++state.generation;
  return true;
}

std::uint64_t IconResolver::themeGeneration() {
  ensureThemeState();
  return iconThemeState().generation;
}

void IconResolver::rebuild() {
  ensureThemeState();
  const auto& state = iconThemeState();
  m_baseDirs = state.plan.baseDirs;
  m_searchDirs = state.plan.searchDirs;
  m_pixmapDirs = state.plan.pixmapDirs;
  m_cache.clear();
  m_generation = state.generation;
}

void IconResolver::ensureFresh() {
  if (m_generation != themeGeneration()) {
    rebuild();
  }
}

const std::string& IconResolver::resolve(const std::string& iconName) {
  if (iconName.empty()) {
    return m_empty;
  }
  ensureFresh();
  auto it = m_cache.find(iconName);
  if (it != m_cache.end()) {
    return it->second;
  }
  auto [ins, _] = m_cache.emplace(iconName, findIcon(iconName));
  return ins->second;
}

std::string IconResolver::findIcon(const std::string& name) const {
  // Absolute path — use directly
  if (!name.empty() && name[0] == '/') {
    return fs::exists(name) ? name : std::string{};
  }

  static const std::vector<std::string> extensions = {".svg", ".png"};

  for (const auto& dir : m_searchDirs) {
    for (const auto& ext : extensions) {
      std::string path = dir + name + ext;
      if (fs::exists(path)) {
        return path;
      }
    }
  }

  // Fallback: pixmaps
  for (const auto& dir : m_pixmapDirs) {
    for (const auto& ext : extensions) {
      std::string path = dir + "/" + name + ext;
      if (fs::exists(path)) {
        return path;
      }
    }
  }

  return {};
}
