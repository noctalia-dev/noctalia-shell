#include "shell/lockscreen/lock_screen.h"

#include "core/log.h"
#include "config/config_service.h"
#include "render/render_context.h"
#include "shell/lockscreen/lock_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <string>

#include <wayland-client.h>
#include <xkbcommon/xkbcommon-keysyms.h>

#include "ext-session-lock-v1-client-protocol.h"

namespace {

constexpr Logger kLog("lockscreen");

const ext_session_lock_v1_listener kSessionLockListener = {
    .locked = &LockScreen::handleLocked,
    .finished = &LockScreen::handleFinished,
};

bool hasTextInputModifiers(std::uint32_t modifiers) {
  return (modifiers & (KeyMod::Ctrl | KeyMod::Alt | KeyMod::Super)) != 0;
}

std::string utf32ToUtf8(std::uint32_t cp) {
  std::string out;
  if (cp <= 0x7F) {
    out.push_back(static_cast<char>(cp));
  } else if (cp <= 0x7FF) {
    out.push_back(static_cast<char>(0xC0U | ((cp >> 6) & 0x1FU)));
    out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
  } else if (cp <= 0xFFFF) {
    out.push_back(static_cast<char>(0xE0U | ((cp >> 12) & 0x0FU)));
    out.push_back(static_cast<char>(0x80U | ((cp >> 6) & 0x3FU)));
    out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
  } else {
    out.push_back(static_cast<char>(0xF0U | ((cp >> 18) & 0x07U)));
    out.push_back(static_cast<char>(0x80U | ((cp >> 12) & 0x3FU)));
    out.push_back(static_cast<char>(0x80U | ((cp >> 6) & 0x3FU)));
    out.push_back(static_cast<char>(0x80U | (cp & 0x3FU)));
  }
  return out;
}

std::size_t prevUtf8Pos(const std::string& s, std::size_t pos) {
  if (pos == 0 || s.empty()) {
    return 0;
  }
  std::size_t p = std::min(pos, s.size()) - 1;
  while (p > 0 && (static_cast<unsigned char>(s[p]) & 0xC0U) == 0x80U) {
    --p;
  }
  return p;
}

std::size_t utf8CodepointCount(const std::string& s) {
  std::size_t count = 0;
  for (std::size_t i = 0; i < s.size(); ++count) {
    const unsigned char c = static_cast<unsigned char>(s[i]);
    if ((c & 0x80U) == 0) {
      i += 1;
    } else if ((c & 0xE0U) == 0xC0U) {
      i += 2;
    } else if ((c & 0xF0U) == 0xE0U) {
      i += 3;
    } else if ((c & 0xF8U) == 0xF0U) {
      i += 4;
    } else {
      i += 1;
    }
  }
  return count;
}

std::string maskedCircles(std::size_t count) {
  std::string out;
  out.reserve(count * 3);
  for (std::size_t i = 0; i < count; ++i) {
    out += "\xE2\x97\x8F"; // U+25CF
  }
  return out;
}

} // namespace

namespace {
LockScreen* g_lockScreenInstance = nullptr;
}

void LockScreen::setInstance(LockScreen* instance) { g_lockScreenInstance = instance; }
LockScreen* LockScreen::instance() { return g_lockScreenInstance; }

LockScreen::LockScreen() = default;

LockScreen::~LockScreen() {
  clearInstances();
  resetLockState();
}

bool LockScreen::initialize(WaylandConnection& wayland, RenderContext* renderContext, ConfigService* configService,
                            SharedTextureCache* textureCache) {
  m_wayland = &wayland;
  m_renderContext = renderContext;
  m_configService = configService;
  m_textureCache = textureCache;
  m_user = PamAuthenticator::currentUsername();
  return true;
}

bool LockScreen::lock() {
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return false;
  }
  if (isActive()) {
    return true;
  }
  if (!m_wayland->hasSessionLockManager()) {
    kLog.warn("session lock protocol unavailable");
    return false;
  }

  m_lock = ext_session_lock_manager_v1_lock(m_wayland->sessionLockManager());
  if (m_lock == nullptr) {
    kLog.warn("failed to create session lock object");
    return false;
  }
  if (ext_session_lock_v1_add_listener(m_lock, &kSessionLockListener, this) != 0) {
    ext_session_lock_v1_destroy(m_lock);
    m_lock = nullptr;
    kLog.warn("failed to register session lock listener");
    return false;
  }

  m_lockPending = true;
  m_locked = false;
  clearSensitiveString(m_password);
  m_passwordSelectedAll = false;
  m_status = "Waiting for lock confirmation...";
  m_statusIsError = false;
  syncInstances();
  if (m_instances.empty()) {
    kLog.warn("no outputs available for lock screen");
    resetLockState();
    return false;
  }
  wl_display_flush(m_wayland->display());
  kLog.info("session lock requested");
  return true;
}

