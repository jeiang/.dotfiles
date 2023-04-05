{ lib }:
lib.makeExtensible (self:
let
  callLibs = file: import file { lib = self; };
in
rec {
  ## Define your own library functions here!
  #id = x: x;
  ## Or in files, containing functions that take {lib}
  #foo = callLibs ./foo.nix;
  ## In configs, they can be used under "lib.our"
  replaceStrings = a: f: builtins.replaceStrings (builtins.attrNames a) (builtins.attrValues a) (builtins.readFile f);
})
