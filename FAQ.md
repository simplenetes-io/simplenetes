Q. Can I change the cluster-id.txt file in my project?
A. You can. Then you will need to run `snt init-host -f` on every host in the cluster.

Q. Can I change the HOSTHOME variable on the `host.env` file?
A. Not a good idea. You would first need to put all pods on the host to 'removed' state, sync the changes, then change the HOSTHOME, run `snt init-host -f`, then resync the cluster. You should also remove the old HOSTHOME dir on the host.
You could after removing all pods instead move the old HOSTNAME to the new HOSTHOME, to preserve logs.

Q. Can I work with multiple hosts on my local dev cluster?
A. You can, however it will require some precautions while configuring.
The `HOSTHOME` for the hosts must of course not be the same, otherwise there will be conflicts when syncing.
The more trickier part to solve is that host ports and cluster ports must not interfere between the different "hosts", since in reality there is only one host.
This would require that all ports are set manually in `cluster-vars.env` and not be set using auto assignments.

Q. Can I work with multiple dev cluster on my laptop at the same time?
A. No, if wanting the internal proxy for communication amongst pods.
There are ways to configure around this, also the precautions about interfering ports applies. At this stage you should just spin up a local VM instead and run each cluster in its separate VM.

Q. How can I configure to run multiple proxies on the same host?
Make the proxy pod listen to another port and configure each host.env so it's `ROUTERADDRESS` reflects the port change.
