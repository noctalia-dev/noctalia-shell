#pragma once

#include "config/config_types.h"
#include "ui/controls/flex.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

class Glyph;
class InputArea;
class Label;
class Renderer;

// Records a KeyChord from live keyboard input. Rejects any chord involving Super.
class KeybindRecorder : public Flex {
public:
  KeybindRecorder();
  ~KeybindRecorder() override;

  void setChord(std::optional<KeyChord> chord);
  [[nodiscard]] std::optional<KeyChord> chord() const noexcept { return m_chord; }
  void setScale(float scale);
  void setEnabled(bool enabled);
  void setUnsetPlaceholder(std::string_view text);
  void setRecordingPlaceholder(std::string_view text);
  void setOnCommit(std::function<void(KeyChord)> callback);

  [[nodiscard]] bool isRecording() const noexcept { return m_recording; }

private:
  enum class VisualState : std::uint8_t {
    Idle,
    Recording,
  };

  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;
  void handleKeyDown(std::uint32_t sym, std::uint32_t modifiers);
  void handleKeyUp(std::uint32_t sym, std::uint32_t modifiers);
  void enterRecording();
  void exitRecording(bool commit);
  void refreshLabel();
  void applyVisualState(VisualState state);
  [[nodiscard]] static bool isModifierKeysym(std::uint32_t sym);
  [[nodiscard]] static bool isSuperKeysym(std::uint32_t sym);

  Label* m_label = nullptr;
  Glyph* m_glyph = nullptr;
  InputArea* m_inputArea = nullptr;
  std::optional<KeyChord> m_chord;
  std::function<void(KeyChord)> m_onCommit;
  std::string m_unsetPlaceholder;
  std::string m_recordingPlaceholder;
  std::uint32_t m_pendingModifiers = 0;
  float m_scale = 1.0f;
  bool m_recording = false;
  bool m_enabled = true;
  VisualState m_visualState = VisualState::Idle;
};
