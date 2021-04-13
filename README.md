# Simplenetes - magic free clusters

Welcome to _Simplenetes_! Let's put the Dev and Ops back into DevOps.

Simplenetes compared to Kubernetes:

    - Simplenetes has a 100x less code than Kubernetes.
    - Simplenetes has fewer moving parts
        - No etcd
        - No iptables
        - Root-less containers
        - Your cluster is also your git repo so you can see it on disk
        - Everything is managed via SSH
        - No magic involved
        - Very GitOps
    - Simplenetes also supports:
        - Multiple replicas of pods
        - Overlapping versions of pods
        - Controlled rollout and rollback of pods
        - Loadbalancers
        - Internal proxying of traffic
        - CI/CD pipelines
        - Letsencrypt certificates
        - Health checks
    - Simplenetes makes it really smooth to work with pods and micro services in development mode on you laptop (spoiler: no VMs needed)
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

See the [doc/README.md](doc/README.md) for topics on HOWTOs in getting started working with Simplenetes Clusters.


## Install
`sns` is a standalone executable, written in POSIX-compliant shell script and will run anywhere there is Bash/Dash/Ash installed.

```sh
LATEST_VERSION=$(curl -s -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/simplenetes-io/simplenetes/releases/latest | grep tag_name | cut -d":" -f2 | tr -d ",|\"| ")
curl -LO https://github.com/simplenetes-io/simplenetes/releases/download/$LATEST_VERSION/sns
chmod +x sns
sudo mv sns /usr/local/bin
```

For further instructions, please refer to the [documentation](https://github.com/simplenetes-io/simplenetes/blob/master/doc/INSTALLING.md).


Simplenetes was built by [@bashlund](https://twitter.com/bashlund) and [filippsen](https://twitter.com/mikediniz)
