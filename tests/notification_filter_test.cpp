#include "notification/notification_filter.h"

#include <iostream>
#include <string>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

} // namespace

int main() {
  bool ok = true;

  const std::vector<std::string> blacklist = normalizeNotificationBlacklist({" Discord ", "discord", ""});

  ok &= check(blacklist.size() == 1, "blacklist dedupes and normalizes");
  ok &= check(
      notificationMatchesBlacklist(
          blacklist, NotificationFilterFields{.appName = "Discord", .category = std::nullopt, .desktopEntry = std::nullopt}
      ),
      "app name exact match"
  );
  ok &= check(
      notificationMatchesBlacklist(
          blacklist,
          NotificationFilterFields{
              .appName = "My Discord Client",
              .category = std::nullopt,
              .desktopEntry = std::nullopt,
          }
      ),
      "app name substring match"
  );
  ok &= check(
      !notificationMatchesBlacklist(
          blacklist,
          NotificationFilterFields{
              .appName = "Other",
              .category = std::nullopt,
              .desktopEntry = std::optional<std::string_view>{"org.telegram.desktop"},
          }
      ),
      "desktop entry no match"
  );
  ok &= check(
      notificationMatchesBlacklist(
          {"org.telegram.desktop"},
          NotificationFilterFields{
              .appName = "Telegram",
              .category = std::nullopt,
              .desktopEntry = std::optional<std::string_view>{"org.telegram.desktop"},
          }
      ),
      "desktop entry exact match"
  );
  ok &= check(
      notificationMatchesBlacklist(
          {"im.received"},
          NotificationFilterFields{
              .appName = "Chat",
              .category = std::optional<std::string_view>{"im.received"},
              .desktopEntry = std::nullopt,
          }
      ),
      "category exact match"
  );

  const auto allUrgencies = normalizeAllowedUrgencies({});
  ok &= check(urgencyIsAllowed(allUrgencies, Urgency::Low), "empty allowed list permits low");
  ok &= check(urgencyIsAllowed(allUrgencies, Urgency::Critical), "empty allowed list permits critical");

  const auto normalOnly = normalizeAllowedUrgencies({"normal", "invalid"});
  ok &= check(urgencyIsAllowed(normalOnly, Urgency::Normal), "configured normal allowed");
  ok &= check(!urgencyIsAllowed(normalOnly, Urgency::Low), "configured normal excludes low");

  return ok ? 0 : 1;
}
