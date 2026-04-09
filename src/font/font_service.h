#pragma once

#include <fontconfig/fontconfig.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

struct ResolvedFont {
  std::string path;
  int faceIndex = 0;
};

class FontService {
public:
  FontService();
  ~FontService();

  FontService(const FontService&) = delete;
  FontService& operator=(const FontService&) = delete;

  [[nodiscard]] std::string resolvePath(const std::string& family) const;
  [[nodiscard]] std::vector<ResolvedFont> resolveFallbackChain(const std::string& family, int limit = 8,
                                                               int weight = FC_WEIGHT_REGULAR) const;
  // Returns the best font covering the given Unicode codepoint, or nullopt.
  [[nodiscard]] std::optional<ResolvedFont> resolveBestForChar(char32_t codepoint) const;
  // Returns the best font matching a family name (e.g. "emoji"), or nullopt.
  [[nodiscard]] std::optional<ResolvedFont> resolveFont(const std::string& family) const;

private:
  FcConfig* m_config = nullptr;
};
