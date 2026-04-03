#include "font/FontService.hpp"

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
