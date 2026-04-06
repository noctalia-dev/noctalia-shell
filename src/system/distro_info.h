#pragma once

#include <optional>
#include <string>

struct DistroInfo {
  std::string id;
  std::string name;
  std::string version;
  std::string prettyName;
};

class DistroDetector {
public:
  [[nodiscard]] static std::optional<DistroInfo> detect();
};
