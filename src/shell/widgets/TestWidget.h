#pragma once

#include "shell/Widget.h"

#include <cstdint>
#include <functional>
#include <string>

class Icon;
struct wl_output;

class TestWidget : public Widget {
public:
  using PanelRequestCallback = std::function<void(const std::string& panelId, wl_output* output, std::int32_t scale,
                                                  float anchorX)>;

  TestWidget(wl_output* output, std::int32_t scale, PanelRequestCallback callback);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  wl_output* m_output;
  std::int32_t m_scale;
  PanelRequestCallback m_panelCallback;
  Icon* m_icon = nullptr;
};
