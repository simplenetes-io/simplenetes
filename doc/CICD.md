# Setting up CI/CD for your cluster

**WORK IN PROGRESS**

The point of CI/CD is to have an automated release flow. There are many ways of achieving this in Simplenetes, what we want to do in the end is to perform an `sns cluster sync`, but the interesting questions are how do we get to that point.

The release pipeline can potentially be run in three different places:  

    -  from the Pod repo
    -  from the Cluster Project repo or,
    -  from the Management Project repo

Most often the release pipeline is run from the Pod repo, because we want to swiftly release a new pod version when it is pushed.

Releasing from Cluster Project repo pipelines and from Management Project repo pipelines are very similar to each other. The difference is merely if you have extracted the SSH keys out from the Cluster Project into the Management Project or not.

## Release directly from within the Pod repo pipelines
The pro's of this approach is that it is straight forward and we can get a fully automated release cycle.

The cons are that the pod project will need access to cluster keys to make the sync; which in many cases is not an issue because the Dev and The Ops people are the same people.
Another con is that we don't want to release many pods simultaneously because it might cause a branch out of the cluster repo and some releases might then get rejected.

This is an example pipeline which is triggered whenever the pod repo pipeline has performed a new build and tagged it for release:  

```sh
set -e

# Install sns, podc
# TODO

# We expect to be put inside the git repository directory of the pod.
podname="${PWD##*/}"
cd ..

# The cluster project is expected to exist and already have the pod "attached" and any configs imported already.
git clone "${clusterUrl}" .cluster  # Clone to a name we know will not clash with any pod name, hence the dot.
cd .cluster
export PODPATH="${PWD}/.."
export CLUSTERPATH="${PWD}"

# Let sns perform all release steps for a zero downtime version overlapping release.
# In the soft release patterns both the new and the previous versions of the pod are running simultanously as the ingress switches over the traffic to the new release and the removes the previous release(s).
# Perform a "soft" release and push all changes to the repo continously.
sns pod release "${podname}" -m soft -p
```

## Release from the Cluster/Management project repo pipelines
The pro's are that we can separate access to the pod repo from access to the SSH keys and that we can release a number of pods simultaneously.

The con's are that the pipelines need to be triggered in some way (manually) to be run when a new pod version has been pushed to the pod repo.
Also that we need to pull the new pod and possibly the cluster project if this is a management project, so it involves a few more steps to get it going.

The process for Cluster Project and Management Project are almost the same, we'll see the cluster project here:  
```sh
set -e

# Install sns, podc
# TODO

# We expect to be put inside the git repository directory of the cluster project.
# The cluster project is expected already have the pod "attached" and any configs imported already.
# If doing this for a Management Project, we would at this point clone the cluster project.

export CLUSTERPATH="${PWD}"
export PODPATH="${PWD}/../pods"

cd ..
mkdir pods
cd pods
git clone "${podUrl}" "${podname}"
cd "${podname}"
git checkout "${podCommit}"
cd "${CLUSTERPATH}"

# Perform a "soft" release and push all changes to the repo continously.
sns pod release "${podname}" -m soft -p
```
