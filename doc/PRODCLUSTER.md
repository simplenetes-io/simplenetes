# Attach pods and run then in your prod-cluster

We'll show here how to add some initial pods to get the cluster up and running. Also see the DEVCLUSTER instructions for details on this.

Attach pods:  

```sh
cd prod-cluster
sns host attach ingress@loadbalancer1 --link=https://github.com/simplenetes-io/ingress
sns host attach proxy@loadbalancer1 --link=https://github.com/simplenetes-io/proxy
sns host attach proxy@worker1 --link=https://github.com/simplenetes-io/proxy
sns host attach letsencrypt@worker1 --link=https://github.com/simplenetes-io/letsencrypt.git
sns host attach simplenetes_io@worker1 --link=https://github.com/simplenetes-io/simplenetes_io.git
```

Configure the cluster:  
```sh
cd prod-cluster

# Have the ingress fetch certificates from the letsencrypt pod:
echo "ingress_useFetcher=true" >>cluster-vars.env

# Allow HTTP ingress traffic for the simplenetes_io pod.
echo "simplenetes_io_allowHttp=true" >>cluster-vars.env
```

Compile all pods:  
```sh
sns pod compile simplenetes_io
sns pod compile proxy
sns pod compile letsencrypt
sns pod compile ingress
```

Generate ingress:  
```sh
sns cluster geningress
sns pod updateconfig ingress
```

Sync the cluster:  
```sh
git add . && git commit -m "Initial"
sns cluster sync
```

## Releasing new versions of pods
When the pod.yaml file has an update `podVersion` value we can release that pod.

```sh
sns pod release NAME
```

The manual alternative is much more cumbersome, but could be useful in same cases.

```sh
sns pod compile NAME
sns cluster geningress
sns pod updateconfig ingress
git add . && git commit -m "Update"
sns cluster sync
# Both the old and the new version of the pod are running at the same time and sharing traffic
sns pod ls NAME
sns pod state NAME:oldversion -s removed
sns cluster geningress
sns pod updateconfig ingress
git add . && git commit -m "Update"
sns cluster sync
# The old version is now removed and the ingress updated.
```

## Letsencrypt certificates
Manually edit the file `./prod-cluster/_config/letsencrypt/certs_list/certs.txt` and add all domains there which you need certificates for.
Then we need to update the config of the pod:  
```sh
sns pod updateconfig letsencrypt
git add . && git commit -m "Configure certs"
sns cluster sync
```

## Troubleshooting
These commands are helpful:  

```sh
sns pod info NAME
sns pod ps NAME
sns pod logs NAME
sns pod state NAME
sns pod ls
sns pod shell NAME [container]
sns host shell NAME
```
