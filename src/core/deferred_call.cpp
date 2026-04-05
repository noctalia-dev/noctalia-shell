#include "core/deferred_call.h"

std::vector<std::function<void()>>& DeferredCall::queue() {
  static std::vector<std::function<void()>> q;
  return q;
}

void DeferredCall::callLater(std::function<void()> fn) { queue().push_back(std::move(fn)); }
