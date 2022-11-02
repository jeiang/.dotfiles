{
  description = "Your new nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NUR
    nur.url = "github:nix-community/NUR";

    # Theming
    # nix-colors.url = "github:misterio77/nix-colors";

    # Impermanence
    impermanence.url = "github:nix-community/impermanence";

    # Nix Formatter
    nixfmt.url = "github:serokell/nixfmt";
  };

  outputs =
    { nixpkgs, home-manager, nur, impermanence, nixfmt, ... }@inputs: rec {
      formatter = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" ]
        (system: nixfmt.packages.${system}.nixfmt);

      # This instantiates nixpkgs for each system listed
      # Allowing you to configure it (e.g. allowUnfree)
      # Our configurations will use these instances
      legacyPackages = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" ]
        (system:
          import inputs.nixpkgs {
            inherit system;

            # NOTE: Using `nixpkgs.config` in your NixOS config won't work
            # Instead, you should set nixpkgs configs here
            # (https://nixos.org/manual/nixpkgs/stable/#idm140737322551056)
            config.allowUnfree = true;

            overlays = [
              # Add nur to pkgs
              nur.overlay
            ];
          });

      nixosConfigurations = {
        asus-nixos = nixpkgs.lib.nixosSystem rec {
          pkgs = legacyPackages.x86_64-linux;
          specialArgs = { inherit inputs; };
          modules = [
            nur.nixosModules.nur
            impermanence.nixosModule
            ./system/asus-nixos/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.aidanp = import ./users/aidanp/home.nix;
            }
          ];
        };
      };
    };
}
