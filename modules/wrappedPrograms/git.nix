{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: {
    packages.difft = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = pkgs.difftastic;
      flags = {
        "--display" = "inline";
      };
      flagSeparator = "=";
    });
    packages.git = inputs.wrapper-modules.wrappers.git.wrap {
      inherit pkgs;
      settings = {
        user = {
          name = "Aidan Pinard";
          email = "aidan@aidanpinard.co";
        };
        signing = {
          key = "C48B088F4FFBBDF0";
          signByDefault = true;
        };
        init.defaultBranch = "main";
        push.autoSetupRemote = "true";
        pull.rebase = false;
        commit.gpgsign = true;
        safe.directory = "*";

        alias = {
          a = "!git add -p";
          co = "!git checkout";
          cob = "!git checkout -b";
          f = "!git fetch -p";
          c = "!git commit";
          p = "!git push";
          ba = "!git branch -a";
          bd = "!git branch -d";
          bD = "!git branch -D";
          d = "!git diff";
          dc = "!git diff --cached";
          ds = "!git diff --staged";
          r = "!git restore";
          rs = "!git restore --staged";
          st = "!git status -sb";

          # reset
          soft = "!git reset --soft";
          hard = "!git reset --hard";
          s1ft = "!git soft HEAD~1";
          h1rd = "!git hard HEAD~1";

          # logging
          lg = "!git log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          plog = "!git log --graph --pretty='format:%C(red)%d%C(reset) %C(yellow)%h%C(reset) %ar %C(green)%aN%C(reset) %s'";
          tlog = "!git log --stat --since='1 Day Ago' --graph --pretty=oneline --abbrev-commit --date=relative";
          rank = "!git shortlog -sn --no-merges";

          # delete merged branches
          bdm = "!git !git branch --merged | grep -v '*' | xargs -n 1 git branch -d";
        };
        diff.external = "${lib.getExe self'.packages.difft}";
        diff.tool = lib.mkDefault "difftastic";
        difftool.difftastic.cmd = "${lib.getExe self'.packages.difft} $LOCAL $REMOTE";
      };
    };
  };
}
