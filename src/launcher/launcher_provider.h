#pragma once

#include <string>
#include <string_view>
#include <vector>

struct LauncherCategory {
  std::string label;
  std::string glyphName;
};

struct LauncherResult {
  std::string id;
  std::string providerId; // Set by LauncherPanel after query; used for activation dispatch and usage tracking
  std::string title;
  std::string subtitle;
  std::string glyphName;
  std::string iconName;
  std::string iconPath;
  std::string actionText;
  // When launching an application via AppProvider, matches DesktopAction::id (primary Exec leaves this empty).
  std::string desktopActionId;
  std::string category;
  double score = 0.0;
  int recentlyUsedIndex = 0; // Higher is more recent. <=0 means no record or too old.
};

class LauncherProvider {
public:
  virtual ~LauncherProvider() = default;

  [[nodiscard]] virtual std::string_view prefix() const = 0;
  // Stable opaque identity. Keys usage-tracking persistence and activation dispatch,
  // so it must never change or be translated.
  [[nodiscard]] virtual std::string_view id() const = 0;
  // Localizable title shown to the user (e.g. the prefix overview). Defaults to the
  // stable id(); override to return a translated string.
  [[nodiscard]] virtual std::string displayName() const { return std::string(id()); }
  [[nodiscard]] virtual std::string_view defaultGlyphName() const { return "search"; }

  // Return true to opt in to usage-based score boosting. The panel will
  // record each activation and surface frequently used entries higher.
  [[nodiscard]] virtual bool trackUsage() const { return false; }

  // Prefixed providers (non-empty prefix()) normally only respond when their prefix is typed.
  // Return true to also contribute results to the general (non-prefixed) search.
  [[nodiscard]] virtual bool includeInGlobalSearch() const { return false; }

  [[nodiscard]] virtual std::vector<LauncherCategory> categories() const { return {}; }

  virtual void initialize() {}

  [[nodiscard]] virtual std::vector<LauncherResult> query(std::string_view text) const = 0;

  virtual bool activate(const LauncherResult& result) = 0;
};
