#include "shell/Bar.hpp"

#include "render/Palette.hpp"
#include "render/scene/RectNode.hpp"
#include "render/scene/TextNode.hpp"

#include <stdexcept>

#include <wayland-client-core.h>

namespace {

constexpr std::uint32_t kBarHeight = 36;

} // namespace

Bar::Bar()
    : m_layerSurface(m_connection, LayerSurfaceConfig{
        .nameSpace = "noctalia-bar",
        .layer = LayerShellLayer::Top,
        .anchor = LayerShellAnchor::Top | LayerShellAnchor::Left | LayerShellAnchor::Right,
        .height = kBarHeight,
        .exclusiveZone = static_cast<std::int32_t>(kBarHeight),
        .defaultHeight = kBarHeight,
    }) {}

bool Bar::initialize() {
    if (!m_connection.connect()) {
        return false;
    }

    m_layerSurface.setConfigureCallback(
        [this](std::uint32_t width, std::uint32_t height) {
            buildScene(width, height);
        });

    m_layerSurface.initialize();
    return true;
}

bool Bar::isRunning() const noexcept {
    return m_layerSurface.isRunning();
}

int Bar::displayFd() const noexcept {
    if (!m_connection.isConnected()) {
        return -1;
    }

    return wl_display_get_fd(m_connection.display());
}

void Bar::dispatchPending() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_dispatch_pending(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch pending Wayland events");
    }
}

void Bar::dispatchReadable() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_dispatch(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
    }
}

void Bar::flush() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_flush(m_connection.display()) < 0) {
        throw std::runtime_error("failed to flush Wayland display");
    }
}

const WaylandConnection& Bar::connection() const noexcept {
    return m_connection;
}

void Bar::buildScene(std::uint32_t width, std::uint32_t height) {
    auto* renderer = m_layerSurface.renderer();
    if (renderer == nullptr) {
        return;
    }

    const auto w = static_cast<float>(width);
    const auto h = static_cast<float>(height);

    if (m_sceneRoot == nullptr) {
        m_sceneRoot = std::make_unique<Node>();

        auto bg = std::make_unique<RectNode>();
        bg->setStyle(RoundedRectStyle{
            .fill = kRosePinePalette.overlay,
            .fillEnd = kRosePinePalette.surface,
            .border = rgba(
                kRosePinePalette.text.r,
                kRosePinePalette.text.g,
                kRosePinePalette.text.b,
                0.85f),
            .fillMode = FillMode::LinearGradient,
            .gradientDirection = GradientDirection::Vertical,
            .radius = 10.0f,
            .softness = 1.2f,
            .borderWidth = 1.0f,
        });
        m_sceneRoot->addChild(std::move(bg));

        auto accent = std::make_unique<RectNode>();
        accent->setPosition(18.0f, 12.0f);
        accent->setSize(116.0f, 4.0f);
        accent->setStyle(RoundedRectStyle{
            .fill = kRosePinePalette.foam,
            .fillEnd = kRosePinePalette.iris,
            .fillMode = FillMode::LinearGradient,
            .gradientDirection = GradientDirection::Horizontal,
        });
        m_sceneRoot->addChild(std::move(accent));

        auto label = std::make_unique<TextNode>();
        label->setText("Noctalia");
        label->setFontSize(14.0f);
        label->setColor(kRosePinePalette.text);
        m_labelNode = static_cast<TextNode*>(m_sceneRoot->addChild(std::move(label)));

        renderer->setScene(m_sceneRoot.get());
    }

    // Update size-dependent layout
    auto& children = m_sceneRoot->children();

    // Background rect
    children[0]->setPosition(10.0f, 6.0f);
    children[0]->setSize(w - 20.0f, h - 12.0f);

    // Center text label
    const auto metrics = renderer->measureText(m_labelNode->text(), m_labelNode->fontSize());
    const float labelX = (w - metrics.width) * 0.5f;
    const float labelHeight = metrics.bottom - metrics.top;
    const float labelBaseline = (h - labelHeight) * 0.5f - metrics.top;
    m_labelNode->setPosition(labelX, labelBaseline);
}
