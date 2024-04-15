{ lib, ... }:
let
  userSubmodule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = ''
          Full name
        '';
      };
      email = lib.mkOption {
        type = lib.types.str;
        description = ''
          Email address
        '';
      };
      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          Authorized SSH public keys
        '';
      };
      hashedPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The full path to a file that contains the hash of the user’s password.
        '';
      };
      # TODO: add home manager config options here
    };
  };
  peopleSubmodule = lib.types.submodule {
    options = {
      users = lib.mkOption {
        type = lib.types.attrsOf userSubmodule;
      };
      myself = lib.mkOption {
        type = lib.types.str;
        description = ''
          The name of the user that represents myself.

          Admin user in all contexts.
        '';
      };
    };
  };
in
{
  options = {
    people = lib.mkOption {
      type = peopleSubmodule;
    };
  };
  config = {
    people = import ./users.nix;
  };
}
