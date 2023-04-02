#! /usr/bin/env nix-shell
#! nix-shell -i bash -p dig ripgrep

# nmcli is slow as frick, also need to cache ip

devices=$(nmcli -t -f DEVICE,STATE device)

if echo "${devices}" | rg '(wlp\ds\d):connected' >/dev/null 2>&1; then
  # myip=$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}' 2> /dev/null)
  myip="${myip:-'unknown public ip'}"
  ssid=$(nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\*/{if (NR!=1) {print $3}}')
  strength=$(nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\*/{if (NR!=1) {print $2}}')
  if [[ $strength -lt "50" ]]; then
    strength="very weak"
  elif [[ $strength -lt "60" ]]; then
    strength="weak"
  elif [[ $strength -lt "80" ]]; then
    strength="strong"
  else
    strength="very strong"
  fi
  icon=""
  status="Connected to ${ssid}. Wifi signal is ${strength}. Public IP: ${myip}."
elif echo $devices | rg '(enp\ds\d):connected' >/dev/null 2>&1; then
  myip=$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}' 2>/dev/null)
  myip="${myip:-'unknown public ip'}"
  icon=""
  status="Connected to Ethernet. Public IP: ${myip}"
else
  icon="睊"
  status="No WiFi or Ethernet connected."
fi

echo "{\"icon\": \"${icon}\", \"status\": \"${status}\"}"
