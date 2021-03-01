
{
  description = "A flake for building vscodium with selected extensions";

  inputs.nixpkgs.url = "nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.flake-utils.follows = "flake-utils";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  inputs.vscode-drawio.url = "https://github.com/hediet/vscode-drawio";
  inputs.vscode-drawio.flake = false;
  inputs.vscode-drawio.type = "git";
  inputs.vscode-drawio.submodules = true;

  outputs = { self, nixpkgs, flake-utils, rust-overlay, vscode-drawio }: flake-utils.lib.simpleFlake {
    inherit self nixpkgs;
    name = "vsc";
    preOverlays = [ rust-overlay.overlay ];
    systems = [ "x86_64-linux" "x86_64-darwin" ];
    config = {
      allowUnsupportedSystem = true;
    };
    overlay = final: prev: {
      vsc = with final; rec {
        env = [ rust-bin.stable.latest.rust asciidoctor wkhtmltopdf go_1_16 ];

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
            {
              name = "Go";
              publisher = "golang";
              version = "0.22.1";
              sha256 = "sha256-VKwKS091nEP0f6i/Mx5/1Kw45mejhERU/F+4WN8Ia70=";
            }
          ] ++ [
            (stdenv.mkDerivation rec {
              name = "vscode-extension-hediet.vscode-drawio";
              vscodeExtUniqueId = "hediet.vscode-drawio";
              version = "1.4.0-alpha.3";
              src = vscode-drawio;
              buildInputs = [ yarn nodePackages.webpack nodePackages.webpack-cli ];
              buildPhase = ''
                mkdir yarn && HOME=$(pwd)/yarn yarn install --immutable && yarn build
              '';
              installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";
              installPhase = ''
                mkdir -p "$out/$installPrefix/";
                for f in CHANGELOG.md README.md dist docs drawio package.json; do
                  mv $f "$out/$installPrefix";
                done
              '';
            })
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
