# Provisioning a prod-cluster on a host provider of choice

Provisioning a cluster is s easy as:  

    1.  Setup your Simplenetes production cluster project
    2.  Create one or many virtual machines
    3.  Let Simplenetes setup the machines
    4.  Maintaining your hosts

## 1.  Setup your Simplenetes production cluster project
Before we create any actual virtual machines, we create it's representation on disk as a Cluster Project. This is also they way to go if you already have existing machines you want to be part of your cluster.

```sh
snt create-cluster prod-cluster
cd prod-cluster
echo "production-cluster-1" >cluster-id.txt

# Create the loadbalancer host
snt create-host loadbalancer1

# Create a worker host, using the loadbalancer1 as jumphost
snt create-host worker1 -j "../loadbalancer1"
```

Each host is created as a sub directory inside the cluster project. Each host has a new `id_rsa` key generated and a `host.env` vars file created which we will need to fill in the details for as soon as we have created the virtual machines.

## 2. Create our Virtual Machines
There are many ways to accomplish this, both in automated fashions but also manually. In both cases the only important things to know is to:  

    -   Create a virtual machine for each one created in the cluster project (a $10 machine is most often enough)
        Create it with a CentOS image. Other images can work also, important thing is that it is a GNU/Linux box using systemd as init system and that Podman can be installed onto it.
        CentOS and Podman both coming from RedHat makes a reliable combo.
        Create the machine with internal networking/private IP enabled.
    -   Make sure all loadbalancers are exposed to the public internet.
    -   Make sure worker machines are not exposed to the public internet, but only on the internal network.
    -   Create the _sntpower_ user and the _snt_ user using the `snt` command.
    -   Install podman and cofigure the machine.

We will show how to manually create a small cluster consisting of one loadbalancer and one worker machine on Linode.
We will also use the loadbalancer1 as our _backdoor_ machine. A backdoor machine is an entry point into the cluster for our management tools. We want this because we want to keep the worker machines unexposed to the public internet but at the same to we need to access them via SSH. Another name for a _Back door host_ host would be a _Jump host_.

Preferably the _Back door host_ is not exposed to DNS names and therefore not necessarily known to any attacker. In this example we use the loadbalancer as back door, because that saves us one machine.

### Create virtual machines on Linode by hand

Steps:  

    1.  Login to Linode
    2.  Create the loadbalancer1 machine (a $10 machine is enough)
        -   Use CentOS8 as operating system
        -   make sure PrivateIP is checked
        -   Set a root password, root login will later be disabled
        -   Label/tag the machine properly
    3.  Copy the Public IP addresses from the dashboard to the `host.env` file as the HOST variable.
    4.  Create the worker1 machine (a $10 machine is enough)
        -   Use CentOS8 as operating system
        -   make sure PrivateIP is checked
        -   Set a root password, root login will later be disabled
        -   Label/tag the machine properly
    5.  Copy the *Private IP* addresses from the dashboard to the `host.env` file as the HOST variable.

Only difference between creating the loadbalancer and the worker machines is that for worker machines refer to the private IP as HOST.

Make sure you have the root passwords available, you will need them in the following steps.

## 3. Let Simplenetes setup the machines
Now that we have the actual machines created and our `host.env` files setup, we can use Simplenetes to provision the machines for us.
Simplenetes can prepare the machines by running a few commands for each host.

Create the superuser we will use for the rest of the provisioning process. If your cloud provider creates a superuser for you then set that SUPERUSER in the `host.env` file and save that SSH key as `id_rsa_super`, and you can skip the two following steps:  
```sh
snt create-superuser loadbalancer1
```

Now that we have the superuser setup, we disable the root account:  
```sh
snt disable-root loadbalancer1
```

If you already have a machine you want to use, you could set the username in the `host.env` file as `USER` and save the SSH key file as `id_rsa`.  
If the user and keyfile does not exist, they will be created by this command.

Using the superuser account we provision the host by installing podman, creating the regular user and performing configurations. The `EXPOSE` variable in the `host.env` file states which ports should be open to the public. This is then configured using `firewalld` (it it is installed):  
```sh
snt setup-host loadbalancer1
```

Using our regular user we now init the host as part of the cluster by setting the `cluster-id.txt` file on the host. If you are using an existing host this step you will always want to run, otherwise sync will not work because it cannot recognize the host as being part of the cluster:  
```sh
snt init-host loadbalancer1
```

Now we do the same steps for the `worker1` machine.

Note that the `worker1` machine is using the `loadbalancer1` machine as its _JUMPHOST_, so we need to set them up in this order.

## 4.  Maintaining your hosts
You can easily enter all your hosts by following these steps:  

    1.  cd into the directory of the host
    2.  To enter as the regular user, issue command:
        space -m ssh /ssh/ -e SSHHOSTFILE=host.env
    3.  To enter as the super user, issue command:
        space -m ssh /ssh/ -e SSHHOSTFILE=host-superuser.env

All keys for the hosts are inside the host directories. We will see later on how you can move them out of there for better security and user isolation.
