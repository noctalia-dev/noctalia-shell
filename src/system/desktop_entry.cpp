#include "system/desktop_entry.h"

#include "core/log.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string_view>
#include <sys/inotify.h>
#include <unistd.h>
#include <unordered_map>
#include <unordered_set>

namespace fs = std::filesystem;

namespace {

  constexpr Logger kLog("desktop_entry");

  std::string toLower(std::string_view s) {
    std::string result(s);
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return result;
  }

  struct LocaleInfo {
    std::string lang;
    std::string country;
  };

  LocaleInfo parseLocale() {
    LocaleInfo info;
    const char* lang = std::getenv("LANG");
    if (lang == nullptr) {
      lang = std::getenv("LC_MESSAGES");
    }
    if (lang == nullptr) {
      return info;
    }

    std::string_view sv(lang);

    // Strip encoding (e.g., ".UTF-8")
    auto dot = sv.find('.');
    if (dot != std::string_view::npos) {
      sv = sv.substr(0, dot);
    }

    // Strip modifier (e.g., "@euro")
    auto at = sv.find('@');
    if (at != std::string_view::npos) {
      sv = sv.substr(0, at);
    }

    auto underscore = sv.find('_');
    if (underscore != std::string_view::npos) {
      info.lang = std::string(sv.substr(0, underscore));
      info.country = std::string(sv);
    } else {
      info.lang = std::string(sv);
    }

    return info;
  }

  std::string extractLocalizedValue(const std::string& line, const std::string& key, const LocaleInfo& locale) {
    // Try key[lang_COUNTRY]=
    if (!locale.country.empty()) {
      std::string locKey = key + "[" + locale.country + "]=";
      if (line.size() > locKey.size() && line.compare(0, locKey.size(), locKey) == 0) {
        return line.substr(locKey.size());
      }
    }
    // Try key[lang]=
    if (!locale.lang.empty()) {
      std::string locKey = key + "[" + locale.lang + "]=";
      if (line.size() > locKey.size() && line.compare(0, locKey.size(), locKey) == 0) {
        return line.substr(locKey.size());
      }
    }
    return {};
  }

  void parseDesktopFile(const fs::path& filepath, std::vector<DesktopEntry>& entries) {
    std::ifstream file(filepath);
    if (!file.is_open()) {
      return;
    }

    static const LocaleInfo locale = parseLocale();

    DesktopEntry entry;
    entry.path = filepath.string();
    entry.id = filepath.stem().string();

    bool inDesktopEntry = false;
    std::string localizedName;
    std::string localizedGenericName;
    std::string localizedComment;
    std::string type;

    std::string line;
    while (std::getline(file, line)) {
      // Strip trailing whitespace/carriage return
      while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) {
        line.pop_back();
      }

      if (line.empty() || line[0] == '#') {
        continue;
      }

      if (line[0] == '[') {
        if (inDesktopEntry) {
          break; // Only parse [Desktop Entry] section
        }
        if (line == "[Desktop Entry]") {
          inDesktopEntry = true;
        }
        continue;
      }

      if (!inDesktopEntry) {
        continue;
      }

      // Check for localized values first
      auto locName = extractLocalizedValue(line, "Name", locale);
      if (!locName.empty()) {
        localizedName = std::move(locName);
        continue;
      }
      auto locGenericName = extractLocalizedValue(line, "GenericName", locale);
      if (!locGenericName.empty()) {
        localizedGenericName = std::move(locGenericName);
        continue;
      }
      auto locComment = extractLocalizedValue(line, "Comment", locale);
      if (!locComment.empty()) {
        localizedComment = std::move(locComment);
        continue;
      }

      auto eq = line.find('=');
      if (eq == std::string::npos) {
        continue;
      }

      std::string_view key(line.data(), eq);
      std::string_view value(line.data() + eq + 1, line.size() - eq - 1);

      if (key == "Type") {
        type = std::string(value);
      } else if (key == "Name") {
        entry.name = std::string(value);
      } else if (key == "GenericName") {
        entry.genericName = std::string(value);
      } else if (key == "Comment") {
        entry.comment = std::string(value);
      } else if (key == "Exec") {
        entry.exec = std::string(value);
      } else if (key == "Icon") {
        entry.icon = std::string(value);
      } else if (key == "Categories") {
        entry.categories = std::string(value);
      } else if (key == "Keywords") {
        entry.keywords = std::string(value);
      } else if (key == "NoDisplay") {
        entry.noDisplay = (value == "true");
      } else if (key == "Hidden") {
        entry.hidden = (value == "true");
      } else if (key == "Terminal") {
        entry.terminal = (value == "true");
      }
    }

    if (type != "Application" || entry.noDisplay || entry.hidden || entry.name.empty()) {
      return;
    }

    // Apply localized values
    if (!localizedName.empty()) {
      entry.name = std::move(localizedName);
    }
    if (!localizedGenericName.empty()) {
      entry.genericName = std::move(localizedGenericName);
    }
    if (!localizedComment.empty()) {
      entry.comment = std::move(localizedComment);
    }

    // Pre-lowercase for matching
    entry.nameLower = toLower(entry.name);
    entry.genericNameLower = toLower(entry.genericName);
    entry.keywordsLower = toLower(entry.keywords);
    entry.categoriesLower = toLower(entry.categories);

