#include "launcher/icon_resolver.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string_view>

namespace fs = std::filesystem;

namespace {

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
      std::string_view value(buf);
      // Output is like: 'Copycat-noctalia'\n — strip quotes and whitespace
      while (!value.empty() && (value.front() == '\'' || value.front() == '"' || value.front() == ' '))
        value = value.substr(1);
      while (!value.empty() && (value.back() == '\'' || value.back() == '"' || value.back() == ' ' || value.back() == '\n'))
        value = value.substr(0, value.size() - 1);
      if (!value.empty()) {
        candidates.emplace_back(value);
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
        std::string_view value(line.data() + eq + 1, line.size() - eq - 1);
        while (!value.empty() && value.front() == ' ') value = value.substr(1);
        while (!value.empty() && value.back() == ' ')  value = value.substr(0, value.size() - 1);
        if (!value.empty()) {
          candidates.emplace_back(value);
        }
      }
    }
  }

  return candidates;
}

// Parse index.theme and return (subdir paths sorted by preference, parent theme names).
// Preference: scalable/large dirs first so we get crisp icons at any size.
std::pair<std::vector<std::string>, std::vector<std::string>>
parseIndexTheme(const std::string& themeRoot) {
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
        // Parse comma-separated list
        std::size_t start = 0;
        while (start < value.size()) {
          auto comma = value.find(',', start);
          auto name = (comma == std::string_view::npos) ? value.substr(start) : value.substr(start, comma - start);
          if (!name.empty()) {
            dirNames.emplace_back(name);
            dirMap[std::string(name)].path = std::string(name);
          }
          if (comma == std::string_view::npos) break;
          start = comma + 1;
        }
      } else if (key == "Inherits") {
        std::size_t start = 0;
        while (start < value.size()) {
          auto comma = value.find(',', start);
          auto name = (comma == std::string_view::npos) ? value.substr(start) : value.substr(start, comma - start);
          if (!name.empty()) {
            inherits.emplace_back(name);
          }
          if (comma == std::string_view::npos) break;
          start = comma + 1;
        }
      }
    } else if (!currentSection.empty() && dirMap.count(currentSection)) {
      auto& entry = dirMap[currentSection];
      if (key == "Size") {
        try { entry.size = std::stoi(std::string(value)); } catch (...) {}
      } else if (key == "Type") {
        entry.scalable = (value == "Scalable" || value == "Threshold");
      } else if (key == "MaxSize") {
        // For threshold/scalable dirs, MaxSize gives a better sense of actual size
        int maxSize = 0;
        try { maxSize = std::stoi(std::string(value)); } catch (...) {}
        if (maxSize > entry.size) entry.size = maxSize;
      }
    }
  }

  // Sort dirs: scalable first, then by size descending
  std::stable_sort(dirNames.begin(), dirNames.end(), [&](const std::string& a, const std::string& b) {
    const auto& da = dirMap[a];
    const auto& db = dirMap[b];
    if (da.scalable != db.scalable) return da.scalable > db.scalable;
    return da.size > db.size;
  });

  std::vector<std::string> sortedPaths;
  sortedPaths.reserve(dirNames.size());
  for (const auto& name : dirNames) {
    sortedPaths.push_back(name);
  }

  return {sortedPaths, inherits};
}

} // namespace

IconResolver::IconResolver() {
  detectTheme();
}

void IconResolver::detectTheme() {
  const char* home = std::getenv("HOME");

  if (home != nullptr) {
    m_baseDirs.push_back(std::string(home) + "/.local/share/icons");
    m_baseDirs.push_back(std::string(home) + "/.icons");
  }
  m_baseDirs.emplace_back("/usr/share/icons");
  m_baseDirs.emplace_back("/usr/local/share/icons");

  std::set<std::string> visited;

  // Use the first candidate theme that actually exists on disk
  for (const auto& candidate : readGtkThemeCandidates()) {
    bool exists = false;
    for (const auto& base : m_baseDirs) {
      if (fs::is_directory(base + "/" + candidate)) {
        exists = true;
        break;
      }
    }
    if (exists) {
      buildThemeSearchPaths(candidate, visited);
      break;
    }
  }

  // hicolor is the mandatory base theme — always include it last
  buildThemeSearchPaths("hicolor", visited);
}

void IconResolver::buildThemeSearchPaths(const std::string& themeName, std::set<std::string>& visited) {
  if (visited.count(themeName)) {
    return;
  }
  visited.insert(themeName);

  for (const auto& base : m_baseDirs) {
    std::string themeRoot = base + "/" + themeName;
    if (!fs::is_directory(themeRoot)) {
      continue;
    }

    auto [dirs, inherits] = parseIndexTheme(themeRoot);

    if (dirs.empty()) {
      // No index.theme — fall back to common paths so the theme isn't silently skipped
      for (const char* p : {"/scalable/apps/", "/48x48/apps/", "/64x64/apps/",
                             "/128x128/apps/", "/256x256/apps/", "/32x32/apps/"}) {
        m_searchDirs.push_back(themeRoot + p);
      }
    } else {
      for (const auto& dir : dirs) {
        m_searchDirs.push_back(themeRoot + "/" + dir + "/");
      }
    }

    // Follow parent themes
    for (const auto& parent : inherits) {
      buildThemeSearchPaths(parent, visited);
    }
  }
}

const std::string& IconResolver::resolve(const std::string& iconName) {
  if (iconName.empty()) {
    return m_empty;
  }
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
  for (const auto& ext : extensions) {
    std::string path = "/usr/share/pixmaps/" + name + ext;
    if (fs::exists(path)) {
      return path;
    }
  }

  return {};
}
