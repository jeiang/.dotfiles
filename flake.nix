{
  description = "aidanp nixos config.";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NUR
    nur.url = "github:nix-community/NUR";

    # Hardware
    hardware.url = "github:nixos/nixos-hardware";

    # Theming
    stylix.url = "github:danth/stylix";
    stylix.inputs = {
      home-manager.follows = "home-manager";
      nixpkgs.follows = "nixpkgs";
    };

    # Impermanence
    impermanence.url = "github:nix-community/impermanence";

    # Nix Formatter
    nixpkgs-fmt.url = "github:nix-community/nixpkgs-fmt";
    nixpkgs-fmt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, impermanence, nur, nixpkgs-fmt, stylix, ... }@inputs:
    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    in
    rec {
      formatter = forAllSystems (system: nixpkgs-fmt.defaultPackage.${system});

      # Your custom packages
      # Acessible through 'nix build', 'nix shell', etc
      customPackages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in import ./pkgs { inherit pkgs; }
      );

      # Devshell for bootstrapping
      # Acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in import ./shell.nix { inherit pkgs; }
      );

      legacyPackages = forAllSystems (system:
        import inputs.nixpkgs {
          inherit system;

          # NOTE: Using `nixpkgs.config` in your NixOS config won't work
          # Instead, you should set nixpkgs configs here
          # (https://nixos.org/manual/nixpkgs/stable/#idm140737322551056)
          config.allowUnfree = true;

          overlays = [
            # Add nur to pkgs
            nur.overlay
            outputs.overlays.additions
            outputs.overlays.modifications
          ];
        }
      );

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays;
      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;
      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      homeManagerModules = import ./modules/home-manager;
      # These are scripts that may be used in the configuration
      scripts = import ./scripts;

      nixosConfigurations = {
        asus-nixos = nixpkgs.lib.nixosSystem rec {
          pkgs = legacyPackages.x86_64-linux;
          specialArgs = { inherit inputs outputs; };
          modules = [
            home-manager.nixosModules.home-manager
            impermanence.nixosModules.impermanence
            nur.nixosModules.nur
            stylix.nixosModules.stylix

            # > Our main nixos configuration file <
            ./nixos/configuration.nix

            # System specific configuration
            ./nixos/system/asus-nixos

            # Theme stuff
            ./theming

            # Home manager configuration through NixOS module
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs outputs; };
              home-manager.users.aidanp = {
                imports = [
                  impermanence.nixosModules.home-manager.impermanence
                  ./home-manager/home.nix
                ];
              };
            }
          ];
        };
      };
    };
}
