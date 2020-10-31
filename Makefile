WAYLAND_PROTOCOLS=$(shell pkg-config --variable=pkgdatadir wayland-protocols)
WAYLAND_SCANNER=$(shell pkg-config --variable=wayland_scanner wayland-scanner)
LIBS_CFLAGS=\
	 $(shell pkg-config --cflags wlroots) \
	 $(shell pkg-config --cflags wayland-server) \
	 $(shell pkg-config --cflags xkbcommon) \
	 $(shell pkg-config --cflags libudev) \
	 $(shell pkg-config --cflags glesv2) \
	 $(shell pkg-config --cflags pixman-1) \
	 $(shell pkg-config --cflags xcb)
LIBS=\
	 $(shell pkg-config --libs wlroots) \
	 $(shell pkg-config --libs wayland-server) \
	 $(shell pkg-config --libs xkbcommon) \
	 $(shell pkg-config --libs libudev) \
	 $(shell pkg-config --libs glesv2) \
	 $(shell pkg-config --libs pixman-1) \
	 $(shell pkg-config --libs xcb)

# wayland-scanner is a tool which generates C headers and rigging for Wayland
# protocols, which are specified in XML. wlroots requires you to rig these up
# to your build system yourself and provide them in the include path.
Sources/Wlroots/xdg-shell-protocol.h:
	$(WAYLAND_SCANNER) server-header \
		$(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml $@

Sources/Wlroots/xdg-shell-protocol.c: Sources/Wlroots/xdg-shell-protocol.h
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml $@

Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.h:
	$(WAYLAND_SCANNER) server-header Sources/Wlroots/protocols/wlr-layer-shell-unstable-v1.xml $@

awc: Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.h
	swift build \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

test: awc
	swift test \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

clean:
	rm -f Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c
	rm -Rf .build

.DEFAULT_GOAL=awc
.PHONY: clean test
