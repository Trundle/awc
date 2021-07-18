{
  description = "A Wayland compositor";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      name = "awc";

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ rust-overlay.overlay ];
      };

      rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain;

      swift = pkgs.callPackage ./nixos/swift.nix { };

      swift-env = pkgs.writeShellScriptBin "swift-env" ''
        denylist="/nix /dev /usr"
        mounts=""
        for dir in /*; do
            if [[ -d "$dir" ]] && grep -v "$dir" <<< "$denylist" >/dev/null; then
                mounts="$mounts --bind $dir $dir"
            fi
        done
        for bin in /usr/bin/*; do
            mounts="$mounts --bind $bin $bin"
        done
        exec ${pkgs.bubblewrap}/bin/bwrap \
             --dev-bind /dev /dev \
             --ro-bind /nix /nix \
             --symlink $(dirname $(which swiftc))/../include /usr/include \
             --symlink ${pkgs.clang}/bin/clang /usr/bin/clang \
             --bind /proc /proc \
             --bind /sys /sys \
             $mounts \
             "$@"
      '';
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        name = "${name}-dev-shell";

        nativeBuildInputs = with pkgs; [
          pkg-config
          rust
          rust-analyzer
          rust-cbindgen
          swift
          swift-env
        ];

        buildInputs = with pkgs; [
          openssl

          wayland
          wayland-protocols
          wlroots
          libxkbcommon
          libudev
          libevdev
          pixman
          libGL
          xorg.libxcb

          dhall
          dhall-lsp-server
        ];

        shellHook = ''
            export PATH="$PATH:${swift}/usr/bin"
            export CC=clang
        '';
      };
    };
}
