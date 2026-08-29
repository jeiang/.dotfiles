{
  # Single source of truth for the kanabox colorscheme; `just wallpaper`
  # regenerates the wallpaper recolor from it.
  flake.lib.palette = rec {
    kanabox = {
      autumnGreen = "#76946A";
      autumnRed = "#C34043";
      autumnYellow = "#DCA561";
      boatYellow1 = "#938056";
      boatYellow2 = "#C0A36E";
      carpYellow = "#E6C384";
      crystalBlue = "#7E9CD8";
      dragonBlue = "#658594";
      fujiGray = "#727169";
      fujiWhite = "#DCD7BA";
      katanaGray = "#717C7C";
      lightBlue = "#A3D4D5";
      oldWhite = "#C8C093";
      oniViolet = "#957FB8";
      peachRed = "#FF5D62";
      roninYellow = "#FF9E3B";
      sakuraPink = "#D27E99";
      samuraiRed = "#E82424";
      springBlue = "#7FB4CA";
      springGreen = "#98BB6C";
      springViolet1 = "#938AA9";
      springViolet2 = "#9CABCA";
      sumiInk0 = "#16161D";
      sumiInk1 = "#1F1F28";
      sumiInk1_5 = "#252530";
      sumiInk2 = "#2A2A37";
      sumiInk3 = "#363646";
      sumiInk4 = "#54546D";
      surimiOrange = "#FFA066";
      waveAqua1 = "#6A9589";
      waveAqua2 = "#7AA89F";
      waveBlue1 = "#252E42";
      waveBlue1_5 = "#2A3D5A";
      waveBlue2 = "#2F496C";
      waveRed = "#E46876";
      winterBlue = "#252535";
      winterGreen = "#2B3328";
      winterRed = "#43242B";
      winterYellow = "#49443C";
    };
    kanaboxDarkHard =
      kanabox
      // {
        sumiInk0 = "#03030A";
        sumiInk1 = "#0C0C15";
        sumiInk1_5 = "#2A2A37";
      };
  };
}
