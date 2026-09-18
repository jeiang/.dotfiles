{inputs, ...}: let
  sopsFile = ./secrets.yaml;
  apiKey = "typesafe/api-key";

  # Managed settings are the one settings source that both the desktop app
  # and the CLI read and that Nix can own; the file must stay readable by
  # the user, or Claude Code refuses to start.
  claudeCode = {
    config,
    managedSettings,
    group,
  }: let
    user = config.preferences.user.name;
  in {
    sops.secrets.${apiKey} = {inherit sopsFile;};
    sops.templates."claude-code-managed-settings.json" = {
      path = managedSettings;
      owner = user;
      inherit group;
      content = builtins.toJSON {
        env = {
          CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1";
          TYPESAFE_API_KEY = config.sops.placeholder.${apiKey};
        };
      };
    };

    # A folder with .claude-plugin/plugin.json under ~/.claude/skills loads
    # as a plugin in place, so the input pin is the installed version.
    hjem.users.${user}.files.".claude/skills/fast-jev-compaction".source = inputs.fast-jev-compaction;
  };
in {
  nixos.modules.artemis = {config, ...}:
    claudeCode {
      inherit config;
      managedSettings = "/etc/claude-code/managed-settings.json";
      group = "users";
    };

  darwin.modules.base = {config, ...}:
    claudeCode {
      inherit config;
      managedSettings = "/Library/Application Support/ClaudeCode/managed-settings.json";
      group = "staff";
    };
}
