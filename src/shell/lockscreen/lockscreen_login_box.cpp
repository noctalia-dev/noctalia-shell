#include "shell/lockscreen/lockscreen_login_box.h"

#include "shell/desktop/desktop_widget_layout.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <format>
#include <unordered_set>

namespace lockscreen_login_box {

  namespace {

    [[nodiscard]] float readFloat(
        const std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view key, float fallback
    ) {
      const auto it = settings.find(std::string(key));
      if (it == settings.end()) {
        return fallback;
      }
      if (const auto* value = std::get_if<double>(&it->second)) {
        return static_cast<float>(*value);
      }
      if (const auto* value = std::get_if<std::int64_t>(&it->second)) {
        return static_cast<float>(*value);
      }
      return fallback;
    }

    [[nodiscard]] bool
    readBool(const std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view key, bool fallback) {
      const auto it = settings.find(std::string(key));
      if (it == settings.end()) {
        return fallback;
      }
      if (const auto* value = std::get_if<bool>(&it->second)) {
        return *value;
      }
      return fallback;
    }

    [[nodiscard]] std::string readString(
        const std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view key,
        std::string_view fallback
    ) {
      const auto it = settings.find(std::string(key));
      if (it == settings.end()) {
        return std::string(fallback);
      }
      if (const auto* value = std::get_if<std::string>(&it->second)) {
        return *value;
      }
      return std::string(fallback);
    }

    void clampOpacitySetting(std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view key) {
      const std::string keyStr(key);
      const auto it = settings.find(keyStr);
      if (it == settings.end()) {
        return;
      }
      if (const auto* doubleValue = std::get_if<double>(&it->second)) {
        settings.insert_or_assign(keyStr, std::clamp(*doubleValue, 0.0, 1.0));
        return;
      }
      if (const auto* intValue = std::get_if<std::int64_t>(&it->second)) {
        settings.insert_or_assign(keyStr, std::clamp(static_cast<double>(*intValue), 0.0, 1.0));
      }
    }

    void clampRadiusSetting(std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view key) {
      const std::string keyStr(key);
      const auto it = settings.find(keyStr);
      if (it == settings.end()) {
        return;
      }
      if (const auto* doubleValue = std::get_if<double>(&it->second)) {
        settings.insert_or_assign(keyStr, std::clamp(*doubleValue, 0.0, 32.0));
        return;
      }
      if (const auto* intValue = std::get_if<std::int64_t>(&it->second)) {
        settings.insert_or_assign(keyStr, std::clamp(static_cast<double>(*intValue), 0.0, 32.0));
      }
    }

  } // namespace

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

  LoginBoxStyle resolveStyle(const std::unordered_map<std::string, WidgetSettingValue>& settings) {
    LoginBoxStyle style;
    ColorSpec panelFill =
        colorSpecFromConfigString(readString(settings, "background_color", "surface_variant"), "background_color");
    panelFill.alpha *= std::clamp(readFloat(settings, "background_opacity", 0.88f), 0.0f, 1.0f);
    style.panelFill = panelFill;
    style.panelRadius = std::clamp(readFloat(settings, "background_radius", style.panelRadius), 0.0f, 32.0f);
    style.inputOpacity = std::clamp(readFloat(settings, kInputOpacityKey, style.inputOpacity), 0.0f, 1.0f);
    style.inputRadius = std::clamp(readFloat(settings, kInputRadiusKey, style.inputRadius), 0.0f, 32.0f);
    style.showLoginButton = readBool(settings, kShowLoginButtonKey, style.showLoginButton);
    return style;
  }

  void applyDefaultSettings(
      std::unordered_map<std::string, WidgetSettingValue>& settings, desktop_settings::DesktopWidgetSettingsScope scope
  ) {
    if (scope == desktop_settings::DesktopWidgetSettingsScope::Widget) {
      settings.insert_or_assign(std::string(kShowLoginButtonKey), true);
      settings.insert_or_assign(std::string(kInputOpacityKey), 1.0);
      settings.insert_or_assign(std::string(kInputRadiusKey), 6.0);
    }
    if (scope == desktop_settings::DesktopWidgetSettingsScope::Background) {
      settings.insert_or_assign("background_color", std::string("surface_variant"));
      settings.insert_or_assign("background_opacity", 0.88);
      settings.insert_or_assign("background_radius", 12.0);
    }
  }

  void applyAllDefaultSettings(std::unordered_map<std::string, WidgetSettingValue>& settings) {
    applyDefaultSettings(settings, desktop_settings::DesktopWidgetSettingsScope::Widget);
    applyDefaultSettings(settings, desktop_settings::DesktopWidgetSettingsScope::Background);
  }

  void normalizeSettings(std::unordered_map<std::string, WidgetSettingValue>& settings) {
    if (!settings.contains(std::string(kShowLoginButtonKey))) {
      settings.insert_or_assign(std::string(kShowLoginButtonKey), true);
    }
    clampOpacitySetting(settings, "background_opacity");
    clampRadiusSetting(settings, "background_radius");
    clampOpacitySetting(settings, kInputOpacityKey);
    clampRadiusSetting(settings, kInputRadiusKey);
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
      normalizeSettings(widget.settings);
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
      applyDefaultSettings(widget.settings, desktop_settings::DesktopWidgetSettingsScope::Widget);
      applyDefaultSettings(widget.settings, desktop_settings::DesktopWidgetSettingsScope::Background);
      widgets.insert(widgets.begin(), std::move(widget));
      outputsWithLoginBox.insert(outputKey);
    }
  }

} // namespace lockscreen_login_box
