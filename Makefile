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
	 $(shell pkg-config --cflags xcb-icccm) \
	 $(shell pkg-config --cflags openssl) \
	 $(shell pkg-config --cflags cairo) \
	 $(shell pkg-config --cflags libdrm)
LIBS=\
	 $(shell pkg-config --libs wlroots) \
	 $(shell pkg-config --libs wayland-server) \
	 $(shell pkg-config --libs xkbcommon) \
	 $(shell pkg-config --libs libudev) \
	 $(shell pkg-config --libs egl) \
	 $(shell pkg-config --libs glesv2) \
	 $(shell pkg-config --libs pixman-1) \
	 $(shell pkg-config --libs xcb) \
	 $(shell pkg-config --libs xcb-icccm) \
	 $(shell pkg-config --libs openssl) \
	 $(shell pkg-config --libs cairo)

LIBS_CLIENT_CFLAGS=\
	$(shell pkg-config --cflags cairo) \
	$(shell pkg-config --cflags glesv2) \
	$(shell pkg-config --cflags wayland-client)
LIBS_CLIENT=\
	$(shell pkg-config --libs cairo) \
	$(shell pkg-config --libs glesv2) \
	$(shell pkg-config --libs wayland-client)
TARGET_TRIPLE=$(shell swiftc -print-target-info | jq -r .target.triple)


# wayland-scanner is a tool which generates C headers and rigging for Wayland
# protocols, which are specified in XML. wlroots requires you to rig these up
# to your build system yourself and provide them in the include path.
Sources/LayerShellClient/wlr-layer-shell-unstable-v1-client-protocol.h: \
  Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/xdg-shell-protocol.h
	$(WAYLAND_SCANNER) client-header Sources/Wlroots/protocols/wlr-layer-shell-unstable-v1.xml $@

.build/${TARGET_TRIPLE}/generated/LayerShellImpl:
	mkdir -p $@

.build/${TARGET_TRIPLE}/generated/LayerShellImpl/protocol.c: .build/${TARGET_TRIPLE}/generated/LayerShellImpl
	$(WAYLAND_SCANNER) private-code Sources/Wlroots/protocols/wlr-layer-shell-unstable-v1.xml $@

.build/${TARGET_TRIPLE}/generated/LayerShellImpl/xdg-output-protocol.c: .build/${TARGET_TRIPLE}/generated/LayerShellImpl
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS)/unstable/xdg-output/xdg-output-unstable-v1.xml $@

.build/${TARGET_TRIPLE}/generated/LayerShellImpl/xdg-shell-protocol.c: Sources/Wlroots/xdg-shell-protocol.h
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml $@

Sources/LayerShellClientImpl/%.o: \
  Sources/LayerShellClient/wlr-layer-shell-unstable-v1-client-protocol.h \
  Sources/LayerShellClient/xdg-output-protocol.h \
  %c.c
.build/${TARGET_TRIPLE}/generated/LayerShellImpl/%.o: %.c
	$(CC) -c $< -o $@

.build/${TARGET_TRIPLE}/generated/libLayerShellImpl.a: \
  .build/${TARGET_TRIPLE}/generated/LayerShellImpl/protocol.o \
  .build/${TARGET_TRIPLE}/generated/LayerShellImpl/xdg-output-protocol.o \
  .build/${TARGET_TRIPLE}/generated/LayerShellImpl/xdg-shell-protocol.o \
  Sources/LayerShellClientImpl/bind.o
	ar -rcs $@ $^

Sources/LayerShellClient/xdg-output-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		$(WAYLAND_PROTOCOLS)/unstable/xdg-output/xdg-output-unstable-v1.xml $@

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

Sources/LayoutSwitcher/target/release/layout_switcher: Sources/LayoutSwitcher/src/main.rs
	cd Sources/LayoutSwitcher && cargo build --release

target/awc: awc
	mkdir -p target
	ln -sf $(shell swift build -c $(config) --show-bin-path)/awc target/awc

target/awcctl: Sources/awcctl/target/release/awcctl
	ln -sf $(shell realpath $<) target/awcctl

