#include "ui/controls/glyph_registry.h"
#include "core/log.h"

#include <string>
#include <unordered_map>

namespace {

  constexpr Logger kLog("glyph");

  // Hand-curated alias → codepoint map.
  // To add a new icon, find its codepoint in assets/fonts/tabler-icons.json.
  // clang-format off
const std::unordered_map<std::string, char32_t> kIcons = {
    // General
    {"close", 0xEB55},             // x
    {"check", 0xEA5E},             // check
    {"settings", 0xEB20},          // settings
    {"refresh", 0xEB13},           // refresh
    {"add", 0xEB0B},               // plus
    {"trash", 0xEB41},             // trash
    {"menu", 0xEC42},              // menu-2
    {"person", 0xEB4D},            // user
    {"folder-open", 0xFAF7},       // folder-open
    {"download", 0xEA96},          // download
    {"search", 0xEB1C},            // search
    {"question-mark", 0xEC9D},     // question-mark
    {"info", 0xF028},              // file-description
    {"eye", 0xEA9A},               // eye
    {"pin", 0xEC9C},               // pin
    {"unpin", 0xED5F},             // pinned-off
    {"image", 0xEB0A},             // photo
    {"keyboard", 0xEBD6},          // keyboard
    {"lock", 0xEAE2},              // lock
    {"star", 0xEB2E},              // star
    {"star-off", 0xED62},          // star-off
    {"plugin", 0xF00A},            // plug-connected
    {"official-plugin", 0xF69F},   // shield-filled
    {"circle-filled", 0xF671},
    {"pentagon-filled", 0xF68C},
    {"michelin-star-filled", 0x1000C},
    {"square-rounded-filled", 0xF6A5},
    {"guitar-pick-filled", 0xF67B},
    {"blob-filled", 0xFEB1},
    {"triangle-filled", 0xF6AD},
    {"calendar", 0xEA53},          // calendar
    {"calculator", 0xEB80},        // calculator
    {"copy", 0xEA7A},              // copy
    {"photo", 0xEB0A},             // photo
    {"file-text", 0xEAA2},         // file-text
    {"home", 0xEAC1},              // home
    {"hourglass", 0XF146},         // hourglass-empty

    // Toast / warnings
    {"toast-notice", 0xEA67},      // circle-check
    {"toast-warning", 0xEA05},     // alert-circle
    {"toast-error", 0xEA6A},       // circle-x
    {"warning", 0xF634},           // exclamation-circle

    // Media
    {"media-pause", 0xF690},       // player-pause-filled
    {"media-play", 0xF691},        // player-play-filled
    {"media-prev", 0xF693},        // player-skip-back-filled
    {"media-next", 0xF694},        // player-skip-forward-filled
    {"shuffle", 0xF000},           // arrows-shuffle
    {"repeat", 0xEB72},            // repeat
    {"repeat-once", 0xEB71},       // repeat-once
    {"stop", 0xF695},              // player-stop-filled
    {"disc", 0x1003E},             // disc-filled
    {"headphones", 0xEABD},        // headphones
    {"microphone", 0xEAF0},        // microphone
    {"microphone-mute", 0xED16},   // microphone-off

    // Volume
    {"volume-high", 0xEB51},       // volume
    {"volume-low", 0xEB4F},        // volume-2
    {"volume-mute", 0xF1C3},       // volume-off
    {"volume-x", 0xEB50},          // volume-3
    {"volume-zero", 0xEB50},       // volume-3

    // Network speed
    {"download-speed", 0xEA96},    // download
    {"upload-speed", 0xEB47},      // upload

    // System monitor
    {"cpu-intensive", 0xECC6},     // alert-octagon
    {"cpu-usage", 0xFA77},         // brand-speedtest
    {"cpu-temperature", 0xEC2C},   // flame
    {"gpu-temperature", 0xEA89},   // device-desktop
    {"memory", 0xEF8E},            // cpu
    {"storage", 0xEA88},           // database
    {"busy", 0xF146},              // hourglass-empty

    // Power
    {"performance", 0xEAB1},       // gauge
    {"balanced", 0xEBC2},          // scale
    {"powersaver", 0xED4F},        // leaf
    {"shutdown", 0xEB0D},          // power
    {"lock", 0xEAE2},              // lock
    {"lock-pause", 0xF92E},        // lock-pause
    {"logout", 0xEBA8},            // logout
    {"reboot", 0xEB13},            // refresh
    {"suspend", 0xED45},           // player-pause
    {"hibernate", 0xF228},         // zzz

    // Night light / dark mode
    {"nightlight-on", 0xEAF8},     // moon
    {"nightlight-off", 0xF162},    // moon-off
    {"nightlight-forced", 0xECE7}, // moon-stars
    {"theme-mode", 0xFE56},        // contrast-filled

    // Notifications
    {"bell", 0xEA35},              // bell
    {"bell-off", 0xECE9},          // bell-off

    // Idle inhibitor
    {"keep-awake-on", 0xEAFB},     // mug
    {"keep-awake-off", 0xF165},    // mug-off

    // Brightness
    {"brightness-low", 0xFB23},    // brightness-down-filled
    {"brightness-high", 0xFB24},   // brightness-up-filled

    // Chevrons / carets / arrows
    {"chevron-left", 0xEA60},      // chevron-left
    {"chevron-right", 0xEA61},     // chevron-right
    {"chevron-up", 0xEA62},        // chevron-up
    {"chevron-down", 0xEA5F},      // chevron-down
    {"caret-up", 0xFB2D},          // caret-up-filled
    {"caret-down", 0xFB2A},        // caret-down-filled
    {"caret-left", 0xFB2B},        // caret-left-filled
    {"caret-right", 0xFB2C},       // caret-right-filled
    {"square-filled", 0xFC40},     // square-filled
    {"arrow-left", 0xEA19},        // arrow-left
    {"arrow-back", 0xEA0c},        // arrow-back

    // Wallpaper / color
    {"camera-video", 0xED22},      // video
    {"wallpaper-selector", 0xFD4A}, // library-photo
    {"color-picker", 0xEBE6},      // color-picker

    // Battery
    {"battery-0", 0xEA34},         // battery
    {"battery-1", 0xEA2F},         // battery-1
    {"battery-2", 0xEA30},         // battery-2
    {"battery-3", 0xEA31},         // battery-3
    {"battery-4", 0xEA32},         // battery-4
    {"battery-charging", 0xEA33},  // battery-charging
    {"battery-plugged", 0xEF3B},    // battery-charging-2
    {"battery-exclamation", 0xFF1D}, // battery-exclamation
    {"battery-off", 0xED1C},       // battery-off

    // WiFi & Network
    {"wifi", 0xEB52},              // wifi
    {"wifi-0", 0xEBA3},            // wifi-0
    {"wifi-1", 0xEBA4},            // wifi-1
    {"wifi-2", 0xEBA5},            // wifi-2
    {"wifi-off", 0xECFA},          // wifi-off
    {"ethernet", 0xECCC},
    {"ethernet-off", 0xECCD},
    {"ethernet-exclamation", 0xECCE},
    {"ethernet-question", 0xECCF},


    // Bluetooth devices
    {"bluetooth", 0xEA37},
    {"bluetooth-connected", 0xECEA},
    {"bluetooth-off", 0xECEB},
    {"bluetooth-device-generic", 0xEA37}, // bluetooth
    {"bluetooth-device-gamepad", 0xF1D2}, // device-gamepad-2
    {"bluetooth-device-microphone", 0xEAF0}, // microphone
    {"bluetooth-device-headset", 0xEB90}, // headset
    {"bluetooth-device-earbuds", 0xF5A9}, // device-airpods
    {"bluetooth-device-headphones", 0xEABD}, // headphones
    {"bluetooth-device-mouse", 0xF1D7},   // mouse-2
    {"bluetooth-device-keyboard", 0xEA37}, // bluetooth
    {"bluetooth-device-phone", 0xEA8A},   // device-mobile
    {"bluetooth-device-watch", 0xEBF9},   // device-watch
    {"bluetooth-device-speaker", 0xEA8B}, // device-speaker
    {"bluetooth-device-tv", 0xEA8D},      // device-tv

    // Antenna
    {"antenna-bars-1", 0xECC7},    // antenna-bars-1
    {"antenna-bars-2", 0xECC8},    // antenna-bars-2
    {"antenna-bars-3", 0xECC9},    // antenna-bars-3
    {"antenna-bars-4", 0xECCA},    // antenna-bars-4
    {"antenna-bars-5", 0xECCB},    // antenna-bars-5
    {"antenna-bars-off", 0xF0AA},  // antenna-bars-off

    // Weather
    {"weather-sun", 0xEB30},       // sun
    {"weather-moon", 0xEAF8},      // moon
    {"weather-moon-stars", 0xECE7}, // moon-stars
    {"weather-cloud", 0xEA76},     // cloud
    {"weather-cloud-off", 0xED3E}, // cloud-off
    {"weather-cloud-haze", 0xECD9}, // cloud-fog
    {"weather-cloud-lightning", 0xF84B}, // cloud-bolt
    {"weather-cloud-rain", 0xEA72}, // cloud-rain
    {"weather-cloud-snow", 0xEA73}, // cloud-snow
    {"weather-cloud-sun", 0xEC6D}, // cloud-sun
    {"weather-sunrise", 0xEF1C},   // sunrise
    {"weather-sunset", 0xEC31},    // sunset
    {"wind", 0xEC34},              // wind
    {"compass", 0xEA79},           // compass
    {"clock", 0xEA70},             // clock
    {"world", 0xEB54},             // world
    {"world-pin", 0xF9E4},         // world-pin
    {"map-pin", 0xEAE8},           // map-pin
    {"mountain", 0xEF97},          // mountain

    // Files & Folders
    {"folder", 0xEAAD},            // folder


    // Settings tabs
    {"settings-general", 0xEC38},  // adjustments-horizontal
    {"settings-bar", 0xFD51},      // crop-16-9
    {"settings-user-interface", 0xEF95}, // layout-board
    {"settings-control-center", 0xEC38}, // adjustments-horizontal
    {"settings-dock", 0xEAD3},     // layout-bottombar
    {"settings-launcher", 0xEC45}, // rocket
    {"settings-audio", 0xEA8B},    // device-speaker
    {"settings-display", 0xEA89}, // device-desktop
    {"settings-network", 0xF4C3},  // circles-relation
    {"settings-brightness", 0xEB7E}, // brightness-up
    {"settings-location", 0xF9E4}, // world-pin
    {"settings-color-scheme", 0xEB01}, // palette
    {"settings-wallpaper", 0xEB00}, // paint
    {"settings-wallpaper-selector", 0xFD4A}, // library-photo
    {"settings-hooks", 0xEADE},    // link
    {"settings-notifications", 0xEA35}, // bell
    {"settings-osd", 0xED35},      // picture-in-picture
    {"settings-about", 0xF635},    // info-square-rounded
    {"settings-idle", 0xEAF8},     // moon
    {"settings-lock-screen", 0xEAE2}, // lock
    {"settings-session-menu", 0xEB0D}, // power
    {"settings-system-monitor", 0xED23}, // activity

    // Branding
    {"noctalia", 0xEC33},          // noctalia
    {"hyprland", 0xEC6A},          // hyprland

    // Experimental
    {"flask", 0xEBD2}             // flask
};
  // clang-format on

} // namespace

char32_t GlyphRegistry::lookup(std::string_view name) {
  auto it = kIcons.find(std::string(name));
  if (it != kIcons.end()) {
    return it->second;
  }

  kLog.warn("missing glyph: {}", name);

  // Fallback to skull
  return 0xF292;
}
