# The Components and Terminology of Simplenetes

This document gives an overview of everything involved in Simplenetes.

    - Pods
        A Simplenetes Pod is the same as a Kubernetes Pod in the sense that it is one or many containers which are managed together and share the same network.
        A Simplenetes Pod is described in a simple `pod.yaml` format and is compiled into a standalone shell script which uses `podman` as container runtime.
        The standalone `pod` shell script can be run as is or managed by the Simplenetes Daemon (simplenetesd).
        The `pod` shell script uses `podman` to run containers, which has the benefit of running containers root-less.
        There are three special Pods in Simplenetes which most often are used in Clusters (but do not have to be):
            - The IngressPod: (inbound traffic routing and TLS termination coming from the interwebz (using haproxy))
            - The LetsencryptPod: (renews SSL/TLS certificates for all domains and makes them available to the IngressPod)
            - The ProxyPod: an internal traffic router so Pods can talk to other Pods on other hosts or on the same host within the internal network.
        Actually, Simplenetes pods do not have to be containers at all. A Simplenetes Pod is an executable named `pod` which conforms to the Simplenetes Pod API.
        The `ProxyPod` above does not run any containers, it runs directly on the Host as a native application, but it is managed just as a Pod.
        However, you don't need to bother about that.
    - Host
        A Virtual Machine, a bare metal machine, or your laptop. Which is part of a Cluster.
        A Host runs Pods.
        A Host is expected to be configured with `podman` if it is to run container pods.
        If a Host is meant to receive internet traffic, it would likely be running an IngressPod, but it does not have to any pod could bind to 0.0.0.0 to be the ingress,
        as long as the firewall rules allow the traffic.
        Hosts which are workers are usually not exposed directly to the internet but receives traffic from IngressPods to the Pods they are harbouring.
    - Clusters and Cluster projects
        A Cluster is a cluster of Hosts on the same VLAN.
        A Cluster is typically one or two loadbalancer Hosts which are exposed to the internet on ports 80 and 443 and a couple of worker hosts where pods are running.
        A Cluster is spread out over many Hosts and is mirrored as a git repo (Cluster Project) on the operators local disk (or in a CI/CD system),
        this not only gives understandable GitOps procedures, but it also makes so you can inspect the full cluster layout in the git repo.
        A Cluster Project is a git repo which represents the Cluster, which is managed by the `sns` tool.
    - Management Project
        A Management Project is an overarching git repo used to manage one or more Cluster Projects, Pods and SSH keys.
        While a Management Project is strictly not needed to manage a Simplenetes Cluster, it does bring some organisational benefits and enables features such
        as separation of roles and isolation of keys.
    - Daemon (simplenetesd)
        The Simplenetes Daemon is installed and runs on each Host in a Cluster.
        The Simplenetes Daemon manages the lifecycle of all the Pods on the Hosts, regardless of their runtime type (be it podman, executable, etc).
        The Simplenetes Daemon is installed with root priviligies so that it can create `ramdisks` for the Pods, but it drops its priviligies when it interacts with any pod executable.
        The Daemon can be run in user mode instead of root and is then considered being run in "dev mode" for a single user straight on the laptop.

## Pods
A Simplenetes Pod is an executable `pod` file which conforms to the pod API. Typically the Pod is a collection of containers which run a service, but it does not have to be, it can be any executable which implements the Pod API (see the pod compiler project for the API spec).

### The Pod compiler (podc)
There is a separate project which compiles `pod.yaml` files into standalone `pod` executables which use `podman` as the container runtime.

### Other Pod types
For example the Simplenetes Proxy is treated as a regular Pod, but is is not containerized. The proxy listens to a wast array of ports and it is more efficient to not bind all those ports into a container, therefore the binary runs better without podman and straight on the Host.

The Simplenetes Daemon however does not know the difference, as long as the proxy has a `pod` executable and conforms to the Pod API the Daemon can manage it's lifecycle.

## Clusters and Cluster Projects
A Cluster is a set of Hosts (one or many) on the same VLAN. A Cluster can simply be your laptop, which is great for development.

