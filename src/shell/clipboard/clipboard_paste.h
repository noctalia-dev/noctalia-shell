#pragma once

#include "config/config_service.h"
#include "wayland/clipboard_service.h"
#include "wayland/virtual_keyboard_service.h"

namespace clipboard_paste {

  [[nodiscard]] bool pasteEntry(const ClipboardEntry& entry, ClipboardAutoPasteMode mode,
                                VirtualKeyboardService& virtualKeyboard);

} // namespace clipboard_paste
