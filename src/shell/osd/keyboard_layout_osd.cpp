#include "shell/osd/keyboard_layout_osd.h"

#include "compositors/compositor_platform.h"
#include "shell/bar/widgets/keyboard_layout_widget.h"
#include "shell/osd/osd_overlay.h"

namespace {

  OsdContent makeKeyboardLayoutContent(const std::string& layoutName) {
    return OsdContent{
        .icon = "keyboard",
        .value = KeyboardLayoutWidget::formatLayoutLabel(layoutName, KeyboardLayoutWidget::DisplayMode::Short),
        .showProgress = false,
    };
  }

} // namespace

void KeyboardLayoutOsd::bindOverlay(OsdOverlay& overlay) { m_overlay = &overlay; }

void KeyboardLayoutOsd::prime(const CompositorPlatform& platform) {
  m_lastLayoutName = platform.currentKeyboardLayoutName();
  m_hasLayout = true;
}

void KeyboardLayoutOsd::onLayoutChanged(const CompositorPlatform& platform) {
  const std::string layoutName = platform.currentKeyboardLayoutName();
  if (layoutName.empty()) {
    return;
  }

  if (!m_hasLayout) {
    m_lastLayoutName = layoutName;
    m_hasLayout = true;
    return;
  }

  if (layoutName == m_lastLayoutName) {
    return;
  }

  m_lastLayoutName = layoutName;
  if (m_overlay == nullptr) {
    return;
  }

  m_overlay->show(makeKeyboardLayoutContent(layoutName));
}
