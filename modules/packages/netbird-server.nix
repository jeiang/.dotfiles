{
  perSystem = {pkgs, ...}: {
    packages = {
      # Reverse proxy and relay components match the deployed topology
      # one-to-one; nixpkgs already builds them as separate by-name
      # packages from the same netbird source tree.
      inherit (pkgs) netbird-relay netbird-proxy netbird-dashboard;

      # The deployed management plane is the unified config.yaml-driven
      # server shipped as netbirdio/netbird-server:0.73.2. nixpkgs has no
      # such component: its netbird package only knows about
      # client/ui/upload/management/signal/relay/proxy, and the legacy
      # `management` component uses a materially different state layout
      # than the unified server. The unified server instead lives at
      # `combined/` in the netbird monorepo (confirmed present at the
      # nixpkgs-pinned tag v0.74.3, which is >= 0.73.2):
      # `combined/main.go` calls `combined/cmd.Execute()`, whose root
      # command requires `--config`/`-c` and loads it via
      # `combined/cmd.LoadConfig` (combined/cmd/config.go), which
      # `yaml.Unmarshal`s into a struct tagged to match
      # `combined/config.yaml.example` (server.listenAddress,
      # exposedAddress, management/signal/relay/stun sections) - i.e. the
      # same config.yaml shape the deployment uses.
      # combined/Dockerfile.multistage builds this exact subpackage as
      # `netbird-server` and runs it with `--config /etc/netbird/config.yaml`,
      # matching the upstream image.
      #
      # Built as an overrideAttrs layer on nixpkgs' netbird derivation
      # (same buildGoModule inputs/vendorHash - `combined` only imports
      # packages already vendored for the other components) rather than a
      # `componentName` override, since nixpkgs' componentName switch is a
      # closed set that does not include "combined".
      netbird-server = pkgs.netbird.overrideAttrs (_: {
        pname = "netbird-server";
        subPackages = ["combined"];
        postInstall = "mv $out/bin/combined $out/bin/netbird-server";
        # No `version`/`--version` subcommand exists on the combined
        # server's cobra root command, so the client component's
        # versionCheckHook wiring doesn't apply here.
        doInstallCheck = false;
        meta = {
          description = "Unified NetBird server (management + signal + relay + STUN)";
          homepage = "https://github.com/netbirdio/netbird/tree/master/combined";
          license = pkgs.lib.licenses.agpl3Only;
          mainProgram = "netbird-server";
        };
      });
    };
  };
}
