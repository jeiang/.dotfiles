# Route Hermes actions through an Approval Broker

Hermes gets public read-only network access and full read/write access to its
workspace, but it still holds no GitHub, root, or Nix daemon authority.
Publication, arbitrary commands, and a fixed set of service actions cross a
one-shot Telegram Approval Broker. The broker keeps the GitHub credential but
never executes command text; a separate credential-free Approved Command
Runner executes approved commands with the same workspace access as Hermes, a
500 MiB memory limit, and public-only networking. This extends the credential
isolation in ADR 0004 while allowing explicit exceptions without weakening the
normal sandbox.
