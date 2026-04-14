#pragma once

#include "shell/widget/widget.h"

#include <memory>
#include <string>

class Label;
class LuauHost;

class ScriptedWidget : public Widget {
public:
  explicit ScriptedWidget(std::string scriptPath);
  ~ScriptedWidget() override;

  void create() override;
  bool needsFrameTick() const override { return true; }
  void onFrameTick(float deltaMs) override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;

  std::string m_scriptPath;
  std::unique_ptr<LuauHost> m_host;
  Label* m_label = nullptr;
  std::string m_lastText;
  float m_accumMs = 0.0f;
};
