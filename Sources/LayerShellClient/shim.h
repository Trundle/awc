#pragma once

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "../Wlroots/xdg-shell-protocol.h"

// Not really required for layer shell, but included for convenience
#include "xdg-output-protocol.h"

void *bind_wl_compositor_interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version);
void *bind_wl_output_interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version);
void *bind_wl_seat_interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version);
void *bind_zwlr_layer_shell_v1_interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version);
void *bind_zxdg_output_manager_v1_interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version);
