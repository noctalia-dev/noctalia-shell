#include "shell/dock/pinned_apps.h"

#include "core/log.h"
#include "system/app_identity.h"
#include "system/internal_app_metadata.h"
#include "util/string_utils.h"

#include <algorithm>

namespace shell::dock::pinned_apps {
  namespace {

    constexpr Logger kLog("dock");

    [[nodiscard]] std::string legacyStemLower(const DesktopEntry& entry) {
      const auto slash = entry.id.rfind('/');
      const auto base = (slash == std::string::npos) ? entry.id : entry.id.substr(slash + 1);
      const auto dot = base.rfind('.');
      return StringUtils::toLower((dot == std::string::npos) ? base : base.substr(0, dot));
    }

    [[nodiscard]] DesktopEntry placeholderEntry(std::string_view pinnedId, std::string_view pinnedLower) {
      DesktopEntry placeholder;
      placeholder.id = std::string(pinnedId);
      placeholder.name = std::string(pinnedId);
      placeholder.nameLower = std::string(pinnedLower);
      return placeholder;
    }

    [[nodiscard]] bool matchesEntryLower(const DesktopEntry& entry, std::string_view pinnedLower) {
      if (pinnedLower.empty()) {
        return false;
      }

      return pinnedLower == legacyStemLower(entry) || app_identity::desktopEntryMatchesLower(entry, pinnedLower);
    }

  } // namespace

  bool matchesEntry(const DesktopEntry& entry, std::string_view pinnedId) {
    if (pinnedId.empty()) {
      return false;
    }

    const std::string pinnedLower = StringUtils::toLower(std::string(pinnedId));
    return matchesEntryLower(entry, pinnedLower);
  }

  bool containsEntry(const std::vector<std::string>& pinned, const DesktopEntry& entry) {
    return std::ranges::any_of(pinned, [&](const std::string& pinnedId) { return matchesEntry(entry, pinnedId); });
  }

  void removeEntry(std::vector<std::string>& pinned, const DesktopEntry& entry) {
    std::erase_if(pinned, [&](const std::string& pinnedId) { return matchesEntry(entry, pinnedId); });
  }

  std::vector<DesktopEntry> resolveEntries(const std::vector<std::string>& pinned) {
    std::vector<DesktopEntry> resolved;
    resolved.reserve(pinned.size());

    const auto& entries = desktopEntries();
    for (const auto& pinnedId : pinned) {
      const std::string pinnedLower = StringUtils::toLower(pinnedId);
      const auto match = std::ranges::find_if(entries, [&](const DesktopEntry& entry) {
        return !entry.hidden && !entry.noDisplay && matchesEntryLower(entry, pinnedLower);
      });

      DesktopEntry entry = match != entries.end() ? *match : [&]() {
        kLog.debug("pinned app not found: {}", pinnedId);
        return placeholderEntry(pinnedId, pinnedLower);
      }();
      internal_apps::applyMetadataToDesktopEntry(entry);
      resolved.push_back(std::move(entry));
    }

    return resolved;
  }

} // namespace shell::dock::pinned_apps
