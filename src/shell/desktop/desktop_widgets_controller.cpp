#include "shell/desktop/desktop_widgets_controller.h"

#include "core/log.h"
#include "core/toml.h"
#include "ipc/ipc_service.h"
#include "pipewire/pipewire_spectrum.h"
#include "shell/desktop/desktop_widget_layout.h"
#include "shell/desktop/desktop_widgets_editor.h"
#include "shell/desktop/desktop_widgets_host.h"
#include "wayland/wayland_connection.h"

#include <charconv>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <limits>
#include <unordered_set>

namespace {

  constexpr Logger kLog("desktop");
  constexpr std::string_view kDesktopWidgetIdPrefix = "desktop-widget-";
  constexpr float kDefaultDesktopAudioVisualizerAspectRatio = 240.0f / 96.0f;

  std::string stateDir() {
    const char* xdg = std::getenv("XDG_STATE_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.local/state/noctalia";
    }
    return {};
  }

  void writeSetting(toml::table& table, const std::string& key, const WidgetSettingValue& value) {
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

  std::optional<WidgetSettingValue> readSetting(const toml::node& node) {
    if (const auto* stringValue = node.as_string()) {
      return WidgetSettingValue{stringValue->get()};
    }
    if (const auto* intValue = node.as_integer()) {
      return WidgetSettingValue{intValue->get()};
    }
    if (const auto* floatValue = node.as_floating_point()) {
      return WidgetSettingValue{floatValue->get()};
    }
    if (const auto* boolValue = node.as_boolean()) {
      return WidgetSettingValue{boolValue->get()};
    }
    if (const auto* arrayValue = node.as_array()) {
      std::vector<std::string> strings;
      for (const auto& item : *arrayValue) {
        if (auto value = item.value<std::string>()) {
          strings.push_back(*value);
        }
      }
      return WidgetSettingValue{std::move(strings)};
    }
    return std::nullopt;
  }

  void normalizeDesktopWidgetSettings(DesktopWidgetState& widget) {
    if (widget.type != "audio_visualizer") {
      return;
    }

    const auto it = widget.settings.find("aspect_ratio");
    if (it != widget.settings.end()) {
      if (const auto* doubleValue = std::get_if<double>(&it->second); doubleValue != nullptr && *doubleValue > 0.0) {
        return;
      }
      if (const auto* intValue = std::get_if<std::int64_t>(&it->second); intValue != nullptr && *intValue > 0) {
        return;
      }
    }

    widget.settings.insert_or_assign("aspect_ratio", static_cast<double>(kDefaultDesktopAudioVisualizerAspectRatio));
  }

  bool parseDesktopWidgetCounter(std::string_view id, std::uint64_t& value) {
    if (!id.starts_with(kDesktopWidgetIdPrefix)) {
      return false;
    }

    const std::string_view suffix = id.substr(kDesktopWidgetIdPrefix.size());
    if (suffix.empty()) {
      return false;
    }

    value = 0;
    const auto* begin = suffix.data();
    const auto* end = suffix.data() + suffix.size();
    const auto [ptr, ec] = std::from_chars(begin, end, value, 16);
    return ec == std::errc{} && ptr == end;
  }

  std::string makeDesktopWidgetId(std::uint64_t counter) { return std::format("desktop-widget-{:016x}", counter); }

} // namespace

DesktopWidgetsController::DesktopWidgetsController() = default;

DesktopWidgetsController::~DesktopWidgetsController() = default;

void DesktopWidgetsController::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                                          PipeWireSpectrum* pipewireSpectrum, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_timeService = timeService;
  m_renderContext = renderContext;
  m_host = std::make_unique<DesktopWidgetsHost>();
  m_host->initialize(wayland, config, timeService, pipewireSpectrum, renderContext);
  m_editor = std::make_unique<DesktopWidgetsEditor>();
  m_editor->initialize(wayland, config, timeService, pipewireSpectrum, renderContext);
  m_editor->setExitRequestedCallback([this]() { exitEdit(); });
  loadState();
  m_initialized = true;
  applyVisibility();

  if (m_config != nullptr) {
    m_config->addReloadCallback([this]() { applyVisibility(); });
  }
}

void DesktopWidgetsController::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "desktop-widgets-edit",
      [this](const std::string&) -> std::string {
        enterEdit();
        return "ok\n";
      },
      "desktop-widgets-edit", "Open the desktop widgets editor");

  ipc.registerHandler(
      "desktop-widgets-exit",
      [this](const std::string&) -> std::string {
        exitEdit();
        return "ok\n";
      },
      "desktop-widgets-exit", "Close the desktop widgets editor");

  ipc.registerHandler(
      "desktop-widgets-toggle-edit",
      [this](const std::string&) -> std::string {
        toggleEdit();
        return "ok\n";
      },
      "desktop-widgets-toggle-edit", "Toggle desktop widgets edit mode");
}

