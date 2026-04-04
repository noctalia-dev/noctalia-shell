#pragma once

#include "render/core/Color.hpp"
#include "render/scene/Node.hpp"

#include <string>

class IconNode : public Node {
public:
    IconNode()
        : Node(NodeType::Icon) {}

    [[nodiscard]] const std::string& text() const noexcept { return m_text; }
    [[nodiscard]] float fontSize() const noexcept { return m_fontSize; }
    [[nodiscard]] const Color& color() const noexcept { return m_color; }

    void setCodepoint(char32_t codepoint) {
        // Encode as UTF-8
        std::string encoded;
        if (codepoint <= 0x7F) {
            encoded += static_cast<char>(codepoint);
        } else if (codepoint <= 0x7FF) {
            encoded += static_cast<char>(0xC0 | (codepoint >> 6));
            encoded += static_cast<char>(0x80 | (codepoint & 0x3F));
        } else if (codepoint <= 0xFFFF) {
            encoded += static_cast<char>(0xE0 | (codepoint >> 12));
            encoded += static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F));
            encoded += static_cast<char>(0x80 | (codepoint & 0x3F));
        } else if (codepoint <= 0x10FFFF) {
            encoded += static_cast<char>(0xF0 | (codepoint >> 18));
            encoded += static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F));
            encoded += static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F));
            encoded += static_cast<char>(0x80 | (codepoint & 0x3F));
        }
        if (m_text == encoded) {
            return;
        }
        m_text = std::move(encoded);
        markDirty();
    }

    void setFontSize(float size) {
        if (m_fontSize == size) {
            return;
        }
        m_fontSize = size;
        markDirty();
    }

    void setColor(const Color& color) {
        m_color = color;
        markDirty();
    }

private:
    std::string m_text;
    float m_fontSize = 16.0f;
    Color m_color;
};
