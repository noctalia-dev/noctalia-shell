#include "launcher/emoji_provider.h"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <json.hpp>
#include <sstream>
#include <string_view>
#include <unistd.h>

#ifndef NOCTALIA_ASSETS_DIR
#define NOCTALIA_ASSETS_DIR "assets"
#endif

namespace {

std::string toLower(std::string_view s) {
  std::string result(s);
  std::transform(result.begin(), result.end(), result.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return result;
}

} // namespace

void EmojiProvider::initialize() {
  std::string path = std::string(NOCTALIA_ASSETS_DIR) + "/emoji.json";
  std::ifstream file(path);
  if (!file.is_open()) {
    return;
  }

  try {
    auto json = nlohmann::json::parse(file);
    if (!json.is_array()) {
      return;
    }

    m_entries.reserve(json.size());
    for (const auto& item : json) {
      EmojiEntry entry;
      entry.emoji = item.value("emoji", "");
      entry.name = item.value("name", "");
      entry.nameLower = toLower(entry.name);
      entry.category = item.value("category", "");

      if (item.contains("keywords") && item["keywords"].is_array()) {
        for (const auto& kw : item["keywords"]) {
          if (kw.is_string()) {
            entry.keywords.push_back(toLower(kw.get<std::string>()));
          }
        }
      }

      if (!entry.emoji.empty() && !entry.name.empty()) {
        m_entries.push_back(std::move(entry));
      }
    }
  } catch (...) {
    // Failed to parse JSON
  }
}

std::vector<LauncherResult> EmojiProvider::query(std::string_view text) const {
  std::string query = toLower(text);
  if (query.empty()) {
    // Show first batch when no query
    std::vector<LauncherResult> results;
    for (std::size_t i = 0; i < m_entries.size() && i < 50; ++i) {
      const auto& e = m_entries[i];
      LauncherResult r;
      r.id = "emoji-" + e.emoji;
      r.title = e.name;
      r.subtitle = e.category;
      r.actionText = e.emoji;
      r.score = static_cast<int>(m_entries.size() - i);
      results.push_back(std::move(r));
    }
    return results;
  }

  struct ScoredEntry {
    int score;
    std::size_t index;
  };

  std::vector<ScoredEntry> scored;

  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    const auto& e = m_entries[i];
    int bestScore = 0;

    // Exact name match
    if (e.nameLower == query) {
      bestScore = 1000;
    }
    // Name prefix
    else if (e.nameLower.size() >= query.size() && e.nameLower.compare(0, query.size(), query) == 0) {
      bestScore = 500;
    }
    // Name contains
    else if (e.nameLower.find(query) != std::string::npos) {
      bestScore = 200;
    }
    // Keyword match
    else {
      for (const auto& kw : e.keywords) {
        if (kw == query) {
          bestScore = std::max(bestScore, 150);
        } else if (kw.size() >= query.size() && kw.compare(0, query.size(), query) == 0) {
          bestScore = std::max(bestScore, 100);
        } else if (kw.find(query) != std::string::npos) {
          bestScore = std::max(bestScore, 50);
        }
      }
    }

    if (bestScore > 0) {
      scored.push_back({bestScore, i});
    }
  }

  std::sort(scored.begin(), scored.end(), [](const ScoredEntry& a, const ScoredEntry& b) { return a.score > b.score; });

  std::vector<LauncherResult> results;
  for (std::size_t i = 0; i < scored.size() && i < 50; ++i) {
    const auto& e = m_entries[scored[i].index];
    LauncherResult r;
    r.id = "emoji-" + e.emoji;
    r.title = e.name;
    r.subtitle = e.category;
    r.actionText = e.emoji;
    r.score = scored[i].score;
    results.push_back(std::move(r));
  }

  return results;
}

bool EmojiProvider::activate(const LauncherResult& result) {
  if (result.id.substr(0, 6) != "emoji-") {
    return false;
  }

  std::string emoji = result.id.substr(6);

  pid_t pid = fork();
  if (pid == 0) {
    execlp("wl-copy", "wl-copy", emoji.c_str(), nullptr);
    _exit(1);
  }

  return true;
}
