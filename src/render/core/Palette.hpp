#pragma once

#include "render/core/Color.hpp"

struct Palette {
    Color base;
    Color surface;
    Color overlay;
    Color muted;
    Color subtle;
    Color text;
    Color love;
    Color gold;
    Color rose;
    Color pine;
    Color foam;
    Color iris;
};

inline constexpr Palette kRosePinePalette{
    .base = hex("#191724"),
    .surface = hex("#1f1d2e"),
    .overlay = hex("#26233a"),
    .muted = hex("#6e6a86"),
    .subtle = hex("#908caa"),
    .text = hex("#e0def4"),
    .love = hex("#eb6f92"),
    .gold = hex("#f6c177"),
    .rose = hex("#ebbcba"),
    .pine = hex("#31748f"),
    .foam = hex("#9ccfd8"),
    .iris = hex("#c4a7e7"),
};
