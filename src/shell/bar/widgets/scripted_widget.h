#pragma once

#include "config/config_service.h"
#include "core/file_watcher.h"
#include "shell/bar/widget.h"
#include "ui/palette.h"

#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

class Flex;
class Glyph;
class InputArea;
class Label;
class LuauHost;

class ScriptedWidget : public Widget {
public:
  explicit ScriptedWidget(std::string scriptPath, const WidgetConfig* config = nullptr,
                          FileWatcher* fileWatcher = nullptr);
  ~ScriptedWidget() override;

  void create() override;
  bool needsFrameTick() const override { return true; }
  void onFrameTick(float deltaMs) override;

  void luaSetText(std::string_view text);
  void luaSetGlyph(std::string_view name);
  void luaSetGlyphCodepoint(char32_t codepoint);
  void luaSetColor(std::string_view role);
  void luaSetGlyphColor(std::string_view role);
  void luaSetVisible(bool visible);
  void luaSetUpdateInterval(float ms);
  [[nodiscard]] bool isVertical() const { return m_isVertical; }

  [[nodiscard]] const std::unordered_map<std::string, WidgetSettingValue>& settings() const { return m_settings; }

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;

  static std::optional<ColorRole> parseColorRole(std::string_view name);

  void reloadScript();
  void setupScriptWatch();
  void teardownScriptWatch();

  std::string m_scriptPath;
  std::filesystem::path m_resolvedPath;
  std::unordered_map<std::string, WidgetSettingValue> m_settings;
  std::unique_ptr<LuauHost> m_host;
  FileWatcher* m_fileWatcher = nullptr;
  FileWatcher::WatchId m_watchId = 0;
  InputArea* m_area = nullptr;
  Flex* m_flex = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  float m_accumMs = 0.0f;
  std::optional<ColorRole> m_textColorRole;
  std::optional<ColorRole> m_glyphColorRole;
  float m_updateIntervalMs = 250.0f;
  bool m_isVertical = false;
  bool m_glyphVisible = false;
  bool m_hotReload = false;
};
