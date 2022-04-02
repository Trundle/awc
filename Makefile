config ?= debug

WAYLAND_PROTOCOLS=$(shell pkg-config --variable=pkgdatadir wayland-protocols)
WAYLAND_SCANNER=$(shell pkg-config --variable=wayland_scanner wayland-scanner)
LIBS_CFLAGS=\
	 $(shell pkg-config --cflags wlroots) \
	 $(shell pkg-config --cflags wayland-server) \
	 $(shell pkg-config --cflags xkbcommon) \
	 $(shell pkg-config --cflags libudev) \
	 $(shell pkg-config --cflags glesv2) \
	 $(shell pkg-config --cflags pixman-1) \
	 $(shell pkg-config --cflags xcb) \
	 $(shell pkg-config --cflags openssl) \
	 $(shell pkg-config --cflags cairo) \
	 $(shell pkg-config --cflags libdrm)
LIBS=\
	 $(shell pkg-config --libs wlroots) \
	 $(shell pkg-config --libs wayland-server) \
	 $(shell pkg-config --libs xkbcommon) \
	 $(shell pkg-config --libs libudev) \
	 $(shell pkg-config --libs glesv2) \
	 $(shell pkg-config --libs pixman-1) \
	 $(shell pkg-config --libs xcb) \
	 $(shell pkg-config --libs openssl) \
	 $(shell pkg-config --libs cairo)

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

Sources/awc_config/libawc_config.h: Sources/awc_config/src/lib.rs
	cd Sources/awc_config && cbindgen -l c > libawc_config.h

Sources/awc_config/libawc_config.so: Sources/awc_config/src/lib.rs Sources/awc_config/libawc_config.h
	cd Sources/awc_config && cargo build --release

Sources/awcctl/target/release/awcctl: Sources/awcctl/src/main.rs
	cd Sources/awcctl && cargo build --release

target/awc: awc
	mkdir -p target
	ln -sf $(shell swift build -c $(config) --show-bin-path)/awc target/awc

target/awcctl: Sources/awcctl/target/release/awcctl
	ln -sf $(shell realpath $<) target/awcctl

target/SpawnHelper: Sources/SpawnHelper/main.c
	mkdir -p target
	$(CC) --std=c99 -o $@ $^

awc: Sources/awc_config/libawc_config.so \
  Sources/awcctl/target/release/awcctl \
  Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.h
	swift build -c $(config) \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -ISources/awc_config \
		-Xlinker -LSources/awc_config/target/release/ \
		-Xlinker -lawc_config -Xlinker -rpath -Xlinker `pwd`/Sources/awc_config \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

test: awc
	swift test \
	    --enable-code-coverage --enable-test-discovery \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xlinker -LSources/awc_config/target/release/ \
		-Xlinker -lawc_config -Xlinker -rpath -Xlinker `pwd`/Sources/awc_config \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

clean:
	rm -f Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.*
	rm -f Sources/awc_config/*.a
	rm -Rf .build target
	cd Sources/awc_config && cargo clean
	cd Sources/awcctl && cargo clean

fmt:
	dhall format Sources/awc_config/Dhall/Types.dhall
	cd Sources/awc_config && cargo fmt
	cd Sources/awcctl && cargo fmt

validateShaders:
	python Tools/validate_shaders.py

validate: validateShaders
	nixpkgs-fmt --check flake.nix

all: target/awc target/awcctl target/SpawnHelper


.DEFAULT_GOAL=all
.PHONY: awc clean fmt test validate validateShaders
