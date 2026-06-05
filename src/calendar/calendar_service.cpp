#include "calendar/calendar_service.h"

#include "calendar/caldav_client.h"
#include "config/config_service.h"
#include "core/log.h"
#include "json.hpp"
#include "net/http_client.h"
#include "net/url_open.h"

#include <algorithm>
#include <charconv>
#include <cstdlib>
#include <fstream>

namespace {
  constexpr Logger kLog("calendar");
  constexpr const char* kCredentialOwner = "calendar_credentials";
  constexpr auto kConnectPollInterval = std::chrono::seconds{2};
  constexpr auto kWindowBefore = std::chrono::hours{24 * 31};
  constexpr auto kWindowAfter = std::chrono::hours{24 * 90};

  std::int64_t toUnix(std::chrono::system_clock::time_point tp) {
    return std::chrono::duration_cast<std::chrono::seconds>(tp.time_since_epoch()).count();
  }

  std::chrono::system_clock::time_point fromUnix(std::int64_t seconds) {
    return std::chrono::system_clock::time_point{std::chrono::seconds{seconds}};
  }
} // namespace

CalendarService::CalendarService(ConfigService& configService, HttpClient& httpClient)
    : m_configService(configService), m_httpClient(httpClient), m_oauth(httpClient), m_google(httpClient) {}

void CalendarService::initialize() {
  m_activeConfig = m_configService.config().calendar;
  m_configService.addReloadCallback([this]() { onConfigReload(); });
  loadCache();
  if (m_activeConfig.enabled) {
    m_nextRefreshAt = std::chrono::steady_clock::now();
  }
}

void CalendarService::addChangeCallback(ChangeCallback callback) {
  if (callback) {
    m_callbacks.push_back(std::move(callback));
  }
}

void CalendarService::notifyChanged() {
  for (auto& callback : m_callbacks) {
    if (callback) {
      callback();
    }
  }
}

void CalendarService::onConfigReload() {
  const CalendarConfig& next = m_configService.config().calendar;
  if (next == m_activeConfig) {
    return;
  }
  m_activeConfig = next;
  if (!m_activeConfig.enabled) {
    m_eventsByAccount.clear();
    m_snapshot = CalendarSnapshot{};
    notifyChanged();
    return;
  }
  // Re-sync soon after any account/config change.
  m_nextRefreshAt = std::chrono::steady_clock::now();
  notifyChanged();
}

int CalendarService::pollTimeoutMs() const {
  const auto now = std::chrono::steady_clock::now();

  int timeout = -1;
  const auto consider = [&](std::chrono::steady_clock::time_point when) {
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(when - now).count();
    const int clamped = ms < 0 ? 0 : static_cast<int>(std::min<std::int64_t>(ms, 60000));
    timeout = timeout < 0 ? clamped : std::min(timeout, clamped);
  };

  if (m_connect.state == ConnectState::Pending && !m_connect.inFlight) {
    consider(m_connect.nextPollAt);
  }
  if (m_activeConfig.enabled && !m_refreshing) {
    consider(m_nextRefreshAt);
  }
  return timeout;
}

void CalendarService::tick() {
  const auto now = std::chrono::steady_clock::now();

  if (m_connect.state == ConnectState::Pending && !m_connect.inFlight && now >= m_connect.nextPollAt) {
    if (now >= m_connect.deadline) {
      kLog.warn("google connect timed out for account {}", m_connect.accountId);
      m_connect.state = ConnectState::Failed;
      notifyChanged();
    } else {
      pollConnect();
    }
  }

  if (m_activeConfig.enabled && !m_refreshing && now >= m_nextRefreshAt) {
    startRefresh();
  }
}

void CalendarService::scheduleNextRefresh() {
  const int minutes = std::max<std::int32_t>(1, m_activeConfig.refreshMinutes);
  m_nextRefreshAt = std::chrono::steady_clock::now() + std::chrono::minutes{minutes};
}