    entries.push_back(std::move(entry));
  }

  std::vector<std::string> xdgDataDirs() {
    std::vector<std::string> dirs;

    const char* home = std::getenv("XDG_DATA_HOME");
    if (home != nullptr && home[0] != '\0') {
      dirs.emplace_back(home);
    } else {
      const char* userHome = std::getenv("HOME");
      if (userHome != nullptr) {
        dirs.push_back(std::string(userHome) + "/.local/share");
      }
    }

    const char* dataDirs = std::getenv("XDG_DATA_DIRS");
    if (dataDirs != nullptr && dataDirs[0] != '\0') {
      std::string_view sv(dataDirs);
      std::size_t start = 0;
      while (start < sv.size()) {
        auto colon = sv.find(':', start);
        if (colon == std::string_view::npos) {
          dirs.emplace_back(sv.substr(start));
          break;
        }
        dirs.emplace_back(sv.substr(start, colon - start));
        start = colon + 1;
      }
    } else {
      dirs.emplace_back("/usr/local/share");
      dirs.emplace_back("/usr/share");
    }

    return dirs;
  }

  class DesktopEntryCache {
  public:
    DesktopEntryCache() { setupWatchFd(); }

    ~DesktopEntryCache() {
      clearWatches();
      if (m_inotifyFd >= 0) {
        ::close(m_inotifyFd);
      }
    }

    const std::vector<DesktopEntry>& entries() {
      refreshIfNeeded();
      return m_entries;
    }

    std::uint64_t version() {
      refreshIfNeeded();
      return m_version;
    }

    int watchFd() const noexcept { return m_inotifyFd; }

    void checkReload() {
      if (m_inotifyFd < 0) {
        return;
      }

      alignas(inotify_event) char buf[4096];
      bool changed = false;
      while (true) {
        const auto n = ::read(m_inotifyFd, buf, sizeof(buf));
        if (n <= 0) {
          break;
        }

        std::size_t offset = 0;
        while (offset < static_cast<std::size_t>(n)) {
          auto* event = reinterpret_cast<inotify_event*>(buf + offset);
          if ((event->mask & IN_IGNORED) != 0) {
            m_watches.erase(event->wd);
          } else {
            changed = true;
          }
          offset += sizeof(inotify_event) + event->len;
        }
      }

      if (changed) {
        m_dirty = true;
      }
    }

  private:
    void setupWatchFd() {
      m_inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
      if (m_inotifyFd < 0) {
        kLog.warn("inotify_init1 failed, desktop entry hot reload disabled");
      }
    }

    void refreshIfNeeded() {
      if (!m_dirty) {
        return;
      }

      m_entries = scanDesktopEntries();
      rebuildWatches();
      m_dirty = false;
      ++m_version;
    }

    void clearWatches() {
      if (m_inotifyFd < 0) {
        m_watches.clear();
        m_watchedPaths.clear();
        return;
      }

      for (const auto& [wd, path] : m_watches) {
        (void)path;
        inotify_rm_watch(m_inotifyFd, wd);
      }
      m_watches.clear();
      m_watchedPaths.clear();
    }

    void rebuildWatches() {
      clearWatches();

      if (m_inotifyFd < 0) {
        return;
      }

      for (const auto& dataDir : xdgDataDirs()) {
        const fs::path appDir = fs::path(dataDir) / "applications";
        std::error_code ec;
        if (!fs::is_directory(appDir, ec)) {
          continue;
        }

        addWatch(appDir);
        for (fs::recursive_directory_iterator it(appDir, ec), end; it != end; it.increment(ec)) {
          if (ec) {
            ec.clear();
            continue;
          }
          if (it->is_directory(ec) && !ec) {
            addWatch(it->path());
          }
        }
      }
    }

    void addWatch(const fs::path& path) {
      const auto key = path.string();
      if (!m_watchedPaths.insert(key).second) {
        return;
      }

      constexpr std::uint32_t kMask = IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE |
                                      IN_DELETE_SELF | IN_MOVE_SELF | IN_ATTRIB;
      const int wd = inotify_add_watch(m_inotifyFd, key.c_str(), kMask);
      if (wd < 0) {
        return;
      }
      m_watches[wd] = key;
    }

    std::vector<DesktopEntry> m_entries;
    std::uint64_t m_version = 0;
    int m_inotifyFd = -1;
    bool m_dirty = true;
    std::unordered_map<int, std::string> m_watches;
    std::unordered_set<std::string> m_watchedPaths;
  };

  DesktopEntryCache& cache() {
    static DesktopEntryCache instance;
    return instance;
  }

} // namespace

std::vector<DesktopEntry> scanDesktopEntries() {
  std::vector<DesktopEntry> entries;

  // Track seen IDs to deduplicate (first occurrence wins per XDG spec)
  std::unordered_map<std::string, bool> seenIds;

  for (const auto& dataDir : xdgDataDirs()) {
    fs::path appDir = fs::path(dataDir) / "applications";
    if (!fs::is_directory(appDir)) {
      continue;
    }

    std::error_code ec;
    for (const auto& dirEntry : fs::recursive_directory_iterator(appDir, ec)) {
      if (!dirEntry.is_regular_file()) {
        continue;
      }
      if (dirEntry.path().extension() != ".desktop") {
        continue;
      }

      std::string id = dirEntry.path().stem().string();
      if (seenIds.count(id) > 0) {
        continue;
      }

      std::size_t prevSize = entries.size();
      parseDesktopFile(dirEntry.path(), entries);
      if (entries.size() > prevSize) {
        seenIds[id] = true;
      }
    }
  }

  // Sort by name for consistent ordering
  std::sort(entries.begin(), entries.end(),
            [](const DesktopEntry& a, const DesktopEntry& b) { return a.nameLower < b.nameLower; });

  return entries;
}

const std::vector<DesktopEntry>& desktopEntries() { return cache().entries(); }

std::uint64_t desktopEntriesVersion() { return cache().version(); }

int desktopEntryWatchFd() noexcept { return cache().watchFd(); }

void checkDesktopEntryReload() { cache().checkReload(); }
