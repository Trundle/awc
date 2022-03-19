/*
 * A minimal helper so spawned processes aren't children of awc's process.
 */

#include <spawn.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }

    posix_spawnattr_t attrs;
    int result;
    if (result = posix_spawnattr_init(&attrs) != 0) {
        _exit(result);
    }

    if (result = posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETPGROUP) != 0) {
        _exit(result);
    }
    if (result = posix_spawnattr_setpgroup(&attrs, 0) != 0) {
        _exit(result);
    }

    _exit(posix_spawn(NULL, argv[1], NULL, &attrs, argv + 1, environ));
}
