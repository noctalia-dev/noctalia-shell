#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

class IconResolver {
public:
  IconResolver();

  const std::string& resolve(const std::string& iconName);

  static bool checkThemeChanged();
  static std::uint64_t themeGeneration();

private:
  void rebuild();
  void ensureFresh();
  std::string findIcon(const std::string& name) const;

  std::unordered_map<std::string, std::string> m_cache;
  std::vector<std::string> m_baseDirs;   // XDG icon theme roots
  std::vector<std::string> m_searchDirs; // Ordered list of concrete theme dirs to search
  std::vector<std::string> m_pixmapDirs; // XDG pixmap fallback roots
  std::string m_empty;
  std::uint64_t m_generation = 0;
};
