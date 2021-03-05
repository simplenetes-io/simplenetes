# Setting up your first dev cluster
This is a guide in how to get started with a local development cluster on your laptop.

To manage a cluster a GNU/BusyBox/Linux, Mac or Window WSL machine will do.

If you want to run the pods locally then Podman is mandatory and therefore a GNU/Linux OS is required.

A dev cluster works exactly as a production cluster, with the differences that:  

    - There is only one host, your laptop
    - The `sntd` Daemon process is often run in foreground in user mode and never installed as a systemd unit.
    - TLS certificates cannot be issued, since it's a closed system and public DNS is not applicable.

If you only want to compile a single pod to use locally or want to learn more about Simplenetes Pods and the Podcompiler, we suggest reading [FIRSTPOD.md](FIRSTPOD.md).  

What we will be doing:  

    1.  Installing the necessary programs
    2.  Create the cluster project
    3.  Add a pod to the cluster
    4.  Compile the pod
    5.  Sync the cluster locally
    6.  Run the Daemon to manage the pods
    7.  Update pods and re-sync the Cluster
    8.  Add Proxy and Ingress
    9.  Setup your development work flow

### 1. Installing all necessary programs
See [INSTALLING.md](INSTALLING.md) for instructions on installing `snt, `sntd`, `podc` and `podman`.  

### 2. Setup a dev cluster
Let's create our first dev cluster inside a new directory and give it the id `laptop-cluster`.
```sh
cd
mkdir simplenetes
cd simplenetes
mkdir mgmt-1
```

You stricly don't have to create the `mgmt-1` parent directory, but we will use it later (hint: it is a _Management Project_), so please do create it.

```sh
cd mgmt-1
snt create-cluster laptop-cluster
cd laptop-cluster
```

We now have three files in the cluster:  

    - `cluster-id.txt` which contains the cluster ID provided to `init-host`.
        This ID is set on each host in the cluster so we can be sure operating only on correct hosts
        when managing the cluster.
    - `cluster-vars.env` a key-value file which still is empty, but can have cluster-wide variables.
    - `log.txt` which is a log file storing all operation done on the cluster.

You can change the cluster ID at this point directly in `cluster-id.txt`, but doing it later is not recommended.

Now, let's create a Host which is not a Virtual Machine but instead refers to our laptop, the second argument "local" states that this is a local disk host  
```sh
cd laptop-cluster
snt create-host laptop -a local -d simplenetes/host-laptop -r localhost:32767
```

The `-d` option dictates what directory is the `HOSTHOME` on the host. A relative directory will be considered relative to the users `$HOME`. We need to set this option when creating a local "cluster" to not have many hosts files clashing.

This will create a directory `laptop` which represents the Host within this cluster. Inside the directory there will be two files: 

    - `host.env`, a key-value file containg the variables needed to connect to the host.
        The variable `HOSTHOME` dictates where on the Host files will get copied to when syncing the cluster repo with the remote cluster. For hosts which have HOST=local this is the directory on your laptop to where pods will get synced.
        This means that if simulating many Hosts on the same laptop they will need different HOSTHOME settings.
    - `host.state`, a simple file which can contain the words `active`, `inactive` or `disabled`, and tells Simplenetes the state of this Host.
        A disabled host is ignored, an inactive host is still being managed by `snt` but will not be part of the ingress configuration.

Now we need to "init" this host, so it belong to our cluster. This will create the `HOSTHOME` directory `${HOME}/simplenetes/laptop` on your laptop.

Initing the host will also install any image registry `config.json` file for that user. But doing this for local cluster will overwrite any existing such `config.json` file, so no point doing so. See (REGISTRY.md)[REGISTRY.md] for more info on image registries.

From inside the `laptop-cluster` dir, type:  
```sh
snt init-host laptop
```

Look inside the `${HOME}/simplenetes/host-laptop` dir and you will see the file `cluster-id.txt`. This is the same file as in the cluster repo you created earlier.

Do not ever edit anything by hand inside the (pretend remote) `simplenetes/host-laptop` directory, all changes are always to be synced here from the cluster project using `snt`.

Note: On a remote Host we would also want to install the Simplenetes Daemon `(sntd)` onto it. The Daemon is the process which manages pod lifecycles according to the state the pod is supposed to have.

### 3. Add a pod to the cluster
When compiling new pod versions into the cluster, we need access to the Pod project and the pod specifications in there.

To do this we can set the `PODPATH` env variable to point to the parent directory of where pod projects are located. The default is to look in `../pods`, which suits us fine when using a Management Project to manage our cluster because we simply add our pod git repos directly inside the Management Project directory.

If you have another place for all your pods, you can set the `PODPATH` env variable to point there instead of using the default `../pods`

From inside the `simplenetes/mgmt-1` dir, type:  
```sh
mkdir pods
cd pods
git pull github.com/simplenetes-io/nginx-webserver webserver
```

Now the pod is accessible to `snt`, so let's add it to the cluster.

Note that a Pod is always attached to a specific Host, one or many. In Kubernetes in general pods are not bound to a specific Host, however in Simplenetes this is a design decision for Simplenetes that the operator attaches a pod to one or many specific Hosts.

From inside the `laptop-cluster` dir, type:  
```sh
snt attach-pod webserver@laptop
```

Depending on the pod attached, Simplenetes could say that:  
```sh
[INFO]  This was the first attachement of this pod to this cluster, if there are configs you might want to import them into the cluster at this point.
```

Some background on this: Some pods have `configs`. Configs are directories which are deployed together with the pod and the pod's containers can mount them.

If a Pod is using configs, then it could provide initial/template configs in the `config` dir in it's pod repo and we can import those into the cluster where we then tailor the configs for this specific cluster.

Configs from a Pod are usually only imported once to the cluster, since they are treated as templates not as live configurations.
The configs can be edited after have been imported to the cluster project and they can be pushed out onto existing pod releases without the need for redeployments.

We import the pod template configs into the cluster below.  
From inside the `laptop-cluster` dir, type:  
```sh
snt import-config webserver
```

Now the `config` dir from the webserver pod repo will have been copied into the cluster repo as `./\_config/webserver/config`.
These configs we now can tune and tailor to the needs of the cluster. Every time a pod is compiled the configs from the cluster will be copied to each pod release under each Host the pod is attached to.

There is one last configuration we will need to make for when attaching this pod. If you look in the `pod.yaml` file in the webserver pod you can see two variables: `${HOSTPORTAUTO1}` and `${clusterPort}`.
These variables are defined in the `pod.env` file alongside the `pod.yaml` file and they are used when compiling single pods which are not attached to a cluster repo. However, when using pods in a cluster we need to define those variables in the cluster-wide `cluster-vars.env` file instead. The `pod.env` file will be ignored when attaching pods to clusters (remember: `.env` stands for "environment").

There is one special case of variables and that is those who look like `${HOSTPORTAUTOxyz}`, those we will not define in `cluster-vars.env` because Simplenetes will assign those values depending on which host ports are already taken on each Host.

Note: one can also auto assign cluster ports by using `${CLUSTERPORTAUTOxyz}`, then a cluster wide unique cluster ports is assigned.

So we simply leave out `${HOSTPORTAUTO1}` and just add `${clusterPort}` with the pod name as prefix, as:  

From inside the `laptop-cluster` dir, type:  
```sh
echo "webserver_clusterPort=2020" >>"cluster-vars.env"
```

All variables for pods which get defined in the cluster wide `cluster-vars.env` file must be prefixed with the pod name, this is to avoid clashes of common variable name, however variable names which are all `CAPS` are not to be prefixed and are treated as globals, this is because some variables should be shared between pods, such as the `DEVMODE` variable.

Clusterports are used to map a containers port to a cluster-wide port so that other pods in the cluster can connect to it.
This means that every running pod which has defined the same cluster port will share traffic incoming on that port.

All replicas of a specific pod version share the same cluster ports, most often also pods of different version which are deployed simultaneously also share the same cluster ports. But the same `clusterPorts` are usually not shared between different types of pods.  

Cluster ports can be manually assigned in the range between `1024-29999 and 32768-65535` while ports `30000-32767` are reserved for host ports and the snt proxy.
Auto assigned cluster ports are assigned in the range of `61000-63999`.

### 4. Compile the pod
When compiling an attached pod it is always required that the pod dir is a git repo.
This is because Simplenetes is very keen on versioning everything that happens in the cluster, both for traceability but also for options to rollback entire deployments.

From inside the `laptop-cluster` dir, type:  
```sh
snt compile webserver
```

At this point you can see in `laptop-cluster/pods/webserver/release/0.0.1/` that we have the compiled `pod`, the `pod.state` which dictates what state the pod should be in and potentially the `config` dir, which holds all configs.

### 5. Sync the cluster locally
After we have updated a cluster repo with new pod release (or updated configs for an existing release) we can sync the cluster repo to the Cluster of Hosts.

This is done in the same way regardless if your cluster is your laptop or if it is a remote Cluster of many Virtual Machines.

Simplenetes is very strict about the cluster repo is committed before syncing, so that traceability and rollbacks are possible.

From inside the `laptop-cluster` dir, type:  
```sh
git add .
git commit -m "First sync"
snt sync
```

Now, look inside the local `HOSTHOME` to see the files have been synced there:  
```sh
cd ${HOME}/simplenetes/host-laptop
ls
```

You will now see another file there: `commit-chain.txt`, this file contains all git commit hashes all the way back to the initial commit, it serves as a way to manage the scenario when the cluster is being synced from multiple sources at the same time so that an unintentional rollback is not performed.

Also when syncing, a `lock-token` is placed in the directory to make sure no concurrent syncing is done.

### 6. Run the Daemon to manage the pods
In a real Cluster the Daemon will be running and would by now have picked up the changes to the Host and managed the effected pods.

Since we are running this on the laptop in dev mode, we won't install the Daemon into systemd (although you could), we will start it manually instead.

Start the Daemon in the foreground to manage the pods.
```sh
cd ${HOME}/simplenetes/host-laptop
sntd .
```

Start the daemon as `root` or with `sudo` if you want proper ramdisks to be created, else fake ramdisks on disk are created instead.
Note: Do not start the daemon as root without any arguments because then it starts as a system daemon.

The Daemon should now be running and it will react on any changes to the pods or their configs.

How can we `curl` to the pod? Remember that the `pod.yaml` has a `clusterPort` configured? That means the pod will be reachable in the Cluster on that port, but not until we have setup the internal Proxy. However since we want to try it out now just for kicks, we can go straight to the given `hostPort` of the pod. Remember the `${HOSTPORTAUTOx}`? This will be a automatically generated port number in the high ranges. We can't know on beforehand what it is, because it will be the first non-taken port on the Host.

Let's find out what the bound host port is. Locate the directory in your cluster repo where the `pod` file is:  
```sh
cd laptop-cluster/laptop/pods/webserver/release/<version>
cat pod.proxy.conf
```

We will get an output such as:  
```sh
2020:30000:4096:false
```

The first field is the clusterPort, the second field is the hostPort, the third fields is the max connections, the last field is weather the container expects proxy-protocol or not.

Take a note of the second column, `30000` in this case.

```sh
curl 127.0.0.1:30000
```

### 7. Update pods and re-sync to Cluster
There are two ways a pod can be updated, either when its version number has been bumped which then requires a recompile and redeploy of that pod, or if only configs of the pod has been updated, then it can be enough to update the configs of an already released pod.

We will first go through the process of updating the configs of a pod.
We will be updating the contents of the nginx server, but please note that configs should preferably not be used for content but for configurations, however for this tutorial it shows how it is done by using content.

```sh
cd laptop-cluster/_config/webserver/nginx-content
echo "Hello Again!" >>index.html

