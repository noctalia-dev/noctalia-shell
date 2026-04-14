#pragma once

#include "render/core/texture_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "wayland/surface.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

struct ext_session_lock_surface_v1;
struct ext_session_lock_v1;
struct wl_output;

class ImageNode;
class Button;
class Input;
class Label;
class RectNode;
class SharedTextureCache;
struct KeyboardEvent;
struct PointerEvent;

class LockSurface : public Surface {
public:
  explicit LockSurface(WaylandConnection& connection);
  ~LockSurface() override;

  using Surface::initialize;
  bool initialize() override { return false; }
  bool initialize(ext_session_lock_v1* lock, wl_output* output, std::int32_t scale);
  void setLockedState(bool locked);
  void setPromptState(std::string user, std::string maskedPassword, std::string status, bool error);
  void setTextureCache(SharedTextureCache* cache) noexcept { m_textureCache = cache; }
  void setWallpaperPath(std::string wallpaperPath);
  void setOnLogin(std::function<void()> onLogin);
  void selectAllPassword();
  void clearPasswordSelection();
  void onSecondTick();
  void onThemeChanged();
  void onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);
  [[nodiscard]] wl_output* output() const noexcept { return m_output; }

  static void handleConfigure(void* data, ext_session_lock_surface_v1* lockSurface, std::uint32_t serial,
                              std::uint32_t width, std::uint32_t height);

private:
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void applyWallpaperTexture();
  void updateClockText();
  void layoutScene(std::uint32_t width, std::uint32_t height);
  void updateCopy();

  ext_session_lock_surface_v1* m_lockSurface = nullptr;
  wl_output* m_output = nullptr;
  Node m_root;
  ImageNode* m_wallpaper = nullptr;
  RectNode* m_backdrop = nullptr;
  Label* m_clockShadow = nullptr;
  Label* m_clock = nullptr;
  RectNode* m_loginPanel = nullptr;
  Input* m_passwordField = nullptr;
  Button* m_loginButton = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  TextureHandle m_wallpaperTexture{};
  std::string m_wallpaperPath;
  bool m_wallpaperDirty = false;
  InputDispatcher m_inputDispatcher;
  std::function<void()> m_onLogin;
  bool m_locked = false;
  std::string m_user;
  std::string m_maskedPassword;
  std::string m_status;
  bool m_error = false;
  bool m_clockShadowEnabled = true;
};
