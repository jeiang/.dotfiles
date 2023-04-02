#!/bin/sh

bat=/sys/class/power_supply/BAT?

if [ -s $bat/capacity ]; then
  per="$(cat $bat/capacity)"
  status="$(cat $bat/status)"

  # Check if charging...
  if [ "$per" -gt "90" ]; then
    icon=""
  elif [ "$per" -gt "80" ]; then
    icon=""
  elif [ "$per" -gt "70" ]; then
    icon=""
  elif [ "$per" -gt "60" ]; then
    icon=""
  elif [ "$per" -gt "50" ]; then
    icon=""
  elif [ "$per" -gt "40" ]; then
    icon=""
  elif [ "$per" -gt "30" ]; then
    icon=""
  elif [ "$per" -gt "20" ]; then
    icon=""
  elif [ "$per" -gt "10" ]; then
    icon=""
  elif [ "$per" -gt "0" ]; then
    icon=""
  else
    icon=""
  fi

  echo "{\"percent\": \"$per%\", \"icon\": \"$icon\", \"visible\": \"true\", \"status\": \"$status\"}"
else
  echo '{"visible": "false" }'
fi
