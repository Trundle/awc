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
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        name = "${name}-dev-shell";

        nativeBuildInputs = with pkgs; [
          pkg-config
          rust
          rust-analyzer
          rust-cbindgen
        ];

        buildInputs = with pkgs; [
          openssl

          wayland
          wayland-protocols
          wlroots
          libdrm
          libxkbcommon
          udev
          libevdev
          pixman
          libGL
          xorg.libxcb
          cairo

          dhall
          dhall-lsp-server
          swift

          # Only used for validation
          glslang
          nixpkgs-fmt
        ];
      };
    };
}
