#pragma once

#include <fontconfig/fontconfig.h>

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

private:
  FcConfig* m_config = nullptr;
};
