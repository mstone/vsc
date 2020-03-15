
{
  description = "A flake for building vscodium with appropriate extensions";

  edition = 201909;

  inputs = {

    nixpkgs = {
      uri = "nixpkgs";
    };

    moz_overlay_src = {
      url = "git+https://github.com/mozilla/nixpkgs-mozilla";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, moz_overlay_src }: let

    moz_overlay = import moz_overlay_src;

    nps = import nixpkgs { system = "x86_64-darwin"; overlays = [ moz_overlay ]; };

    rust1 = with nps; (rustChannelOf {
      channel = "stable";
      date = "2020-03-12";
      sha256 = "0pddwpkpwnihw37r8s92wamls8v0mgya67g9m8h6p5zwgh4il1z6";
    }).rust.override {
      targets = ["wasm32-unknown-unknown"];
    };

    vsc = with nps; vscode-with-extensions.override {
      vscode = vscodium;
      vscodeExtensions = with vscode-extensions; [
        bbenoist.Nix
        ms-vscode.Go
      ] ++ vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "rust";
          publisher = "rust-lang";
          version = "0.7.0";
          sha256 = "sha256-QPO5IA5mrYo6cn3hdTjmzhbRN/YU7G4yMspJ+dRBx5o=";
        }
      ];
    };

  in rec {

    packages.x86_64-darwin.vsc = with nixpkgs.legacyPackages.x86_64-darwin; stdenv.mkDerivation {
      pname = "vsc";
      version = "1.0";
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/bin
        makeWrapper ${vsc}/bin/codium $out/bin/codium --prefix PATH : ${lib.makeBinPath [ go_1_13 rust1 ]}
      '';
      buildInputs = [
        makeWrapper
      ];
    };

    defaultPackage.x86_64-darwin = packages.x86_64-darwin.vsc;

    apps.x86_64-darwin.vsc = {
      type = "app";
      program = "${self.packages.x86_64-darwin.vsc}/bin/codium";
    };

    defaultApp.x86_64-darwin = apps.x86_64-darwin.vsc;

  };
}
