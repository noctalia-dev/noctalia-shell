#pragma once

#include <cstddef>
#include <string>

namespace ProcessFds {

  [[nodiscard]] std::string describeOpenFileDescriptors(std::size_t maxTargets = 8);

  // Raise the soft RLIMIT_NOFILE toward the hard limit. The default 1024 soft cap
  // is far too low for a long-running GPU client: the NVIDIA EGL/Wayland driver
  // accumulates internal sync_file fences over a session, and exhausting the soft
  // limit makes the Wayland connection fail fatally. Captures the pre-raise soft
  // limit so children can be reset to it. Returns a human-readable summary of the
  // outcome for logging.
  [[nodiscard]] std::string raiseOpenFileLimit();

  // Restore the soft RLIMIT_NOFILE captured before raiseOpenFileLimit() ran. Call
  // this in a forked child just before exec: our raised soft limit is inherited by
  // spawned processes, and programs using select() (fds must be < FD_SETSIZE) or a
  // close-all-fds loop up to rlim_cur choke on the huge limit — Steam launches but
  // its games fail to start. Async-signal-safe (getrlimit/setrlimit only).
  void resetOpenFileLimitForChild() noexcept;

} // namespace ProcessFds
