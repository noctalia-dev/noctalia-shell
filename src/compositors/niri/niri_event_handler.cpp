#include "compositors/niri/niri_event_handler.h"

#include "compositors/niri/niri_runtime.h"

namespace compositors::niri {

  NiriEventHandler::NiriEventHandler(NiriRuntime& runtime) : m_runtime(runtime) {
    m_runtime.registerEventHandler(this);
  }

  NiriEventHandler::~NiriEventHandler() { m_runtime.unregisterEventHandler(this); }

} // namespace compositors::niri
