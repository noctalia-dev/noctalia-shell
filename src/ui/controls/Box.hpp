#pragma once

#include "render/Color.hpp"
#include "render/scene/Node.hpp"

class Renderer;
class RectNode;

enum class BoxDirection : std::uint8_t {
    Horizontal,
    Vertical,
};

enum class BoxAlign : std::uint8_t {
    Start,
    Center,
    End,
};

class Box : public Node {
public:
    Box();

    void setDirection(BoxDirection direction);
    void setGap(float gap);
    void setAlign(BoxAlign align);
    void setPadding(float top, float right, float bottom, float left);
    void setPadding(float all);

    void setBackground(const Color& color);
    void setRadius(float radius);
    void setBorderColor(const Color& color);
    void setBorderWidth(float width);

    [[nodiscard]] BoxDirection direction() const noexcept { return m_direction; }
    [[nodiscard]] float gap() const noexcept { return m_gap; }
    [[nodiscard]] BoxAlign align() const noexcept { return m_align; }

    void layout(Renderer& renderer);

private:
    void ensureBackground();

    RectNode* m_background = nullptr;
    BoxDirection m_direction = BoxDirection::Horizontal;
    BoxAlign m_align = BoxAlign::Center;
    float m_gap = 0.0f;
    float m_paddingTop = 0.0f;
    float m_paddingRight = 0.0f;
    float m_paddingBottom = 0.0f;
    float m_paddingLeft = 0.0f;
};
