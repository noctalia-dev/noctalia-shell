#include "shell/Bar.hpp"

#include "config/ConfigService.hpp"
#include "core/Log.hpp"
#include "render/Palette.hpp"
#include "render/scene/RectNode.hpp"
#include "time/TimeService.hpp"
#include "ui/Widget.hpp"
#include "ui/controls/Box.hpp"
#include "wayland/WaylandConnection.hpp"

#include <algorithm>

#include <wayland-client-core.h>

namespace {

std::uint32_t positionToAnchor(const std::string& position) {
    if (position == "bottom") {
        return LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right;
    }
    if (position == "left") {
        return LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left;
    }
    if (position == "right") {
        return LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Right;
    }
    // Default: top
    return LayerShellAnchor::Top | LayerShellAnchor::Left | LayerShellAnchor::Right;
}

} // namespace

Bar::Bar() = default;

bool Bar::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService) {
    m_wayland = &wayland;
    m_config = config;
    m_time = timeService;

    m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config());

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

    m_config->setReloadCallback([this]() {
        reload();
    });

    syncInstances();
    return true;
}

void Bar::reload() {
    logInfo("bar: reloading config");
    m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config());
    m_instances.clear();
    syncInstances();
}

void Bar::closeAllInstances() {
    m_instances.clear();
}

void Bar::onOutputChange() {
    syncInstances();
}

void Bar::onWorkspaceChange() {
    for (auto& inst : m_instances) {
        if (inst->surface == nullptr || inst->surface->renderer() == nullptr) {
            continue;
        }
        inst->surface->renderer()->makeCurrent();
        updateWidgets(*inst);
        inst->surface->renderNow();
    }
}

bool Bar::isRunning() const noexcept {
    return std::any_of(m_instances.begin(), m_instances.end(),
        [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
}

void Bar::syncInstances() {
    const auto& outputs = m_wayland->outputs();
    const auto& bars = m_config->config().bars;

    // Remove instances for outputs that no longer exist
    std::erase_if(m_instances, [&outputs](const auto& inst) {
        bool found = std::any_of(outputs.begin(), outputs.end(),
            [&inst](const auto& out) { return out.name == inst->outputName; });
        if (!found) {
            logInfo("bar: removing instance for output {}", inst->outputName);
        }
        return !found;
    });

    // Create instances for each bar definition × each output
    for (std::size_t barIdx = 0; barIdx < bars.size(); ++barIdx) {
        for (const auto& output : outputs) {
            bool exists = std::any_of(m_instances.begin(), m_instances.end(),
                [&output, barIdx](const auto& inst) {
                    return inst->outputName == output.name && inst->barIndex == barIdx;
                });
            if (!exists) {
                auto resolved = ConfigService::resolveForOutput(bars[barIdx], output);
                if (!resolved.enabled) {
                    continue;
                }
                createInstance(output, resolved);
                m_instances.back()->barIndex = barIdx;
            }
        }
    }
}

void Bar::createInstance(const WaylandOutput& output, const BarConfig& barConfig) {
    logInfo("bar: creating \"{}\" on {} ({}), height={} position={}",
            barConfig.name, output.connectorName, output.description,
            barConfig.height, barConfig.position);

    auto instance = std::make_unique<BarInstance>();
    instance->outputName = output.name;
    instance->output = output.output;
    instance->scale = output.scale;
    instance->barConfig = barConfig;

    const auto anchor = positionToAnchor(barConfig.position);
    const bool vertical = (barConfig.position == "left" || barConfig.position == "right");

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-" + barConfig.name,
        .layer = LayerShellLayer::Top,
        .anchor = anchor,
        .width = vertical ? barConfig.height : 0,
        .height = vertical ? 0 : barConfig.height,
        .exclusiveZone = static_cast<std::int32_t>(barConfig.height),
        .defaultHeight = vertical ? 0 : barConfig.height,
    };

    instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));

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
    auto createWidgets = [&](const std::vector<std::string>& names,
                             std::vector<std::unique_ptr<Widget>>& dest) {
        for (const auto& name : names) {
            auto widget = m_widgetFactory->create(name, instance.output);
            if (widget != nullptr) {
                dest.push_back(std::move(widget));
            }
        }
    };

    createWidgets(instance.barConfig.startWidgets, instance.startWidgets);
    createWidgets(instance.barConfig.centerWidgets, instance.centerWidgets);
    createWidgets(instance.barConfig.endWidgets, instance.endWidgets);
}

void Bar::buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height) {
    auto* renderer = instance.surface->renderer();
    if (renderer == nullptr) {
        return;
    }

    const auto w = static_cast<float>(width);
    const auto h = static_cast<float>(height);
    const float padding = instance.barConfig.padding;
    const float gap = instance.barConfig.gap;

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
        auto makeSection = [gap]() {
            auto box = std::make_unique<Box>();
            box->setDirection(BoxDirection::Horizontal);
            box->setGap(gap);
            box->setAlign(BoxAlign::Center);
            return box;
        };

        instance.startSection = static_cast<Box*>(instance.sceneRoot->addChild(makeSection()));
        instance.centerSection = static_cast<Box*>(instance.sceneRoot->addChild(makeSection()));
        instance.endSection = static_cast<Box*>(instance.sceneRoot->addChild(makeSection()));

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

    // Position sections
    const float contentY = (h - instance.startSection->height()) * 0.5f;
    instance.startSection->setPosition(padding, contentY);

    const float centerX = (w - instance.centerSection->width()) * 0.5f;
    const float centerY = (h - instance.centerSection->height()) * 0.5f;
    instance.centerSection->setPosition(centerX, centerY);

    const float endX = w - instance.endSection->width() - padding;
    const float endY = (h - instance.endSection->height()) * 0.5f;
    instance.endSection->setPosition(endX, endY);
}

void Bar::updateWidgets(BarInstance& instance) {
    auto* renderer = instance.surface->renderer();
    if (renderer == nullptr) {
        return;
    }

    const auto w = static_cast<float>(instance.surface->width());
    const auto h = static_cast<float>(instance.surface->height());
    const float padding = instance.barConfig.padding;

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
        instance.startSection->setPosition(padding, contentY);

        const float centerX = (w - instance.centerSection->width()) * 0.5f;
        const float centerY = (h - instance.centerSection->height()) * 0.5f;
        instance.centerSection->setPosition(centerX, centerY);

        const float endX = w - instance.endSection->width() - padding;
        const float endY = (h - instance.endSection->height()) * 0.5f;
        instance.endSection->setPosition(endX, endY);
    }
}
