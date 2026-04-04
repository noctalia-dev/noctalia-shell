#pragma once

#include <functional>
#include <vector>

class Bar;
class PollSource;
class WaylandConnection;

class MainLoop {
public:
  MainLoop(WaylandConnection& wayland, Bar& bar, std::vector<PollSource*> sources);

  void run();

  /// Schedule a callback to run once at the top of the next main loop iteration.
  static void callLater(std::function<void()> fn);

private:
  static MainLoop* s_instance;

  WaylandConnection& m_wayland;
  Bar& m_bar;
  std::vector<PollSource*> m_sources;
  std::vector<std::function<void()>> m_deferred;
};
