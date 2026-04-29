#pragma once

#include <string>
#include <string_view>
#include <vector>

struct LauncherResult {
  std::string id;
  std::string providerName; // Set by LauncherPanel after query; used for activation dispatch and usage tracking
  std::string title;
  std::string subtitle;
  std::string glyphName;
  std::string iconName;
  std::string iconPath;
  std::string actionText;
  int score = 0;
};

class LauncherProvider {
public:
  virtual ~LauncherProvider() = default;

  [[nodiscard]] virtual std::string_view prefix() const = 0;
  [[nodiscard]] virtual std::string_view name() const = 0;

  // Return true to opt in to usage-based score boosting. The panel will
  // record each activation and surface frequently used entries higher.
  [[nodiscard]] virtual bool trackUsage() const { return false; }

  virtual void initialize() {}

  [[nodiscard]] virtual std::vector<LauncherResult> query(std::string_view text) const = 0;

  virtual bool activate(const LauncherResult& result) = 0;
};
