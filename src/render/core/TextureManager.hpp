#pragma once

#include <GLES2/gl2.h>

#include <cstdint>
#include <string>
#include <vector>

struct TextureHandle {
    GLuint id = 0;
    int width = 0;
    int height = 0;
};

class TextureManager {
public:
    TextureManager() = default;
    ~TextureManager();

    TextureManager(const TextureManager&) = delete;
    TextureManager& operator=(const TextureManager&) = delete;

    [[nodiscard]] TextureHandle loadFromFile(const std::string& path, int targetSize = 0);
    [[nodiscard]] TextureHandle loadFromArgbPixmap(const std::uint8_t* data, int width, int height);
    void unload(TextureHandle& handle);
    void cleanup();

private:
    TextureHandle uploadRgba(const std::uint8_t* data, int width, int height);
    std::vector<GLuint> m_textures;
};
