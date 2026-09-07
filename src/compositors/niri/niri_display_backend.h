#pragma once

#include "compositors/display_backend.h"

namespace compositors::display {

  class NiriDisplayBackend final : public DisplayBackend {
  public:
    std::vector<std::string> fetchArgs() const override;
    std::vector<OutputState> parseFetch(std::string_view payload, std::string& error) const override;
    std::vector<DisplayCommand> changeCommands(
        DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
    ) override;
    std::vector<DisplayCommand> revertCommands(
        const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
    ) override;
    [[nodiscard]] bool writable() const override { return true; }
    [[nodiscard]] std::string kindName() const override { return "niri"; }
  };

} // namespace compositors::display
