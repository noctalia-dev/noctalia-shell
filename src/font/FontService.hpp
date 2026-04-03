#pragma once

#include <fontconfig/fontconfig.h>

#include <string>

class FontService {
public:
    FontService();
    ~FontService();

    FontService(const FontService&) = delete;
    FontService& operator=(const FontService&) = delete;

    [[nodiscard]] std::string resolvePath(const std::string& family) const;

private:
    FcConfig* m_config = nullptr;
};
