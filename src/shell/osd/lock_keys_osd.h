#pragma once

#include "wayland/wayland_seat.h"

class LockKeysService;
class OsdOverlay;

class LockKeysOsd {
public:
  void bindOverlay(OsdOverlay& overlay);
  void primeFromService(const LockKeysService& service);
  void onLockKeysChanged(const WaylandSeat::LockKeysState& previous, const WaylandSeat::LockKeysState& current);

private:
  OsdOverlay* m_overlay = nullptr;
  WaylandSeat::LockKeysState m_lastState;
  bool m_hasState = false;
};
