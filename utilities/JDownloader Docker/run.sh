#!/bin/sh
docker load < $(nix-build build-jd-image.nix)

mkdir -p "$(pwd)/config"
mkdir -p "$(pwd)/downloads"

docker run -d --rm --name=jdownloader-2 -p 5800:5800 \
  --mount type=bind,source="$(pwd)"/config,target=/config \
  --mount type=bind,source="$(pwd)"/downloads,target=/output \
  jlesage/jdownloader-2:latest

trap 'docker stop jdownloader-2 > /dev/null' EXIT
trap 'docker stop jdownloader-2 > /dev/null' INT

echo 'Launched JDownloader Docker Image'
sleep 1
xdg-open 'http://localhost:5800'
echo 'Opening http://localhost:5800'
echo 'Press ''q'' to exit...'

while : ; do
  read -s -n 1 k <&1
  if [[ $k = q ]]; then
    break
  fi
done

echo 'Exiting...'
