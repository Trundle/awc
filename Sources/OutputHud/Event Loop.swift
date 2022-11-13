import Glibc
import Logging

import CEpoll
import LayerShellClient

fileprivate let logger = Logger(label: "Event Loop")

fileprivate let overlayTimeoutInSeconds = 3

func viewsChanged(state: State, update: () -> ()) -> Bool {
    let outputs: [AwcOutput]
    do {
        outputs = try getAwcOutputs()
    } catch {
        logger.warning("Error when refreshing view list")
        return false
    }

    if state.outputName != outputs[0].name {
        return true
    } else if state.workspace != outputs[0].workspace {
        state.workspace = outputs[0].workspace
        update()
        return true
    } else {
        return false
    }    
}


func run(wlDisplay: OpaquePointer, state: State, update: () -> ()) {
    let epollFd = epoll_create1(0)
    guard epollFd >= 0 else {
        logger.critical("Could not open epoll FD")
        return
    }

    var event = epoll_event()
    event.events = EPOLLIN.rawValue
    event.data.fd = wl_display_get_fd(wlDisplay)
    guard epoll_ctl(epollFd, EPOLL_CTL_ADD, wl_display_get_fd(wlDisplay), &event) == 0 else {
        logger.critical("Could not watch Wayland FD")
        return
    }

    guard let queue = wl_display_create_queue(wlDisplay) else {
        logger.critical("Could not create Wayland event queue")
        return
    }

    var started = timespec()
    clock_gettime(CLOCK_MONOTONIC, &started)
    var now = started

    while state.keepRunning && now.tv_sec - started.tv_sec < overlayTimeoutInSeconds {
        while wl_display_prepare_read_queue(wlDisplay, queue) != 0 {
            wl_display_dispatch_queue_pending(wlDisplay, queue)
        }
        wl_display_flush(wlDisplay)

        var events = epoll_event()
        let nfds = epoll_wait(epollFd, &events, 1, 50)
        if nfds < 0 {
            wl_display_cancel_read(wlDisplay)
        } else {
            wl_display_read_events(wlDisplay)
        }

        wl_display_dispatch_queue_pending(wlDisplay, queue)

        clock_gettime(CLOCK_MONOTONIC, &now)
        if viewsChanged(state: state, update: update) {
            started = now
        }
    }

    state.keepRunning = false
}
