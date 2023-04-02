#!/usr/bin/env nix-shell
#! nix-shell -i fish -p fish lua

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

function workspaces
  # lua ./scripts/workspaces.lua
  function generate_workspaces
    set active_workspaces (hyprctl monitors | grep active | sed 's/()/(1)/g' | sort | awk 'NR>1{print $1}' RS='(' FS=')' | sort -n)
    set workspaces (hyprctl workspaces | grep ID | sed 's/()/(1)/g' | sort | awk 'NR>1{print $1}' RS='(' FS=')' | sort -n)

    echo -n '(box :orientation "v" :spacing 1 :space-evenly "true" '
    for i in $workspaces
      if contains $i $active_workspaces > /dev/null 2>&1
        echo -n "(button :class \"active\" :onclick \"hyprctl dispatch workspace $i\" \"\") "
      else
        echo -n "(button :class \"inactive\" :onclick \"hyprctl dispatch workspace $i\" \"\") "
      end
    end
    echo ")"
    return
  end

  generate_workspaces

  set hypr_socket "UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

  socat - $hypr_socket | while read -l line
    # detect when the focused monitor or workspace changes
    # (changing monitor focus changes workspace as well)
    if string match -r '(workspace|focusedmon).*' $line > /dev/null 2>&1
      generate_workspaces
    end
  end
end

switch $argv[1]
  case 'battery'
    battery $argv[2..-1]
    return
  case 'wifi'
    wifi $argv[2..-1]
    return
  case 'workspaces'
    workspaces $argv[2..-1]
    return
end
