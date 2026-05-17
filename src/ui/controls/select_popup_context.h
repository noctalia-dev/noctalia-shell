#pragma once

#include "ui/palette.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

class SelectPopupContext {
public:
  virtual ~SelectPopupContext() = default;

  struct DropdownRequest {
    std::int32_t anchorX = 0;
    std::int32_t anchorY = 0;
    std::int32_t anchorWidth = 1;
    std::int32_t anchorHeight = 1;
    float menuWidth = 0.0f;
    float optionHeight = 0.0f;
    float fontSize = 0.0f;
    float glyphSize = 14.0f;
    float horizontalPadding = 0.0f;
    std::vector<std::string> options;
    std::vector<ColorSpec> indicatorColors;
    std::size_t selectedIndex = static_cast<std::size_t>(-1);
    std::size_t maxVisibleOptions = 6;
  };

  struct DropdownCallbacks {
    std::function<void(std::size_t index)> onSelect;
    std::function<void()> onDismiss;
    std::function<void(std::size_t hoveredIndex)> onHoverChanged;
  };

  virtual void openSelectDropdown(const DropdownRequest& request, DropdownCallbacks callbacks) = 0;
  virtual void closeSelectDropdown() = 0;
  [[nodiscard]] virtual bool isSelectDropdownOpen() const = 0;
};
