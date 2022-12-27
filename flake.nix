
{
  description = "A flake for building codium with selected extensions";

  inputs.nixpkgs.url = "nixpkgs/3eb07eeafb52bcbf02ce800f032f18d666a9498d";

  inputs.utils.url = "github:numtide/flake-utils";

  inputs.filter.url = "github:numtide/nix-filter";

  inputs.codiumSrc.url = "github:mstone/vscodium";
  inputs.codiumSrc.flake = false;

  inputs.vscodeSrc.url = "github:microsoft/vscode";
  inputs.vscodeSrc.flake = false;

  inputs.rust-analyzerSrc.url = "github:rust-analyzer/rust-analyzer";
  inputs.rust-analyzerSrc.flake = false;

  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.flake-utils.follows = "utils";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  inputs.vscode-drawio.url = "https://github.com/hediet/vscode-drawio";
  inputs.vscode-drawio.flake = false;
  inputs.vscode-drawio.type = "git";
  inputs.vscode-drawio.submodules = true;

  inputs.clangdExtensionSrc.url = "github:clangd/vscode-clangd";
  inputs.clangdExtensionSrc.flake = false;

  outputs = { self, nixpkgs, utils, filter, codiumSrc, vscodeSrc, rust-analyzerSrc, rust-overlay, vscode-drawio, clangdExtensionSrc }: let
    name = "codium";
  in utils.lib.simpleFlake {
    inherit self nixpkgs name;
    preOverlays = [ rust-overlay.overlay ];
    systems = utils.lib.defaultSystems;
    config = {
      allowUnsupportedSystem = true;
    };
    overlay = final: prev: {
      codium = with final; rec {
	env = [ 
          rust-bin.stable.latest.default 
          asciidoctor 
          go_1_16 
          python39 
          coreutils 
          gitFull 
          (terraform.withPlugins (ps: with ps; [ aws gandi vultr ] ))
          cmake
        ];

        codiumVersion = "1.65.0";

        # nixpkgs and vscode use refer to the same target systems via different system doubles
        # https://github.com/NixOS/nixpkgs/blob/master/lib/systems/doubles.nix
        # https://github.com/microsoft/vscode/blob/main/build/azure-pipelines/product-build.yml
        codiumOsName = {
          darwin = "osx";
          linux = "linux";
        }."${lib.elemAt (lib.splitString "-" system) 1}";

        codiumArch = {
          aarch64 = "arm64";
          armv7l = "armhf";
          x86_64 = "x64";
          i686 = "ia32";
        }."${lib.elemAt (lib.splitString "-" system) 0}";

        fakeSwVers = writeShellScriptBin "sw_vers" ''
          echo 10.15
        '';

        hdiutilWrapper = writeShellScriptBin "hdiutil" ''
          exec /usr/bin/hdiutil "$@"
        '';

        codiumFromSrc = stdenv.mkDerivation {
          pname = "codium";
          version = codiumVersion;
          longName = "codium";
          shortName = "codium";
          executableName = "vscodium";
          src = codiumSrc;
          buildInputs = [
            nodejs-14_x
            git
            cacert
            yarn
            python39
            fakeSwVers
            jq
            xcbuild
          ] ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
            Security
            AppKit
            Cocoa
          ]);
          nativeBuildInputs = lib.optionals stdenv.isDarwin [ darwin.cctools hdiutilWrapper ];
          buildPhase = ''
            #set -x
            #set -euo pipefail
            export GIT_SSL_CAINFO="${cacert}/etc/ssl/certs/ca-bundle.crt";
            mkdir vscode; cp -a ${vscodeSrc}/. vscode/.
            chmod -R u+rwX vscode
            # remove postinstall commands that expect vscode/.git
            head -n -2 vscode/build/npm/postinstall.js > js.tmp
            mv js.tmp vscode/build/npm/postinstall.js
            mkdir yarn
            HOME=$(pwd)/yarn MS_COMMIT=${vscodeSrc.rev} SHOULD_BUILD=yes CI_BUILD=no OS_NAME=${codiumOsName} VSCODE_ARCH=${codiumArch} . build.sh
          '';
          installPhase = ''
            cp -a ./ $out/
          '';
        };

        codiumSubset = stdenv.mkDerivation {
          pname = "codium";
          version = codiumVersion;
          src = codiumFromSrc;
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out
            cp -a $src/VSCode-darwin-arm64/VSCodium.app/. $out/.
          '';
        };

        codiumGeneric = callPackage "${nixpkgs}/pkgs/applications/editors/vscode/generic.nix" rec {
          sourceRoot = "";
          version = codiumVersion;
          pname = "vscodium";
          executableName = "codium";
          longName = "VSCodium";
          shortName = "codium";
          src = codiumSubset;
          updateScript = "";
          meta = {
            description = ''
              Open source source code editor developed by Microsoft for Windows,
              Linux and macOS (VS Code without MS branding/telemetry/licensing),
              built from source
            '';
            homepage = "https://github.com/VSCodium/vscodium";
          };
        };

        hediet.vscode-drawio = stdenv.mkDerivation rec {
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
        };

        ra = stdenv.mkDerivation rec {
          name = "vscode-extension-matklad.rust-analyzer";
          vscodeExtUniqueId = "matklad.rust-analyzer";
          version = "0.4.0-dev";
          src = filter.lib { 
            root = rust-analyzerSrc + "/editors/code";
          };
          buildInputs = [ tree unzip yarn nodePackages.npm nodejs-14_x nodePackages.node-gyp ];
          nativeBuildInputs = [ jq moreutils ];
          buildPhase = ''
            #mkdir yarn && HOME=$(pwd)/yarn yarn install --immutable && yarn build
            mkdir -p "$(pwd)/home"
            export HOME="$(pwd)/home"
            npm ci
            npm run package
          '';
          installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";
          installPhase = ''
            origDir="$(pwd)"
            mkdir -p "$out/$installPrefix/";
            cd "$out/$installPrefix";
            unzip "$origDir/rust-analyzer.vsix"
            mv extension/* .
            rmdir extension
            rm *.xml
            rm extension.vsixmanifest
            jq '.contributes.configuration.properties."rust-analyzer.server.path".default = $s' \
              --arg s "${rust-analyzer}/bin/rust-analyzer" \
              package.json | sponge package.json
          '';
        };

        llvm-vs-code-extensions.vscode-clangd = stdenv.mkDerivation rec {
          name = "vscode-extension-llvm-vs-code-extensions.vscode-clangd";
          vscodeExtUniqueId = "llvm-vs-code-extensions.vscode-clangd";
          version = "0.1.13";
          src = clangdExtensionSrc;
          buildInputs = [ nodePackages.npm nodePackages.typescript ];
          propagatedBuildInputs = [ clang-tools ];
          buildPhase = ''
            mkdir -p "$(pwd)/home"
            export HOME="$(pwd)/home"
            #npm ci
            npm install
            tsc -p ./
          '';
          installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";
          installPhase = ''
            mkdir -p "$out/$installPrefix/";
            mv * $out/$installPrefix/;
          '';
        };

        codiumWithExtensions = vscode-with-extensions.override {
          vscode = codiumGeneric;
          vscodeExtensions = with vscode-extensions; [
            bbenoist.nix
            #matklad.rust-analyzer
            ra
            usernamehw.errorlens
            golang.go
            hediet.vscode-drawio
            #llvm-vs-code-extensions.vscode-clangd
            hashicorp.terraform
          ];
        };

        codium = stdenv.mkDerivation {
          pname = "codium";
          version = codiumVersion;
          phases = ["installPhase"];
          installPhase = ''
            mkdir -p $out/bin;
            makeWrapper ${codiumWithExtensions}/bin/codium $out/bin/codium --prefix PATH : ${lib.makeBinPath env}
          '';
          buildInputs = [ makeWrapper ];
        };

        defaultPackage = codium;
      };
    };
  };
}
