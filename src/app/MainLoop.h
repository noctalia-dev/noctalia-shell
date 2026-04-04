#pragma once

#include <vector>

class Bar;
class PollSource;
class WaylandConnection;

class MainLoop {
public:
    MainLoop(WaylandConnection& wayland, Bar& bar, std::vector<PollSource*> sources);

    void run();

private:
    WaylandConnection& m_wayland;
    Bar& m_bar;
    std::vector<PollSource*> m_sources;
};
