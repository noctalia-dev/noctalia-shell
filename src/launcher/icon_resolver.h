#pragma once

#include <string>
#include <unordered_map>
#include <vector>

class IconResolver {
public:
  IconResolver();

  const std::string& resolve(const std::string& iconName);

private:
  std::string findIcon(const std::string& name) const;
  void detectTheme();

  std::unordered_map<std::string, std::string> m_cache;
  std::string m_themeName;
  std::vector<std::string> m_themeDirs;
  std::string m_empty;
};
