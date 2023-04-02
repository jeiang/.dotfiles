#! /usr/bin/env nix-shell
#! nix-shell -i bash -p ripgrep

# figure out what this is for??

if eww windows | rg -q "\*volume"; then
  eww update volume-level=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{print $2}')
  if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | rg -q '\[MUTED\]'; then
    eww update volume-muted=true
  else
    eww update volume-muted=false
  fi
  eww update volume-hidden=false
else
  eww close brightness
  eww open volume

  eww update volume-level=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{print $2}')
  if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | rg -q '\[MUTED\]'; then
    eww update volume-muted=true
  else
    eww update volume-muted=false
  fi
  eww update volume-hidden=false
  sleep 2
  eww update volume-hidden=true
  sleep 1
  eww close volume
fi
