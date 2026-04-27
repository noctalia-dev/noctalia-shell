#pragma once

#include <functional>
#include <vector>

class Bar;
class PollSource;
class WaylandConnection;

class MainLoop {
public:
  using PollSourcesProvider = std::function<std::vector<PollSource*>()>;

  MainLoop(WaylandConnection& wayland, Bar& bar, PollSourcesProvider sourcesProvider);

  void run();

private:
  WaylandConnection& m_wayland;
  Bar& m_bar;
  PollSourcesProvider m_sourcesProvider;
};
