#pragma once

class WaylandConnection;

namespace compositors::mango {
  class MangoRuntime;
  [[nodiscard]] bool setOutputPower(MangoRuntime& runtime, WaylandConnection& wayland, bool on);

} // namespace compositors::mango
