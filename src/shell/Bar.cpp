#include "shell/Bar.hpp"

#include "core/Log.hpp"
#include "render/Palette.hpp"
#include "time/TimeService.hpp"
#include "render/scene/RectNode.hpp"
#include "ui/Widget.hpp"
#include "ui/controls/Box.hpp"
#include "ui/widgets/ClockWidget.hpp"
#include "ui/widgets/SpacerWidget.hpp"
#include "ui/widgets/WorkspacesWidget.hpp"

#include <algorithm>
#include <stdexcept>

#include <wayland-client-core.h>

namespace {

constexpr std::uint32_t kBarHeight = 42;
constexpr float kSectionGap = 8.0f;
constexpr float kBarPaddingX = 16.0f;

} // namespace

Bar::Bar() = default;

bool Bar::initialize(TimeService* timeService) {
    m_time = timeService;

    if (!m_wayland.connect()) {
        return false;
    }

    m_wayland.setOutputChangeCallback([this]() {
        syncInstances();
    });

    m_wayland.setWorkspaceChangeCallback([this]() {
        for (auto& inst : m_instances) {
            if (inst->surface == nullptr || inst->surface->renderer() == nullptr) {
                continue;
            }
            inst->surface->renderer()->makeCurrent();
            updateWidgets(*inst);
            inst->surface->renderNow();
        }
    });

    if (timeService != nullptr) {
        timeService->setTickCallback([this]() {
            for (auto& inst : m_instances) {
                if (inst->surface == nullptr || inst->surface->renderer() == nullptr) {
                    continue;
                }
                inst->surface->renderer()->makeCurrent();
                updateWidgets(*inst);
                if (inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
                    inst->surface->requestRedraw();
                }
            }
        });
    }

    syncInstances();
    return true;
}

