#include "shell/lockscreen/lockscreen_login_box.h"

#include "shell/desktop/desktop_widget_layout.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <unordered_set>

namespace lockscreen_login_box {

  bool isLoginBoxWidget(const DesktopWidgetState& state) { return state.type == kWidgetType; }

  bool isLoginBoxWidgetType(std::string_view type) { return type == kWidgetType; }

  bool isLoginBoxWidgetId(std::string_view id) { return id.starts_with(kWidgetIdPrefix); }

  std::string widgetIdForOutput(std::string_view outputKey) { return std::format("{}{}", kWidgetIdPrefix, outputKey); }

  float panelWidth(float screenWidth) { return std::min(screenWidth - Style::spaceLg * 2.0f, 520.0f); }

  float panelHeight() { return 78.0f; }

  void defaultPanelCenter(float screenWidth, float screenHeight, float& cx, float& cy) {
    const float width = panelWidth(screenWidth);
    const float height = panelHeight();
    const float panelX = std::round((screenWidth - width) * 0.5f);
    const float panelY = std::max(Style::spaceLg, screenHeight - height - 84.0f);
    cx = panelX + width * 0.5f;
    cy = panelY + height * 0.5f;
  }

  void
  panelOriginFromCenter(float cx, float cy, float screenWidth, float& panelX, float& panelY, float& panelWidthOut) {
    panelWidthOut = panelWidth(screenWidth);
    const float height = panelHeight();
    panelX = cx - panelWidthOut * 0.5f;
    panelY = cy - height * 0.5f;
  }

  const DesktopWidgetState* findForOutput(const std::vector<DesktopWidgetState>& widgets, std::string_view outputKey) {
    for (const auto& widget : widgets) {
      if (!isLoginBoxWidget(widget)) {
        continue;
      }
      if (widget.outputName == outputKey) {
        return &widget;
      }
    }
    return nullptr;
  }

  void ensureWidgets(std::vector<DesktopWidgetState>& widgets, const WaylandConnection& wayland) {
    std::unordered_set<std::string> outputsWithLoginBox;
    std::erase_if(widgets, [&](const DesktopWidgetState& widget) {
      if (!isLoginBoxWidget(widget)) {
        return false;
      }
      if (widget.outputName.empty() || outputsWithLoginBox.contains(widget.outputName)) {
        return true;
      }
      outputsWithLoginBox.insert(widget.outputName);
      return false;
    });

    for (auto& widget : widgets) {
      if (!isLoginBoxWidget(widget)) {
        continue;
      }
      widget.boxWidth = 0.0f;
      widget.boxHeight = 0.0f;
      widget.rotationRad = 0.0f;
      widget.enabled = true;
      widget.type = std::string(kWidgetType);
      widget.settings.clear();
    }

    for (const auto& output : wayland.outputs()) {
      if (!output.done || output.output == nullptr) {
        continue;
      }
      const std::string outputKey = desktop_widgets::outputKey(output);
      if (outputsWithLoginBox.contains(outputKey)) {
        continue;
      }

      DesktopWidgetState widget;
      widget.id = widgetIdForOutput(outputKey);
      widget.type = std::string(kWidgetType);
      widget.outputName = outputKey;
      widget.rotationRad = 0.0f;
      widget.enabled = true;
      defaultPanelCenter(
          desktop_widgets::outputLogicalWidth(output), desktop_widgets::outputLogicalHeight(output), widget.cx,
          widget.cy
      );
      widgets.insert(widgets.begin(), std::move(widget));
      outputsWithLoginBox.insert(outputKey);
    }
  }

} // namespace lockscreen_login_box
