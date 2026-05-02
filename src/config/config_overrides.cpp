#include "config/config_service.h"
#include "core/log.h"
#include "util/file_utils.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <type_traits>
#include <vector>

namespace {
  constexpr Logger kLog("config");
  constexpr const char* kInternalStateTable = "noctalia_state";
  constexpr const char* kSetupWizardCompletedKey = "setup_wizard_completed";

  toml::table* ensureTable(toml::table& parent, std::string_view key) {
    if (auto* existing = parent.get_as<toml::table>(key)) {
      return existing;
    }
    auto [it, _] = parent.insert_or_assign(key, toml::table{});
    return it->second.as_table();
  }

  void insertOverrideValue(toml::table& table, std::string_view key, const ConfigOverrideValue& value) {
    std::visit(
        [&](const auto& concrete) {
          using T = std::decay_t<decltype(concrete)>;
          if constexpr (std::is_same_v<T, std::vector<std::string>>) {
            toml::array array;
            for (const auto& item : concrete) {
              array.push_back(item);
            }
            table.insert_or_assign(key, std::move(array));
          } else {
            table.insert_or_assign(key, concrete);
          }
        },
        value);
  }

  std::vector<std::string> barOrderNames(const std::vector<BarConfig>& bars) {
    std::vector<std::string> order;
    order.reserve(bars.size());
    for (const auto& bar : bars) {
      order.push_back(bar.name);
    }
    return order;
  }

  bool setBarOverrideOrder(toml::table& root, const std::vector<std::string>& order) {
    auto* barRoot = ensureTable(root, "bar");
    if (barRoot == nullptr) {
      return false;
    }
    insertOverrideValue(*barRoot, "order", order);
    return true;
  }

  const toml::node* findOverrideNode(const toml::table& root, const std::vector<std::string>& path) {
    const toml::table* table = &root;
    for (std::size_t i = 0; i < path.size(); ++i) {
      if (i + 1 == path.size()) {
        return table->get(path[i]);
      }
      auto* next = table->get_as<toml::table>(path[i]);
      if (next == nullptr) {
        return nullptr;
      }
      table = next;
    }
    return nullptr;
  }

  void pruneEmptyOverrideTables(toml::table& root, const std::vector<std::string>& changedPath,
                                std::size_t preserveDepth = 0) {
    if (changedPath.size() < 2) {
      return;
    }

    for (std::size_t depth = changedPath.size() - 1; depth > 0; --depth) {
      if (preserveDepth > 0 && depth <= preserveDepth) {
        break;
      }

      toml::table* parent = &root;
      for (std::size_t i = 0; i + 1 < depth; ++i) {
        parent = parent->get_as<toml::table>(changedPath[i]);
        if (parent == nullptr) {
          return;
        }
      }

      auto* node = parent->get(changedPath[depth - 1]);
      auto* table = node != nullptr ? node->as_table() : nullptr;
      if (table == nullptr || !table->empty()) {
        break;
      }
      parent->erase(changedPath[depth - 1]);
    }
  }
} // namespace

void ConfigService::setThemeMode(ThemeMode mode) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* themeTbl = ensureTable(m_overridesTable, "theme");
  themeTbl->insert_or_assign("mode", std::string(enumToKey(kThemeModes, mode)));

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  // Rebuild Config and fan out reload callbacks so ThemeService transitions.
  loadAll();
  fireReloadCallbacks();
}

void ConfigService::setDockEnabled(bool enabled) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* dockTbl = ensureTable(m_overridesTable, "dock");
  const auto existing = (*dockTbl)["enabled"].value<bool>();
  if (existing.has_value() && *existing == enabled && m_config.dock.enabled == enabled) {
    return;
  }

  dockTbl->insert_or_assign("enabled", enabled);

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  loadAll();
  fireReloadCallbacks();
}

