#include "ui/controls/Chip.hpp"

#include "ui/controls/Label.hpp"
#include "ui/style/Palette.hpp"
#include "ui/style/Style.hpp"

#include <memory>

Chip::Chip() {
    setAlign(BoxAlign::Center);
    setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
    setRadius(Style::radiusMd);
    setSoftness(0.75f);

    auto label = std::make_unique<Label>();
    m_label = static_cast<Label*>(addChild(std::move(label)));
    m_label->setFontSize(Style::fontSizeXs);
    setWorkspaceActive(false);
}

void Chip::setText(std::string_view text) {
    m_label->setText(text);
}

void Chip::setWorkspaceActive(bool active) {
    if (active) {
        setBackground(palette.primary);
        m_label->setColor(palette.onPrimary);
        setBorderWidth(0.0f);
    } else {
        setBackground(palette.surfaceVariant);
        m_label->setColor(palette.onSurfaceVariant);
        setBorderColor(palette.outline);
        setBorderWidth(Style::borderWidth);
    }
}
