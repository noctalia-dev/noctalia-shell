#include "compositors/sway/sway_display_backend.h"

#include "core/process/process.h"
#include "util/string_utils.h"

#include <cmath>
#include <nlohmann/json.hpp>
#include <string>

namespace compositors::display {

  namespace {

    [[nodiscard]] int normalizeRefreshMilli(const nlohmann::json& value) {
      if (!value.is_number()) {
        return 60000;
      }
      const double raw = value.get<double>();
      if (raw <= 0.0 || !std::isfinite(raw)) {
        return 60000;
      }
      return static_cast<int>(std::lround(raw < 1000.0 ? raw * 1000.0 : raw));
    }

    [[nodiscard]] bool adaptiveSyncEnabled(const nlohmann::json& output) {
      if (const auto it = output.find("adaptive_sync_status"); it != output.end()) {
        if (it->is_boolean()) {
          return it->get<bool>();
        }
        if (it->is_string()) {
          const auto value = StringUtils::toLower(it->get<std::string>());
          return value == "enabled" || value == "on" || value == "true";
        }
      }
      return output.value("adaptive_sync", false);
    }

    [[nodiscard]] std::vector<OutputState> parseFetchJson(std::string_view payload, std::string& error) {
      std::vector<OutputState> outputs;
      try {
        const auto json = nlohmann::json::parse(payload);
        if (!json.is_array()) {
          error = "unexpected sway get_outputs payload";
          return outputs;
        }
        for (const auto& mon : json) {
          if (!mon.is_object()) {
            continue;
          }
          const auto nameIt = mon.find("name");
          if (nameIt == mon.end() || !nameIt->is_string()) {
            continue;
          }
          OutputState out;
          out.name = nameIt->get<std::string>();
          out.enabled = mon.value("active", false) || mon.value("enabled", false);
          out.make = mon.value("make", "");
          out.model = mon.value("model", "");

          const auto currentMode = mon.value("current_mode", nlohmann::json::object());
          int currentW = 0;
          int currentH = 0;
          int currentRefresh = 60000;
          if (currentMode.is_object()) {
            currentW = currentMode.value("width", 0);
            currentH = currentMode.value("height", 0);
            currentRefresh = normalizeRefreshMilli(currentMode.value("refresh", 60000));
          }
          if (const auto modesIt = mon.find("modes"); modesIt != mon.end() && modesIt->is_array()) {
            for (const auto& mode : *modesIt) {
              if (!mode.is_object()) {
                continue;
              }
              const auto w = mode.find("width");
              const auto h = mode.find("height");
              if (w == mode.end() || h == mode.end() || !w->is_number() || !h->is_number()) {
                continue;
              }
              const int mw = w->get<int>();
              const int mh = h->get<int>();
              const int refresh = normalizeRefreshMilli(mode.value("refresh", 60000));
              DisplayMode entry{mw, mh, refresh, mode.value("preferred", false), false};
              if (mode.value("current", false)
                  || (mw == currentW && mh == currentH && std::abs(refresh - currentRefresh) < 2)) {
                entry.current = true;
                out.currentModeIndex = static_cast<int>(out.modes.size());
              }
              out.modes.push_back(entry);
            }
          }
          if (out.modes.empty() && currentW > 0 && currentH > 0) {
            out.modes.push_back(DisplayMode{currentW, currentH, currentRefresh, false, true});
            out.currentModeIndex = 0;
          }

          out.scale = mon.value("scale", 1.0);
          if (out.scale <= 0.0) {
            out.scale = 1.0;
          }
          out.transform = transformFromName(mon.value("transform", "normal"));
          const auto current = static_cast<std::size_t>(out.currentModeIndex);
          const auto rect = mon.value("rect", nlohmann::json::object());
          out.x = rect.is_object() ? rect.value("x", 0) : 0;
          out.y = rect.is_object() ? rect.value("y", 0) : 0;
          out.modeStr = std::to_string(out.modes[current].width)
              + "x"
              + std::to_string(out.modes[current].height)
              + "@"
              + formatRateHz(out.modes[current].refreshMhz);
          out.vrr = adaptiveSyncEnabled(mon);
          outputs.push_back(std::move(out));
        }
      } catch (const std::exception& e) {
        error = e.what();
      }
      return outputs;
    }

  } // namespace

