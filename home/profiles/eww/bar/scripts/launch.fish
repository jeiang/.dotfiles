#!/usr/bin/env nix-shell
#! nix-shell -i fish -p fish

function battery
  set charging_icons "󰢟" "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅"
  set discharging_icons "󱃍" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"

  set bat /sys/class/power_supply/BAT?
  # check for a match
  if count $bat -eq 1 > /dev/null 2>&1
    set bat $bat[1]
    set current_capacity (cat $bat/capacity)
    set battery_status (cat $bat/status)
    set charge_cap (cat $bat/charge_control_end_threshold)
    test -z $charge_cap; and set charge_cap 100

    set icon "󰂑"
    if test -n $current_capacity
      set idx (math floor $current_capacity / 10)
      if [ $battery_status = "Charging" ]
        set icon $charging_icons[(math $idx + 1)]
      else if [ $battery_status = "Discharging" ]
        set icon $discharging_icons[(math $idx + 1)]
      else if [ $battery_status = "Not charging" ] && [ $current_capacity -ge $charge_cap ]
        set icon "󱞜"
      end
    end
    echo "{\"percent\": \"$current_capacity%\", \"icon\": \"$icon\", \"visible\": \"true\", \"status\": \"$battery_status\"}"
  end
end

function wifi
  set net_dev (nmcli -t -f DEVICE,STATE,CONNECTION device)
  # filter loopback & unavailable
  set connected_dev (string match -r '.+connected.+' (string replace -r 'lo:.*' '' $net_dev))

  set icon "󰲛"
  set net_status "No WiFi or Ethernet connected."

  if count $connected_dev -eq 0 > /dev/null 2>&1
    # take the first one
    set connected_dev $connected_dev[1]

    set interface (string split -f1 ':' $connected_dev)
    set connection_name (string split -f3 ':' $connected_dev)

    if string match 'wlp?s?' $interface > /dev/null 2>&1
      set signal_strength (nmcli -t -f SSID,SIGNAL device wifi)
      string match -r "$connection_name:(?<connection_strength>\d+)" $signal_strength > /dev/null 2>&1
      if [ $connection_strength -ge 90 ]
        set icon "󰤨"
      else if [ $connection_strength -ge 60 ]
        set icon "󰤥"
      else if [ $connection_strength -ge 30 ]
        set icon "󰤢"
      else
        set icon "󰤟"
      end
      set net_status "Connected to $connection_name via Wifi."
    else if string match 'enp?s?' $interface > /dev/null 2>&1
      set icon "󰈀"
      set net_status "Connected to $connection_name via Ethernet."
    else
      set icon "󰛵"
      set net_status "Connected to $connection_name via unknown interface."
    end
  end
  echo "{\"icon\": \"$icon\", \"status\": \"$net_status\"}"
end

switch $argv[1]
  case 'battery'
    battery
    return
  case 'wifi'
    wifi
  case 'workspaces'
    # semi arbitrary relative path
    ./scripts/workspaces.lua
    return
end
