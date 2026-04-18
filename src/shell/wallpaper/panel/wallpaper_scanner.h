#pragma once

#include <filesystem>
#include <string>
#include <unordered_map>
#include <vector>

struct WallpaperEntry {
  std::string name;
  std::filesystem::path absPath;
  bool isDir = false;
};

struct WallpaperScanResult {
  std::vector<WallpaperEntry> entries;
  std::filesystem::file_time_type dirMtime{};
  bool flatten = false;
};

class WallpaperScanner {
public:
  // Returns a reference to the cached scan for (dir, flatten). If the on-disk
  // mtime is unchanged and the cache entry exists, returns it unmodified;
  // otherwise walks the directory and updates the cache.
  const WallpaperScanResult& scan(const std::filesystem::path& dir, bool flatten);

  // Drops all cached results. The next scan() will re-walk.
  void invalidate();

private:
  struct CacheKey {
    std::string dir;
    bool flatten;
    bool operator==(const CacheKey& other) const noexcept { return flatten == other.flatten && dir == other.dir; }
  };
  struct CacheKeyHash {
    std::size_t operator()(const CacheKey& k) const noexcept {
      return std::hash<std::string>{}(k.dir) ^ (k.flatten ? 0x9e3779b9u : 0u);
    }
  };

  std::unordered_map<CacheKey, WallpaperScanResult, CacheKeyHash> m_cache;
  WallpaperScanResult m_empty;
};
