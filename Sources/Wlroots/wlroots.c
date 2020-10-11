#include <unistd.h>

#include "include/wlroots.h"


void awc_session_command() {
    if (fork() == 0) {
        execl("/bin/sh", "/bin/sh", "-c", "kitty -o linux_display_server=wayland", (void *)NULL);
    }
}
