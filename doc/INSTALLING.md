# Installing Simplenetes

There are three main components of Simplenetes which need to be installed:

    1.  The Management Tool, called `snt`
    2.  The Pod compiler, called `podc`
    3.  The Daemon, called `sntd`

To manage a cluster, at least the `snt` tool needs to be installed.  
If managing the cluster also means compiling pods to create new releases then also `podc` needs to be installed.  
The Daemon `(sntd)` should always installed on all hosts in your cluster. It can also be installed locally on your laptop to simulate working on a cluster.

## Prerequisites
To run pods you will need `podman version>=1.8.1` installed and `slirp4netns` to run pods as rootless. To install Podman and slirp4netns please refer to your distributions package manager.  

## Installing `snt`
`snt` is a standalone executable, written in Posix complaint shell script and will run anywhere there is Bash/Dash/Ash installed.  
It interacts with a few programs in the OS, such as `grep`, `awk`, `date` and others. The usage of these tools is tailored to work under both Linux and BSD variants such as OSX. It might even run under Windows WSL.

Install straight from GitHub, as:  
```sh
# TODO
wget github.com/simpletenes/snt/release/snt
chmod +x snt
sudo mv snt /usr/local/bin
```

## Installing `podc`
`podc` is also a standalone executable, written in Bash and will run anywhere Bash is installed.  
The reason `podc` is written in Bash and not Posix shell is that it has a built in YAML parser which requires the more feature rich Bash to run.  
Even though `podc` it self is a standalone executable it requires a runtime template file for generating pod scripts. This file must also be accessible on the system.  
`podc` will look for the `podman-runtime` template file first in the same directory as it self (`./`), then in `./release` and finally in `/opt/podc`.  
The reason for that it looks in `./release` is because it makes developing the pod compiler easier.  

In our case we will install the `podman-runtime` file into `/opt/podc`.

Install straight from GitHub, as:  
```sh
# TODO
wget github.com/simpletenes/podc/release/podc
chmod +x podc
sudo mv podc /usr/local/bin

# TODO
wget github.com/simpletenes/podc/release/podman-runtime
sudo mkdir -p /opt/podc
sudo mv podman-runtime /opt/podc
```

## Installing `sntd`
`sntd` is a standalone executable, written in Posix complaint shell script and will run anywhere there is Bash/Dash/Ash installed.  
The Daemon should always be installed onto the GNU/BusyBox/Linux Virtual Machines making up the cluster.  

It can also be installed onto your GNU/BusyBox/Linux laptop to simulate working on a cluster.  
When installing it locally it does not have to be installed as a Daemon, but can instead be run in user mode as a foreground process.

The Daemon activates the pod scripts which uses `podman` to run containers.

To provision new hosts and clusters, and to install `sntd` on a server please see [PROVISIONING.md](PROVISIONING.md).  

To install `sntd` locally to use it for development, do:
```sh
# TODO
wget https://github.com/simpletenes/sntd/releases/tag/1.0.0
chmod +x sntd
sudo mv sntd /usr/local/bin
```
