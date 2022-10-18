#!/bin/sh
pushd ~/.dotfiles > /dev/null
home-manager switch -f ./users/aidanp/home.nix
popd > /dev/null
