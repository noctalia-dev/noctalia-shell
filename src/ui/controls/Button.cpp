#include "ui/controls/Button.hpp"

#include "render/core/Color.hpp"
#include "ui/controls/Label.hpp"
#include "ui/style/Palette.hpp"
#include "ui/style/Style.hpp"

#include <memory>

Button::Button() {
    setAlign(BoxAlign::Center);
    setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
    setRadius(Style::radiusMd);

    auto label = std::make_unique<Label>();
    m_label = static_cast<Label*>(addChild(std::move(label)));
    applyVariant();
}

void Button::setText(std::string_view text) {
    m_label->setText(text);
}

void Button::setFontSize(float size) {
    m_label->setFontSize(size);
}

void Button::setVariant(ButtonVariant variant) {
    if (m_variant == variant) {
        return;
    }
    m_variant = variant;
    applyVariant();
}

void Button::applyVariant() {
    setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
    setRadius(Style::radiusMd);

    switch (m_variant) {
    case ButtonVariant::Default:
        setBackground(kRosePinePalette.iris);
        m_label->setColor(kRosePinePalette.base);
        setBorderColor(kRosePinePalette.overlay);
        setBorderWidth(0.0f);
        break;
    case ButtonVariant::Secondary:
        setBackground(kRosePinePalette.overlay);
        m_label->setColor(kRosePinePalette.text);
        setBorderColor(kRosePinePalette.overlay);
        setBorderWidth(0.0f);
        break;
    case ButtonVariant::Destructive:
        setBackground(kRosePinePalette.love);
        m_label->setColor(kRosePinePalette.base);
        setBorderColor(kRosePinePalette.overlay);
        setBorderWidth(0.0f);
        break;
    case ButtonVariant::Outline:
        setBackground(rgba(0.0f, 0.0f, 0.0f, 0.0f));
        m_label->setColor(kRosePinePalette.text);
        setBorderColor(kRosePinePalette.overlay);
        setBorderWidth(Style::borderWidth);
        break;
    case ButtonVariant::Ghost:
        setBackground(rgba(0.0f, 0.0f, 0.0f, 0.0f));
        m_label->setColor(kRosePinePalette.text);
        setBorderWidth(0.0f);
        break;
    }
}
