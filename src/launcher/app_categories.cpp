#include "launcher/app_categories.h"

#include <algorithm>
#include <array>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

namespace {

  struct CategoryDefinition {
    std::string_view id;
    std::string_view labelKey;
    std::string_view glyphName;
  };

  constexpr std::array<CategoryDefinition, 12> kCategories = {{
      {LauncherAppCategories::All, "launcher.categories.all", "apps"},
      {"AudioVideo", "launcher.categories.audiovideo", "music"},
      {"Chat", "launcher.categories.chat", "message-circle"},
      {"Development", "launcher.categories.development", "code"},
      {"Education", "launcher.categories.education", "school"},
      {"Game", "launcher.categories.game", "device-gamepad"},
      {"Graphics", "launcher.categories.graphics", "brush"},
      {"Network", "launcher.categories.network", "wifi"},
      {"Office", "launcher.categories.office", "file-text"},
      {"System", "launcher.categories.system", "device-desktop"},
      {"Misc", "launcher.categories.misc", "dots"},
      {"WebBrowser", "launcher.categories.webbrowser", "world"},
  }};

  std::vector<std::string_view> splitCategories(std::string_view categories) {
    std::vector<std::string_view> result;
    std::size_t start = 0;
    while (start <= categories.size()) {
      const auto end = categories.find(';', start);
      auto item = end == std::string_view::npos ? categories.substr(start) : categories.substr(start, end - start);
      while (!item.empty() && item.front() == ' ') {
        item.remove_prefix(1);
      }
      while (!item.empty() && item.back() == ' ') {
        item.remove_suffix(1);
      }
      if (!item.empty()) {
        result.push_back(item);
      }
      if (end == std::string_view::npos) {
        break;
      }
      start = end + 1;
    }
    return result;
  }

  bool hasCategory(const std::vector<std::string_view>& categories, std::string_view category) {
    return std::find(categories.begin(), categories.end(), category) != categories.end();
  }

  std::string_view primaryCategory(const DesktopEntry& entry) {
    const auto categories = splitCategories(entry.categories);
    if (categories.empty()) {
      return {};
    }

    if (hasCategory(categories, "AudioVideo") || hasCategory(categories, "Audio") || hasCategory(categories, "Video")) {
      return "AudioVideo";
    }
    if (hasCategory(categories, "Chat") || hasCategory(categories, "InstantMessaging")) {
      return "Chat";
    }
    if (hasCategory(categories, "WebBrowser")) {
      return "WebBrowser";
    }
    if (hasCategory(categories, "Science")) {
      return "Education";
    }
    if (hasCategory(categories, "Settings") || hasCategory(categories, "Utility")) {
      return "System";
    }

    constexpr std::array<std::string_view, 10> kPriority = {
        "Development", "Education", "Game", "Graphics", "Network", "Office", "System", "AudioVideo", "Chat", "Misc"};
    for (const auto category : kPriority) {
      if (hasCategory(categories, category)) {
        return category;
      }
    }

    return "Misc";
  }

  LauncherAppCategory makeCategory(const CategoryDefinition& definition) {
    return LauncherAppCategory{
        std::string(definition.id),
        std::string(definition.labelKey),
        std::string(definition.glyphName),
    };
  }

} // namespace

std::vector<LauncherAppCategory> availableLauncherAppCategories(const std::vector<DesktopEntry>& entries) {
  std::unordered_set<std::string_view> present;
  for (const auto& entry : entries) {
    const auto category = primaryCategory(entry);
    if (!category.empty()) {
      present.insert(category);
    }
  }

  std::vector<LauncherAppCategory> result;
  result.push_back(makeCategory(kCategories.front()));
  for (std::size_t i = 1; i < kCategories.size(); ++i) {
    if (present.contains(kCategories[i].id)) {
      result.push_back(makeCategory(kCategories[i]));
    }
  }
  return result;
}

bool launcherAppEntryMatchesCategory(const DesktopEntry& entry, std::string_view category) {
  if (category.empty() || category == LauncherAppCategories::All) {
    return true;
  }

  const auto categories = splitCategories(entry.categories);
  if (category == "AudioVideo") {
    return hasCategory(categories, "AudioVideo") || hasCategory(categories, "Audio") ||
           hasCategory(categories, "Video");
  }
  if (category == "Education") {
    return hasCategory(categories, "Education") || hasCategory(categories, "Science");
  }
  if (category == "System") {
    return hasCategory(categories, "System") || hasCategory(categories, "Settings") ||
           hasCategory(categories, "Utility");
  }

  return primaryCategory(entry) == category;
}
