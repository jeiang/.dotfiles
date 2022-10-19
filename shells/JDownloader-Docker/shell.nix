{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "JDownloader Docker";
  buildInputs = with pkgs; [
    docker
  ];
  shellHook = ''
    docker load < $(nix-build build-jd-image.nix)
    docker run -d --name=jdownloader-2 -p 5800:5800 \
      --mount type=bind,source="$(pwd)"/config,target=/config \
      --mount type=bind,source="$(pwd)"/downloads,target=/output \
      jlesage/jdownloader-2:latest
    xdg-open 'http://localhost:5800'
    echo 'Opening http://localhost:5800'
    trap "docker stop jdownloader-2 && docker rm jdownloader-2" EXIT
  '';
}
