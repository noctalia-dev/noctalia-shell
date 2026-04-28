#include "compositors/ext_workspace_output_backend.h"

#include "core/process.h"

namespace compositors::ext_workspace {

  bool setOutputPower(bool on) { return process::runAsync({"wlr-randr", on ? "--on" : "--off"}); }

} // namespace compositors::ext_workspace
