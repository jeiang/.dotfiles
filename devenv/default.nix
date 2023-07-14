{
  pkgs,
  ...
}: {
  devenv.shells.default = {
    packages = with pkgs; [
      helix
      git
      nixUnstable
    ];

    languages.lua.enable = true;
    languages.nix.enable = true;

    pre-commit.hooks = {
      alejandra.enable = true;
      deadnix.enable = true;
      editorconfig-checker.enable = true;
      lua-ls.enable = true;
      luacheck.enable = true;
      markdownlint.enable = true;
      nil.enable = true;
      prettier.enable = true;
      shellcheck.enable = true;
      shfmt.enable = true;
      statix.enable = true;
    };
  };
}
