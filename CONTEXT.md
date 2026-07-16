# System Access

Terms for identities that administer and deploy the systems managed by this
flake.

## Language

**Human Administrator**:
A person who performs interactive system administration and recovery.
_Avoid_: Deployment identity, automation user

**Deployment Identity**:
A privileged, non-human identity used only by automation to deploy system
configurations. Its credentials grant administrative control of deployment
targets.
_Avoid_: Human administrator, personal account
