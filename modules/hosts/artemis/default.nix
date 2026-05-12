{
  inputs,
  self,
  ...
}: {
  flake = {
    nixosConfigurations.artemis = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.artemisConfiguration
      ];
    };
    nixosModules.artemisConfiguration = {pkgs, ...}: let
      originalKernel = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linux-cachyos-latest;
      kernel = originalKernel.override {
        pname = "linux-cachyos-bore-lto-zen4";
        processorOpt = "zen4";
        cpusched = "bore";
        lto = "full";
        autofdo = true;
        # structuredExtraConfig = {
        #   CONFIG_PROPELLER_CLANG = lib.kernel.yes;
        # };
      };
    in {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.artemisHardware
        self.nixosModules.doas
        self.nixosModules.desktop
        self.nixosModules.netbird
        self.nixosModules.vr
        self.nixosModules.gaming

        # disks
        self.diskoConfigurations.artemis
      ];
      netbird.management.enable = false;
      boot = {
        loader.systemd-boot.enable = true;
        supportedFilesystems = ["ntfs"];
        tmp.cleanOnBoot = true;
        plymouth = {
          enable = true;
          theme = "black_hud";
          themePackages = with pkgs; [
            (adi1090x-plymouth-themes.override {
              selected_themes = ["black_hud"];
            })
          ];
        };
        # Enable "Silent boot"
        consoleLogLevel = 3;
        initrd.verbose = false;
        kernelParams = [
          "quiet"
          "udev.log_level=3"
          "systemd.show_status=auto"
        ];
        kernelPackages = let
          helpers = pkgs.callPackage "${inputs.nix-cachyos-kernel.outPath}/helpers.nix" {};
        in
          helpers.kernelModuleLLVMOverride (pkgs.linuxKernel.packagesFor kernel);
        # extraModulePackages = [config.boot.kernelPackages.zenpower];
        blacklistedKernelModules = ["algif_aead"];
        # kernelModules = ["zenpower"];
      };
      environment.variables = {
        AMD_VULKAN_ICD = "RADV";
        MESA_SHADER_CACHE_MAX_SIZE = "12G";
      };
      networking = {
        hostName = "artemis";
        networkmanager.enable = true;
        nftables.enable = true;
      };
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
      users.users.root.openssh.authorizedKeys.keys = [
        "AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
  };
}
