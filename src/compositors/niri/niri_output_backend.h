#pragma once

#include <optional>
#include <string>

namespace compositors::niri {
  class NiriRuntime;
} // namespace compositors::niri

class NiriOutputBackend {
public:
  explicit NiriOutputBackend(compositors::niri::NiriRuntime& runtime);

  [[nodiscard]] std::optional<std::string> focusedOutputName() const;

private:
  compositors::niri::NiriRuntime& m_runtime;
};

namespace compositors::niri {

  [[nodiscard]] bool setOutputPower(NiriRuntime& runtime, bool on);

} // namespace compositors::niri
