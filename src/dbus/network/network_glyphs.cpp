#include "dbus/network/network_glyphs.h"

#include "dbus/network/network_types.h"

namespace network_glyphs {

  const char* glyphForState(const NetworkState& state) noexcept {
    if (state.vpnActive) {
      return "shield-check";
    }
    if (state.kind == NetworkConnectivity::Wired) {
      return state.connected ? "ethernet" : "ethernet-off";
    }
    return wifiGlyphForState(state);
  }

  const char* wifiGlyphForState(const NetworkState& state) noexcept {
    if (!state.wirelessEnabled) {
      return "wifi-off";
    }
    if (state.kind == NetworkConnectivity::Unknown) {
      return "wifi-question";
    }
    if (state.kind == NetworkConnectivity::Wireless && state.connected) {
      return wifiGlyphForSignal(state.signalStrength);
    }
    return "wifi-exclamation";
  }

  const char* wifiGlyphForSignal(std::uint8_t signal) noexcept {
    if (signal >= 80) {
      return "wifi";
    }
    if (signal >= 60) {
      return "wifi-3";
    }
    if (signal >= 35) {
      return "wifi-2";
    }
    if (signal >= 15) {
      return "wifi-1";
    }
    return "wifi-0";
  }

} // namespace network_glyphs
