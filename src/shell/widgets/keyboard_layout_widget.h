#pragma once

#include "compositors/keyboard_backend.h"
#include "core/timer_manager.h"
#include "shell/widget/widget.h"

#include <string>

class Glyph;
class Label;
class Renderer;
class WaylandConnection;

class KeyboardLayoutWidget : public Widget {
public:
  enum class DisplayMode : std::uint8_t { Short = 0, Full = 1 };

  KeyboardLayoutWidget(WaylandConnection& wayland, std::string cycleCommand, DisplayMode displayMode);
  static DisplayMode parseDisplayMode(const std::string& value);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void sync(Renderer& renderer);
  [[nodiscard]] std::string resolvedLayoutName() const;
  void armRefreshTick();
  void scheduleRefreshBurst();
  void cycleLayout();
  static std::string formatLayoutLabel(const std::string& layoutName, DisplayMode displayMode);

  WaylandConnection& m_wayland;
  KeyboardBackend m_keyboardBackend;
  std::string m_cycleCommand;
  DisplayMode m_displayMode = DisplayMode::Short;

  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;

  std::string m_lastLayoutName;
  std::string m_lastLabel;
  std::string m_pendingLayoutName;
  bool m_clickArmed = false;
  int m_refreshAttemptsRemaining = 0;
  Timer m_refreshTimer;
  Timer m_idleRefreshTimer;
  bool m_isVertical = false;
  bool m_lastVertical = false;
};