void CalendarService::startRefresh() {
  if (m_activeConfig.accounts.empty()) {
    scheduleNextRefresh();
    return;
  }
  m_refreshing = true;
  m_pendingAccounts = m_activeConfig.accounts.size();
  for (const CalendarConfig::Account& account : m_activeConfig.accounts) {
    if (account.type == "caldav") {
      fetchCalDav(account);
    } else if (account.type == "google") {
      fetchGoogle(account);
    } else {
      kLog.warn("unknown calendar account type '{}' for id {}", account.type, account.id);
      accountDone(account.id, false, {});
    }
  }
}

void CalendarService::accountDone(const std::string& accountId, bool ok, std::vector<CalendarEvent> events) {
  if (ok) {
    m_eventsByAccount[accountId] = std::move(events);
  }
  if (m_pendingAccounts > 0) {
    --m_pendingAccounts;
  }
  if (m_pendingAccounts == 0) {
    m_refreshing = false;
    rebuildSnapshot();
    saveCache();
    scheduleNextRefresh();
    notifyChanged();
  }
}

void CalendarService::rebuildSnapshot() {
  // Drop cached events for accounts no longer configured.
  for (auto it = m_eventsByAccount.begin(); it != m_eventsByAccount.end();) {
    const bool stillConfigured = std::any_of(
        m_activeConfig.accounts.begin(), m_activeConfig.accounts.end(),
        [&](const CalendarConfig::Account& a) { return a.id == it->first; }
    );
    it = stillConfigured ? std::next(it) : m_eventsByAccount.erase(it);
  }

  std::vector<CalendarEvent> merged;
  for (const auto& [accountId, events] : m_eventsByAccount) {
    merged.insert(merged.end(), events.begin(), events.end());
  }
  std::sort(merged.begin(), merged.end(), [](const CalendarEvent& a, const CalendarEvent& b) {
    return a.start < b.start;
  });
  m_snapshot.events = std::move(merged);
  m_snapshot.valid = true;
}

void CalendarService::fetchCalDav(const CalendarConfig::Account& account) {
  calendar::CalDavAccount caldav;
  caldav.url = account.url;
  caldav.username = account.username;
  caldav.password = credential(account.id, "password");
  caldav.calendarName = account.displayName;
  caldav.color = account.color;

  if (caldav.url.empty() || caldav.username.empty() || caldav.password.empty()) {
    kLog.warn("caldav account {} is missing url/username/password", account.id);
    accountDone(account.id, false, {});
    return;
  }

  const auto now = std::chrono::system_clock::now();
  const std::string id = account.id;
  calendar::fetchCalDavEvents(
      m_httpClient, caldav, now - kWindowBefore, now + kWindowAfter,
      [this, id](bool ok, std::vector<CalendarEvent> events) { accountDone(id, ok, std::move(events)); }
  );
}

void CalendarService::refreshGoogleToken(const std::string& accountId, std::function<void(bool, std::string)> cb) {
  const std::string refreshToken = credential(accountId, "refresh_token");
  if (refreshToken.empty()) {
    cb(false, {});
    return;
  }
  m_oauth.refresh(
      refreshToken,
      [this, accountId, refreshToken, cb = std::move(cb)](bool ok, bool invalidGrant, calendar::OAuthTokens tokens) {
        if (!ok) {
          if (invalidGrant) {
            kLog.warn("google account {} refresh token rejected; reconnect required", accountId);
            setCredential(accountId, "refresh_token", "");
            setCredential(accountId, "access_token", "");
          }
          cb(false, {});
          return;
        }
        if (tokens.refreshToken.empty()) {
          tokens.refreshToken = refreshToken;
        }
        storeGoogleTokens(accountId, tokens);
        cb(true, tokens.accessToken);
      }
  );
}

