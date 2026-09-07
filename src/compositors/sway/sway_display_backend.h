#pragma once

#include "compositors/display_backend.h"
#include "compositors/sway/sway_runtime.h"

namespace compositors::display {

  class SwayDisplayBackend final : public DisplayBackend {
  public:
    explicit SwayDisplayBackend(compositors::sway::SwayRuntime& runtime);

    std::vector<std::string> fetchArgs() const override;
    std::vector<OutputState> parseFetch(std::string_view payload, std::string& error) const override;
    std::vector<DisplayCommand> changeCommands(
        DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
    ) override;
    std::vector<DisplayCommand> revertCommands(
        const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
    ) override;
    [[nodiscard]] bool writable() const override { return true; }
    [[nodiscard]] std::string kindName() const override { return "sway"; }

  private:
    compositors::sway::SwayRuntime& m_runtime;
  };

} // namespace compositors::display
