#pragma once

#include "ui/controls/Box.hpp"

#include <string_view>

class Label;

enum class ButtonVariant : std::uint8_t {
    Default,
    Secondary,
    Destructive,
    Outline,
    Ghost,
};

class Button : public Box {
public:
    Button();

    void setText(std::string_view text);
    void setFontSize(float size);
    void setVariant(ButtonVariant variant);

    [[nodiscard]] Label* label() const noexcept { return m_label; }

private:
    void applyVariant();

    Label* m_label = nullptr;
    ButtonVariant m_variant = ButtonVariant::Default;
};