void CalendarService::googleFetchWithToken(
    const std::string& accountId, const std::string& accessToken, bool allowRefreshRetry
) {
  const auto now = std::chrono::system_clock::now();
  m_google.fetchEvents(
      accessToken, now - kWindowBefore, now + kWindowAfter,
      [this, accountId, allowRefreshRetry](bool ok, bool unauthorized, std::vector<CalendarEvent> events) {
        if (unauthorized && allowRefreshRetry) {
          refreshGoogleToken(accountId, [this, accountId](bool refreshed, std::string newToken) {
            if (!refreshed) {
              accountDone(accountId, false, {});
            } else {
              googleFetchWithToken(accountId, newToken, false);
            }
          });
          return;
        }
        accountDone(accountId, ok && !unauthorized, std::move(events));
      }
  );
}

void CalendarService::fetchGoogle(const CalendarConfig::Account& account) {
  const std::string id = account.id;
  if (credential(id, "refresh_token").empty()) {
    kLog.info("google account {} is not connected yet; skipping", id);
    accountDone(id, false, {});
    return;
  }

  const std::string accessToken = credential(id, "access_token");
  const std::string expiryRaw = credential(id, "access_expiry");
  std::int64_t expiryUnix = 0;
  std::from_chars(expiryRaw.data(), expiryRaw.data() + expiryRaw.size(), expiryUnix);
  const auto expiry = fromUnix(expiryUnix);
  const bool valid = !accessToken.empty() && expiry > std::chrono::system_clock::now() + std::chrono::seconds{60};

  if (valid) {
    googleFetchWithToken(id, accessToken, true);
  } else {
    refreshGoogleToken(id, [this, id](bool ok, std::string token) {
      if (!ok) {
        accountDone(id, false, {});
      } else {
        googleFetchWithToken(id, token, false);
      }
    });
  }
}

void CalendarService::connectGoogleAccount(const std::string& accountId) {
  const auto it = std::find_if(
      m_activeConfig.accounts.begin(), m_activeConfig.accounts.end(),
      [&](const CalendarConfig::Account& a) { return a.id == accountId && a.type == "google"; }
  );
  if (it == m_activeConfig.accounts.end()) {
    kLog.warn("connectGoogleAccount: no google account with id {}", accountId);
    return;
  }

  m_connect.state = ConnectState::Pending;
  m_connect.accountId = accountId;
  m_connect.inFlight = true;
  m_connect.pollToken.clear();
  notifyChanged();

  m_oauth.start([this](bool ok, calendar::GoogleOAuthBroker::StartResult result) {
    m_connect.inFlight = false;
    if (!ok) {
      m_connect.state = ConnectState::Failed;
      notifyChanged();
      return;
    }
    m_connect.pollToken = result.pollToken;
    const int expiresIn = result.expiresIn > 0 ? result.expiresIn : 600;
    m_connect.deadline = std::chrono::steady_clock::now() + std::chrono::seconds{expiresIn};
    m_connect.nextPollAt = std::chrono::steady_clock::now() + kConnectPollInterval;
    if (!net::openInBrowser(result.authUrl)) {
      kLog.warn("failed to open browser for google consent; url logged at debug");
      kLog.debug("google consent url: {}", result.authUrl);
    }
    notifyChanged();
  });
}

void CalendarService::pollConnect() {
  m_connect.inFlight = true;
  const std::string accountId = m_connect.accountId;
  m_oauth.poll(
      m_connect.pollToken,
      [this, accountId](calendar::GoogleOAuthBroker::PollStatus status, calendar::OAuthTokens tokens) {
        m_connect.inFlight = false;
        if (m_connect.accountId != accountId) {
          return; // a newer flow superseded this one
        }
        using PollStatus = calendar::GoogleOAuthBroker::PollStatus;
        switch (status) {
        case PollStatus::Pending:
          m_connect.nextPollAt = std::chrono::steady_clock::now() + kConnectPollInterval;
          break;
        case PollStatus::Complete:
          storeGoogleTokens(accountId, tokens);
          m_connect.state = ConnectState::Success;
          m_nextRefreshAt = std::chrono::steady_clock::now();
          notifyChanged();
          break;
        case PollStatus::Expired:
        case PollStatus::Error:
          m_connect.state = ConnectState::Failed;
          notifyChanged();
          break;
        }
      }
  );
}

