#include "ui/dialogs/layer_popup_host.h"

void LayerPopupHostRegistry::registerHost(ContextResolver contextResolver, PopupHook beginAttachedPopup,
                                          PopupHook endAttachedPopup, FallbackResolver fallbackResolver) {
  m_hosts.push_back(Host{
      .contextResolver = std::move(contextResolver),
      .beginAttachedPopup = std::move(beginAttachedPopup),
      .endAttachedPopup = std::move(endAttachedPopup),
      .fallbackResolver = std::move(fallbackResolver),
  });
}

std::optional<LayerPopupParentContext> LayerPopupHostRegistry::contextForSurface(wl_surface* surface) const {
  if (surface == nullptr) {
    return std::nullopt;
  }

  for (const Host& host : m_hosts) {
    if (!host.contextResolver) {
      continue;
    }
    if (auto context = host.contextResolver(surface); context.has_value()) {
      return context;
    }
  }

  return std::nullopt;
}

std::optional<LayerPopupParentContext> LayerPopupHostRegistry::fallbackContext() const {
  for (const Host& host : m_hosts) {
    if (!host.fallbackResolver) {
      continue;
    }
    if (auto context = host.fallbackResolver(); context.has_value()) {
      return context;
    }
  }

  return std::nullopt;
}

void LayerPopupHostRegistry::beginAttachedPopup(wl_surface* surface) const {
  if (surface == nullptr) {
    return;
  }

  for (const Host& host : m_hosts) {
    if (host.beginAttachedPopup) {
      host.beginAttachedPopup(surface);
    }
  }
}

void LayerPopupHostRegistry::endAttachedPopup(wl_surface* surface) const {
  if (surface == nullptr) {
    return;
  }

  for (const Host& host : m_hosts) {
    if (host.endAttachedPopup) {
      host.endAttachedPopup(surface);
    }
  }
}
