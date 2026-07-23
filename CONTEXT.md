# Managed Systems

Terms for the systems, services, state, and identities managed by this flake.

## Language

### System Roles

**Artemis**:
The recoverable, performance-oriented workstation.
_Avoid_: Desktop host, Legion node

**Legion Fleet**:
The resource-constrained remote NixOS systems managed together as service
hosts.
_Avoid_: K3s cluster

**Host-Native Service**:
A service whose placement, configuration, state, and lifecycle are managed
directly on an assigned Legion node without a cluster scheduler.
_Avoid_: Bare-metal service, Kubernetes workload

**Edge Node**:
The single Legion node that receives public web traffic and forwards it to
Host-Native Services over the private network.
_Avoid_: Load balancer, service node

### State

**Persistent State**:
State that must survive a reboot, rebuild, or service restart.
_Avoid_: Backup, cache

**Backup Set**:
An explicitly reviewed subset of Persistent State copied off-node for disaster
recovery.
_Avoid_: Persistence list, cache

**Disposable State**:
State that may be discarded because it can be regenerated or reacquired.
_Avoid_: Persistent State, Backup Set

### System Access

**Human Administrator**:
A person who performs interactive system administration and recovery.
_Avoid_: Deployment Identity, automation user

**Deployment Identity**:
A privileged, non-human identity used only by automation to deploy system
configurations. Its credentials grant administrative control of deployment
targets.
_Avoid_: Human Administrator, personal account

**Hermes Agent**:
A Telegram-facing personal agent that prepares repository changes and reports
observed fleet state without holding deployment or publication authority.
_Avoid_: Deployment Identity, cluster operator

**Publication Broker**:
A separate identity that publishes an approved Hermes worktree branch to
GitHub; it is the only Hermes-related identity with repository write access.
_Avoid_: Hermes Agent, Deployment Identity

**Knowledge Base**:
A private, reviewed Markdown repository that holds durable operational facts
and links to their source revisions.
_Avoid_: Session history, agent memory

**Observed Snapshot**:
A timestamped, bounded report of current host and service state; it is not a
declaration of intended configuration.
_Avoid_: Knowledge Base, desired state
