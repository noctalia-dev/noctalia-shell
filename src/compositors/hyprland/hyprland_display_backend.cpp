#include "compositors/hyprland/hyprland_display_backend.h"

#include "core/process/process.h"
#include "util/string_utils.h"

#include <cmath>
#include <nlohmann/json.hpp>
#include <string>

namespace compositors::display {

  namespace {

    [[nodiscard]] std::vector<std::string> monitorKeyword(const std::string& outputName, const OutputState& cfg) {
      const std::string mode = cfg.modeStr.empty() ? "preferred" : cfg.modeStr;
      const auto scale = StringUtils::formatDotDecimal(cfg.scale);
      return {
          "hyprctl", "keyword", "monitor",
          outputName
              + ","
              + mode
              + ","
              + std::to_string(cfg.x)
              + "x"
              + std::to_string(cfg.y)
              + ","
              + scale
              + ",transform,"
              + std::to_string(transformToCode(cfg.transform))
      };
    }

    [[nodiscard]] std::vector<OutputState> parseFetchJson(std::string_view payload, std::string& error) {
      std::vector<OutputState> outputs;
      try {
        const auto json = nlohmann::json::parse(payload);
        if (!json.is_array()) {
          error = "unexpected hyprctl monitors payload";
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
          out.enabled = !mon.value("disabled", false);
          out.make = mon.value("make", "");
          out.model = mon.value("model", "");
          out.x = mon.value("x", 0);
          out.y = mon.value("y", 0);
          out.scale = mon.value("scale", 1.0);
          out.transform = transformFromCode(mon.value("transform", 0));
          out.vrr = mon.value("vrr", false);
          const int width = mon.value("width", 0);
          const int height = mon.value("height", 0);
          const double refreshRate = mon.value("refreshRate", 0.0);
          if (const auto modesIt = mon.find("availableModes"); modesIt != mon.end() && modesIt->is_array()) {
            for (const auto& modeStr : *modesIt) {
              if (!modeStr.is_string()) {
                continue;
              }
              const std::string raw = modeStr.get<std::string>();
              const auto at = raw.find('@');
              if (at == std::string::npos) {
                continue;
              }
              const auto xPos = raw.find('x');
              if (xPos == std::string::npos || xPos > at) {
                continue;
              }
              const int mw = std::stoi(raw.substr(0, xPos));
              const int mh = std::stoi(raw.substr(xPos + 1, at - xPos - 1));
              std::string rateStr = raw.substr(at + 1);
              if (rateStr.ends_with("Hz")) {
                rateStr = rateStr.substr(0, rateStr.size() - 2);
              }
              const int rateMhz = static_cast<int>(std::lround(std::stof(rateStr) * 1000.0));
              DisplayMode mode{mw, mh, rateMhz, false, false};
              if (mw == width && mh == height && std::abs(rateMhz / 1000.0 - refreshRate) < 1.0) {
                mode.current = true;
                out.currentModeIndex = static_cast<int>(out.modes.size());
              }
              out.modes.push_back(mode);
            }
          }
          if (out.modes.empty()) {
            out.modes.push_back(
                DisplayMode{width, height, static_cast<int>(std::lround(refreshRate * 1000.0)), false, true}
            );
            out.currentModeIndex = 0;
          }
          const auto current = static_cast<std::size_t>(out.currentModeIndex);
          out.modeStr = out.modes[current].width != 0 ? std::to_string(out.modes[current].width)
                  + "x"
                  + std::to_string(out.modes[current].height)
                  + "@"
                  + formatRateHz(out.modes[current].refreshMhz)
                                                      : "";
          outputs.push_back(std::move(out));
        }
      } catch (const std::exception& e) {
        error = e.what();
      }
      return outputs;
    }

  } // namespace

  std::vector<std::string> HyprlandDisplayBackend::fetchArgs() const { return {"hyprctl", "monitors", "all", "-j"}; }

  std::vector<OutputState> HyprlandDisplayBackend::parseFetch(std::string_view payload, std::string& error) const {
    return parseFetchJson(payload, error);
  }

  std::vector<DisplayCommand> HyprlandDisplayBackend::changeCommands(
      DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
  ) {
    if (kind == DisplayChangeKind::Vrr) {
      return {};
    }
    if (kind == DisplayChangeKind::Toggle) {
      const auto it = target.find(outputName);
      if (it == target.end()) {
        return {};
      }
      return {DisplayCommand{
          {"hyprctl", "keyword", "monitor", outputName + "," + (it->second.enabled ? "preferred,auto,1" : "disable")},
          std::nullopt
      }};
    }
    if (kind == DisplayChangeKind::Positions) {
      std::vector<DisplayCommand> cmds;
      for (const auto& [name, cfg] : target) {
        if (!cfg.enabled) {
          continue;
        }
        cmds.push_back(DisplayCommand{monitorKeyword(name, cfg), std::nullopt});
      }
      return cmds;
    }
    const auto it = target.find(outputName);
    if (it == target.end() || !it->second.enabled) {
      return {};
    }
    return {DisplayCommand{monitorKeyword(outputName, it->second), std::nullopt}};
  }

  std::vector<DisplayCommand> HyprlandDisplayBackend::revertCommands(
      const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
  ) {
    std::vector<DisplayCommand> onOff;
    std::vector<DisplayCommand> pending;
    for (const auto& [name, snap] : snapshot) {
      const auto curIt = current.find(name);
      const OutputState& cur = curIt != current.end() ? curIt->second : OutputState{};

      if (snap.enabled != cur.enabled) {
        if (!snap.enabled) {
          onOff.push_back(DisplayCommand{{"hyprctl", "keyword", "monitor", name + ",disable"}, std::nullopt});
        } else {
          onOff.push_back(DisplayCommand{monitorKeyword(name, snap), std::nullopt});
        }
      }
      if (!snap.enabled) {
        continue;
      }
      if (snap.modeStr != cur.modeStr
          || std::abs(snap.scale - cur.scale) > 0.01
          || snap.x != cur.x
          || snap.y != cur.y
          || snap.transform != cur.transform) {
        pending.push_back(DisplayCommand{monitorKeyword(name, snap), std::nullopt});
      }
    }
    onOff.insert(onOff.end(), pending.begin(), pending.end());
    return onOff;
  }

} // namespace compositors::display
