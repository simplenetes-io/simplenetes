# Setting up your first dev cluster
This is a guide in how to get started with a local development cluster on your laptop.

To manage a cluster a GNU/BusyBox/Linux, Mac or Window WSL machine will do.

If you want to run the pods locally then Podman is required and therefore a GNU/Linux OS is required.

A dev cluster works exactly as a production cluster, with the differences that:  

    - there is only one host, your laptop
    - the `sntd` Daemon process is often run in foreground user mode and never installed as a systemd unit.
    - certificates cannot be issued, since it's a closed system and public DNS is not applicable.

If you only want to compile a single pod to use locally or want to learn more about Simplenetes Pods and the Podcompiler, we suggest reading [FIRSTPOD.md](FIRSTPOD.md).  

What we will be doing:  

    1.  Installing the necessary programs
    2.  Create the cluster project
    3.  Add a pod to the cluster
    4.  Compile the pod
    5.  Sync the cluster locally
    6.  Run the Daemon to manage the pods
    7.  Update pods and re-sync to Cluster
    8.  Add Proxy and Ingress
    9.  Setup your development work flow

### 1. Installing all necessary programs
See [INSTALLING.md](INSTALLING.md) for instructions on installing `snt, `sntd`, `podc` and `podman`.  

### 2. Setup a dev cluster
Let's create our first dev cluster inside a new directory and give it the id `dev-cluster`.
```sh
mkdir snt-1
cd snt-1
snt create-cluster dev-cluster
cd dev-cluster
```

You stricly don't have to create the `snt-1` directory, but we will need it later (hint: it is a _Management Project_), so please do create it.

We now have three files in the cluster:  

    - `cluster-id.txt` which contains the cluster ID provided to `init`.
    - `cluster-vars.env` a key-value file which still is empty, but can have cluster-wide variables.
    - `log.txt` which is a log file storing all operation done on the cluster.

You can change the cluster ID at this point directly in `cluster-id.txt`, but doing it later is not recommended.

Now, let's create a Host which is not a Virtual Machine but instead refers to our laptop, the second argument "local" states that this is a local disk host  
```sh
cd dev-cluster
snt create-host my-laptop -j local
```
This will create a directory `my-laptop` which represents the Host. Inside the directory there will be two files: 

    - `host.env`, a key-value file containg the variables needed to connec to to the host.
        The variable `HOSTHOME` dictates where on the Host files will get copied to when syncing the cluster repo with the remote cluster. For hosts which have JUMPHOST=local this is the directory on your laptop to where pods will get synced.
        This means that if simulating many Hosts on the same laptop they will need different HOSTHOME settings.
    - `host.state`, a simple file which can contain the words `active`, `inactive` or `disabled`, and tells Simplenetes the state of this Host.
        A disabled host is ignored, an inactive host is still being managed by `snt` but will not be part of the ingress configuration.

Now we need to "init" this host, so it belong to our cluster. This will create the `HOSTHOME` directory `${HOME}/cluster-host` on your laptop.

From inside the `dev-cluster` dir, type:  
```sh
snt init-host my-laptop
```

Look inside the `${HOME}/cluster-host` dir and you will see the file `cluster-id.txt`. This is the same file as in the cluster repo you created earlier.

Do not ever edit anything by hand inside the (remote) `cluster-host` directory, all changes are always to be synced here from the cluster project using `snt`.

Note: On a remote Host we would also want to install the Simplenetes Daemon `(sntd)` onto it. The Daemon is the process which manages pod lifecycles according to the state the pod is supposed to have.

### 3. Add a pod to the cluster
When compiling new pod versions into the cluster, we need access to the Pod project and the pod specifications in there.

To do this we can set the `PODPATH` env variable to point to the parent directory of where pod projects are located. The default is to look in `../pods`, which suits us fine when using a Management Project to manage our cluster because we simply add our pods directly inside the Project directory.

If you have another place for all your pods, you can set the `PODPATH` env variable to point there instead of using the default `../pods`

From inside the `snt-1` dir, type:  
```sh
mkdir pods
cd pods
git pull github.com/simplenetes/nginx-webserver webserver
```

Now the pod is accessible to snt, so let's add it to the cluster.

Note that a Pod is always attached to a specific Host, one or many. In Kubernetes in general pods are not bound to a specific Host, however in Simplenetes this is a design decision that the operator attaches a pod to one or many specific Hosts.

From inside the `dev-cluster` dir, type:  
```sh
snt attach-pod webserver@my-laptop
```

Simplenetes says that:  
```sh
[INFO]  This was the first attachement of this pod to this cluster, if there are configs you might want to import them into the cluster at this point.
```

Some background on this: Some pods have `configs`. Configs are directories which are deployed together with the pod and the pod's container can mount them.
If a Pod is using configs, then it could provide initial/template configs in the `config` dir in it's pod repo and we can import those into the cluster where we then tailor the configs for this specific cluster.
Configs from a Pod are isually only imported once to the cluster, since they are treated as templates not as live configurations.
The configs can be edited after have been imported to the cluster project and they can be pushed out onto existing pod releases.

We import the pod template configs into the cluster below.  
From inside the `dev-cluster` dir, type:  
```sh
snt import-pod-config webserver
```

Now the `config` dir from the webserver pod repo will have been copied into the cluster repo as `./\_config/webserver/config`.
These configs we now can tune and tailor to the needs of the cluster. Every time a pod is compiled the configs from the cluster will be copied to each pod release under each Host the pod is attached to.

There is one last configuration we will need to make for when attaching this pod. If you look in the `pod.yaml` file in the webserver pod you can see two variables: `${HOSTPORTAUTO1}` and `${clusterPortWebserver}`.
These variables are defined in the `pod.env` file alongside the `pod.yaml` file and they are used when compiling single pods which are not attached to a cluster repo. However, when using pods in a cluster we need to define those variables in the cluster-wide `cluster-vars.env` file instead. The `pod.env` file will be ignored when attaching pods to clusters.

There is one special case of variables and that is those who look like `${HOSTPORTAUTOxyz}`, those we will not define in `cluster-vars.env` because Simplenetes will assign those values depending on which host ports are already taken on each Host. So we simply leave out `${HOSTPORTAUTO1}` and just add `${clusterPort}` with the pod name as prefix, as:  

From inside the `dev-cluster` dir, type:  
```sh
echo "webserver_clusterPort=2020" >>"cluster-vars.env"
```

All variables for pods which get defined in the cluster wide `cluster-vars.env` file must be prefixed with the pod name, this is to avoid clashes of common variable name, however variable names which are all `CAPS` are not to be prefixed and are treated as globals, this is because some variables should be shared between pods, such as the `DEVMODE` variable.

Clusterports are used to map a containers port to a cluster-wide port so that other pods in the cluster can connect to it.
Note that the same `clusterPorts` are usually not shared between different pods, but often between different version of the same pod.  
Cluster ports come in the range of `abc-xyz`.

### 4. Compile the pod
From inside the `dev-cluster` dir, type:  
```sh
snt compile webserver
```

At this point you can see in `dev-cluster/pods/webserver/release/0.0.1/` that we have the compiled `pod`, the `pod.state` which dictates what state the pod should be in and the `config` dir which holds all configs.

### 5. Sync the cluster locally
After we have updated a cluster repo with new pod release (or updated configs for an existing release) we can sync the cluster repo to the Cluster of Hosts.

This is done in the same way regardless if your cluster is your laptop or if it is a remote Cluster of many Virtual Machines.

Since Simplenetes adheres to GitOps principles it is very strict about the cluster repo is committed before syncing.

From inside the `dev-cluster` dir, type:  
```sh
git add .
git commit -m "First sync"
snt sync
```

Now, look inside the local `HOSTHOME` to see the files have been synced there:  
```sh
cd ${HOME}/cluster-host
ls
```

You will now see another file there: `commit-chain.txt`, this file contains all git commit hashes all the way back to the initial commit, it serves as a way to manage the scenario when the cluster is being synced from multiple sources at the same time so that an unintentional rollback is not performed.

Also when syncing, a `lock-token` is placed in the directory to make sure no concurrent syncing is done.

### 6. Run the Daemon to manage the pods
In a real Cluster the Daemon will be running and would by now have picked up the changes to the Host and managed the effected pods.

Since we are running this on the laptop in dev mode, we won't install the Daemon into systemd (although you could), we will start it manually instead.

Start the Daemon in the foreground to manage the pods.
```sh
cd ${HOME}/cluster-host
sntd .
```

Start the daemon as `root` or with `sudo` if you want proper ramdisks to be created.
Note: Do not start the daemon as root without any arguments because then it starts as a system daemon.

The Daemon should now be running and it will react on any changes to the pods or their configs.

How can we `curl` to the pod? Remember that the `pod.yaml` has a `clusterPort` configured? That means the pod will be reachable on in the Cluster on that port, as soon as we setup the internal Proxy. However we want to try it out now, so we can go straight to the given `hostPort` of the pod. Remember the `${HOSTPORTAUTOx}`? This will be a automatically generated port number in the high ranges. We can't know on beforehand what it is, because it will be the first non-taken port on the Host.

We can find out what it is. Locate the directory in your cluster repo where the `pod` file is:  
```sh
cd dev-cluster/my-laptop/pods/webserver/release/<version>
cat pod.proxy.conf
```

We will get an output such as:  
```sh
2020:30000:4096:false
```

The first field is the clusterPort, the second field is the hostPort, the third fields is the max connections, the last field is weather the container accepts proxy-protocol or not.

```sh
curl 127.0.0.1:30000
```

### 7. Update pods and re-sync to Cluster
There are two ways a pod can be updated, either when its version number has been bumped which then requires a recompile and redeploy of that pod, or if only configs of the pod has been updated, then it can be enough to update the configs of an already released pod.

We will first go through the process of updating the configs of a pod.
We will be updating the contents of the nginx server, but please note that configs should preferably not be used for content but for configurations, however for this tutorial it shows how it is done by using content.

```sh
cd dev-cluster/_config/webserver/nginx-content
echo "Hello Again!" >>index.html