bool ConfigService::markSetupWizardCompleted() {
  if (m_setupWizardCompleted) {
    return true;
  }

  m_setupWizardCompleted = true;
  if (!writeOverridesToFile()) {
    m_setupWizardCompleted = false;
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  return true;
}

bool ConfigService::hasOverride(const std::vector<std::string>& path) const {
  if (path.empty()) {
    return false;
  }
  return findOverrideNode(m_overridesTable, path) != nullptr;
}

bool ConfigService::isOverrideOnlyBar(std::string_view name) const {
  if (name.empty() || !hasOverride({"bar", std::string(name)})) {
    return false;
  }
  return !m_configFileBarNames.contains(std::string(name));
}

bool ConfigService::canMoveBarOverride(std::string_view name, int direction) const {
  if (direction == 0 || name.empty()) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [name](const BarConfig& bar) { return bar.name == name; });
  if (barIt == m_config.bars.end()) {
    return false;
  }

  if (direction < 0) {
    return barIt != m_config.bars.begin();
  }

  return std::next(barIt) != m_config.bars.end();
}

bool ConfigService::canDeleteBarOverride(std::string_view name) const {
  return m_config.bars.size() > 1 && isOverrideOnlyBar(name);
}

bool ConfigService::isOverrideOnlyMonitorOverride(std::string_view barName, std::string_view match) const {
  if (barName.empty() || match.empty() || !hasOverride({"bar", std::string(barName), "monitor", std::string(match)})) {
    return false;
  }

  const auto barIt = m_configFileMonitorOverrideNames.find(std::string(barName));
  if (barIt == m_configFileMonitorOverrideNames.end()) {
    return true;
  }
  return !barIt->second.contains(std::string(match));
}

bool ConfigService::createBarOverride(std::string_view name) {
  if (m_overridesPath.empty() || name.empty()) {
    return false;
  }

  for (const auto& bar : m_config.bars) {
    if (bar.name == name) {
      return false;
    }
  }

  auto* barRoot = ensureTable(m_overridesTable, "bar");
  if (barRoot == nullptr || barRoot->get(std::string(name)) != nullptr) {
    return false;
  }

  if (m_configFileBarNames.empty() && barRoot->empty() && m_config.bars.size() == 1 &&
      m_config.bars.front().name == "default") {
    auto* defaultBar = ensureTable(*barRoot, "default");
    if (defaultBar == nullptr) {
      return false;
    }
    defaultBar->insert_or_assign("enabled", m_config.bars.front().enabled);
  }

  auto* barTbl = ensureTable(*barRoot, name);
  if (barTbl == nullptr) {
    return false;
  }
  barTbl->insert_or_assign("enabled", true);

  auto order = barOrderNames(m_config.bars);
  order.push_back(std::string(name));
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::moveBarOverride(std::string_view name, int direction) {
  if (!canMoveBarOverride(name, direction)) {
    return false;
  }

  auto order = barOrderNames(m_config.bars);
  const auto currentIt = std::find(order.begin(), order.end(), std::string(name));
  if (currentIt == order.end()) {
    return false;
  }

  if (direction < 0) {
    std::iter_swap(currentIt, std::prev(currentIt));
  } else {
    std::iter_swap(currentIt, std::next(currentIt));
  }

  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameBarOverride(std::string_view oldName, std::string_view newName) {
  if (oldName.empty() || newName.empty() || oldName == newName || !isOverrideOnlyBar(oldName)) {
    return false;
  }

  for (const auto& bar : m_config.bars) {
    if (bar.name == newName) {
      return false;
    }
  }

  auto order = barOrderNames(m_config.bars);
  for (auto& item : order) {
    if (item == oldName) {
      item = std::string(newName);
      break;
    }
  }
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  return renameOverrideTable({"bar", std::string(oldName)}, {"bar", std::string(newName)});
}

bool ConfigService::deleteBarOverride(std::string_view name) {
  if (!canDeleteBarOverride(name)) {
    return false;
  }
  auto order = barOrderNames(m_config.bars);
  std::erase(order, std::string(name));
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }
  return clearOverride({"bar", std::string(name)});
}

bool ConfigService::createMonitorOverride(std::string_view barName, std::string_view match) {
  if (m_overridesPath.empty() || barName.empty() || match.empty()) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [barName](const BarConfig& bar) { return bar.name == barName; });
  if (barIt == m_config.bars.end()) {
    return false;
  }
  const auto monitorIt = std::find_if(barIt->monitorOverrides.begin(), barIt->monitorOverrides.end(),
                                      [match](const BarMonitorOverride& ovr) { return ovr.match == match; });
  if (monitorIt != barIt->monitorOverrides.end()) {
    return false;
  }

  auto* barRoot = ensureTable(m_overridesTable, "bar");
  if (barRoot == nullptr) {
    return false;
  }
  auto* barTbl = ensureTable(*barRoot, barName);
  if (barTbl == nullptr) {
    return false;
  }
  auto* monitorRoot = ensureTable(*barTbl, "monitor");
  if (monitorRoot == nullptr || monitorRoot->get(std::string(match)) != nullptr) {
    return false;
  }
  if (ensureTable(*monitorRoot, match) == nullptr) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameMonitorOverride(std::string_view barName, std::string_view oldMatch,
                                          std::string_view newMatch) {
  if (barName.empty() || oldMatch.empty() || newMatch.empty() || oldMatch == newMatch ||
      !isOverrideOnlyMonitorOverride(barName, oldMatch)) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [barName](const BarConfig& bar) { return bar.name == barName; });
  if (barIt == m_config.bars.end()) {
    return false;
  }
  const auto monitorIt = std::find_if(barIt->monitorOverrides.begin(), barIt->monitorOverrides.end(),
                                      [newMatch](const BarMonitorOverride& ovr) { return ovr.match == newMatch; });
  if (monitorIt != barIt->monitorOverrides.end()) {
    return false;
  }

  return renameOverrideTable({"bar", std::string(barName), "monitor", std::string(oldMatch)},
                             {"bar", std::string(barName), "monitor", std::string(newMatch)});
}

