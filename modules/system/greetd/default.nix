{
  pkgs,
  inputs,
  ...
}: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd ${inputs.hyprland.packages.x86_64-linux.hyprland}/bin/Hyprland";
        user = "greeter";
      };
    };
  };
}
