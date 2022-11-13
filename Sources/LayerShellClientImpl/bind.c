#include "../LayerShellClient/wlr-layer-shell-unstable-v1-client-protocol.h"
#include "../LayerShellClient/xdg-output-protocol.h"

// Helpers because it's not possible to take addresses from const values with Swift currently
// and using wl_registry_bind in a header results in a swiftc crash
#define BIND(interface) \
    void * \
    bind_##interface(struct wl_registry *wl_registry, uint32_t name, uint32_t version) { \
        return wl_registry_bind(wl_registry, name, &interface, version); \
    }

BIND(wl_compositor_interface)
BIND(wl_output_interface)
BIND(wl_seat_interface)
BIND(zwlr_layer_shell_v1_interface)
BIND(zxdg_output_manager_v1_interface)
#undef BIND
