#include "ui/Widget.hpp"

void Widget::update(Renderer& /*renderer*/) {}

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
