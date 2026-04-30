#pragma once

#include "app/poll_source.h"
#include "wayland/clipboard_service.h"

class ClipboardPollSource final : public PollSource {
public:
  explicit ClipboardPollSource(ClipboardService& clipboard) : m_clipboard(clipboard) {}

  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override {
    m_clipboard.dispatchPollEvents(fds, startIdx, m_pollFdCount);
  }

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override { m_pollFdCount = m_clipboard.addPollFds(fds); }

private:
  ClipboardService& m_clipboard;
  std::size_t m_pollFdCount = 0;
};