bool ConfigService::deleteMonitorOverride(std::string_view barName, std::string_view match) {
  if (!isOverrideOnlyMonitorOverride(barName, match)) {
    return false;
  }
  return clearOverride({"bar", std::string(barName), "monitor", std::string(match)});
}

bool ConfigService::setOverride(const std::vector<std::string>& path, ConfigOverrideValue value) {
  if (m_overridesPath.empty() || path.empty()) {
    return false;
  }

  toml::table* table = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < path.size(); ++i) {
    table = ensureTable(*table, path[i]);
    if (table == nullptr) {
      return false;
    }
  }

  insertOverrideValue(*table, path.back(), value);

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::clearOverride(const std::vector<std::string>& path) {
  if (m_overridesPath.empty() || path.empty()) {
    return false;
  }

  std::size_t preserveDepth = 0;
  if (path.size() > 4 && path[0] == "bar" && path[2] == "monitor" && isOverrideOnlyMonitorOverride(path[1], path[3])) {
    preserveDepth = 4;
  } else if (path.size() > 2 && path[0] == "bar" && isOverrideOnlyBar(path[1])) {
    preserveDepth = 2;
  }

  toml::table* table = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < path.size(); ++i) {
    auto* next = table->get_as<toml::table>(path[i]);
    if (next == nullptr) {
      return false;
    }
    table = next;
  }

  if (table->erase(path.back()) == 0) {
    return false;
  }
  pruneEmptyOverrideTables(m_overridesTable, path, preserveDepth);

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameOverrideTable(const std::vector<std::string>& oldPath,
                                        const std::vector<std::string>& newPath) {
  if (m_overridesPath.empty() || oldPath.empty() || newPath.empty() || oldPath == newPath) {
    return false;
  }

  toml::table* oldParent = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < oldPath.size(); ++i) {
    auto* next = oldParent->get_as<toml::table>(oldPath[i]);
    if (next == nullptr) {
      return false;
    }
    oldParent = next;
  }

  toml::node* oldNode = oldParent->get(oldPath.back());
  if (oldNode == nullptr || oldNode->as_table() == nullptr) {
    return false;
  }

  toml::table* newParent = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < newPath.size(); ++i) {
    newParent = ensureTable(*newParent, newPath[i]);
    if (newParent == nullptr) {
      return false;
    }
  }

  if (newParent->get(newPath.back()) != nullptr) {
    return false;
  }

  if (oldParent == newParent) {
    std::vector<std::pair<std::string, const toml::node*>> entries;
    entries.reserve(oldParent->size());
    for (const auto& [key, node] : *oldParent) {
      std::string entryKey(key.str());
      if (entryKey == oldPath.back()) {
        entryKey = newPath.back();
      }
      entries.emplace_back(std::move(entryKey), &node);
    }

    toml::table renamed;
    for (const auto& [key, node] : entries) {
      renamed.insert_or_assign(key, *node);
    }
    *oldParent = std::move(renamed);
  } else {
    newParent->insert_or_assign(newPath.back(), *oldNode);
    oldParent->erase(oldPath.back());
    pruneEmptyOverrideTables(m_overridesTable, oldPath);
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

std::string ConfigService::getWallpaperPath(const std::string& connectorName) const {
  auto it = m_monitorWallpaperPaths.find(connectorName);
  if (it != m_monitorWallpaperPaths.end()) {
    return it->second;
  }
  return m_defaultWallpaperPath;
}

std::string ConfigService::getDefaultWallpaperPath() const { return m_defaultWallpaperPath; }

void ConfigService::setWallpaperChangeCallback(ChangeCallback callback) {
  m_wallpaperChangeCallback = std::move(callback);
}

void ConfigService::setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path) {
  if (m_overridesPath.empty()) {
    return;
  }

  bool changed = false;
  if (connectorName.has_value()) {
    auto it = m_monitorWallpaperPaths.find(*connectorName);
    if (it == m_monitorWallpaperPaths.end() || it->second != path) {
      m_monitorWallpaperPaths[*connectorName] = path;
      changed = true;
    }
  } else {
    if (m_defaultWallpaperPath != path) {
      m_defaultWallpaperPath = path;
      changed = true;
    }
  }

  if (!changed) {
    return;
  }

  // Mirror the change into the overrides table so writeOverridesToFile() serializes it.
  auto* wallpaperTbl = ensureTable(m_overridesTable, "wallpaper");
  if (connectorName.has_value()) {
    auto* monitorsTbl = ensureTable(*wallpaperTbl, "monitors");
    auto* monTbl = ensureTable(*monitorsTbl, *connectorName);
    monTbl->insert_or_assign("path", path);
  } else {
    auto* defaultTbl = ensureTable(*wallpaperTbl, "default");
    defaultTbl->insert_or_assign("path", path);
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;
  if (m_wallpaperBatchDepth > 0) {
    m_wallpaperBatchDirty = true;
    return;
  }
  if (m_wallpaperChangeCallback) {
    m_wallpaperChangeCallback();
  }
}

void ConfigService::extractWallpaperFromOverrides() {
  m_defaultWallpaperPath.clear();
  m_monitorWallpaperPaths.clear();

  if (auto* wpDefault = m_overridesTable["wallpaper"]["default"].as_table()) {
    if (auto v = (*wpDefault)["path"].value<std::string>()) {
      m_defaultWallpaperPath = FileUtils::expandUserPath(*v).string();
    }
  }
  if (auto* monitors = m_overridesTable["wallpaper"]["monitors"].as_table()) {
    for (const auto& [key, value] : *monitors) {
      if (auto* monTbl = value.as_table()) {
        if (auto v = (*monTbl)["path"].value<std::string>()) {
          m_monitorWallpaperPaths[std::string(key.str())] = FileUtils::expandUserPath(*v).string();
        }
      }
    }
  }
}

bool ConfigService::writeOverridesToFile() {
  if (m_overridesPath.empty()) {
    return false;
  }
  toml::table output = m_overridesTable;
  if (m_setupWizardCompleted) {
    auto* state = ensureTable(output, kInternalStateTable);
    state->insert_or_assign(kSetupWizardCompletedKey, true);
  }

  const std::string tmpPath = m_overridesPath + ".tmp";
  {
    std::ofstream out(tmpPath, std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    out << toml::toml_formatter{output,
                                toml::toml_formatter::default_flags & ~toml::format_flags::allow_literal_strings};
    if (!out.good()) {
      return false;
    }
  }
  std::error_code ec;
  std::filesystem::rename(tmpPath, m_overridesPath, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    return false;
  }
  return true;
}