void DesktopWidgetsController::onOutputChange() {
  if (!m_initialized) {
    return;
  }
  normalizeSnapshot();
  if (isEditing()) {
    m_editor->onOutputChange();
  } else if (m_host != nullptr) {
    m_host->onOutputChange();
  }
}

void DesktopWidgetsController::onSecondTick() {
  if (!m_initialized) {
    return;
  }
  if (isEditing()) {
    m_editor->onSecondTick();
  } else if (m_host != nullptr) {
    m_host->onSecondTick();
  }
}

void DesktopWidgetsController::requestLayout() {
  if (!m_initialized) {
    return;
  }
  if (isEditing()) {
    m_editor->requestLayout();
  } else if (m_host != nullptr) {
    m_host->requestLayout();
  }
}

void DesktopWidgetsController::requestRedraw() {
  if (!m_initialized) {
    return;
  }
  if (isEditing()) {
    m_editor->requestRedraw();
  } else if (m_host != nullptr) {
    m_host->requestRedraw();
  }
}

void DesktopWidgetsController::enterEdit() {
  if (!m_initialized || m_editor == nullptr || m_host == nullptr || isEditing()) {
    return;
  }
  if (m_config != nullptr && !m_config->config().desktopWidgets.enabled) {
    return;
  }
  m_host->hide();
  m_editor->open(m_snapshot);
}

void DesktopWidgetsController::exitEdit() {
  if (!isEditing() || m_editor == nullptr) {
    return;
  }

  m_snapshot = m_editor->close();
  normalizeSnapshot();
  saveState();
  applyVisibility();
}

void DesktopWidgetsController::toggleEdit() {
  if (isEditing()) {
    exitEdit();
  } else {
    enterEdit();
  }
}

bool DesktopWidgetsController::isEditing() const noexcept { return m_editor != nullptr && m_editor->isOpen(); }

bool DesktopWidgetsController::onPointerEvent(const PointerEvent& event) {
  if (!isEditing() || m_editor == nullptr) {
    return false;
  }
  return m_editor->onPointerEvent(event);
}

void DesktopWidgetsController::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isEditing() || m_editor == nullptr) {
    return;
  }
  m_editor->onKeyboardEvent(event);
}

void DesktopWidgetsController::loadState() {
  m_snapshot = DesktopWidgetsSnapshot{};
  const std::string path = stateFilePath();
  if (path.empty() || !std::filesystem::exists(path)) {
    return;
  }

  try {
    const toml::table table = toml::parse_file(path);
    if (auto schemaVersion = table["schema_version"].value<int64_t>()) {
      m_snapshot.schemaVersion = static_cast<std::int32_t>(*schemaVersion);
    }

    if (const auto* gridTable = table["grid"].as_table()) {
      if (auto visible = (*gridTable)["visible"].value<bool>()) {
        m_snapshot.grid.visible = *visible;
      }
      if (auto cellSize = (*gridTable)["cell_size"].value<int64_t>()) {
        m_snapshot.grid.cellSize = std::clamp(static_cast<std::int32_t>(*cellSize), 8, 256);
      }
      if (auto majorInterval = (*gridTable)["major_interval"].value<int64_t>()) {
        m_snapshot.grid.majorInterval = std::clamp(static_cast<std::int32_t>(*majorInterval), 1, 16);
      }
    }

    if (const auto* widgets = table["widget"].as_array()) {
      for (const auto& node : *widgets) {
        const auto* widgetTable = node.as_table();
        if (widgetTable == nullptr) {
          continue;
        }

        DesktopWidgetState widget;
        if (auto id = (*widgetTable)["id"].value<std::string>()) {
          widget.id = *id;
        }
        if (auto type = (*widgetTable)["type"].value<std::string>()) {
          widget.type = *type;
        }
        if (auto output = (*widgetTable)["output"].value<std::string>()) {
          widget.outputName = *output;
        }
        if (auto cx = (*widgetTable)["cx"].value<double>()) {
          widget.cx = static_cast<float>(*cx);
        }
        if (auto cy = (*widgetTable)["cy"].value<double>()) {
          widget.cy = static_cast<float>(*cy);
        }
        if (auto scale = (*widgetTable)["scale"].value<double>()) {
          widget.scale = static_cast<float>(*scale);
        }
        if (auto rotation = (*widgetTable)["rotation"].value<double>()) {
          widget.rotationRad = static_cast<float>(*rotation);
        }
        if (const auto* settingsTable = (*widgetTable)["settings"].as_table()) {
          for (const auto& [key, value] : *settingsTable) {
            if (auto parsed = readSetting(value); parsed.has_value()) {
              widget.settings.emplace(std::string(key.str()), std::move(*parsed));
            }
          }
        }
        if (!widget.id.empty() && !widget.type.empty()) {
          m_snapshot.widgets.push_back(std::move(widget));
        }
      }
    }
  } catch (const std::exception& e) {
    kLog.warn("desktop widgets: failed to load state {}: {}", path, e.what());
    m_snapshot = DesktopWidgetsSnapshot{};
  }
  normalizeSnapshot();
}