# At this point we should to commit our changes.
git add _config/webserver
git commit -m "Update webserver configs"
```

```sh
# This will copy the config into the lest released pod on each Host it is attached to.
# Note that the version number is implicit as "snt webserver:latest". `snt` will find the latest released version (it will ignore any prerelease version such as "0.1.0-beta1").
cd laptop-cluster
snt update-config webserver
```

We need to commit our changes before we sync:  
```sh
cd laptop-cluster
git commit laptop/pods/webserver -m "Update webserver configs"

# Let's sync
snt sync
```

Now try that curl example above again.

Now let's update the pod version and deploy it with another image.
Change the `pod.yaml` in the `pods/webserver` repo, bump the `podVersion` number and change the image version slightly, say to: `image: nginx:1.16.1-alpine`

We need to commit the `pod.yaml`.
```sh
cd pods/webserver
git commit . -m "Update pod version"
```

Before we compile it, let's change the pod configs in the cluster so that this new pod version gets an unique config.  
```sh
cd laptop-cluster/_config/webserver/nginx-content
echo "Hello from a new version!" >>index.html

# At this point we should to commit our changes.
git add _config/webserver
git commit -m "Update webserver configs"
```

Let's compile this new version:  

```sh
cd laptop-cluster
snt compile webserver
```

We need to commit our changes before we sync:  
```sh
cd laptop-cluster
git add .
git commit -m "Add webserver release"

