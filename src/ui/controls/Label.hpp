#pragma once

#include "render/core/Color.hpp"
#include "render/scene/Node.hpp"

#include <string>
#include <string_view>

class Renderer;
class TextNode;

class Label : public Node {
public:
    Label();

    void setText(std::string_view text);
    void setFontSize(float size);
    void setColor(const Color& color);
    void setMaxWidth(float maxWidth);

    [[nodiscard]] const std::string& text() const noexcept;
    [[nodiscard]] float fontSize() const noexcept;
    [[nodiscard]] const Color& color() const noexcept;
    [[nodiscard]] float maxWidth() const noexcept;

    void measure(Renderer& renderer);

    void setCaptionStyle();

private:
    TextNode* m_textNode = nullptr;
};
