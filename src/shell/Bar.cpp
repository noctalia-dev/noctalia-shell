#include "shell/Bar.hpp"

#include "core/Log.hpp"
#include "render/Palette.hpp"
#include "render/TextureManager.hpp"
#include "render/scene/ImageNode.hpp"
#include "render/scene/RectNode.hpp"
#include "render/scene/TextNode.hpp"

#include <algorithm>
#include <stdexcept>

#include <wayland-client-core.h>

namespace {

constexpr std::uint32_t kBarHeight = 42;

} // namespace

Bar::Bar() = default;

bool Bar::initialize() {
    if (!m_connection.connect()) {
        return false;
    }

    m_connection.setOutputChangeCallback([this]() {
        syncInstances();
    });

    syncInstances();
    return true;
}

bool Bar::isRunning() const noexcept {
    return std::any_of(m_instances.begin(), m_instances.end(),
        [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
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

void Bar::syncInstances() {
    const auto& outputs = m_connection.outputs();

    // Remove instances for outputs that no longer exist
    std::erase_if(m_instances, [&outputs](const auto& inst) {
        bool found = std::any_of(outputs.begin(), outputs.end(),
            [&inst](const auto& out) { return out.name == inst->outputName; });
        if (!found) {
            logInfo("bar: removing instance for output {}", inst->outputName);
        }
        return !found;
    });

    // Create instances for new outputs
    for (const auto& output : outputs) {
        bool exists = std::any_of(m_instances.begin(), m_instances.end(),
            [&output](const auto& inst) { return inst->outputName == output.name; });
        if (!exists) {
            createInstance(output);
        }
    }
}

void Bar::createInstance(const WaylandOutput& output) {
    logInfo("bar: creating instance for output {} scale={}", output.name, output.scale);

    auto instance = std::make_unique<BarInstance>();
    instance->outputName = output.name;
    instance->output = output.output;
    instance->scale = output.scale;

    auto config = LayerSurfaceConfig{
        .nameSpace = "noctalia-bar",
        .layer = LayerShellLayer::Top,
        .anchor = LayerShellAnchor::Top | LayerShellAnchor::Left | LayerShellAnchor::Right,
        .height = kBarHeight,
        .exclusiveZone = static_cast<std::int32_t>(kBarHeight),
        .defaultHeight = kBarHeight,
    };

    instance->surface = std::make_unique<LayerSurface>(m_connection, std::move(config));

    auto* inst = instance.get();
    instance->surface->setConfigureCallback(
        [this, inst](std::uint32_t width, std::uint32_t height) {
            buildScene(*inst, width, height);
        });

    instance->surface->setAnimationManager(&instance->animations);

    if (!instance->surface->initialize(output.output, output.scale)) {
        logWarn("bar: failed to initialize surface for output {}", output.name);
        return;
    }

    m_instances.push_back(std::move(instance));
}

void Bar::destroyInstance(std::uint32_t outputName) {
    std::erase_if(m_instances, [outputName](const auto& inst) {
        return inst->outputName == outputName;
    });
}

void Bar::buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height) {
    auto* renderer = instance.surface->renderer();
    if (renderer == nullptr) {
        return;
    }

    const auto w = static_cast<float>(width);
    const auto h = static_cast<float>(height);

    if (instance.sceneRoot == nullptr) {
        instance.sceneRoot = std::make_unique<Node>();

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
        instance.sceneRoot->addChild(std::move(bg));

        auto accent = std::make_unique<RectNode>();
        accent->setPosition(18.0f, 12.0f);
        accent->setSize(116.0f, 4.0f);
        accent->setStyle(RoundedRectStyle{
            .fill = kRosePinePalette.foam,
            .fillEnd = kRosePinePalette.iris,
            .fillMode = FillMode::LinearGradient,
            .gradientDirection = GradientDirection::Horizontal,
        });
        instance.sceneRoot->addChild(std::move(accent));

        auto label = std::make_unique<TextNode>();
        label->setText("Noctalia");
        label->setFontSize(14.0f);
        label->setColor(kRosePinePalette.text);
        instance.labelNode = static_cast<TextNode*>(instance.sceneRoot->addChild(std::move(label)));

        // Test: truncated text
        auto truncLabel = std::make_unique<TextNode>();
        truncLabel->setText("This is a long label that should be truncated with an ellipsis");
        truncLabel->setFontSize(12.0f);
        truncLabel->setMaxWidth(120.0f);
        truncLabel->setColor(kRosePinePalette.foam);
        truncLabel->setPosition(150.0f, 22.0f);
        instance.sceneRoot->addChild(std::move(truncLabel));

        // Test: image (try PNG first, fall back to SVG)
        auto& texMgr = renderer->textureManager();
        auto handle = texMgr.loadFromFile("/usr/share/icons/hicolor/48x48/apps/firefox.png", 24);
        if (handle.id == 0) {
            handle = texMgr.loadFromFile("/usr/share/icons/hicolor/scalable/apps/foot.svg", 24);
        }
        if (handle.id != 0) {
            auto icon = std::make_unique<ImageNode>();
            icon->setTextureId(handle.id);
            icon->setPosition(300.0f, 6.0f);
            icon->setSize(24.0f, 24.0f);
            instance.sceneRoot->addChild(std::move(icon));
        }

        // Test: fade-in animation
        instance.sceneRoot->setOpacity(0.0f);
        instance.animations.animate(0.0f, 1.0f, 400.0f, Easing::EaseOutCubic,
            [root = instance.sceneRoot.get()](float v) { root->setOpacity(v); });

        renderer->setScene(instance.sceneRoot.get());
    }

    // Update size-dependent layout
    auto& children = instance.sceneRoot->children();

    // Background rect
    children[0]->setPosition(10.0f, 6.0f);
    children[0]->setSize(w - 20.0f, h - 12.0f);

    // Center text label
    const auto metrics = renderer->measureText(instance.labelNode->text(), instance.labelNode->fontSize());
    const float labelX = (w - metrics.width) * 0.5f;
    const float labelHeight = metrics.bottom - metrics.top;
    const float labelBaseline = (h - labelHeight) * 0.5f - metrics.top;
    instance.labelNode->setPosition(labelX, labelBaseline);
}