# Let's sync
snt sync
```

Find the hostPort of this new pod in the same way as before.

Feel free to look at the files in `simplenetes/host-laptop/pods/webserver/release/<version>/`.

Alright, now you have two versions of the same pod running. Both these pods will be sharing any incoming traffic from the cluster since they use the same clusterPort (but we still haven't added the proxy or the ingress pod, so there is no incoming traffic in that sense).

If we are happy with our new release, we can then retire the previous version. In this case we *must* provide the pod version we want to retire, since the default is to operate on the latest release if no version if given.

```sh
cd laptop-cluster
snt set-pod-state webserver:0.0.1 -s removed
```

We need to commit our changes before we sync:  
```sh
cd laptop-cluster
git add .
git commit -m "Retire old version"

# Let's sync
snt sync
```

You should now be able to see that the first pod is not responding on requests anymore.

Note that Simplenetes does support transactional ways of doing rolling releases so we don't have to deal with these details each time.

### 8. Add Proxy and Ingress
To be able to reach our pod as it was exposed to the internet we need to add the ProxyPod and the IngressPod.

A special thing about the IngressPod is that it most often binds to ports 80 and 443 on the host but ports below 1024 are root only, so this requires that podman is properly setup to allow for non-root users to bind to ports as low as 80 for the Ingress to work.
Find these details in the (INSTALLATION.md)[INSTALLATION.md] instructions.

```sh
cd pods
git pull github.com/simplenetes-io/ingress
```

In a proper cluster we would attach the IngressPod to the hosts which are exposed to the internet and have DNS pointed to them,
but now we attached it to our single host.

```sh
cd laptop-cluster
snt attach-pod ingress@laptop
```

The config templates in the pod should have been automatically copied to the cluster project.

Let's generate the haproxy ingress configuration for this cluster:  
```sh
cd laptop-cluster
snt generate-ingress
```

You can inspect the generated `haproxy.cfg` if you are curious, it is inside `\_config/ingress/conf`.  

```sh
cd laptop-cluster
snt compile ingress
```

When we add some other pod, or update any pods ingress we need to again run `snt generate-ingress` and then follow the pattern of updating configs for existing pods, so that the ingress (haproxy) gets the new config and re-reads it.

The IngressPod will proxy traffic from the public internet to the pods within the cluster who match the ingress rules.
The IngressPod will also (optionally) terminate TLS traffic.

When the IngressPod has matched rules and optionally terminated TLS, it will route the traffic to the right Pod by connecting to the local ProxyPod on one of the listening ports we call _ClusterPort_.

The cluster port number is configured in the Ingress config and found by matching the rules of incoming traffic.
This configuration comes from the `pod.yaml` files when configuring for `ingress` and defining `clusterPort`.

The ProxyPod runs on each host and knows the addresses to all other hosts in the cluster.
When a Pod (be it IngressPod or any other pod) connects to a cluster port the proxy is listening to then the Proxy will try connecting to each Proxy on every other host on the reserved proxy port, with the hope that the remote proxy can tunnel the connection to a local pod's bound host port. See (PROXY.md)[PROXY.md] for more details.

Note that the ProxyPod is a "special" pod because it runs no containers, but instead is a native executable. However since it adheres to the Pod API it is still treated and managed as a Pod.
The reason the ProxyPod runs natively on the Host is that it binds so many (cluster) ports that it is more efficient to skip the extra layer of running in a container.

```sh
cd pods
git pull github.com/simplenetes/proxy
```

The ProxyPod should be attached to every Host in the Cluster, in our case it is only `laptop`.

```sh
cd laptop-cluster
snt attach-pod proxy@laptop
```

```sh
cd laptop-cluster
snt import-config proxy
```

```sh
cd laptop-cluster
snt compile proxy
```

We need to commit our changes before we sync:  
```sh
cd laptop-cluster
git add laptop/pods
git commit -m "Add Ingress and Proxy"

# Let's sync
snt sync
```

Now let's test to access the pods through the Ingress:  
```
curl 127.0.0.1/hello/
```

### 9. Setup your development work flow
Now that we have the local laptop-cluster setup, we can simulate all the pods and as they are communicating inside the cluster, locally.

If simulating the production environment, then you will be building new image version for each update of a pod, which in dev mode is not very efficient. So what we can do instead is to reuse the pattern of when working with a single local pod and mount build directories of the project.

To do this we adjust the env variables in the `cluster-vars.env` file so that build files are mounted into the containers.
