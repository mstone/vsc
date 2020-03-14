
{
  description = "A flake for building vscodium with appropriate extensions";

  edition = 201909;

  outputs = { self, nixpkgs }: rec {

    packages.x86_64-darwin.vsc = with nixpkgs.legacyPackages.x86_64-darwin; vscode-with-extensions.override {
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

    defaultPackage.x86_64-darwin = packages.x86_64-darwin.vsc;

    apps.x86_64-darwin.vsc = {
      type = "app";
      program = "${self.packages.x86_64-darwin.vsc}/bin/codium";
    };

    defaultApp.x86_64-darwin = apps.x86_64-darwin.vsc;

  };
}
