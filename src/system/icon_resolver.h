#pragma once

#include <set>
#include <string>
#include <unordered_map>
#include <vector>

class IconResolver {
public:
  IconResolver();

  const std::string& resolve(const std::string& iconName);

private:
  void detectTheme();
  void buildThemeSearchPaths(const std::string& themeName, std::set<std::string>& visited);
  std::string findIcon(const std::string& name) const;

  std::unordered_map<std::string, std::string> m_cache;
  std::vector<std::string> m_baseDirs;   // ~/.local/share/icons, /usr/share/icons, etc.
  std::vector<std::string> m_searchDirs; // Ordered list of concrete dirs to search
  std::string m_empty;
};