void LockScreen::unlock() {
  if (!isActive()) {
    return;
  }

  if (m_lock != nullptr) {
    if (m_locked) {
      ext_session_lock_v1_unlock_and_destroy(m_lock);
      kLog.info("session unlock requested");
    } else {
      ext_session_lock_v1_destroy(m_lock);
      kLog.info("session lock request cancelled");
    }
    m_lock = nullptr;
  }

  m_lockPending = false;
  m_locked = false;
  clearSensitiveString(m_password);
  m_passwordSelectedAll = false;
  m_status.clear();
  m_statusIsError = false;
  m_wayland->stopKeyRepeat();
  clearInstances();
  m_pointerSurface = nullptr;
  wl_display_flush(m_wayland->display());
}

void LockScreen::onOutputChange() {
  if (!isActive()) {
    return;
  }
  syncInstances();
}

void LockScreen::onSecondTick() {
  if (!isActive()) {
    return;
  }
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      instance.surface->onSecondTick();
    }
  }
}

void LockScreen::onThemeChanged() {
  if (!isActive()) {
    return;
  }
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      instance.surface->onThemeChanged();
    }
  }
}

void LockScreen::onPointerEvent(const PointerEvent& event) {
  if (!isActive()) {
    return;
  }

  if (event.type == PointerEvent::Type::Enter && event.surface != nullptr) {
    m_pointerSurface = event.surface;
  } else if (event.type == PointerEvent::Type::Leave && event.surface == m_pointerSurface) {
    m_pointerSurface = nullptr;
  } else if ((event.type == PointerEvent::Type::Button || event.type == PointerEvent::Type::Axis) &&
             event.surface != nullptr) {
    m_pointerSurface = event.surface;
  }

  wl_surface* target = event.surface != nullptr ? event.surface : m_pointerSurface;
  if (target == nullptr) {
    return;
  }

  for (auto& instance : m_instances) {
    if (instance.surface->wlSurface() == target) {
      instance.surface->onPointerEvent(event);
      return;
    }
  }
}

void LockScreen::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isActive() || !event.pressed) {
    return;
  }
  if (!m_locked) {
    return;
  }

  if (event.sym == XKB_KEY_Return || event.sym == XKB_KEY_KP_Enter) {
    tryAuthenticate();
    return;
  }

  if ((event.modifiers & KeyMod::Ctrl) != 0 && event.sym == XKB_KEY_a) {
    setPasswordSelectedAll(!m_password.empty());
    return;
  }

  if (event.sym == XKB_KEY_BackSpace) {
    if (m_passwordSelectedAll) {
      clearSensitiveString(m_password);
      m_status.clear();
      m_statusIsError = false;
      setPasswordSelectedAll(false);
      updatePromptOnSurfaces();
    } else if (!m_password.empty()) {
      m_password.erase(prevUtf8Pos(m_password, m_password.size()));
      m_status.clear();
      m_statusIsError = false;
      setPasswordSelectedAll(false);
      updatePromptOnSurfaces();
    }
    return;
  }

  if (event.sym == XKB_KEY_Escape) {
    clearSensitiveString(m_password);
    m_status = "Password cleared";
    m_statusIsError = false;
    setPasswordSelectedAll(false);
    updatePromptOnSurfaces();
    return;
  }

  if (!event.preedit && event.utf32 >= 0x20U && event.utf32 != 0x7FU && !hasTextInputModifiers(event.modifiers)) {
    if (m_passwordSelectedAll) {
      clearSensitiveString(m_password);
    }
    m_password += utf32ToUtf8(event.utf32);
    m_status.clear();
    m_statusIsError = false;
    setPasswordSelectedAll(false);
    updatePromptOnSurfaces();
  }
}

bool LockScreen::isActive() const noexcept { return m_lockPending || m_locked; }

void LockScreen::handleLocked(void* data, ext_session_lock_v1* /*lock*/) {
  auto* self = static_cast<LockScreen*>(data);
  self->m_lockPending = false;
  self->m_locked = true;
  self->m_status = "Type your password and press Enter.";
  self->m_statusIsError = false;
  for (auto& instance : self->m_instances) {
    instance.surface->setLockedState(true);
    instance.surface->setOnLogin([self]() { self->tryAuthenticate(); });
  }
  self->updatePromptOnSurfaces();
  kLog.info("session is locked");
}

