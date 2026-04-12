#include "shell/lockscreen/lock_surface.h"

#include "render/programs/rounded_rect_program.h"
#include "render/render_context.h"
#include "render/scene/image_node.h"
#include "render/scene/rect_node.h"
#include "ui/controls/button.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <memory>
#include <wayland-client.h>

#include "ext-session-lock-v1-client-protocol.h"

namespace {

const ext_session_lock_surface_v1_listener kLockSurfaceListener = {
    .configure = &LockSurface::handleConfigure,
};

} // namespace

LockSurface::LockSurface(WaylandConnection& connection) : Surface(connection) {
  auto wallpaper = std::make_unique<ImageNode>();
  m_wallpaper = static_cast<ImageNode*>(m_root.addChild(std::move(wallpaper)));

  auto backdrop = std::make_unique<RectNode>();
  m_backdrop = static_cast<RectNode*>(m_root.addChild(std::move(backdrop)));

  auto clockShadow = std::make_unique<Label>();
  m_clockShadow = static_cast<Label*>(m_root.addChild(std::move(clockShadow)));

  auto clock = std::make_unique<Label>();
  clock->setColor(roleColor(ColorRole::Primary));
  m_clock = static_cast<Label*>(m_root.addChild(std::move(clock)));

  auto loginPanel = std::make_unique<RectNode>();
  m_loginPanel = static_cast<RectNode*>(m_root.addChild(std::move(loginPanel)));

  auto passwordField = std::make_unique<Input>();
  passwordField->setPlaceholder("Password");
  m_passwordField = static_cast<Input*>(m_root.addChild(std::move(passwordField)));

  auto loginButton = std::make_unique<Button>();
  loginButton->setText("");
  loginButton->setGlyph("check");
  loginButton->setGlyphSize(16.0f);
  loginButton->setVariant(ButtonVariant::Accent);
  loginButton->setOnClick([this]() {
    if (m_onLogin) {
      m_onLogin();
    }
  });
  m_loginButton = static_cast<Button*>(m_root.addChild(std::move(loginButton)));

  m_inputDispatcher.setSceneRoot(&m_root);
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_connection.setCursorShape(serial, shape); });

  setSceneRoot(&m_root);
  setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) { requestLayout(); });
  setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });
  requestUpdate();
}

LockSurface::~LockSurface() {
  if (renderContext() != nullptr) {
    renderContext()->textureManager().unload(m_wallpaperTexture);
  }
  if (m_lockSurface != nullptr) {
    ext_session_lock_surface_v1_destroy(m_lockSurface);
    m_lockSurface = nullptr;
  }
}

bool LockSurface::initialize(ext_session_lock_v1* lock, wl_output* output, std::int32_t scale) {
  if (lock == nullptr || output == nullptr || renderContext() == nullptr) {
    return false;
  }

  if (!createWlSurface()) {
    return false;
  }

  m_output = output;
  setBufferScale(scale);

  m_lockSurface = ext_session_lock_v1_get_lock_surface(lock, m_surface, output);
  if (m_lockSurface == nullptr) {
    destroySurface();
    return false;
  }

  if (ext_session_lock_surface_v1_add_listener(m_lockSurface, &kLockSurfaceListener, this) != 0) {
    ext_session_lock_surface_v1_destroy(m_lockSurface);
    m_lockSurface = nullptr;
    destroySurface();
    return false;
  }

  setRunning(true);
  return true;
}

void LockSurface::setLockedState(bool locked) {
  if (m_locked == locked) {
    return;
  }
  m_locked = locked;
  if (m_locked && m_passwordField != nullptr) {
    m_inputDispatcher.setFocus(m_passwordField->inputArea());
  } else {
    m_inputDispatcher.setFocus(nullptr);
  }
  requestUpdate();
}

void LockSurface::setPromptState(std::string user, std::string maskedPassword, std::string status, bool error) {
  if (m_user == user && m_maskedPassword == maskedPassword && m_status == status && m_error == error) {
    return;
  }
  m_user = std::move(user);
  m_maskedPassword = std::move(maskedPassword);
  m_status = std::move(status);
  m_error = error;
  requestUpdate();
}

void LockSurface::setWallpaperPath(std::string wallpaperPath) {
  if (m_wallpaperPath == wallpaperPath) {
    return;
  }
  m_wallpaperPath = std::move(wallpaperPath);
  m_wallpaperDirty = true;
  requestLayout();
}

void LockSurface::setOnLogin(std::function<void()> onLogin) { m_onLogin = std::move(onLogin); }

void LockSurface::selectAllPassword() {
  if (m_passwordField == nullptr) {
    return;
  }
  m_passwordField->selectAll();
  requestLayout();
}

void LockSurface::clearPasswordSelection() {
  if (m_passwordField == nullptr) {
    return;
  }
  m_passwordField->clearSelection();
  requestLayout();
}

void LockSurface::onPointerEvent(const PointerEvent& event) {
  switch (event.type) {
  case PointerEvent::Type::Enter:
    m_inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    break;
  case PointerEvent::Type::Leave:
    m_inputDispatcher.pointerLeave();
    break;
  case PointerEvent::Type::Motion:
    m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    break;
  case PointerEvent::Type::Button:
    m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                    event.state == WL_POINTER_BUTTON_STATE_PRESSED);
    break;
  case PointerEvent::Type::Axis:
    m_inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                  event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                  event.axisLines);
    break;
  }

  if (m_root.dirty()) {
    requestLayout();
  }
}

