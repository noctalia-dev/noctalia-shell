#pragma once

#include <string>
#include <string_view>
#include <unordered_map>

class DependencyService {
public:
  DependencyService();

  [[nodiscard]] bool has(std::string_view name) const;
  [[nodiscard]] bool hasWlsunset() const { return has("wlsunset"); }

  void rescan();

private:
  std::unordered_map<std::string, bool> m_present;
};
