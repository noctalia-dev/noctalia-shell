#include "ui/Widget.hpp"

void Widget::update(Renderer& /*renderer*/) {}

void Widget::onPointerEnter(float /*localX*/, float /*localY*/) {}
void Widget::onPointerLeave() {}
void Widget::onPointerMotion(float /*localX*/, float /*localY*/) {}
bool Widget::onPointerButton(std::uint32_t /*button*/, bool /*pressed*/) { return false; }
std::uint32_t Widget::cursorShape() const { return 0; }

float Widget::width() const noexcept {
    return m_rootPtr ? m_rootPtr->width() : 0.0f;
}

float Widget::height() const noexcept {
    return m_rootPtr ? m_rootPtr->height() : 0.0f;
}

std::unique_ptr<Node> Widget::releaseRoot() {
    m_rootPtr = m_root.get();
    return std::move(m_root);
}

void Widget::setAnimationManager(AnimationManager* mgr) noexcept {
    m_animations = mgr;
}

void Widget::setRedrawCallback(RedrawCallback callback) {
    m_redrawCallback = std::move(callback);
}

void Widget::requestRedraw() {
    if (m_redrawCallback) {
        m_redrawCallback();
    }
}
