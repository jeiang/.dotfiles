{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$sudo$directory$rust$package$git_branch$git_commit$git_state$git_status$git_metrics$fill$cmd_duration$jobs$nix_shell\n$character";
      right_format = "$status$time$username$hostname";
      username = {
        style_user = "bright-purple bold";
        style_root = "bright-red bold";
      };
      hostname = {
        format = "[@$hostname]($style)\[$ssh_symbol\]";
        style = "bright-green bold";
        ssh_only = true;
        ssh_symbol = "";
      };
      nix_shell = {
        symbol = " ";
        format = "[$symbol$name]($style) ";
        style = "bright-purple bold";
      };
      git_branch = {
        only_attached = true;
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        symbol = "שׂ";
        style = "bright-yellow bold";
      };
      git_commit = {
        only_detached = true;
        format = "[ﰖ$hash]($style) ";
        style = "bright-yellow bold";
      };
      git_state = {
        style = "bright-purple bold";
      };
      git_status = {
        conflicted = "=";
        ahead = "$count⇡";
        behind = "$count⇣";
        diverged = "($ahead_count|$behind_count)⇕";
        up_to_date = "";
        untracked = "$count?";
        stashed = "$count$";
        modified = "$count!";
        staged = "$count+";
        renamed = "$count»";
        deleted = "$count✘";
        style = "bright-blue";
      };
      git_metrics = {
        disabled = false;
      };
      directory = {
        read_only = " ";
        truncation_length = 0;
      };
      cmd_duration = {
        format = "⏱ [$duration]($style) ";
        style = "bright-blue";
      };
      jobs = {
        style = "bright-green bold";
      };
      fill = {
        symbol = " ";
        style = "black";
      };
      character = {
        success_symbol = "[➜](bright-green bold)";
        error_symbol = "[➜](bright-red bold)";
      };
      package = {
        format = "[$symbol$version]($style) ";
        symbol = "󰏖 ";
        version_format = "v$raw";
      };
      rust = {
        format = "[$symbol($version )]($style) ";
        version_format = "v$major.$minor";
      };
      status = {
        disabled = false;
        format = "[$symbol$status]($style) ";
        map_symbol = true;
        symbol = "";
        not_executable_symbol = "󰜺";
        not_found_symbol = "";
        signal_symbol = "";
        pipestatus = true;
        pipestatus_format = "[$pipestatus] => [$symbol$common_meaning$signal_name$maybe_int]($style)";
        pipestatus_separator = "|";
        style = "bold bright-red";
      };
      sudo = {
        disabled = false;
        format = "[$symbol]($style)";
      };
      time = {
        disabled = false;
        format = "[$symbol $time]($style) ";
        time_format = "%R"; # Hour:Minute Format;
        time_range = "-";
      };
    };
  };
}
