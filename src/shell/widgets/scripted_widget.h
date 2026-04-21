#pragma once

#include "shell/widget/widget.h"
#include "ui/palette.h"

#include <memory>
#include <optional>
#include <string>
#include <string_view>

class Flex;
class Glyph;
class InputArea;
class Label;
class LuauHost;

class ScriptedWidget : public Widget {
public:
  explicit ScriptedWidget(std::string scriptPath);
  ~ScriptedWidget() override;

  void create() override;
  bool needsFrameTick() const override { return true; }
  void onFrameTick(float deltaMs) override;

  void luaSetText(std::string_view text);
  void luaSetGlyph(std::string_view name);
  void luaSetGlyphCodepoint(char32_t codepoint);
  void luaSetColor(std::string_view role);
  void luaSetGlyphColor(std::string_view role);

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;

  static std::optional<ColorRole> parseColorRole(std::string_view name);

  std::string m_scriptPath;
  std::unique_ptr<LuauHost> m_host;
  InputArea* m_area = nullptr;
  Flex* m_flex = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  float m_accumMs = 0.0f;
  std::optional<ColorRole> m_textColorRole;
  std::optional<ColorRole> m_glyphColorRole;
  bool m_glyphVisible = false;
};
