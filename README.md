# Simplenetes
This is the Simplenetes Management tool, called `snt`.

The `snt` tool is used to manage the full life cycle of your clusters. It integrates with the Simplenetes Podcompiler project `podc` to compile pods.

See the [doc/README.md](doc/README.md) for topics on HOWTOs in getting started working with Simplenets Clusters.

See the [doc/COMPONENTS.md](doc/COMPONENTS.md) for an overview of all components of Simplenetes and the terminology used.

## Introduction to Simplenetes

Simplenetes is not Kubernetes, it has fewer moving parts and has less mystery to it. It is also great to work with in dev mode.

Pro's of Simplenetes:
    - A Cloud Native approach which also works smooth for local (offline) development
    - Mystery free
        Actually understand what your cluster is doing and why/not it is working.
    - Root not required.
        If wanting ramdisks then the Daemon needs to be run as root.
    - No iptables hacking and constant updating of routing tables
    - No "master" servers, not a "living breathing system", instead very deterministic and understandable.

## Install Simplenetes
To install Simplenetes, please see [doc/INSTALLING.md](doc/INSTALLING.md) for detailed instructions. 