# At this point we should to commit our changes.
git add _config/webserver
git commit -m "Update webserver configs"
```

```sh
# This will copy the config into the lest released pod on each Host it is attached to.
# Note that the version number is implicit as "snt webserver:latest". `snt` will find the latest released version (it will ignore any prerelease version such as "0.1.0-beta1").
cd dev-cluster
snt update-config webserver
```

We need to commit our changes before we sync:  
```sh
cd dev-cluster
git commit my-laptop/pods/webserver -m "Update webserver configs"

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
cd dev-cluster/_config/webserver/nginx-content
echo "Hello from a new version!" >>index.html

# At this point we should to commit our changes.
git add _config/webserver
git commit -m "Update webserver configs"
```

Let's compile this new version:  

```sh
cd dev-cluster
snt compile webserver
```

We need to commit our changes before we sync:  
```sh
cd dev-cluster
git add my-laptop/pods/webserver
git commit -m "Add webserver release"

# Let's sync
snt sync
```

Find the hostPort of this new pod in the same way as before.

Alright, now you have two versions of the same pod running. Both these pods will be sharing any incoming traffic from the cluster since they use the same clusterPort (but we still haven't added the proxy or the ingress pod, so no incoming traffic in that sense).

If we are happy with our new release, we can then retire the previous version. In this case we *must* provide the pod version we want to retire, sine the default is to use the latest release if no version if given.

```sh
cd dev-cluster
snt set-pod-state webserver:0.0.1 -s removed
```

We need to commit our changes before we sync:  
```sh
cd dev-cluster
git add my-laptop/pods/webserver
git commit -m "Retire old version"

