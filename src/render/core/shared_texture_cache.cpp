#include "render/core/shared_texture_cache.h"

#include "core/log.h"
#include "render/gl_shared_context.h"

namespace {
  constexpr Logger kLog("texcache");
} // namespace

SharedTextureCache::~SharedTextureCache() {
  makeCurrent();
  m_textureManager.cleanup();
}

void SharedTextureCache::initialize(GlSharedContext* sharedGl) { m_sharedGl = sharedGl; }

TextureHandle SharedTextureCache::acquire(const std::string& path) {
  if (path.empty()) {
    return {};
  }

  auto it = m_entries.find(path);
  if (it != m_entries.end()) {
    ++it->second.refCount;
    kLog.info("hit {} (refCount={})", path, it->second.refCount);
    return it->second.handle;
  }

  makeCurrent();
  auto handle = m_textureManager.loadFromFile(path, 0, true);
  if (handle.id == 0) {
    return handle;
  }

  m_entries[path] = Entry{.handle = handle, .refCount = 1};
  kLog.info("uploaded {}", path);
  return handle;
}

void SharedTextureCache::release(TextureHandle& handle, const std::string& path) {
  if (handle.id == 0 || path.empty()) {
    handle = {};
    return;
  }

  auto it = m_entries.find(path);
  if (it == m_entries.end()) {
    handle = {};
    return;
  }

  --it->second.refCount;
  if (it->second.refCount <= 0) {
    makeCurrent();
    m_textureManager.unload(it->second.handle);
    m_entries.erase(it);
    kLog.info("evicted {}", path);
  }

  handle = {};
}

void SharedTextureCache::makeCurrent() {
  if (m_sharedGl != nullptr) {
    m_sharedGl->makeCurrentSurfaceless();
  }
}
