#include "launcher/icon_resolver.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string_view>

namespace fs = std::filesystem;

namespace {

std::string readGtkTheme() {
  const char* home = std::getenv("HOME");
  if (home == nullptr) {
    return "Adwaita";
  }

  // Try GTK 3 settings
  std::ifstream file(std::string(home) + "/.config/gtk-3.0/settings.ini");
  if (!file.is_open()) {
    // Try GTK 4 settings
    file.open(std::string(home) + "/.config/gtk-4.0/settings.ini");
  }
  if (!file.is_open()) {
    return "Adwaita";
  }

  std::string line;
  while (std::getline(file, line)) {
    if (line.compare(0, 16, "gtk-icon-theme-name") == 0) {
      auto eq = line.find('=');
      if (eq != std::string::npos) {
        std::string_view value(line.data() + eq + 1, line.size() - eq - 1);
        // Trim whitespace
        while (!value.empty() && value.front() == ' ') {
          value = value.substr(1);
        }
        while (!value.empty() && value.back() == ' ') {
          value = value.substr(0, value.size() - 1);
        }
        if (!value.empty()) {
          return std::string(value);
        }
      }
    }
  }

  return "Adwaita";
}

bool fileExists(const std::string& path) { return fs::exists(path); }

} // namespace

IconResolver::IconResolver() { detectTheme(); }

void IconResolver::detectTheme() {
  m_themeName = readGtkTheme();

  // Build search directories for the theme
  const char* home = std::getenv("HOME");
  std::vector<std::string> baseDirs;

  if (home != nullptr) {
    baseDirs.push_back(std::string(home) + "/.local/share/icons");
    baseDirs.push_back(std::string(home) + "/.icons");
  }
  baseDirs.emplace_back("/usr/share/icons");
  baseDirs.emplace_back("/usr/local/share/icons");

  // Add theme directories and hicolor fallback
  for (const auto& base : baseDirs) {
    m_themeDirs.push_back(base + "/" + m_themeName);
  }
  if (m_themeName != "hicolor") {
    for (const auto& base : baseDirs) {
      m_themeDirs.push_back(base + "/hicolor");
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

  std::string resolved = findIcon(iconName);
  auto [inserted, _] = m_cache.emplace(iconName, std::move(resolved));
  return inserted->second;
}

std::string IconResolver::findIcon(const std::string& name) const {
  // If it's an absolute path, use directly
  if (!name.empty() && name[0] == '/') {
    if (fileExists(name)) {
      return name;
    }
    return {};
  }

  // Preferred sizes for app icons (48px, scalable)
  static const std::vector<std::string> sizePaths = {
      "/48x48/apps/",   "/scalable/apps/", "/64x64/apps/",      "/32x32/apps/",
      "/256x256/apps/", "/128x128/apps/",  "/48x48/mimetypes/", "/scalable/mimetypes/",
  };

  static const std::vector<std::string> extensions = {".svg", ".png"};

  for (const auto& themeDir : m_themeDirs) {
    for (const auto& sizePath : sizePaths) {
      for (const auto& ext : extensions) {
        std::string path = themeDir + sizePath + name + ext;
        if (fileExists(path)) {
          return path;
        }
      }
    }
  }

  // Fallback: pixmaps
  for (const auto& ext : extensions) {
    std::string path = "/usr/share/pixmaps/" + name + ext;
    if (fileExists(path)) {
      return path;
    }
  }

  return {};
}