void LockScreen::handleFinished(void* data, ext_session_lock_v1* /*lock*/) {
  auto* self = static_cast<LockScreen*>(data);
  kLog.info("session lock finished by compositor");

  if (self->m_lock != nullptr) {
    if (self->m_locked) {
      ext_session_lock_v1_unlock_and_destroy(self->m_lock);
    } else {
      ext_session_lock_v1_destroy(self->m_lock);
    }
    self->m_lock = nullptr;
  }
  self->m_lockPending = false;
  self->m_locked = false;
  clearSensitiveString(self->m_password);
  self->m_passwordSelectedAll = false;
  self->m_status.clear();
  self->m_statusIsError = false;
  self->clearInstances();
  self->m_pointerSurface = nullptr;
}

void LockScreen::syncInstances() {
  if (m_wayland == nullptr) {
    return;
  }

  const auto& outputs = m_wayland->outputs();

  std::erase_if(m_instances, [&](Instance& instance) {
    const bool exists = std::any_of(outputs.begin(), outputs.end(),
                                    [&](const WaylandOutput& output) { return output.name == instance.outputName; });
    return !exists;
  });

  for (const auto& output : outputs) {
    const bool exists = std::any_of(m_instances.begin(), m_instances.end(),
                                    [&](const Instance& instance) { return instance.outputName == output.name; });
    if (!exists) {
      createInstance(output);
    }
  }
}

void LockScreen::createInstance(const WaylandOutput& output) {
  auto surface = std::make_unique<LockSurface>(*m_wayland);
  surface->setRenderContext(m_renderContext);
  surface->setTextureCache(m_textureCache);
  surface->setLockedState(m_locked);
  if (m_configService != nullptr) {
    surface->setWallpaperPath(m_configService->getWallpaperPath(output.connectorName));
  }
  surface->setOnLogin([this]() { tryAuthenticate(); });
  const auto masked = maskedCircles(utf8CodepointCount(m_password));
  surface->setPromptState(m_user, masked, m_status, m_statusIsError);

  if (!surface->initialize(m_lock, output.output, output.scale)) {
    kLog.warn("failed to create lock surface for output {}", output.name);
    return;
  }

  m_instances.push_back(Instance{
      .outputName = output.name,
      .output = output.output,
      .surface = std::move(surface),
  });
}

void LockScreen::resetLockState() {
  if (m_lock == nullptr) {
    m_lockPending = false;
    m_locked = false;
    return;
  }
  if (m_locked) {
    ext_session_lock_v1_unlock_and_destroy(m_lock);
  } else {
    ext_session_lock_v1_destroy(m_lock);
  }
  m_lock = nullptr;
  m_lockPending = false;
  m_locked = false;
}

void LockScreen::clearInstances() { m_instances.clear(); }

void LockScreen::updatePromptOnSurfaces() {
  const auto masked = maskedCircles(utf8CodepointCount(m_password));
  for (auto& instance : m_instances) {
    instance.surface->setPromptState(m_user, masked, m_status, m_statusIsError);
  }
}

void LockScreen::setPasswordSelectedAll(bool selected) {
  m_passwordSelectedAll = selected;
  for (auto& instance : m_instances) {
    if (selected) {
      instance.surface->selectAllPassword();
    } else {
      instance.surface->clearPasswordSelection();
    }
  }
}

void LockScreen::tryAuthenticate() {
  if (m_password.empty()) {
    m_status = "Password required";
    m_statusIsError = true;
    updatePromptOnSurfaces();
    return;
  }

  m_status = "Authenticating...";
  m_statusIsError = false;
  updatePromptOnSurfaces();

  const auto result = m_authenticator.authenticateCurrentUser(m_password);
  clearSensitiveString(m_password);
  m_passwordSelectedAll = false;

  if (result.success) {
    m_status = "Unlocked";
    m_statusIsError = false;
    updatePromptOnSurfaces();
    unlock();
    return;
  }

  m_status = result.message.empty() ? "Authentication failed" : result.message;
  m_statusIsError = true;
  updatePromptOnSurfaces();
}

void LockScreen::clearSensitiveString(std::string& value) {
  volatile char* ptr = value.empty() ? nullptr : &value[0];
  for (std::size_t i = 0; i < value.size(); ++i) {
    ptr[i] = '\0';
  }
  value.clear();
}
