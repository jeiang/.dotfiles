{
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    checks = lib.mkMerge [
      (lib.mkIf (system == "x86_64-linux") (
        lib.mapAttrs' (name: nixosConfig: lib.nameValuePair "toplevel-${name}" nixosConfig.config.system.build.toplevel) self.nixosConfigurations
        // {
          statix = pkgs.runCommand "statix-check" {nativeBuildInputs = [pkgs.statix];} ''
            statix check ${self}
            touch $out
          '';

          legion-nodes-json = pkgs.runCommand "legion-nodes-json-check" {} ''
            diff -u ${self}/dns/nodes.json ${pkgs.writeText "nodes.json" self.lib.legionNodesJson} \
              || { echo "dns/nodes.json is stale; regenerate it with: just dns-nodes" >&2; exit 1; }
            touch $out
          '';

          # Exercises modules/hcloud-drift/check.sh's comparison logic against
          # fixtures (modules/hcloud-drift/tests/fixtures), standing in for
          # the network calls it can't make in the build sandbox: a fake
          # `hcloud` fed by HCLOUD_TEST_DIR, and HCLOUD_DRIFT_EXPECTED in
          # place of `nix eval`. A regression test for the two bugs a live
          # run can't exercise: source_ips being silently ignored, and one
          # drifted category hiding the others.
          hcloud-drift = let
            fakeHcloud = pkgs.writeShellScriptBin "hcloud" ''
              set -euo pipefail
              dir="$HCLOUD_TEST_DIR"
              if [ -z "$dir" ]; then
                echo "fake hcloud: HCLOUD_TEST_DIR is unset" >&2
                exit 1
              fi
              if [ -e "$dir/fail" ]; then
                echo "fake hcloud: simulated failure" >&2
                exit 1
              fi
              case "$1 $2" in
              "context active") echo test ;;
              "firewall describe") cat "$dir/firewall.json" ;;
              "server list") cat "$dir/servers.json" ;;
              "volume list") cat "$dir/volumes.json" ;;
              *)
                echo "fake hcloud: unhandled args: $*" >&2
                exit 1
                ;;
              esac
            '';
            fixtures = "${self}/modules/hcloud-drift/tests/fixtures";
            script = "${self}/modules/hcloud-drift/check.sh";
          in
            pkgs.runCommand "hcloud-drift-check" {nativeBuildInputs = [pkgs.jq fakeHcloud];} ''
              export HCLOUD_TOKEN=test
              HCLOUD_DRIFT_EXPECTED=$(cat ${fixtures}/expected.json)
              export HCLOUD_DRIFT_EXPECTED

              fail=0
              status=0

              run_case() {
                status=0
                HCLOUD_TEST_DIR=${fixtures}/$1 bash ${script} >"$1.out" 2>&1 || status=$?
              }

              run_case baseline
              [ "$status" -eq 0 ] || { echo "FAIL baseline: expected no drift, exit $status" >&2; cat baseline.out >&2; fail=1; }

              run_case all_drift
              if [ "$status" -eq 0 ]; then
                echo "FAIL all_drift: expected drift, exit 0" >&2
                fail=1
              else
                for needle in "rules drift" "attachments drift" "Volumes drift"; do
                  grep -qF "$needle" all_drift.out || { echo "FAIL all_drift: missing '$needle' in output" >&2; cat all_drift.out >&2; fail=1; }
                done
              fi

              run_case source_ips_narrowed
              [ "$status" -ne 0 ] || { echo "FAIL source_ips_narrowed: expected drift, exit 0" >&2; fail=1; }

              run_case ipv4_only
              [ "$status" -ne 0 ] || { echo "FAIL ipv4_only: expected drift, exit 0" >&2; fail=1; }

              run_case icmp_added
              [ "$status" -eq 0 ] || { echo "FAIL icmp_added: expected no drift, exit $status" >&2; cat icmp_added.out >&2; fail=1; }

              run_case hcloud_fails
              if [ "$status" -eq 0 ]; then
                echo "FAIL hcloud_fails: expected nonzero exit, got 0" >&2
                fail=1
              fi
              grep -qF "no drift" hcloud_fails.out && { echo "FAIL hcloud_fails: printed 'no drift' despite hcloud failure" >&2; fail=1; }

              [ "$fail" -eq 0 ] || exit 1
              touch $out
            '';
        }
      ))
      # Only the toplevel: garret push sends its whole closure, which already holds every darwin package zakkart installs.
      (lib.mkIf (system == "aarch64-darwin") {
        zakkart-system = self.darwinConfigurations.zakkart.config.system.build.toplevel;
      })
    ];
  };
}
