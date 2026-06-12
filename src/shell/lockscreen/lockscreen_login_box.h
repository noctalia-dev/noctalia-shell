#pragma once

#include "config/config_types.h"
#include "shell/desktop/desktop_widget_settings_registry.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace lockscreen_login_box {

  constexpr std::string_view kWidgetType = "login_box";
  constexpr std::string_view kWidgetIdPrefix = "lockscreen-login-box@";

  constexpr std::string_view kInputOpacityKey = "input_opacity";
  constexpr std::string_view kInputRadiusKey = "input_radius";
  constexpr std::string_view kShowLoginButtonKey = "show_login_button";

  struct LoginBoxStyle {
    ColorSpec panelFill = colorSpecFromRole(ColorRole::SurfaceVariant, 0.88f);
    float panelRadius = 12.0f;
    float inputOpacity = 1.0f;
    float inputRadius = 6.0f;
    bool showLoginButton = true;
  };

  [[nodiscard]] bool isLoginBoxWidget(const DesktopWidgetState& state);
  [[nodiscard]] bool isLoginBoxWidgetType(std::string_view type);
  [[nodiscard]] bool isLoginBoxWidgetId(std::string_view id);
  [[nodiscard]] std::string widgetIdForOutput(std::string_view outputKey);

  [[nodiscard]] float panelWidth(float screenWidth);
  [[nodiscard]] float panelHeight();
  void defaultPanelCenter(float screenWidth, float screenHeight, float& cx, float& cy);
  void panelOriginFromCenter(float cx, float cy, float screenWidth, float& panelX, float& panelY, float& panelWidthOut);

  [[nodiscard]] const DesktopWidgetState*
  findForOutput(const std::vector<DesktopWidgetState>& widgets, std::string_view outputKey);

  [[nodiscard]] LoginBoxStyle resolveStyle(const std::unordered_map<std::string, WidgetSettingValue>& settings);
  void applyDefaultSettings(
      std::unordered_map<std::string, WidgetSettingValue>& settings, desktop_settings::DesktopWidgetSettingsScope scope
  );
  void applyAllDefaultSettings(std::unordered_map<std::string, WidgetSettingValue>& settings);
  void normalizeSettings(std::unordered_map<std::string, WidgetSettingValue>& settings);

  void ensureWidgets(std::vector<DesktopWidgetState>& widgets, const WaylandConnection& wayland);

} // namespace lockscreen_login_box
