#pragma once

#include <string>

class CompositorPlatform;
class OsdOverlay;

class KeyboardLayoutOsd {
public:
  void bindOverlay(OsdOverlay& overlay);
  void prime(const CompositorPlatform& platform);
  void onLayoutChanged(const CompositorPlatform& platform);

private:
  OsdOverlay* m_overlay = nullptr;
  std::string m_lastLayoutName;
  bool m_hasLayout = false;
};
