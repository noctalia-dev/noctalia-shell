#include "compositors/sway/sway_output_backend.h"

#include "core/process.h"

namespace compositors::sway {

  bool setOutputPower(bool on) {
    const char* msgCommand = process::commandExists("scrollmsg") ? "scrollmsg" : "swaymsg";
    if (!process::commandExists(msgCommand)) {
      msgCommand = "i3-msg";
    }
    return process::runAsync({msgCommand, "output", "*", "dpms", on ? "on" : "off"});
  }

} // namespace compositors::sway
