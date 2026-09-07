#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace compositors {

  class CompositorRuntimeRegistry;

  namespace display {

    struct DisplayMode {
      int width = 0;
      int height = 0;
      int refreshMhz = 60000;
      bool preferred = false;
      bool current = false;
    };

    struct OutputState {
      std::string name;
      bool enabled = true;
      std::string make;
      std::string model;
      std::string modeStr; // "1920x1080@60.000"
      double scale = 1.0;
      std::string transform = "Normal"; // Normal|90|180|270|Flipped|Flipped90|Flipped180|Flipped270
      int x = 0;
      int y = 0;
      bool vrr = false;
      std::vector<DisplayMode> modes;
      int currentModeIndex = 0;
    };

    struct DisplayCommand {
      std::vector<std::string> args;
      std::optional<int> sleepMs; // set = wait before the next command
    };

    enum class DisplayChangeKind : std::uint8_t { Mode, Scale, Transform, Vrr, Toggle, Positions };

    class DisplayBackend {
    public:
      virtual ~DisplayBackend() = default;

      // Empty args = in-process fetch (readonly backend).
      virtual std::vector<std::string> fetchArgs() const = 0;
      virtual std::vector<OutputState> parseFetch(std::string_view payload, std::string& error) const = 0;
      virtual std::vector<DisplayCommand> changeCommands(
          DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
      ) = 0;
      virtual std::vector<DisplayCommand> revertCommands(
          const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
      ) = 0;
      [[nodiscard]] virtual bool writable() const = 0;
      [[nodiscard]] virtual std::string kindName() const = 0;
    };

    [[nodiscard]] std::unique_ptr<DisplayBackend> createDisplayBackend(CompositorRuntimeRegistry& runtimeRegistry);

    // Canonical transform names shared by all backends (niri/sway/wlr-randr spell them lowercase).
    [[nodiscard]] std::string_view transformToName(std::string_view transform);
    [[nodiscard]] std::string transformFromName(std::string_view name);
    [[nodiscard]] std::string transformFromCode(int code);
    [[nodiscard]] int transformToCode(std::string_view transform);
    [[nodiscard]] std::string swayModeStr(std::string_view modeStr);
    [[nodiscard]] std::string formatRateHz(int refreshMhz);
    [[nodiscard]] bool rotatedTransform(std::string_view transform);

  } // namespace display

} // namespace compositors
