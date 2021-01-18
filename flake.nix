
{
  description = "A flake for building vscodium with selected extensions";

  inputs.nixpkgs.url = "nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.flake-utils.follows = "flake-utils";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils, rust-overlay }: flake-utils.lib.simpleFlake {
    inherit self nixpkgs;
    name = "vsc";
    preOverlays = [ rust-overlay.overlay ];
    systems = [ "x86_64-linux" "x86_64-darwin" ];
    overlay = final: prev: {
      vsc = with final; rec {
        env = [ rust-bin.stable.latest.rust asciidoctor ];

        wrapper = vscode-with-extensions.override {
          vscode = vscodium;
          vscodeExtensions = with vscode-extensions; [
            bbenoist.Nix
            matklad.rust-analyzer
          ] ++ vscode-utils.extensionsFromVscodeMarketplace [
            {
              name = "asciidoctor-vscode";
              publisher = "joaompinto";
              version = "2.7.13";
              sha256 = "sha256-os4vsusgf6izymcvUAN+XCJFBuG0fzh+gIxabHgxjeI=";
            }
          ];
        };

	codium = stdenv.mkDerivation {
          pname = "codium";
          version = "1.0";
          phases = ["installPhase"];
          installPhase = ''
            mkdir -p $out/bin;
            makeWrapper ${wrapper}/bin/codium $out/bin/codium --prefix PATH : ${lib.makeBinPath env}
          '';
          buildInputs = [ makeWrapper ];
        };

        defaultPackage = codium;
      };
    };
  };
}
