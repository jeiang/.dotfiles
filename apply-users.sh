#!/bin/sh
pushd ~/.dotfiles
home-manager switch -f ./users/aidanp/home.nix
popd
