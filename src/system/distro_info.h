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

// Best-effort pretty label for the running distribution.
[[nodiscard]] std::string distroLabel();

// Kernel release string (uname -r), or "unknown" on failure.
[[nodiscard]] std::string kernelRelease();

// Approximate OS install age, formatted as "{y}y {m}mo" / "{y}y" / "{d}d".
[[nodiscard]] std::string osAgeLabel();

// Display name of the current session user (gecos or login).
[[nodiscard]] std::string sessionDisplayName();

// Machine hostname (uname nodename), or "unknown" on failure.
[[nodiscard]] std::string hostName();
