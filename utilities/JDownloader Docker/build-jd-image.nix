{
  pkgs ? import <nixpkgs> {},
  pkgsLinux ? import <nixpkgs> {system = "x86_64-linux";},
}:
pkgs.dockerTools.pullImage {
  imageName = "jlesage/jdownloader-2";
  imageDigest = "sha256:6e83b8f25bcb1849328b1552b6934a7aa27919c98396f0b99d7d2576cb65b18e";
  sha256 = "1cmwsz6j75173qxv0zqv837prrppm7q9p38bjicmdh5bmrrb2kn3";
  finalImageName = "jlesage/jdownloader-2";
  finalImageTag = "latest";
}
