#pragma once

#include "render/Color.hpp"
#include "render/scene/Node.hpp"

#include <string>

class TextNode : public Node {
public:
    TextNode()
        : Node(NodeType::Text) {}

    [[nodiscard]] const std::string& text() const noexcept { return m_text; }
    [[nodiscard]] float fontSize() const noexcept { return m_fontSize; }
    [[nodiscard]] const Color& color() const noexcept { return m_color; }
    [[nodiscard]] float maxWidth() const noexcept { return m_maxWidth; }

    void setText(std::string text) {
        if (m_text == text) {
            return;
        }
        m_text = std::move(text);
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

    void setMaxWidth(float maxWidth) {
        if (m_maxWidth == maxWidth) {
            return;
        }
        m_maxWidth = maxWidth;
        markDirty();
    }

private:
    std::string m_text;
    float m_fontSize = 14.0f;
    float m_maxWidth = 0.0f;
    Color m_color;
};
