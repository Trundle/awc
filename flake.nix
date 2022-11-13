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
        overlays = [ rust-overlay.overlays.default ];
      };

      rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain;
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        name = "${name}-dev-shell";

        nativeBuildInputs = with pkgs; [
          pkg-config
          rust
          rust-analyzer
          rust-cbindgen
          xorg.xcbutilwm

          swift
          swiftpm
          swiftPackages.clang
        ];

        buildInputs = with pkgs; [
          jq
          openssl

          wayland
          wayland-protocols
          wlroots_0_16
          libdrm
          libxkbcommon
          udev
          libevdev
          pixman
          libGL
          xorg.libxcb
          cairo

          gtk4

          dhall
          dhall-lsp-server
          swiftPackages.Dispatch
          swiftPackages.Foundation
          swiftPackages.XCTest

          # Only used for validation
          glslang
          nixpkgs-fmt
        ];
      };
    };
}
