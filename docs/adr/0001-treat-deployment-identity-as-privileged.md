# Treat the deployment identity as privileged

The Deployment Identity is a Nix trusted user so deploy-rs can copy unsigned
closures, which makes it effectively root-equivalent. Keep sudo restricted to
deploy-rs activation executables as defense-in-depth and for audit clarity, but
do not treat that rule as containment for a compromised deployment credential;
avoiding Nix trust would require a separate signed-closure delivery design.