# Let's sync
snt sync
```

You should now be able to see that the first pod is not responding on requests anymore.

### 8. Add Proxy and Ingress
To be able to reach our pod as it was exposed to the internet we need to add the ProxyPod and the IngressPod.

A special thing about the IngressPod is that it most often binds to ports 80 and 443 and ports below 1024 are root only, so this requires that podman is properly setup to allow for users to bind to ports as low as 80 for the Ingress to work.
Note that ingress for pods can be configured to bind to other ports from 1024 and above, if needed.

```sh
cd pods
git pull github.com/simplenetes/ingress
```

In a proper cluster we would attach the IngressPod to the hosts which are exposed to the internet att have DNS pointed to them.  

```sh
cd dev-cluster
snt attach-pod ingress@my-laptop
```

We need to import the config templates from the pod because they are needed by `snt` when generating the `haproxy` configuration.  

```sh
cd dev-cluster
snt import-pod-config ingress
```

Let's generate the haproxy ingress configuration for this cluster:  
```sh
cd dev-cluster
snt generate-ingress
```

You can inspect the generated `haproxy.cfg` if you are curious, it is inside `\_config/ingress/conf`.  

```sh
cd dev-cluster
snt compile ingress
```

Note: the next time we need to regenereate the ingress config, then we follow the pattern of updating configs for already released pod versions.

The ingress will proxy traffic to clusterPorts in the cluster, it connects to pods in the cluster just as any other pod would do.
In order to allow for pods to talk to each other we need to add the `ProxyPod` to the cluster.

The ProxyPod is also a special pod, because it runs no containers, but instead a native executable. However since it adheres to the Pod API it is still treated and managed as a Pod.

The reason the ProxyPod runs natively on the Host is that it binds so many ports that it is more efficient to skip the extra layer of running a container.

```sh
cd pods
git pull github.com/simplenetes/proxy
```

The ProxyPod should be attached to every Host in the Cluster, in our case it is only `my-laptop`.

```sh
cd dev-cluster
snt attach-pod proxy@my-laptop
```

```sh
cd dev-cluster
snt import-pod-config proxy
```

```sh
cd dev-cluster
snt compile proxy
```

We need to commit our changes before we sync:  
```sh
cd dev-cluster
git add my-laptop/pods
git commit -m "Add Ingress and Proxy"

# Let's sync
snt sync
```

Now let's test to access the pods through the Ingress:  
```
curl 127.0.0.1/hello/
```

### 9. Setup your development work flow
Now that we have the local dev-cluster setup, we can simulate all the pods and as they are communicating inside the cluster, locally.

If simulating the production environment, then you will be building new image version for each update of a pod, which in dev mode is not very efficient. So what we can do instead is to reuse the pattern of when working with a single local pod and mount build directories of the project.

To do this we adjust the env variables in the `cluster-vars.env` file so that build files are mounted into the containers.
