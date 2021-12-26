
{
  description = "A flake for building codium with selected extensions";

  inputs.nixpkgs.url = "nixpkgs";

  inputs.utils.url = "github:numtide/flake-utils";

  inputs.codiumSrc.url = "github:VSCodium/vscodium";
  inputs.codiumSrc.flake = false;

  inputs.vscodeSrc.url = "github:microsoft/vscode";
  inputs.vscodeSrc.flake = false;

  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.flake-utils.follows = "utils";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  inputs.vscode-drawio.url = "https://github.com/hediet/vscode-drawio";
  inputs.vscode-drawio.flake = false;
  inputs.vscode-drawio.type = "git";
  inputs.vscode-drawio.submodules = true;

  inputs.clangdExtensionSrc.url = "github:clangd/vscode-clangd";
  inputs.clangdExtensionSrc.flake = false;

  outputs = { self, nixpkgs, utils, codiumSrc, vscodeSrc, rust-overlay, vscode-drawio, clangdExtensionSrc }: let
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
        # env = [ rust-bin.stable.latest.default asciidoctor wkhtmltopdf go_1_16 ];
        env = [ python39 coreutils gitFull clang clang-tools ];

        fakeSwVers = writeShellScriptBin "sw_vers" ''
          echo 10.15
        '';

        hdiutilWrapper = writeShellScriptBin "hdiutil" ''
          exec /usr/bin/hdiutil "$@"
        '';

        codiumFromSrc = stdenv.mkDerivation {
          pname = "codium";
          version = "1.59.1";
          longName = "codium";
          shortName = "codium";
          executableName = "vscodium";
          src = codiumSrc;
          buildInputs = [ nodejs-14_x git cacert yarn python39 fakeSwVers jq ] ++ (with darwin.apple_sdk.frameworks; [ Security AppKit Cocoa ]);
          nativeBuildInputs = [ darwin.cctools hdiutilWrapper ];
          buildPhase = ''
            #set -x
            #set -euo pipefail
            export GIT_SSL_CAINFO="${cacert}/etc/ssl/certs/ca-bundle.crt";
            mkdir vscode; cp -a ${vscodeSrc}/. vscode/.
            chmod -R u+rwX vscode
            # remove postinstall commands that expect vscode/.git
            head -n -2 vscode/build/npm/postinstall.js > js.tmp
            mv js.tmp vscode/build/npm/postinstall.js
            rm patches/custom-gallery.patch patches/fix-cors.patch
            mkdir yarn
            HOME=$(pwd)/yarn MS_COMMIT=${vscodeSrc.rev} SHOULD_BUILD=yes CI_BUILD=no OS_NAME=osx VSCODE_ARCH=arm64 . build.sh
          '';
          installPhase = ''
            cp -a ./ $out/
          '';
        };

        codiumSubset = stdenv.mkDerivation {
          pname = "codium";
          version = "1.59.1";
          src = codiumFromSrc;
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out
            cp -a $src/VSCode-darwin-arm64/VSCodium.app/. $out/.
          '';
        };

        codiumGeneric = callPackage "${nixpkgs}/pkgs/applications/editors/vscode/generic.nix" rec {
          sourceRoot = "";
          version = "1.59.1";
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
            matklad.rust-analyzer
            golang.go
            hediet.vscode-drawio
            llvm-vs-code-extensions.vscode-clangd    
          ];
        };

        codium = stdenv.mkDerivation {
          pname = "codium";
          version = "1.0";
          phases = ["installPhase"];
          installPhase = ''
            mkdir -p $out/bin;
            makeWrapper ${codiumWithExtensions}/bin/codium $out/bin/codium --prefix PATH : ${lib.makeBinPath env}
            #makeWrapper ${codiumWithExtensions}/bin/codium $out/bin/codium --set PATH ${lib.makeBinPath env} --set NIX_CFLAGS_COMPILE "-frandom-seed=x6igk4967n -isystem /nix/store/ahzhg9b7zqpb87qg1j6h7bgbfdhzxgrm-flex-2.6.4/include -isystem /nix/store/li2q2f8kvcd2znijvy8lwmyjp0h8cbqq-gettext-0.21/include -isystem /nix/store/g09779ik6apscr8gff9v40wkfw32qc8i-libtool-2.4.6/include -isystem /nix/store/wjrlmgdbf2rcsd51a3aqxgcc6vgklq5j-python3-3.8.9/include -isystem /nix/store/h6qhll51c0gvbv24f9bzsckgz4is3372-jq-1.6-dev/include -isystem /nix/store/qrvhvsbhgkm5fkclf3w5m97svxga1lfa-libcxx-11.1.0-dev/include -isystem /nix/store/7z5ybdphiplcmv3n8xwfv0vdnbdzny27-libcxxabi-11.1.0-dev/include -isystem /nix/store/cj3d2hmg1s8barrifl3vakj6r2dzgf52-curl-7.76.1-dev/include -isystem /nix/store/40khm32dk9dvjc6k8vf67dpd5b6zcdy7-nghttp2-1.43.0-dev/include -isystem /nix/store/i5p8sc1i8jsm191ix6jnbnnxyg5q11a8-libidn-1.36-dev/include -isystem /nix/store/lcspd8k4frzx0adib4yfdhm0xh9va88s-zlib-1.2.11-dev/include -isystem /nix/store/bmz33003iiy20ikhwlv41vs0dqyjr8fw-libkrb5-1.18-dev/include -isystem /nix/store/ryzwkgv67xz5gdp8fhwjbj90vjlkjkr0-openssl-1.1.1k-dev/include -isystem /nix/store/6rahh9lmfwb0bbbfvwkj2nqs7nm8qw6v-libssh2-1.9.0-dev/include -isystem /nix/store/41j5rllbjmbq98vva0kigbmpbimn63sx-brotli-1.0.9-dev/include -isystem /nix/store/qhwl1r7nk8lb7h3i3dqqrgzzg0cckf4v-bzip2-1.0.6.0.2-dev/include -isystem /nix/store/r50sy377vm56dl6yvdg4bzs9y4jrfv18-xz-5.2.5-dev/include -isystem /nix/store/xaz2p67khmzr8ymxjcn4bqdymjvq8v2b-editline-1.17.1-dev/include -isystem /nix/store/m1qrcwiqa1mjrkxf3vn4pghfwj8j59zr-sqlite-3.35.5-dev/include -isystem /nix/store/08f0hgffyyn1fk542ikfw1q8xva4r0rl-libarchive-3.5.1-dev/include -isystem /nix/store/8i8nk91b08gh1rjqgm4sqpjx0p1s84xz-boost-1.69.0-dev/include -isystem /nix/store/f17q23s9pxarw76ay396bdwh6iva5czg-lowdown-0.8.6-dev/include -isystem /nix/store/j7sjinw0r1rrdsa9ni036r5a5rl6793y-gtest-1.10.0-dev/include -isystem /nix/store/w545xmz6pqxghzb0m8lci9jm7r835x07-libsodium-1.0.18-dev/include -isystem /nix/store/k878qh3a697xa880ym633ps8vfabhw06-boehm-gc-8.0.4-dev/include -isystem /nix/store/lhardvj657klq5nrjdb2pfym8yf5cb8z-aws-sdk-cpp-1.8.121-dev/include -isystem /nix/store/wa35820f4k863w99hbsb42bya7rzykgm-aws-c-cal-0.4.5/include -iframework /nix/store/hhnkmr9fbgzdxa114p59y386nh22sw1v-apple-framework-Security-11.0.0/Library/Frameworks -iframework /nix/store/xam2ksf9xd9q0dxi3k4hl3ha1qr5wy07-apple-framework-IOKit-11.0.0/Library/Frameworks -isystem /nix/store/8njajsq82h52yjc8d8b5ba69dsmwx4d7-apple-lib-libDER/include -isystem /nix/store/hzp42878lx71pga325dla7y2cmyd5cjc-aws-c-io-0.9.1/include -isystem /nix/store/yyr27jnjsrapksy09dkzadx9waibj7z7-aws-sdk-cpp-1.8.121/include -iframework /nix/store/g85bsjzzr2r0cr4kkz3l41s47fha2x4r-apple-framework-CoreFoundation-11.0.0/Library/Frameworks -isystem /nix/store/62bm6ra93saz94c32z34rq4lvmj4w6jb-libobjc-11.0.0/include -isystem /nix/store/ahzhg9b7zqpb87qg1j6h7bgbfdhzxgrm-flex-2.6.4/include -isystem /nix/store/li2q2f8kvcd2znijvy8lwmyjp0h8cbqq-gettext-0.21/include -isystem /nix/store/g09779ik6apscr8gff9v40wkfw32qc8i-libtool-2.4.6/include -isystem /nix/store/wjrlmgdbf2rcsd51a3aqxgcc6vgklq5j-python3-3.8.9/include -isystem /nix/store/h6qhll51c0gvbv24f9bzsckgz4is3372-jq-1.6-dev/include -isystem /nix/store/qrvhvsbhgkm5fkclf3w5m97svxga1lfa-libcxx-11.1.0-dev/include -isystem /nix/store/7z5ybdphiplcmv3n8xwfv0vdnbdzny27-libcxxabi-11.1.0-dev/include -isystem /nix/store/cj3d2hmg1s8barrifl3vakj6r2dzgf52-curl-7.76.1-dev/include -isystem /nix/store/40khm32dk9dvjc6k8vf67dpd5b6zcdy7-nghttp2-1.43.0-dev/include -isystem /nix/store/i5p8sc1i8jsm191ix6jnbnnxyg5q11a8-libidn-1.36-dev/include -isystem /nix/store/lcspd8k4frzx0adib4yfdhm0xh9va88s-zlib-1.2.11-dev/include -isystem /nix/store/bmz33003iiy20ikhwlv41vs0dqyjr8fw-libkrb5-1.18-dev/include -isystem /nix/store/ryzwkgv67xz5gdp8fhwjbj90vjlkjkr0-openssl-1.1.1k-dev/include -isystem /nix/store/6rahh9lmfwb0bbbfvwkj2nqs7nm8qw6v-libssh2-1.9.0-dev/include -isystem /nix/store/41j5rllbjmbq98vva0kigbmpbimn63sx-brotli-1.0.9-dev/include -isystem /nix/store/qhwl1r7nk8lb7h3i3dqqrgzzg0cckf4v-bzip2-1.0.6.0.2-dev/include -isystem /nix/store/r50sy377vm56dl6yvdg4bzs9y4jrfv18-xz-5.2.5-dev/include -isystem /nix/store/xaz2p67khmzr8ymxjcn4bqdymjvq8v2b-editline-1.17.1-dev/include -isystem /nix/store/m1qrcwiqa1mjrkxf3vn4pghfwj8j59zr-sqlite-3.35.5-dev/include -isystem /nix/store/08f0hgffyyn1fk542ikfw1q8xva4r0rl-libarchive-3.5.1-dev/include -isystem /nix/store/8i8nk91b08gh1rjqgm4sqpjx0p1s84xz-boost-1.69.0-dev/include -isystem /nix/store/f17q23s9pxarw76ay396bdwh6iva5czg-lowdown-0.8.6-dev/include -isystem /nix/store/j7sjinw0r1rrdsa9ni036r5a5rl6793y-gtest-1.10.0-dev/include -isystem /nix/store/w545xmz6pqxghzb0m8lci9jm7r835x07-libsodium-1.0.18-dev/include -isystem /nix/store/k878qh3a697xa880ym633ps8vfabhw06-boehm-gc-8.0.4-dev/include -isystem /nix/store/lhardvj657klq5nrjdb2pfym8yf5cb8z-aws-sdk-cpp-1.8.121-dev/include -isystem /nix/store/wa35820f4k863w99hbsb42bya7rzykgm-aws-c-cal-0.4.5/include -iframework /nix/store/hhnkmr9fbgzdxa114p59y386nh22sw1v-apple-framework-Security-11.0.0/Library/Frameworks -iframework /nix/store/xam2ksf9xd9q0dxi3k4hl3ha1qr5wy07-apple-framework-IOKit-11.0.0/Library/Frameworks -isystem /nix/store/8njajsq82h52yjc8d8b5ba69dsmwx4d7-apple-lib-libDER/include -isystem /nix/store/hzp42878lx71pga325dla7y2cmyd5cjc-aws-c-io-0.9.1/include -isystem /nix/store/yyr27jnjsrapksy09dkzadx9waibj7z7-aws-sdk-cpp-1.8.121/include -iframework /nix/store/g85bsjzzr2r0cr4kkz3l41s47fha2x4r-apple-framework-CoreFoundation-11.0.0/Library/Frameworks -isystem /nix/store/62bm6ra93saz94c32z34rq4lvmj4w6jb-libobjc-11.0.0/include"
          '';
          buildInputs = [ makeWrapper ];
        };

        defaultPackage = codium;
      };
    };
  };
}
