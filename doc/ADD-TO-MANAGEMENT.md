# Add a cluster project to a management project
If you followed the previous chapter about creating a production cluster, you can now see how we can "up" the management by adding it to a management project.

A Management Project is simply a parent directory of a Cluster Project. This directory can hold many cluster projects and it can also hold personal SSH keys which are abstraced out of the cluster projects.

These are the benefits of using a Management Project:

    1.  Managing SSH keys on a personal level, detached from Cluster Projects
    2.  Having a common place for Pods being used in different clusters, such as dev, staging and production
    3.  Enabling CI/CD practices while keeping control over keys, to not necessarily share them with all developers
    4.  There is no change in how you manage a cluster belonging to a management project and not

Table of Contents:

    1.  Create your Management Project
    2.  Add Cluster Project
    3.  Extract keys from Cluster Project
    4.  Add Pods to the mix

## 1. Create Management Project
```sh
mkdir mgmt-1
cd mgmt-1
git init
```

## 2. Add Cluster Project
The best way to add cluster projects is to add it as a git submodule. In this way it is easy to sync and share them with others, and it is also a requirement for automated CI/CD to work.

```sh
git submodule add <path-to-cluster-repo>
git submodule init
git submodule update
```

## 3. Extract keys from Cluster Project
```sh
cd mgmt-1
mkdir keys
```

For each host in the cluster project, move the keys to the `./keys` directory in the management project and update the `host*.env` files so that the path to the `KEYFILE` is `../../keys/keyfile`.  
Either you keep separate directories for all keys, or you rename the keys and heve them in the same directory.

## 4. Add Pods to the mix
All pod projects should be in the `./pods` directory in the management project directory. This is the default place for `snt` to look for pods `(../pods)`.
