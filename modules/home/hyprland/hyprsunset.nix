{
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "7:00";
          identity = true;
        }
        {
          time = "18:30";
          temperature = 4500;
          gamma = 0.8;
        }
      ];
    };
  };
}
