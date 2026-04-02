#pragma once

#include <cstdint>
#include <optional>
#include <string>

enum class Urgency : uint8_t {
    Low      = 0,
    Normal   = 1,
    Critical = 2,
};

struct Notification {
    uint32_t                    id;
    std::string                 app_name;
    std::string                 summary;
    std::string                 body;
    int32_t                     timeout;
    Urgency                     urgency;
    std::optional<std::string>  icon;
    std::optional<std::string>  category;
    std::optional<std::string>  desktop_entry;
};
