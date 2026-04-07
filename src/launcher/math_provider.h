#pragma once

#include "launcher/launcher_provider.h"

class MathProvider : public LauncherProvider {
public:
  [[nodiscard]] std::string_view prefix() const override { return ""; }
  [[nodiscard]] std::string_view name() const override { return "Calculator"; }

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;
};
