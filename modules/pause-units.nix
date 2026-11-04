{lib, ...}: {
  # Bash that stops units and later starts only the ones that were running, so a resume never
  # starts a unit the operator stopped. Pauses append to the record, so a pause whose resume never
  # ran is resumed by the next one.
  flake.lib.pauseUnits = state: units: {
    pause = ''
      units=(${lib.escapeShellArgs units})
      for unit in "''${units[@]}"; do
        case $(systemctl is-active "$unit") in
        inactive | failed) ;;
        *) echo "$unit" ;;
        esac
      done >>"${state}"
      systemctl --no-ask-password stop "''${units[@]}"
    '';
    resume = ''
      if [ -s "${state}" ]; then
        mapfile -t paused <"${state}"
        systemctl --no-ask-password start "''${paused[@]}"
      fi
      rm -f "${state}"
    '';
  };
}
