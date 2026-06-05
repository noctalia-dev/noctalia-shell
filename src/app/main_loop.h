#pragma once

#include <chrono>
#include <functional>
#include <unordered_map>
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

  // Absolute deadline by which each source must next be dispatched, armed from
  // the timeout it advertised and retained across iterations until it fires.
  std::unordered_map<PollSource*, std::chrono::steady_clock::time_point> m_sourceDeadlines;
};
