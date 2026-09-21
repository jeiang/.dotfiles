{self, ...}: let
  pluginName = "hermes-ops-tier2";

  # flake8 E501: the block and approval strings read better unwrapped than
  # reflowed, same as modules/hermes/jev.
  pyWriterArgs = {flakeIgnore = ["E501"];};

  mkPlugin = pkgs: let
    gate = pkgs.writers.writePython3 "tier2-gate" pyWriterArgs (builtins.readFile ./tier2_gate.py);

    tiers = pkgs.writeText "tiers.json" (builtins.toJSON self.lib.hermesOpsCommands);

    manifest = pkgs.writeText "plugin.yaml" ''
      name: ${pluginName}
      version: "1.0.0"
      description: "Escalate a hermes-ops tier-2 fleet command to Telegram approval, and refuse tier 3."
      provides_hooks:
        - pre_tool_call
    '';
  in
    pkgs.runCommand pluginName {} ''
      mkdir -p $out
      install -m 0644 ${gate} $out/__init__.py
      install -m 0644 ${manifest} $out/plugin.yaml
      install -m 0644 ${tiers} $out/tiers.json
    '';
in {
  perSystem = {pkgs, ...}: {
    checks.hermes-ops-tier2-gate =
      pkgs.runCommand "hermes-ops-tier2-gate-check" {
        TIER2_PLUGIN = mkPlugin pkgs;
      } ''
        ${pkgs.writers.writePython3Bin "tier2-gate-test" pyWriterArgs (builtins.readFile ./tier2_gate_test.py)}/bin/tier2-gate-test
        touch $out
      '';
  };

  nixos.modules.artemis = {pkgs, ...}: {
    services.hermes-agent = {
      extraPlugins = [(mkPlugin pkgs)];

      settings = {
        # Directory plugins are opt-in; discovery skips anything absent here.
        plugins.enabled = [pluginName];

        # The tier-2 contract: only an explicit approve runs the command. A
        # denial, an expired prompt, and every surface with nobody to ask
        # (the Jev webhook routes, cron) all resolve to "not run".
        approvals = {
          timeout = 300;
          cron_mode = "deny";
          single_query_mode = "deny";
          unattended_mode = "deny";
        };
      };
    };
  };
}
