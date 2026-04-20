#pragma once

#include "shell/desktop/desktop_widget.h"

#include <string>

class Image;

class DesktopStickerWidget : public DesktopWidget {
public:
  explicit DesktopStickerWidget(std::string imagePath);

  void create() override;

private:
  void doLayout(Renderer& renderer) override;

  std::string m_imagePath;
  Image* m_image = nullptr;
  bool m_loaded = false;
};
