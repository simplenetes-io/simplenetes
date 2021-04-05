# Installing Simplenetes

There are three main components of Simplenetes which need to be installed:

    1.  The Management Tool, called `sns`
    2.  The Pod compiler, called `podc`
    3.  The Daemon, called `simplenetesd`

To manage a cluster, at least the `sns` tool needs to be installed on your laptop.
If managing the cluster also means compiling pods to create new releases then also `podc` needs to be installed.  
The Daemon `(simplenetesd)` should always installed on all hosts in your cluster. It can also be installed locally on your laptop to simulate working on a cluster.

## Prerequisites
To run pods locally you will need `podman version>=1.8.1` installed and `slirp4netns` to run pods as rootless. To install Podman and slirp4netns please refer to the official documentation: https://podman.io/getting-started/installation
Alternatively, check your distribution's package manager. It's usually not more complicated than `sudo pacman -S podman`.

Since Podman being root-less we want to allow non-root users to bind ports from 80 and upwards.
This row should be put into 1/etc/sysctl.conf`:  
`net.ipv4.ip_unprivileged_port_start=80`


## Installing `sns`
`sns` is a standalone executable, written in POSIX-compliant shell script and will run anywhere there is Bash/Dash/Ash installed.
It interacts with a few programs in the OS, such as `grep`, `awk`, `date` and others. The usage of these tools is tailored to work under both Linux and BSD variants such as OSX. It might even run under Windows WSL.

Install straight from GitHub, as:  
```sh
wget https://raw.githubusercontent.com/simplenetes-io/simplenetes/0.3.3/release/sns
chmod +x sns
sudo mv sns /usr/local/bin
```
NOTE: Check the latest tag on GitHub to get the latest version.

## Installing `podc`
See [https://github.com/simplenetes-io/podc/blob/master/README.md#install](https://github.com/simplenetes-io/podc/blob/master/README.md#install).


## Installing `simplenetesd`
`simplenetesd` is a standalone executable, written in POSIX-compliant shell script and will run anywhere there is Bash/Dash/Ash installed.
The Daemon should always be installed onto the GNU/BusyBox/Linux Virtual Machines making up the cluster.  

It can also be installed onto your GNU/BusyBox/Linux laptop to simulate working on a cluster.  
When installing it locally it does not have to be installed as a Daemon, but can instead be run in user mode as a foreground process.

The Daemon activates the pod scripts which uses `podman` to run containers.

To provision new hosts and clusters, and to install `simplenetesd` on a server please see [PROVISIONING.md](PROVISIONING.md).  

To install `simplenetesd` locally to use it for development, do:
```sh
wget https://raw.githubusercontent.com/simplenetes-io/simplenetesd/0.6.1/release/simplenetesd
chmod +x simplenetesd
sudo mv simplenetesd /usr/local/bin
```

Note that the version "0.6.1" might be old when reading this.
