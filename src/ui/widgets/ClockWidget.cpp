#include "ui/widgets/ClockWidget.hpp"

#include "render/Palette.hpp"
#include "render/Renderer.hpp"
#include "time/TimeService.hpp"
#include "ui/controls/Label.hpp"

ClockWidget::ClockWidget(const TimeService& timeService, std::string format)
    : m_time(timeService)
    , m_format(std::move(format)) {}

void ClockWidget::create(Renderer& renderer) {
    auto label = std::make_unique<Label>();
    label->setFontSize(13.0f);
    label->setColor(kRosePinePalette.text);
    m_label = label.get();
    m_root = std::move(label);
    update(renderer);
}

void ClockWidget::layout(Renderer& renderer, float /*barWidth*/, float /*barHeight*/) {
    m_label->measure(renderer);
}

void ClockWidget::update(Renderer& renderer) {
    auto text = m_time.format(m_format.c_str());

    if (text != m_lastText) {
        m_lastText = std::move(text);
        m_label->setText(m_lastText);
        m_label->measure(renderer);
    }
}