target/layout_switcher: Sources/LayoutSwitcher/target/release/layout_switcher
	ln -sf $(shell realpath $<) target/layout_switcher

target/NeonSlurp: NeonSlurp
	mkdir -p target
	ln -sf $(shell swift build -c $(config) --show-bin-path)/NeonSlurp $@

target/OutputHud: OutputHud
	mkdir -p target
	ln -sf $(shell swift build -c $(config) --show-bin-path)/OutputHud $@

target/SpawnHelper: Sources/SpawnHelper/main.c
	mkdir -p target
	$(CC) --std=c99 -o $@ $^

NeonSlurp: \
  Sources/Wlroots/xdg-shell-protocol.h \
  Sources/LayerShellClient/wlr-layer-shell-unstable-v1-client-protocol.h \
  Sources/LayerShellClient/xdg-output-protocol.h \
  .build/${TARGET_TRIPLE}/generated/libLayerShellImpl.a
	swift build --product NeonSlurp -c $(config) \
		$(shell echo "$(LIBS_CLIENT_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		-Xlinker -L.build/${TARGET_TRIPLE}/generated \
		$(shell echo "$(LIBS_CLIENT)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

OutputHud: \
  Sources/Wlroots/xdg-shell-protocol.h \
  Sources/LayerShellClient/wlr-layer-shell-unstable-v1-client-protocol.h \
  Sources/LayerShellClient/xdg-output-protocol.h \
  .build/${TARGET_TRIPLE}/generated/libLayerShellImpl.a
	swift build --product OutputHud -c $(config) \
		$(shell echo "$(LIBS_CLIENT_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		-Xlinker -L.build/${TARGET_TRIPLE}/generated \
		$(shell echo "$(LIBS_CLIENT)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

awc: Sources/awc_config/libawc_config.so \
  Sources/awcctl/target/release/awcctl \
  Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.h
	swift build -c $(config) --product awc \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xcc -ISources/awc_config \
		-Xlinker -LSources/awc_config/target/release/ \
		-Xlinker -lawc_config -Xlinker -rpath -Xlinker `pwd`/Sources/awc_config \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

test: awc \
  .build/${TARGET_TRIPLE}/generated/libLayerShellImpl.a
	swift test \
	    --enable-code-coverage \
	    $(shell echo "$(LIBS_CFLAGS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xcc {} " ) \
		-Xlinker -LSources/awc_config/target/release/ \
		-Xlinker -lawc_config -Xlinker -rpath -Xlinker `pwd`/Sources/awc_config \
		-Xlinker -L.build/${TARGET_TRIPLE}/generated \
		-Xcc -DWLR_USE_UNSTABLE \
		-Xcc -ISources/Wlroots \
		$(shell echo "$(LIBS)" | tr ' ' '\n' | xargs -I {} echo -n "-Xlinker {} ")

clean:
	rm -f Sources/Wlroots/xdg-shell-protocol.h Sources/Wlroots/xdg-shell-protocol.c Sources/Wlroots/wlr-layer-shell-unstable-v1-protocol.*
	rm -f Sources/LayerShellClient/*protocol.h Sources/LayerShellClientImplementation/*protocol.c
	rm -f Sources/awc_config/*.a
	rm -Rf .build target
	cd Sources/awc_config && cargo clean
	cd Sources/awcctl && cargo clean
	cd Sources/LayoutSwitcher && cargo clean

fmt:
	dhall format Sources/awc_config/Dhall/Types.dhall
	cd Sources/awc_config && cargo fmt
	cd Sources/awcctl && cargo fmt
	cd Sources/LayoutSwitcher && cargo fmt

clippy:
	cd Sources/awc_config && cargo clippy
	cd Sources/awcctl && cargo clippy

validateShaders:
	python Tools/validate_shaders.py

validate: validateShaders clippy
	nixpkgs-fmt --check flake.nix
	dhall type < Sources/awc_config/Dhall/Types.dhall

all: target/awc target/awcctl target/layout_switcher target/SpawnHelper OutputHud


.DEFAULT_GOAL=all
.PHONY: awc clean clippy fmt test validate validateShaders NeonSlurp OutputHud
