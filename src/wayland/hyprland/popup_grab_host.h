#pragma once

struct wl_surface;

// Interface implemented by anything that owns an active hyprland_focus_grab_v1
// (e.g. PanelManager). PopupSurface looks up the currently-installed host on
// init and registers its wl_surface with it; on destroy it unregisters. This
// keeps popups out of the path of the host's `cleared` event when the user
// interacts with them (otherwise the compositor sees the popup as "outside"
// and tears the entire grab — and the panel — down).
//
// Hosts publish themselves via FocusGrabService::setPopupGrabHost while their
// grab is active, and clear the slot when the grab is released.
class PopupGrabHost {
public:
  virtual ~PopupGrabHost() = default;

  virtual void registerPopupSurface(wl_surface* surface) = 0;
  virtual void unregisterPopupSurface(wl_surface* surface) = 0;
};
