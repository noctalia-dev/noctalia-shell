#include "ui/widgets/ClockWidget.hpp"

#include "render/Palette.hpp"
#include "render/Renderer.hpp"
#include "ui/controls/Label.hpp"

#include <chrono>
#include <format>

void ClockWidget::create(Renderer& /*renderer*/) {
    auto label = std::make_unique<Label>();
    label->setFontSize(13.0f);
    label->setColor(kRosePinePalette.text);
    m_label = label.get();
    m_root = std::move(label);
}

void ClockWidget::layout(Renderer& renderer, float /*barWidth*/, float /*barHeight*/) {
    m_label->measure(renderer);
}

void ClockWidget::update(Renderer& renderer) {
    const auto now = std::chrono::system_clock::now();
    const auto local = std::chrono::current_zone()->to_local(now);
    auto text = std::format("{:%H:%M}", local);

    if (text != m_lastText) {
        m_lastText = std::move(text);
        m_label->setText(m_lastText);
        m_label->measure(renderer);
    }
}
