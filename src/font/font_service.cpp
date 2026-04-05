#include "font/font_service.h"

#include "core/log.h"

#include <stdexcept>

FontService::FontService() {
  m_config = FcInitLoadConfigAndFonts();
  if (m_config == nullptr) {
    throw std::runtime_error("FcInitLoadConfigAndFonts failed");
  }
}

FontService::~FontService() {
  if (m_config != nullptr) {
    FcConfigDestroy(m_config);
    m_config = nullptr;
  }
}

std::string FontService::resolvePath(const std::string& family) const {
  FcPattern* pattern = FcNameParse(reinterpret_cast<const FcChar8*>(family.c_str()));
  if (pattern == nullptr) {
    throw std::runtime_error("FcNameParse failed for: " + family);
  }

  FcConfigSubstitute(m_config, pattern, FcMatchPattern);
  FcDefaultSubstitute(pattern);

  FcResult result = FcResultNoMatch;
  FcPattern* match = FcFontMatch(m_config, pattern, &result);
  FcPatternDestroy(pattern);

  if (match == nullptr || result != FcResultMatch) {
    throw std::runtime_error("no font found for: " + family);
  }

  FcChar8* filePath = nullptr;
  if (FcPatternGetString(match, FC_FILE, 0, &filePath) != FcResultMatch || filePath == nullptr) {
    FcPatternDestroy(match);
    throw std::runtime_error("fontconfig matched but returned no file path for: " + family);
  }

  std::string path(reinterpret_cast<const char*>(filePath));
  FcPatternDestroy(match);
  return path;
}

std::vector<ResolvedFont> FontService::resolveFallbackChain(const std::string& family, int limit, int weight) const {
  FcPattern* pattern = FcNameParse(reinterpret_cast<const FcChar8*>(family.c_str()));
  if (pattern == nullptr) {
    throw std::runtime_error("FcNameParse failed for: " + family);
  }

  if (weight != FC_WEIGHT_REGULAR) {
    FcPatternAddInteger(pattern, FC_WEIGHT, weight);
  }

  FcConfigSubstitute(m_config, pattern, FcMatchPattern);
  FcDefaultSubstitute(pattern);

  FcResult result = FcResultNoMatch;
  FcFontSet* fontSet = FcFontSort(m_config, pattern, FcTrue, nullptr, &result);
  FcPatternDestroy(pattern);

  if (fontSet == nullptr || result != FcResultMatch) {
    throw std::runtime_error("no fonts found for: " + family);
  }

  std::vector<ResolvedFont> chain;
  for (int i = 0; i < fontSet->nfont && static_cast<int>(chain.size()) < limit; ++i) {
    FcChar8* filePath = nullptr;
    int faceIndex = 0;
    if (FcPatternGetString(fontSet->fonts[i], FC_FILE, 0, &filePath) != FcResultMatch || filePath == nullptr) {
      continue;
    }
    FcPatternGetInteger(fontSet->fonts[i], FC_INDEX, 0, &faceIndex);

    std::string path(reinterpret_cast<const char*>(filePath));

    // Skip duplicates (same file + face index)
    bool duplicate = false;
    for (const auto& existing : chain) {
      if (existing.path == path && existing.faceIndex == faceIndex) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }

    chain.push_back(ResolvedFont{.path = std::move(path), .faceIndex = faceIndex});
  }

  FcFontSetDestroy(fontSet);

  if (chain.empty()) {
    throw std::runtime_error("no fonts resolved for: " + family);
  }

  logDebug("font fallback chain for \"{}\" ({} fonts):", family, chain.size());
  for (const auto& font : chain) {
    logDebug("  {} [{}]", font.path, font.faceIndex);
  }

  return chain;
}
