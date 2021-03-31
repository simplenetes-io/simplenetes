Q. Why does the proxy (by default) listen to over 61000 TCP ports? This seems like a lot!
A. This is because we opted for a super robust low config proxy with few moving parts and with no syncing of routing tables across the cluster.
   Listening to 61k ports costs about 500 MB extra memory (in addition to the process it self. In informal tests).
   This is the default setting when cluster ports are available between 1024-29999 and 32768-65535.
   This ranges can be configured to be lower if needed, say between 61000 and 63999 (which are the range for auto assigned of cluster ports). Which would then only use about 20 MB of extra memory.

Q. Can I change the cluster-id.txt file in my project?
A. You can. Then you will need to run `sns host init <host> -f` on every host in the cluster.

Q. Can two clusters have the same ID?
A. Yes, but avoid it. The cluster ID is a safety precaution to prevent operating on the wrong hosts by mistake.


Q. What are the variables and which can I manualy change in the `host.env` file?
   HOST - if your host changes IP address.
   PORT - if the host SSH daemon get reconfigured for another port.
   USER - if the user on the host gets renamed.
   FLAGS - these are SSH flags which you can add, space separated.
   KEYFILE - path to the SSH keyfile
   JUMPHOST - if needed to jump via a host to reach the target host. This is the name of another host in your cluster.
   HOSTHOME - directory on host where to we sync files. Don't change this.
   EXPOSE - space separated list of port numbers to expose to the public internet. If not using JUMPHOST YOU MUST HAVE 22 (SSH port) SET. If changed run "sns host setup" again.
   INTERNAL - space separated list of networks treated as internal networks in the cluster. Important so that hosts can talk internally. If changed run "sns host setup" again.
   ROUTERADDRESS - InternalIP:port where other hosts can connect to to reach the proxy pod running on the host. Leave blank if no proxy pod is running on the host. If changed it will get propagated on the next "sns cluster sync".

Q. Can I change the HOSTHOME variable on the `host.env` file?
A. Not a good idea. You would first need to put all pods on the host to 'removed' state, sync the changes, then change the HOSTHOME, run `sns host init -f`, then resync the cluster. You should also remove the old HOSTHOME dir on the host.
   You could after removing all pods instead move the old HOSTNAME to the new HOSTHOME, to preserve logs.

Q. What are the different hosts states?
A  active, inactive and disabled.
   active - are synced, has ingress generated and are part of internal proxy routing
   inactive - are synced, but has no ingress generated and is not part of internal proxy routing.
   disabled - are not synced, just ignored.

Q. How can a I delete a host?
   set all pods to stopped or removed on the host.
   Set the host to inactive state.
   Regenerate the ingress.
   Sync the cluster.
   Then put the host to disabled state.
   Feel free to delete the host directory if you want to.

Q. Can I work with multiple hosts on my local dev cluster?
A. You can, however it will require some precautions while configuring.
   The `HOSTHOME` for the hosts must of course not be the same, otherwise there will be conflicts when syncing.
   The more trickier part to solve is that host ports and cluster ports must not interfere between the different "hosts", since in reality there is only one underlaying host (your laptop).
   This would require that all ports are set manually in `cluster-vars.env` and not be set using auto assignments.

Q. Can I work with multiple dev cluster on my laptop at the same time?
A. Yes, if not running any pods simultaneously in the different clusters.
   No, if wanting the internal proxy for communication amongst pods and running the clusters at the same time.
   There are ways to configure around this, also the precautions about interfering ports applies. At this stage you should just spin up a local VM instead and run each cluster in its separate VM.

Q. How can I configure to run multiple proxies on the same host?
A. Make the proxy pod listen to another port and configure each host.env so it's `ROUTERADDRESS` reflects the port change.

Q. Can I run the daemon without systemd?
A. Yes, you can run it as it is, if you want ramdisk then you need to run it as root.
   You can run it with other init systems too, the important thing is to have the equivalaent of systemd's `KillMode=process`, so that the pods are not killed if the daemon is restarted.

Q. Why is my data lost when I rerun a pod or a container?
A. Simplenetes pods have no concept of restarting. If a pod is stopped and started again it is a new instance of the pod and its containers, which means any data stored internally in containers is lost.
   To keep state between pod reruns (restarts) you will need to use a volume to store data in.
   Following this pattern will make it easier for you to upgrade pods since non temporary data is never expected to be stored inside any containers.
