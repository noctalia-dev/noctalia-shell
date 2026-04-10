#pragma once

struct wl_output;

class OutputBackend {
public:
  virtual ~OutputBackend() = default;
  virtual void onOutputAdded(wl_output* output) = 0;
  virtual void onOutputRemoved(wl_output* output) = 0;
};