std::string CalendarService::credential(const std::string& accountId, const char* field) const {
  return m_configService.stateString(kCredentialOwner, accountId + "_" + field).value_or(std::string{});
}

void CalendarService::setCredential(const std::string& accountId, const char* field, const std::string& value) {
  m_configService.setStateString(kCredentialOwner, accountId + "_" + field, value);
}

void CalendarService::storeGoogleTokens(const std::string& accountId, const calendar::OAuthTokens& tokens) {
  if (!tokens.refreshToken.empty()) {
    setCredential(accountId, "refresh_token", tokens.refreshToken);
  }
  setCredential(accountId, "access_token", tokens.accessToken);
  setCredential(accountId, "access_expiry", std::to_string(toUnix(tokens.expiry)));
}

std::filesystem::path CalendarService::cacheFilePath() {
  const char* xdgCache = std::getenv("XDG_CACHE_HOME");
  std::filesystem::path base;
  if (xdgCache != nullptr && xdgCache[0] != '\0') {
    base = xdgCache;
  } else if (const char* home = std::getenv("HOME"); home != nullptr) {
    base = std::filesystem::path(home) / ".cache";
  } else {
    base = "/tmp";
  }
  return base / "noctalia" / "calendar" / "events.json";
}

void CalendarService::loadCache() {
  const std::filesystem::path path = cacheFilePath();
  std::ifstream in(path);
  if (!in.is_open()) {
    return;
  }
  try {
    const auto j = nlohmann::json::parse(in);
    for (const auto& item : j.at("events")) {
      CalendarEvent event;
      event.id = item.value("id", std::string{});
      event.title = item.value("title", std::string{});
      event.calendarName = item.value("calendar", std::string{});
      event.colorHex = item.value("color", std::string{});
      event.location = item.value("location", std::string{});
      event.start = fromUnix(item.value("start", std::int64_t{0}));
      event.end = fromUnix(item.value("end", std::int64_t{0}));
      event.allDay = item.value("all_day", false);
      const std::string account = item.value("account", std::string{});
      m_eventsByAccount[account].push_back(std::move(event));
    }
    if (!m_eventsByAccount.empty()) {
      rebuildSnapshot();
    }
  } catch (const std::exception& e) {
    kLog.warn("failed to load calendar cache: {}", e.what());
    m_eventsByAccount.clear();
  }
}

void CalendarService::saveCache() const {
  const std::filesystem::path path = cacheFilePath();
  std::error_code ec;
  std::filesystem::create_directories(path.parent_path(), ec);
  if (ec) {
    return;
  }

  nlohmann::json events = nlohmann::json::array();
  for (const auto& [accountId, accountEvents] : m_eventsByAccount) {
    for (const CalendarEvent& event : accountEvents) {
      events.push_back({
          {"account", accountId},
          {"id", event.id},
          {"title", event.title},
          {"calendar", event.calendarName},
          {"color", event.colorHex},
          {"location", event.location},
          {"start", toUnix(event.start)},
          {"end", toUnix(event.end)},
          {"all_day", event.allDay},
      });
    }
  }

  const std::filesystem::path tmp = path.string() + ".tmp";
  {
    std::ofstream out(tmp, std::ios::trunc);
    if (!out.is_open()) {
      return;
    }
    out << nlohmann::json{{"events", std::move(events)}}.dump();
  }
  std::filesystem::rename(tmp, path, ec);
  if (ec) {
    std::filesystem::remove(tmp, ec);
  }
}
