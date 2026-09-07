#pragma once

#include "compositors/display_backend.h"

namespace compositors::display {

  // wlr-randr backend; with readonly=true it only walks DRM sysfs for connected outputs.
  class WlrDisplayBackend final : public DisplayBackend {
  public:
    explicit WlrDisplayBackend(bool readonly);

    std::vector<std::string> fetchArgs() const override;
    std::vector<OutputState> parseFetch(std::string_view payload, std::string& error) const override;
    std::vector<DisplayCommand> changeCommands(
        DisplayChangeKind kind, const std::string& outputName, const std::map<std::string, OutputState>& target
    ) override;
    std::vector<DisplayCommand> revertCommands(
        const std::map<std::string, OutputState>& snapshot, const std::map<std::string, OutputState>& current
    ) override;
    [[nodiscard]] bool writable() const override { return !m_readonly; }
    [[nodiscard]] std::string kindName() const override { return m_readonly ? "readonly" : "wlroots"; }

  private:
    bool m_readonly;
  };

} // namespace compositors::display