A Cluster Project is a git repo which mirrors the full Cluster with all it's Hosts. Each Host is a subdirectory in the repo and it identified by having a `host.env` file inside of it.

When syncing to a Cluster from a Cluster Project, Simplenetes will connect to each Host (in parallel) and copy/update/delete files on the Host, so it mirrors the contents of the Cluster Project.

Following GitOps procedures the sync will not be allowed if the cluster repo branch which we are syncing from is behind the cluster it self, unless forced for major rollbacks.

The Daemon running on each Host will pick up the changes and manage the changes of all pods.

Setting up the Cluster with it's Virtual Machines is outside the scope of this document but is describe here [PROVISIONING.md](PROVISIONING.md)
Typically the setup is a VPC with two loadbalancer hosts which are exposed to the internet and are open to ports 80 and 443. Also two worker hosts which only accepts traffic coming from within the VLAN. Finally a fifth host which we call the "backdoor" which is exposed to the internet on port 22 (or some other port) for SSH connections. All SSH connections made to any loadbalancer or worker host is always jumped via the backdoor host. This reduces the surface area of attack since none of the known IP addresses are open to SSH connections from the internet.

## Hosts
A Host is typically a Virtual Machine in a VLAN, but it can also be your local laptop.

When Simplenetes is connecting to a Host it reads the `host.env` file and uses that information to establish an SSH connection to the Host.

A Host can declare in it's `host.env` file a `JUMPHOST`, which is used in the SSH connection to connect to first before connecting to the actual Host. This is a recommended way of doing it to not expose worker Hosts to incoming traffic from the public internet at all, so that all incoming connections made must be made via `jumphosts`.
p   

If the `host.env` file has `HOST=local` set then it does not connect via SSH, it connects directly on local disk, which is great for local development.

## Proxy and clusterPorts
For Pods to be able to communicate with each other within the Cluster and across Hosts, there is a concept of `clusterPorts` and the `Simplenetes Proxy`.

A Pod which is open for traffic declares a `clusterPort` in it's `expose` section in the `pod.yaml` file. Such a `clusterPort` is then targeted at a specific port in the Pod.
Other Pods can open connections to that clusterPort from anywhere in the Cluster and be "proxied" to one of the Pods exposing that clusterPort.

This is achieved in the way that a process open a socket to `proxy:clusterPort` from within it's pod. The `proxy` host name is automatically set in each containers `/etc/hosts` file to point to the IP address of the Host.
The native ProxyPod is listening to a set of clusterPorts and its job is to proxy that connection to another Proxy on a host in the cluster which then can forward the connection to a pod running on the Host.

The Proxy is very clever and robust and requires very little configurations to work. It needs an updated list of host addresses in the cluster and it needs a `proxy.conf` to be generated by the Daemon telling it what clusterPorts are bound on the Host. The Proxy it self will when proxying a connection try all hosts for answering connections and remember the results for a while. This gives a robust and easy to manage system which is free from iptables hacks or constantly needing to update global routing tables when pods come and go in the cluster.

Cluster ports can be manually assigned in the range between `1024 and 65535`, however ports `30000-32767` are reserved for host ports and the sns proxy (which claims port 32767).
Auto assigned cluster ports are assigned in the range of `61000-63999`.  
Auto assigned host ports are assigned in the range of `30000-31999` (the full range of dedicated host ports is `30000-32766`).

For a full specification of the proxy look here [PROXY.md](PROXY.md).

## Management Projects
While not strictly needed, a Management Project is an overarching git repo which works as parent directory to the Cluster Project repo.

With a Management Project you can collect your personal SSH keys in one secure place and don't have to distribute them together with the cluster project.
You can manage multiple clusters from the same place, say for "dev", "staging" and "production".
You can collect the Pods you are using to be shared by different clusters.

Using Management Projects is a good way of separating concerns also when developing pods and releasing them.

## Daemon
The Simplenetes Daemon is responsible for the lifecycle of Pods.  
It reads `.state` files alongside the `pod` file and executes the `pod` file with arguments relating to the desired state of the pod.
