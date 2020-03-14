
{
  description = "A flake for building vscodium with appropriate extensions";

  edition = 201909;

  outputs = { self, nixpkgs }: rec {

    packages.x86_64-darwin.vsc = with nixpkgs.legacyPackages.x86_64-darwin; vscode-with-extensions.override {
      vscode = vscodium;
      vscodeExtensions = with vscode-extensions; [
        bbenoist.Nix
      ];
    };

    defaultPackage.x86_64-darwin = packages.x86_64-darwin.vsc;

    defaultApp.x86_64-darwin = packages.x86_64-darwin.vsc;

  };
}
