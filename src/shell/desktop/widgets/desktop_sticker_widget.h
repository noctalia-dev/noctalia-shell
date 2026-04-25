#pragma once

#include "shell/desktop/desktop_widget.h"

#include <string>

class Image;

class DesktopStickerWidget : public DesktopWidget {
public:
  DesktopStickerWidget(std::string imagePath, float opacity);

  void create() override;

private:
  void doLayout(Renderer& renderer) override;

  std::string m_imagePath;
  float m_opacity = 1.0f;
  Image* m_image = nullptr;
  bool m_loaded = false;
};