void LockSurface::onSecondTick() {
  using clock = std::chrono::system_clock;
  const std::time_t t = clock::to_time_t(clock::now());
  std::tm local{};
  localtime_r(&t, &local);
  char buf[16];
  std::strftime(buf, sizeof(buf), "%H:%M", &local);
  if (m_clock != nullptr && m_clock->text() != buf) {
    requestUpdate();
  }
}

void LockSurface::onThemeChanged() { requestLayout(); }

void LockSurface::onKeyboardEvent(const KeyboardEvent& event) {
  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_root.dirty()) {
    requestLayout();
  }
}

void LockSurface::handleConfigure(void* data, ext_session_lock_surface_v1* lockSurface, std::uint32_t serial,
                                  std::uint32_t width, std::uint32_t height) {
  auto* self = static_cast<LockSurface*>(data);
  ext_session_lock_surface_v1_ack_configure(lockSurface, serial);
  self->Surface::onConfigure(width, height);
}

void LockSurface::prepareFrame(bool needsUpdate, bool needsLayout) {
  auto* renderer = renderContext();
  if (renderer == nullptr || width() == 0 || height() == 0) {
    return;
  }

  renderer->makeCurrent(renderTarget());

  if (needsUpdate) {
    updateCopy();
  }

  if (needsUpdate || needsLayout) {
    layoutScene(width(), height());
  }
}

void LockSurface::layoutScene(std::uint32_t width, std::uint32_t height) {
  auto* renderer = renderContext();
  if (renderer == nullptr) {
    return;
  }
  ensureWallpaperTexture();

  const float sw = static_cast<float>(width);
  const float sh = static_cast<float>(height);
  const float panelWidth = std::min(sw - Style::spaceLg * 2.0f, 520.0f);
  const float panelHeight = 78.0f;
  const float panelX = std::round((sw - panelWidth) * 0.5f);
  const float panelY = std::max(Style::spaceLg, sh - panelHeight - 84.0f);

  m_root.setSize(sw, sh);

  m_wallpaper->setPosition(0.0f, 0.0f);
  m_wallpaper->setSize(sw, sh);
  m_wallpaper->setTint(Color{1.0f, 1.0f, 1.0f, 0.95f});

  m_backdrop->setPosition(0.0f, 0.0f);
  m_backdrop->setSize(sw, sh);
  m_backdrop->setVisible(false);

  constexpr float kClockFontSize = 64.0f;
  m_clock->setFontSize(kClockFontSize);
  m_clock->setBold(true);
  m_clock->measure(*renderer);
  const float clockX = sw - 48.0f - m_clock->width();
  const float clockY = 86.0f;

  m_clockShadow->setVisible(m_clockShadowEnabled);
  m_clockShadow->setFontSize(kClockFontSize);
  m_clockShadow->setBold(true);
  m_clockShadow->setColor(roleColor(ColorRole::Shadow, 0.55f));
  m_clockShadow->setText(m_clock->text());
  m_clockShadow->measure(*renderer);
  m_clockShadow->setPosition(clockX + 3.0f, clockY + 4.0f);
  m_clock->setPosition(clockX, clockY);

  m_loginPanel->setPosition(panelX, panelY);
  m_loginPanel->setSize(panelWidth, panelHeight);
  m_loginPanel->setStyle(RoundedRectStyle{
      .fill = resolveThemeColor(roleColor(ColorRole::SurfaceVariant, 0.88f)),
      .border = resolveThemeColor(roleColor(ColorRole::Outline, 0.95f)),
      .fillMode = FillMode::Solid,
      .radius = Style::radiusXl,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });

  const float contentLeft = panelX + Style::spaceLg;
  const float contentTop = panelY + 22.0f;
  const float rightInset = Style::spaceLg + Style::spaceSm;
  const float contentWidth = panelWidth - Style::spaceLg - rightInset;
  const float buttonWidth = Style::controlHeight;
  const float gap = Style::spaceSm;
  const float inputWidth = std::max(120.0f, contentWidth - buttonWidth - gap);

  m_passwordField->setSize(inputWidth, 0.0f);
  m_passwordField->setPosition(contentLeft, contentTop);
  m_passwordField->layout(*renderer);

  m_loginButton->setSize(buttonWidth, Style::controlHeight);
  m_loginButton->setPosition(contentLeft + inputWidth + gap, contentTop);
  m_loginButton->layout(*renderer);

  m_root.markDirty();
}

void LockSurface::updateCopy() {
  m_passwordField->setValue(m_maskedPassword);
  updateClockText();
}

void LockSurface::ensureWallpaperTexture() {
  auto* renderer = renderContext();
  if (renderer == nullptr || !m_wallpaperDirty || !renderTarget().isReady()) {
    return;
  }

  renderer->makeCurrent(renderTarget());

  if (m_wallpaperTexture.id != 0) {
    renderer->textureManager().unload(m_wallpaperTexture);
  }

  if (!m_wallpaperPath.empty()) {
    m_wallpaperTexture = renderer->textureManager().loadFromFile(m_wallpaperPath);
    m_wallpaper->setTextureId(m_wallpaperTexture.id);
    m_wallpaper->setTint(Color{1.0f, 1.0f, 1.0f, 1.0f});
  } else {
    m_wallpaperTexture = {};
    m_wallpaper->setTextureId(0);
  }

  m_wallpaperDirty = false;
}

void LockSurface::updateClockText() {
  using clock = std::chrono::system_clock;
  const std::time_t t = clock::to_time_t(clock::now());
  std::tm local{};
  localtime_r(&t, &local);
  char buf[16];
  std::strftime(buf, sizeof(buf), "%H:%M", &local);
  m_clock->setText(buf);
}
