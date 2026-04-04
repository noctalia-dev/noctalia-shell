#include "ui/controls/Icon.hpp"

#include "render/core/Renderer.hpp"
#include "render/scene/IconNode.hpp"
#include "ui/icons/IconRegistry.hpp"
#include "ui/style/Palette.hpp"
#include "ui/style/Style.hpp"

#include <memory>

Icon::Icon() {
    auto iconNode = std::make_unique<IconNode>();
    m_iconNode = static_cast<IconNode*>(addChild(std::move(iconNode)));
    m_iconNode->setFontSize(Style::fontSizeSm);
    m_iconNode->setColor(palette.onSurface);
}

void Icon::setIcon(std::string_view name) {
    char32_t cp = IconRegistry::lookup(name);
    if (cp != 0) {
        m_iconNode->setCodepoint(cp);
    }
}

void Icon::setCodepoint(char32_t codepoint) {
    m_iconNode->setCodepoint(codepoint);
}

void Icon::setSize(float size) {
    m_iconNode->setFontSize(size);
}

void Icon::setColor(const Color& color) {
    m_iconNode->setColor(color);
}

void Icon::measure(Renderer& renderer) {
    auto metrics = renderer.measureGlyph(m_iconNode->codepoint(), m_iconNode->fontSize());
    Node::setSize(metrics.width, metrics.bottom - metrics.top);
    m_iconNode->setPosition(0.0f, -metrics.top);
}