bool Bar::isRunning() const noexcept {
    return std::any_of(m_instances.begin(), m_instances.end(),
        [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
}

int Bar::displayFd() const noexcept {
    if (!m_wayland.isConnected()) {
        return -1;
    }
    return wl_display_get_fd(m_wayland.display());
}

void Bar::dispatchPending() {
    if (!m_wayland.isConnected()) {
        return;
    }
    if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to dispatch pending Wayland events");
    }
}

void Bar::dispatchReadable() {
    if (!m_wayland.isConnected()) {
        return;
    }
    if (wl_display_dispatch(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
    }
}

void Bar::flush() {
    if (!m_wayland.isConnected()) {
        return;
    }
    if (wl_display_flush(m_wayland.display()) < 0) {
        throw std::runtime_error("failed to flush Wayland display");
    }
}

const WaylandConnection& Bar::connection() const noexcept {
    return m_wayland;
}

void Bar::syncInstances() {
    const auto& outputs = m_wayland.outputs();

    std::erase_if(m_instances, [&outputs](const auto& inst) {
        bool found = std::any_of(outputs.begin(), outputs.end(),
            [&inst](const auto& out) { return out.name == inst->outputName; });
        if (!found) {
            logInfo("bar: removing instance for output {}", inst->outputName);
        }
        return !found;
    });

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

    instance->surface = std::make_unique<LayerSurface>(m_wayland, std::move(config));

    auto* inst = instance.get();
    instance->surface->setConfigureCallback(
        [this, inst](std::uint32_t width, std::uint32_t height) {
            buildScene(*inst, width, height);
        });

    instance->surface->setAnimationManager(&instance->animations);
    populateWidgets(*instance);

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

void Bar::populateWidgets(BarInstance& instance) {
    if (m_time != nullptr) {
        instance.startWidgets.push_back(std::make_unique<ClockWidget>(*m_time));
    }

    instance.centerWidgets.push_back(std::make_unique<WorkspacesWidget>(m_wayland, instance.output));

    if (m_time != nullptr) {
        instance.endWidgets.push_back(std::make_unique<ClockWidget>(*m_time));
    }
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

        // Bar background
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

        // Create section boxes
        auto makeSection = [](float gap) {
            auto box = std::make_unique<Box>();
            box->setDirection(BoxDirection::Horizontal);
            box->setGap(gap);
            box->setAlign(BoxAlign::Center);
            return box;
        };

        auto start = makeSection(kSectionGap);
        auto center = makeSection(kSectionGap);
        auto end = makeSection(kSectionGap);

        instance.startSection = static_cast<Box*>(instance.sceneRoot->addChild(std::move(start)));
        instance.centerSection = static_cast<Box*>(instance.sceneRoot->addChild(std::move(center)));
        instance.endSection = static_cast<Box*>(instance.sceneRoot->addChild(std::move(end)));

        // Create widgets and transfer their roots to section boxes
        auto initWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets, Box* section) {
            for (auto& widget : widgets) {
                widget->setAnimationManager(&instance.animations);
                widget->create(*renderer);
                if (widget->root() != nullptr) {
                    section->addChild(widget->releaseRoot());
                }
            }
        };

        initWidgets(instance.startWidgets, instance.startSection);
        initWidgets(instance.centerWidgets, instance.centerSection);
        initWidgets(instance.endWidgets, instance.endSection);

        // Fade-in animation
        instance.sceneRoot->setOpacity(0.0f);
        instance.animations.animate(0.0f, 1.0f, 400.0f, Easing::EaseOutCubic,
            [root = instance.sceneRoot.get()](float v) { root->setOpacity(v); });

        renderer->setScene(instance.sceneRoot.get());
        instance.surface->setSceneRoot(instance.sceneRoot.get());
    }

    // Layout
    auto& children = instance.sceneRoot->children();

    // Background rect
    children[0]->setPosition(10.0f, 6.0f);
    children[0]->setSize(w - 20.0f, h - 12.0f);

    // Layout widgets
    auto layoutWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
        for (auto& widget : widgets) {
            widget->layout(*renderer, w, h);
        }
    };
    layoutWidgets(instance.startWidgets);
    layoutWidgets(instance.centerWidgets);
    layoutWidgets(instance.endWidgets);

    // Layout section boxes
    instance.startSection->layout(*renderer);
    instance.centerSection->layout(*renderer);
    instance.endSection->layout(*renderer);

    // Position sections: left-aligned, centered, right-aligned
    const float contentY = (h - instance.startSection->height()) * 0.5f;

    instance.startSection->setPosition(kBarPaddingX, contentY);

    const float centerX = (w - instance.centerSection->width()) * 0.5f;
    const float centerY = (h - instance.centerSection->height()) * 0.5f;
    instance.centerSection->setPosition(centerX, centerY);

    const float rightX = w - instance.endSection->width() - kBarPaddingX;
    const float rightY = (h - instance.endSection->height()) * 0.5f;
    instance.endSection->setPosition(rightX, rightY);
}

void Bar::updateWidgets(BarInstance& instance) {
    auto* renderer = instance.surface->renderer();
    if (renderer == nullptr) {
        return;
    }

    const auto w = static_cast<float>(instance.surface->width());
    const auto h = static_cast<float>(instance.surface->height());

    auto updateSection = [&](std::vector<std::unique_ptr<Widget>>& widgets, Box* section) {
        bool changed = false;
        for (auto& widget : widgets) {
            widget->update(*renderer);
            if (widget->root() != nullptr && widget->root()->dirty()) {
                changed = true;
                widget->layout(*renderer, w, h);
            }
        }
        if (changed) {
            section->layout(*renderer);
        }
    };

    updateSection(instance.startWidgets, instance.startSection);
    updateSection(instance.centerWidgets, instance.centerSection);
    updateSection(instance.endWidgets, instance.endSection);

    // Reposition sections if sizes changed
    if (instance.startSection->dirty() || instance.centerSection->dirty() || instance.endSection->dirty()) {
        const float contentY = (h - instance.startSection->height()) * 0.5f;
        instance.startSection->setPosition(kBarPaddingX, contentY);

        const float centerX = (w - instance.centerSection->width()) * 0.5f;
        const float centerY = (h - instance.centerSection->height()) * 0.5f;
        instance.centerSection->setPosition(centerX, centerY);

        const float rightX = w - instance.endSection->width() - kBarPaddingX;
        const float rightY = (h - instance.endSection->height()) * 0.5f;
        instance.endSection->setPosition(rightX, rightY);
    }
}
