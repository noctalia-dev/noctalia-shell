#include "system/app_identity.h"

#include "system/internal_app_metadata.h"
#include "util/string_utils.h"

#include <unordered_set>

namespace app_identity {

  bool matchesLower(std::string_view valueLower, std::string_view idLower, std::string_view startupWmClassLower,
                    std::string_view nameLower) {
    if (valueLower.empty()) {
      return false;
    }
    return valueLower == idLower || valueLower == startupWmClassLower || valueLower == nameLower;
  }

  bool desktopEntryMatchesLower(const DesktopEntry& entry, std::string_view valueLower) {
    return matchesLower(valueLower, StringUtils::toLower(entry.id), StringUtils::toLower(entry.startupWmClass),
                        entry.nameLower);
  }

  DesktopEntry resolveRunningDesktopEntry(std::string_view runningAppId, const std::vector<DesktopEntry>& allEntries) {
    const std::string runningLower = StringUtils::toLower(std::string(runningAppId));

    for (const auto& entry : allEntries) {
      if (entry.hidden || entry.noDisplay) {
        continue;
      }
      if (desktopEntryMatchesLower(entry, runningLower)) {
        return entry;
      }
    }

    DesktopEntry fallback;
    fallback.id = std::string(runningAppId);
    fallback.name = std::string(runningAppId);
    fallback.nameLower = runningLower;
    if (const auto internal = internal_apps::metadataForAppId(std::string(runningAppId)); internal.has_value()) {
      fallback.name = internal->displayName;
      fallback.nameLower = StringUtils::toLower(fallback.name);
      fallback.icon = internal->iconPath;
    }

    return fallback;
  }

  std::vector<ResolvedRunningApp> resolveRunningApps(const std::vector<std::string>& runningAppIds,
                                                     const std::vector<DesktopEntry>& allEntries) {
    std::vector<ResolvedRunningApp> resolved;
    resolved.reserve(runningAppIds.size());

    std::unordered_set<std::string> seen;
    seen.reserve(runningAppIds.size());

    for (const auto& runningAppId : runningAppIds) {
      const std::string runningLower = StringUtils::toLower(runningAppId);
      if (!seen.insert(runningLower).second) {
        continue;
      }

      resolved.push_back(ResolvedRunningApp{
          .runningAppId = runningAppId,
          .runningLower = runningLower,
          .entry = resolveRunningDesktopEntry(runningAppId, allEntries),
      });
    }

    return resolved;
  }

} // namespace app_identity