  SwayDisplayBackend::SwayDisplayBackend(compositors::sway::SwayRuntime& runtime) : m_runtime(runtime) {}

  std::vector<std::string> SwayDisplayBackend::fetchArgs() const {
    const auto& msg = m_runtime.outputCommand();
    if (msg.empty()) {
      return {};
    }
    return {msg, "-t", "get_outputs", "-r"};
  }

  std::vector<OutputState> SwayDisplayBackend::parseFetch(std::string_view payload, std::string& error) const {
    return parseFetchJson(payload, error);
  }

  std::vector<DisplayCommand> SwayDisplayBackend::changeCommands(
      DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
  ) {
    const auto& msg = m_runtime.outputCommand();
    if (msg.empty()) {
      return {};
    }
    const auto it = target.find(outputName);
    if (it == target.end()) {
      return {};
    }
    const OutputState& cfg = it->second;
    std::vector<std::string> args{msg, "output", outputName};
    switch (kind) {
    case DisplayChangeKind::Mode:
      if (!cfg.enabled)
        return {};
      args.push_back("mode");
      args.push_back(swayModeStr(cfg.modeStr));
      break;
    case DisplayChangeKind::Scale:
      if (!cfg.enabled)
        return {};
      args.push_back("scale");
      args.push_back(StringUtils::formatDotDecimal(cfg.scale));
      break;
    case DisplayChangeKind::Transform:
      if (!cfg.enabled)
        return {};
      args.push_back("transform");
      args.push_back(std::string(transformToName(cfg.transform)));
      break;
    case DisplayChangeKind::Vrr:
      args.push_back("adaptive_sync");
      args.push_back(cfg.vrr ? "on" : "off");
      break;
    case DisplayChangeKind::Toggle:
      args.push_back(cfg.enabled ? "enable" : "disable");
      break;
    case DisplayChangeKind::Positions: {
      std::vector<DisplayCommand> cmds;
      for (const auto& [name, other] : target) {
        if (!other.enabled) {
          continue;
        }
        cmds.push_back(
            DisplayCommand{
                {msg, "output", name, "position", std::to_string(other.x), std::to_string(other.y)}, std::nullopt
            }
        );
      }
      return cmds;
    }
    }
    return {DisplayCommand{std::move(args), std::nullopt}};
  }

  std::vector<DisplayCommand> SwayDisplayBackend::revertCommands(
      const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
  ) {
    const auto& msg = m_runtime.outputCommand();
    if (msg.empty()) {
      return {};
    }
    std::vector<DisplayCommand> onOff;
    std::vector<DisplayCommand> pending;
    for (const auto& [name, snap] : snapshot) {
      const auto curIt = current.find(name);
      const OutputState& cur = curIt != current.end() ? curIt->second : OutputState{};

      if (snap.enabled != cur.enabled) {
        onOff.push_back(DisplayCommand{{msg, "output", name, snap.enabled ? "enable" : "disable"}, std::nullopt});
      }
      if (!snap.enabled) {
        continue;
      }
      if (!snap.modeStr.empty() && snap.modeStr != cur.modeStr) {
        pending.push_back(DisplayCommand{{msg, "output", name, "mode", swayModeStr(snap.modeStr)}, std::nullopt});
      }
      if (std::abs(snap.scale - cur.scale) > 0.01) {
        pending.push_back(
            DisplayCommand{{msg, "output", name, "scale", StringUtils::formatDotDecimal(snap.scale)}, std::nullopt}
        );
      }
      if (snap.transform != cur.transform) {
        pending.push_back(
            DisplayCommand{
                {msg, "output", name, "transform", std::string(transformToName(snap.transform))}, std::nullopt
            }
        );
      }
      if (snap.x != cur.x || snap.y != cur.y) {
        pending.push_back(
            DisplayCommand{
                {msg, "output", name, "position", std::to_string(snap.x), std::to_string(snap.y)}, std::nullopt
            }
        );
      }
      if (snap.vrr != cur.vrr) {
        pending.push_back(
            DisplayCommand{{msg, "output", name, "adaptive_sync", snap.vrr ? "on" : "off"}, std::nullopt}
        );
      }
    }
    onOff.insert(onOff.end(), pending.begin(), pending.end());
    return onOff;
  }

} // namespace compositors::display
