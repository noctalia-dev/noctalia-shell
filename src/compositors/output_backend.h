#pragma once

struct wl_output;
class WaylandConnection;

class OutputBackend {
public:
  virtual ~OutputBackend() = default;
  virtual void onOutputAdded(wl_output* output) = 0;
  virtual void onOutputRemoved(wl_output* output) = 0;
};

namespace compositors {

  // Compositor-aware monitor power control.
  // Returns true when a matching backend launched at least one command.
  [[nodiscard]] bool setOutputPower(WaylandConnection& wayland, bool on);

} // namespace compositors
