#pragma once

#include "app/poll_source.h"
#include "calendar/calendar_service.h"

class CalendarPollSource final : public PollSource {
public:
  explicit CalendarPollSource(CalendarService& calendar) : m_calendar(calendar) {}

  [[nodiscard]] int pollTimeoutMs() const override { return m_calendar.pollTimeoutMs(); }
  void dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) override { m_calendar.tick(); }

protected:
  void doAddPollFds(std::vector<pollfd>& /*fds*/) override {}

private:
  CalendarService& m_calendar;
};
