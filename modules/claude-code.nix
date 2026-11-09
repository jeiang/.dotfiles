{inputs, ...}: {
  shared.modules.workstation = {
    lib,
    pkgs,
    ...
  }: let
    inherit (pkgs.stdenv.hostPlatform) system;
    upstream = inputs.llm-agents.packages.${system}.claude-code;
    # llm-agents lags Claude Code's releases; this pin supplies a newer release until llm-agents catches up.
    version = "2.1.321";
    sources = {
      aarch64-darwin = {
        platform = "darwin-arm64";
        hash = "sha256-q8n+7sqAkdUbYjKR4ETPBSjC9rdODB1u9nHVLHP3zTw=";
      };
      x86_64-linux = {
        platform = "linux-x64";
        hash = "sha256-QmwzgVymZFp3L3Ivv/ENvyy9sSSorqtzPBNl2/i79h8=";
      };
    };
    claude-code =
      if lib.versionOlder upstream.version version
      then
        upstream.overrideAttrs {
          inherit version;
          src = pkgs.fetchurl {
            url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${sources.${system}.platform}/claude";
            inherit (sources.${system}) hash;
          };
        }
      else upstream;
  in {
    environment.systemPackages = [claude-code];
  };

  nixos.modules.artemis.persistence = {
    data.files = [".claude.json"];
    cache.directories = [".cache/claude-cli-nodejs"];
  };
}
