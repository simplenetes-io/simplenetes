# Simplenetes - magic free clusters

Welcome to _Simplenetes_! Let's put the Dev and Ops back into DevOps.

Simplenetes compared to Kubernetes:

    - Simplenetes has 10k lines of code, Kubernetes has 3M lines of code
    - Simplenetes has less moving parts
        - no etcd
        - no iptables
        - root-less containers
        - your cluster is also your git repo so you can see it on disk
        - everything is managed via SSH
        - no magic involved
        - very GitOps
    - Simplenetes also supports:
        - multiple replicas of pods
        - overlapping versions of pods
        - controlled rollout and rollback of pods
        - loadbalancers
        - internal proxying of traffic
        - CI/CD pipelines
        - Letsencrypt certificates
    - Simplenetes makes it very smooth to work with pods in development mode
    - Simplenetes uses `podman` as container runtime

In short: Simplenetes takes the raisins out of the cake, but it does not have everything Kubernetes offers.

While Kubernetes is "true cloud computing" in the sense that it can expand your cluster with more worker machines as needed and it can request resources from the environment as needed such as persistent disk, Simplenetes doesn't go there because that is when DevOps becomes MagicOps.

## When should I use Simplenetes?

In what cases should I really consider using Simplenetes?

    1.  You enjoy the simple things in life.
    2.  You might have struggled getting into a good local development flow using k8s.
    3.  You know you will have a small cluster, between 1 and 20 nodes.
    4.  You are happy just running N replicas of a pod instead of setting up auto scaling parameters.
    5.  You want a deterministic cluster which you can troubleshoot in detail
    6.  You want less moving parts in your cluster

In which cases should I *not* use Simplenetes over Kubernetes?

    1.  Simplenetes is in beta.
    2.  Because you are anticipating having more than 20 nodes in your cluster.
    3.  You need auto scaling in your cluster.
    4.  You really need things such as namespaces.
    5.  You are not using Linux as your development machine.
    6.  Your boss has pointy-hair.



## Simplenetes explained

Simplenetes has three parts:

    - This repo, the `sns` tool which setup and manages the cluster
    - `podc` - the pod compiler which takes yaml specs into executable standalone shell scripts managing a pod
    - `simplenetesd` - the daemon which runs on each host to start and stop pods.

See the [doc/README.md](doc/README.md) for topics on HOWTOs in getting started working with Simplenets Clusters.

See the [doc/COMPONENTS.md](doc/COMPONENTS.md) for an overview of all components of Simplenetes and the terminology used.
