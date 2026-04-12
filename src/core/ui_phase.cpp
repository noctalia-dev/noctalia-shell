#include "core/ui_phase.h"

#include <cstdio>
#include <cstdlib>

namespace {

  thread_local UiPhase g_currentUiPhase = UiPhase::Idle;

} // namespace

UiPhase currentUiPhase() noexcept { return g_currentUiPhase; }

const char* uiPhaseName(UiPhase phase) noexcept {
  switch (phase) {
  case UiPhase::Idle:
    return "Idle";
  case UiPhase::PrepareFrame:
    return "PrepareFrame";
  case UiPhase::Update:
    return "Update";
  case UiPhase::Layout:
    return "Layout";
  case UiPhase::Render:
    return "Render";
  }
  return "Unknown";
}

UiPhaseScope::UiPhaseScope(UiPhase phase) noexcept : m_previous(g_currentUiPhase) { g_currentUiPhase = phase; }

UiPhaseScope::~UiPhaseScope() { g_currentUiPhase = m_previous; }

void uiAssertSceneMutationAllowed(const char* operation) {
#ifndef NDEBUG
  if (g_currentUiPhase == UiPhase::Render) {
    std::fprintf(stderr, "UI phase violation: %s is not allowed during %s\n", operation, uiPhaseName(g_currentUiPhase));
    std::abort();
  }
#else
  (void)operation;
#endif
}