void DesktopWidgetsController::saveState() const {
  const std::string path = stateFilePath();
  if (path.empty()) {
    return;
  }

  std::error_code ec;
  std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);

  toml::table root;
  root.insert_or_assign("schema_version", m_snapshot.schemaVersion);

  toml::table grid;
  grid.insert_or_assign("visible", m_snapshot.grid.visible);
  grid.insert_or_assign("cell_size", m_snapshot.grid.cellSize);
  grid.insert_or_assign("major_interval", m_snapshot.grid.majorInterval);
  root.insert_or_assign("grid", std::move(grid));

  toml::array widgets;
  for (const auto& widget : m_snapshot.widgets) {
    toml::table widgetTable;
    widgetTable.insert_or_assign("id", widget.id);
    widgetTable.insert_or_assign("type", widget.type);
    widgetTable.insert_or_assign("output", widget.outputName);
    widgetTable.insert_or_assign("cx", widget.cx);
    widgetTable.insert_or_assign("cy", widget.cy);
    widgetTable.insert_or_assign("scale", widget.scale);
    widgetTable.insert_or_assign("rotation", widget.rotationRad);
    if (!widget.settings.empty()) {
      toml::table settingsTable;
      for (const auto& [key, value] : widget.settings) {
        writeSetting(settingsTable, key, value);
      }
      widgetTable.insert_or_assign("settings", std::move(settingsTable));
    }
    widgets.push_back(std::move(widgetTable));
  }
  root.insert_or_assign("widget", std::move(widgets));

  const std::string tmpPath = path + ".tmp";
  std::ofstream out(tmpPath, std::ios::trunc);
  if (!out.is_open()) {
    kLog.warn("desktop widgets: failed to open {} for writing", tmpPath);
    return;
  }
  out << root;
  out.close();

  std::filesystem::rename(tmpPath, path, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    kLog.warn("desktop widgets: failed to atomically write {}", path);
  }
}

void DesktopWidgetsController::applyVisibility() {
  if (!m_initialized || m_host == nullptr || m_config == nullptr) {
    return;
  }

  const bool enabled = m_config->config().desktopWidgets.enabled;
  if (!enabled) {
    if (isEditing() && m_editor != nullptr) {
      m_snapshot = m_editor->close();
      saveState();
    }
    m_host->hide();
    return;
  }

  if (!isEditing()) {
    m_host->show(m_snapshot);
  }
}

void DesktopWidgetsController::normalizeSnapshot() {
  if (m_wayland == nullptr) {
    return;
  }

  std::uint64_t maxCounter = 0;
  for (const auto& widget : m_snapshot.widgets) {
    std::uint64_t counter = 0;
    if (parseDesktopWidgetCounter(widget.id, counter)) {
      maxCounter = std::max(maxCounter, counter);
    }
  }

  std::unordered_set<std::string> seenIds;
  for (auto& widget : m_snapshot.widgets) {
    normalizeDesktopWidgetSettings(widget);

    if (widget.id.empty() || seenIds.contains(widget.id)) {
      const std::uint64_t nextCounter =
          maxCounter == std::numeric_limits<std::uint64_t>::max() ? maxCounter : (maxCounter + 1);
      maxCounter = nextCounter;
      widget.id = makeDesktopWidgetId(nextCounter);
    }
    seenIds.insert(widget.id);

    const WaylandOutput* output = desktop_widgets::resolveEffectiveOutput(*m_wayland, widget.outputName);
    if (output == nullptr) {
      continue;
    }

    widget.outputName = desktop_widgets::outputKey(*output);
    // cx/cy clamping is owned by the editor (during drag) and the host (on widget creation and
    // prepareFrame). Both of those paths know the widget's actual intrinsic size; clamping here
    // with an estimate can push widgets that the editor had legitimately placed at the edge.
  }
}

std::string DesktopWidgetsController::stateFilePath() const {
  const std::string dir = stateDir();
  if (dir.empty()) {
    return {};
  }
  return dir + "/desktop_widgets.toml";
}
