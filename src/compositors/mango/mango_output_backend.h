#pragma once

class WaylandConnection;

namespace compositors::mango {

  [[nodiscard]] bool setOutputPower(WaylandConnection& wayland, bool on);

} // namespace compositors::mango
