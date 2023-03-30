final: prev: {
  # As of Mar 29, 2023, nixpkgs-unstable does not include openssl
  # Once unstable is up to date, then :thumbs-up: change as needed
  wezterm = with final; rustPlatform.buildRustPackage rec {
    inherit (prev.sources.wezterm) pname version src;

    # didnt seem to work when build :shrug:, did it get overridden or something??
    postPatch = ''
      echo ${version} > .tag
      # tests are failing with: Unable to exchange encryption keys
      # all 37 tests in wezterm-ssh (under e2e::sftp) fail with no such file or directory
      rm -r wezterm-ssh/tests
    '';

    nativeBuildInputs = (prev.wezterm.nativeBuildInputs or [ ]) ++ (with final; [ openssl openssl.dev ]);
    buildInputs = (prev.wezterm.buildInputs or [ ]) ++ (with final; [ openssl ]);

    cargoLock = prev.sources.wezterm.cargoLock."./Cargo.lock";
  };
}
