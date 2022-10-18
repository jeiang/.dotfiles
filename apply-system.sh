#!/bin/sh
pushd ~/.dotfiles > /dev/null
sudo nixos-rebuild switch -I nixos-config=./system/configuration.nix
popd > /dev/null
