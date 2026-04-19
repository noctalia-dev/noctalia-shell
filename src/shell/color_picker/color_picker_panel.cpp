#include "shell/color_picker/color_picker_panel.h"

#include "core/deferred_call.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/color_picker.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>
#include <string>

float ColorPickerPanel::preferredWidth() const { return ColorPickerSheet::preferredPanelWidth(contentScale()); }

float ColorPickerPanel::preferredHeight() const {
  return ColorPickerSheet::preferredPanelHeight(preferredWidth(), contentScale());
}

void ColorPickerPanel::create() {
  auto sheet = std::make_unique<ColorPickerSheet>(contentScale());
  sheet->colorPicker()->setColor(resolveThemeColor(roleColor(ColorRole::Primary)));
  sheet->setOnCancel([]() { DeferredCall::callLater([]() { PanelManager::instance().dismissColorPickerPanel(); }); });
  sheet->setOnApply([](const Color& chosen) {
    DeferredCall::callLater([chosen]() {
      PanelManager::instance().notifyColorPickerResult(chosen);
      PanelManager::instance().dismissColorPickerPanel();
    });
  });
  m_sheet = sheet.get();
  setRoot(std::move(sheet));
}

void ColorPickerPanel::onClose() {
  m_sheet = nullptr;
  clearReleasedRoot();
}

void ColorPickerPanel::onOpen(std::string_view context) {
  if (m_sheet == nullptr || m_sheet->colorPicker() == nullptr) {
    return;
  }
  ColorPicker* picker = m_sheet->colorPicker();
  if (context.empty()) {
    picker->setColor(resolveThemeColor(roleColor(ColorRole::Primary)));
    return;
  }
  std::string buf(context);
  while (!buf.empty() && (buf.front() == ' ' || buf.front() == '\t')) {
    buf.erase(buf.begin());
  }
  if (buf.empty()) {
    picker->setColor(resolveThemeColor(roleColor(ColorRole::Primary)));
    return;
  }
  if (buf.front() != '#') {
    buf.insert(buf.begin(), '#');
  }
  try {
    picker->setColor(hex(std::string_view(buf)));
  } catch (...) {
    picker->setColor(resolveThemeColor(roleColor(ColorRole::Primary)));
  }
}

void ColorPickerPanel::doLayout(Renderer& renderer, float width, float height) {
  if (root() == nullptr || m_sheet == nullptr) {
    return;
  }
  const float scale = contentScale();
  const float pad = Style::spaceSm * scale * 2.0f;
  m_sheet->setPickerColumnWidth(std::max(160.0f, width - pad));
  root()->setSize(width, height);
  root()->layout(renderer);
}
