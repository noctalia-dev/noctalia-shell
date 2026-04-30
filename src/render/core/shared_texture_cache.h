#pragma once

#include "render/core/texture_manager.h"

#include <string>
#include <unordered_map>

class GlSharedContext;

// Path-keyed, refcounted texture cache backed by a TextureManager living in
// the shared EGL context. Any subsystem in the shared context's share group
// (shell, lockscreen, backdrop, wallpaper) can acquire a texture by path and
// get back the same GLuint — textures are decoded and uploaded once.
class SharedTextureCache {
public:
  SharedTextureCache() = default;
  ~SharedTextureCache();

  SharedTextureCache(const SharedTextureCache&) = delete;
  SharedTextureCache& operator=(const SharedTextureCache&) = delete;

  void initialize(GlSharedContext* sharedGl);

  [[nodiscard]] TextureHandle acquire(const std::string& path);
  void release(TextureHandle& handle, const std::string& path);

private:
  void makeCurrent();

  struct Entry {
    TextureHandle handle;
    int refCount = 0;
  };

  GlSharedContext* m_sharedGl = nullptr;
  TextureManager m_textureManager;
  std::unordered_map<std::string, Entry> m_entries;
};
