#pragma once

namespace noctalia::config {

  // Entry point for `noctalia config <command> [options]`. Returns a process
  // exit code. Pure CLI helper; does not start Application or mutate live config.
  int runCli(int argc, char* argv[]);

} // namespace noctalia::config
