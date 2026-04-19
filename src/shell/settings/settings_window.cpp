#include "shell/settings/settings_window.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <cmath>
#include <cstdint>
#include <memory>

namespace {

  constexpr Logger kLog("settings");

} // namespace

void SettingsWindow::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
}

float SettingsWindow::uiScale() const {
  if (m_config == nullptr) {
    return 1.0f;
  }
  return std::max(0.1f, m_config->config().shell.uiScale);
}

void SettingsWindow::open() {
  if (m_wayland == nullptr || m_renderContext == nullptr || !m_wayland->hasXdgShell()) {
    return;
  }
  if (isOpen()) {
    return;
  }

  wl_output* output = m_wayland->lastPointerOutput();
  if (output == nullptr) {
    const auto& outs = m_wayland->outputs();
    if (!outs.empty() && outs.front().output != nullptr) {
      output = outs.front().output;
    }
  }

  auto surface = std::make_unique<ToplevelSurface>(*m_wayland);
  surface->setRenderContext(m_renderContext);
  surface->setAnimationManager(&m_animations);

  const float scale = uiScale();
  const std::uint32_t w = static_cast<std::uint32_t>(std::round(640.0f * scale));
  const std::uint32_t h = static_cast<std::uint32_t>(std::round(420.0f * scale));

  ToplevelSurfaceConfig cfg{
      .width = std::max<std::uint32_t>(1, w),
      .height = std::max<std::uint32_t>(1, h),
      .title = "Noctalia Settings",
      .appId = "dev.noctalia.Noctalia",
  };

  if (!surface->initialize(output, cfg)) {
    kLog.warn("settings: failed to create toplevel surface");
    return;
  }

  surface->setClosedCallback([this]() { destroyWindow(); });

  surface->setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) {
    if (m_surface != nullptr) {
      m_surface->requestLayout();
    }
  });

  surface->setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });

  surface->setUpdateCallback([]() {});

  m_surface = std::move(surface);
  m_pointerInside = false;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
}

void SettingsWindow::close() {
  if (!isOpen()) {
    return;
  }
  destroyWindow();
}

void SettingsWindow::destroyWindow() {
  if (m_surface != nullptr) {
    m_inputDispatcher.setSceneRoot(nullptr);
    m_surface->setSceneRoot(nullptr);
  }
  m_sceneRoot.reset();
  m_surface.reset();
  m_pointerInside = false;
  m_lastSceneWidth = 0;
  m_lastSceneHeight = 0;
}

void SettingsWindow::prepareFrame(bool /*needsUpdate*/, bool needsLayout) {
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }

  const auto width = m_surface->width();
  const auto height = m_surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(m_surface->renderTarget());
  m_renderContext->syncContentScale(m_surface->renderTarget());

  const bool sizeChanged = m_sceneRoot == nullptr || m_lastSceneWidth != width || m_lastSceneHeight != height;
  const bool needRebuild = sizeChanged || needsLayout;

  if (needRebuild) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(width, height);
    m_lastSceneWidth = width;
    m_lastSceneHeight = height;
  }
}

void SettingsWindow::buildScene(std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("SettingsWindow::buildScene");
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }

  const float w = static_cast<float>(width);
  const float h = static_cast<float>(height);
  const float scale = uiScale();

  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setSize(w, h);
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  bg->setPosition(0.0f, 0.0f);
  bg->setSize(w, h);
  m_sceneRoot->addChild(std::move(bg));

  auto main = std::make_unique<Flex>();
  main->setDirection(FlexDirection::Vertical);
  main->setAlign(FlexAlign::Stretch);
  main->setJustify(FlexJustify::Start);
  main->setGap(Style::spaceMd * scale);
  main->setPadding(Style::spaceLg * scale);

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setJustify(FlexJustify::SpaceBetween);
  header->setGap(Style::spaceSm * scale);

  auto title = std::make_unique<Label>();
  title->setText("Settings");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(roleColor(ColorRole::OnSurface));
  title->setFlexGrow(1.0f);
  header->addChild(std::move(title));

  auto closeBtn = std::make_unique<Button>();
  closeBtn->setGlyph("close");
  closeBtn->setVariant(ButtonVariant::Default);
  closeBtn->setGlyphSize(Style::fontSizeBody * scale);
  closeBtn->setMinWidth(Style::controlHeightSm * scale);
  closeBtn->setMinHeight(Style::controlHeightSm * scale);
  closeBtn->setPadding(Style::spaceXs * scale);
  closeBtn->setRadius(Style::radiusMd * scale);
  closeBtn->setOnClick([this]() { close(); });
  header->addChild(std::move(closeBtn));

  main->addChild(std::move(header));

  auto body = std::make_unique<Label>();
  body->setText("Shell settings will live here... at some point :p.");
  body->setFontSize(Style::fontSizeBody * scale);
  body->setColor(roleColor(ColorRole::OnSurfaceVariant));
  main->addChild(std::move(body));

  main->setSize(w, h);
  main->layout(*m_renderContext);

  m_sceneRoot->addChild(std::move(main));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());
}

bool SettingsWindow::onPointerEvent(const PointerEvent& event) {
  if (!isOpen() || m_surface == nullptr) {
    return false;
  }

  wl_surface* const ws = m_surface->wlSurface();
  const bool onThis = (event.surface != nullptr && event.surface == ws);
  bool consumed = false;

  switch (event.type) {
  case PointerEvent::Type::Enter:
    if (onThis) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    }
    break;
  case PointerEvent::Type::Leave:
    if (onThis) {
      m_pointerInside = false;
      m_inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (onThis || m_pointerInside) {
      if (onThis) {
        m_pointerInside = true;
      }
      m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      consumed = m_pointerInside;
    }
    break;
  case PointerEvent::Type::Button: {
    const bool pressed = (event.state == 1);
    if (onThis || m_pointerInside) {
      if (onThis) {
        m_pointerInside = true;
      }
      m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                      pressed);
      consumed = m_pointerInside;
    }
    break;
  }
  case PointerEvent::Type::Axis:
    if (m_pointerInside) {
      m_inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                    event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                    event.axisLines);
      consumed = true;
    }
    break;
  }

  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }

  return consumed;
}

void SettingsWindow::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isOpen() || m_config == nullptr) {
    return;
  }
  if (event.pressed && m_config->matchesKeybind(KeybindAction::Cancel, event.sym, event.modifiers)) {
    close();
    return;
  }
  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_sceneRoot != nullptr && m_surface != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }
}

void SettingsWindow::onThemeChanged() {
  if (isOpen()) {
    m_surface->requestRedraw();
  }
}

void SettingsWindow::onFontChanged() {
  if (isOpen()) {
    m_surface->requestLayout();
  }
}
