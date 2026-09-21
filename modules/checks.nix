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
          # Runs modules/netbird-invariants/check.sh against fixtures with a fake curl; the build sandbox has no network.
          netbird-invariants = let
            fakeCurl = pkgs.writeShellScriptBin "curl" (builtins.readFile "${self}/modules/netbird-invariants/tests/fake-curl.sh");
            fixtures = "${self}/modules/netbird-invariants/tests/fixtures";
            script = "${self}/modules/netbird-invariants/check.sh";
            expectedFile = pkgs.writeText "netbird-invariants-expected.json" self.lib.netbirdInvariantsExpectedJson;
          in
            pkgs.runCommand "netbird-invariants-check" {nativeBuildInputs = [pkgs.jq fakeCurl];} ''
              export NETBIRD_API_TOKEN=test
              NETBIRD_INVARIANTS_EXPECTED=$(cat ${expectedFile})
              export NETBIRD_INVARIANTS_EXPECTED

              fail=0
              status=0

              run_case() {
                status=0
                NETBIRD_TEST_DIR=${fixtures}/$1 bash ${script} >"$1.out" 2>&1 || status=$?
              }

              run_case baseline
              if [ "$status" -ne 0 ]; then
                echo "FAIL baseline: expected no violations, exit $status" >&2
                cat baseline.out >&2
                fail=1
              fi
              grep -qF "ok:" baseline.out || { echo "FAIL baseline: missing success line" >&2; fail=1; }

              for bad in search_domains_enabled_true blocky_wrong secondary_missing route_disabled route_missing auto_update_enabled proxy_observe; do
                run_case "$bad"
                if [ "$status" -eq 0 ]; then
                  echo "FAIL $bad: expected a violation, exit 0" >&2
                  fail=1
                fi
                grep -q "^VIOLATION" "$bad.out" || { echo "FAIL $bad: no VIOLATION line printed" >&2; cat "$bad.out" >&2; fail=1; }
              done

              run_case all_violations
              if [ "$status" -eq 0 ]; then
                echo "FAIL all_violations: expected violations, exit 0" >&2
                fail=1
              fi
              for needle in "quad9-search-domain" "legion-node2-route" "client-auto-update" "reverse-proxy-crowdsec-mode"; do
                grep -qF "$needle" all_violations.out || { echo "FAIL all_violations: missing '$needle' in output" >&2; cat all_violations.out >&2; fail=1; }
              done

              for closed in http_401 http_500 non_json curl_fail; do
                run_case "$closed"
                if [ "$status" -eq 0 ]; then
                  echo "FAIL $closed: expected nonzero exit, got 0" >&2
                  fail=1
                fi
                grep -qF "ok:" "$closed.out" && { echo "FAIL $closed: printed a success line despite failure" >&2; fail=1; }
              done

              # The missing-token path never reaches the network at all.
              status=0
              (unset NETBIRD_API_TOKEN; NETBIRD_TEST_DIR=${fixtures}/baseline bash ${script}) >missing_token.out 2>&1 || status=$?
              [ "$status" -ne 0 ] || { echo "FAIL missing_token: expected nonzero exit, got 0" >&2; fail=1; }
              grep -qF "ok:" missing_token.out && { echo "FAIL missing_token: printed a success line despite missing token" >&2; fail=1; }

              [ "$fail" -eq 0 ] || exit 1
              touch $out
            '';

          statix = pkgs.runCommand "statix-check" {nativeBuildInputs = [pkgs.statix];} ''
            statix check ${self}
            touch $out
          '';

          legion-nodes-json = pkgs.runCommand "legion-nodes-json-check" {} ''
            diff -u ${self}/dns/nodes.json ${pkgs.writeText "nodes.json" self.lib.legionNodesJson} \
              || { echo "dns/nodes.json is stale; regenerate it with: just dns-nodes" >&2; exit 1; }
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
