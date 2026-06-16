#include "launcher/plugin_launcher_provider.h"

#include "core/log.h"

#include <chrono>
#include <fstream>
#include <sstream>
#include <utility>

namespace {
  constexpr Logger kLog("plugin-launcher");

  std::string readFile(const std::filesystem::path& path) {
    std::ifstream file(path);
    if (!file) {
      return {};
    }
    std::stringstream ss;
    ss << file.rdbuf();
    return ss.str();
  }
} // namespace

PluginLauncherProvider::PluginLauncherProvider(
    std::string entryId, std::string displayName, std::filesystem::path sourcePath, std::string prefix,
    std::string glyph, bool globalSearch, int debounceMs, std::vector<LauncherCategory> categories,
    std::unordered_map<std::string, WidgetSettingValue> settings, scripting::ScriptApiContext& scriptApi,
    HttpClient* httpClient, ClipboardService* clipboard
)
    : m_entryId(std::move(entryId)), m_displayName(std::move(displayName)), m_sourcePath(std::move(sourcePath)),
      m_pluginDir(m_sourcePath.parent_path()), m_prefix(std::move(prefix)), m_glyph(std::move(glyph)),
      m_globalSearch(globalSearch), m_debounceMs(debounceMs), m_categories(std::move(categories)),
      m_settings(std::move(settings)), m_scriptApi(scriptApi), m_httpClient(httpClient), m_clipboard(clipboard) {}

PluginLauncherProvider::~PluginLauncherProvider() {
  if (m_alive) {
    *m_alive = false;
  }
  if (m_runtime != nullptr) {
    if (m_subscription != 0) {
      m_runtime->unsubscribe(m_subscription);
    }
    m_runtime->stop();
  }
}

void PluginLauncherProvider::initialize() {
  std::string code = readFile(m_sourcePath);
  if (code.empty()) {
    kLog.warn("launcher provider '{}': empty or unreadable source {}", m_entryId, m_sourcePath.string());
    return;
  }
  m_runtime = std::make_shared<scripting::ScriptRuntime>(
      m_entryId, m_settings, m_scriptApi, m_pluginDir, m_httpClient, m_clipboard
  );

  auto alive = std::weak_ptr<bool>(m_alive);
  m_subscription = m_runtime->subscribe([this, alive](const scripting::ScriptResult& result) {
    auto token = alive.lock();
    if (token == nullptr || !*token) {
      return;
    }
    handleResult(result);
  });

  m_runtime->start(m_sourcePath.string(), std::move(code), {});
}

void PluginLauncherProvider::reset() {
  m_queryTimer.stop();
  m_cache.clear();
  m_resultsQuery.clear();
  m_lastSentQuery.clear();
  m_pendingQuery.clear();
  m_hasSentInitial = false;
}

std::vector<LauncherResult> PluginLauncherProvider::query(std::string_view text) const {
  if (m_runtime == nullptr) {
    return m_cache;
  }
  const std::string q(text);
  m_pendingQuery = q;
  // Cached results already answer this exact query — nothing to fetch.
  if (m_hasSentInitial && q == m_resultsQuery) {
    m_queryTimer.stop();
    return m_cache;
  }
  // Debounce subsequent keystrokes so a network-backed provider isn't hit on every
  // character; the first query (panel open) fires immediately for a snappy first paint.
  if (m_debounceMs > 0 && m_hasSentInitial) {
    armQueryTimer();
  } else {
    dispatchQuery(q);
  }
  return m_cache;
}

void PluginLauncherProvider::dispatchQuery(const std::string& text) const {
  if (m_runtime == nullptr || (m_hasSentInitial && text == m_lastSentQuery)) {
    return;
  }
  m_hasSentInitial = true;
  m_lastSentQuery = text;
  // Coalesced: a newer queued onQuery supersedes this one while it waits. The empty
  // second arg is ignored by onQuery(text).
  (void)m_runtime->enqueueCallStrings("onQuery", text, std::string(), {}, /*coalesce=*/true);
}

void PluginLauncherProvider::armQueryTimer() const {
  m_queryTimer.stop();
  auto alive = std::weak_ptr<bool>(m_alive);
  m_queryTimer.start(std::chrono::milliseconds(m_debounceMs), [this, alive]() {
    auto token = alive.lock();
    if (token != nullptr && *token) {
      dispatchQuery(m_pendingQuery);
    }
  });
}

bool PluginLauncherProvider::activate(const LauncherResult& result) {
  if (m_runtime != nullptr) {
    (void)m_runtime->enqueueCallStrings("onActivate", result.id, std::string(), {}, /*coalesce=*/false);
  }
  return true; // Close the launcher; the plugin handles the action off-thread.
}

void PluginLauncherProvider::handleResult(const scripting::ScriptResult& result) {
  if (!result.patch.launcherResults.has_value()) {
    return;
  }
  const auto& set = *result.patch.launcherResults;
  m_cache.clear();
  m_cache.reserve(set.results.size());
  for (const auto& r : set.results) {
    LauncherResult lr;
    lr.id = r.id;
    lr.title = r.title.empty() ? r.id : r.title;
    lr.subtitle = r.subtitle;
    lr.glyphName = r.glyph;
    lr.iconName = r.icon;
    lr.badge = r.badge;
    lr.score = r.score;
    m_cache.push_back(std::move(lr));
  }
  m_resultsQuery = set.query;
  if (m_onResultsChanged) {
    m_onResultsChanged();
  }
}
