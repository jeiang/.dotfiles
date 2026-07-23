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
A Telegram-facing personal agent that prepares repository changes, reports
observed fleet state, and submits bounded actions for human approval without
holding deployment, root, or publication credentials.
_Avoid_: Deployment Identity, cluster operator

**Approval Broker**:
The Telegram human-approval boundary that publishes exact approved commits and
routes approved actions without executing arbitrary commands itself. It is the
only Hermes-related identity with repository write credentials.
_Avoid_: Publication Broker, Hermes Agent, Approved Command Runner

**Approved Command Runner**:
A credential-free identity that executes one human-approved command within the
Hermes workspace and its fixed resource and network limits.
_Avoid_: Approval Broker, Deployment Identity, root shell

**Agent Memory**:
The compact native memory and user profile that Hermes maintains automatically
and submits for review from a reserved Knowledge Base subtree.
_Avoid_: Session history, general knowledge

**Knowledge Base**:
A private Markdown repository containing reviewed, explicitly directed general
knowledge and a reserved subtree for Agent Memory.
_Avoid_: Session history, Observed Snapshot

**Observed Snapshot**:
A timestamped, bounded report of current host and service state; it is not a
declaration of intended configuration.
_Avoid_: Knowledge Base, desired state
