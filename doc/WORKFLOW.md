# Workflow for working with your development and releases

Following is an example of how you might go by getting started with Simplenetes and getting into a productive workflow.

One of the tricky parts of working with micro services is how to run, develop and test it locally.

For example working with a single NodeJS process it is common to run it straight on the OS and not in a container, when developing. But when one NodeJS process needs to communicate with another process, as micro services are designed to do, it can start getting tricky and messy running all processes outside of containers.

With Simplenetes we can with little efforts run local clusters which mimic your micro services architecture (but running on your laptop) and stay in a snappy workflow as when working outside of containers.

If you are developing a single project which does not leverage any other micro service which you need to run locally, then you could use the OnePod development workflow for developing that service, see [FIRSTPOD.md](FIRSTPOD.md). Then when you want to try it out in your local cluster you can step into this type of process.

The trick in working with a dev-cluster locally in development mode is to set the `DEVMODE=true` variable in `cluster-vars.env`. In the `pod.yaml` this should make the pod mount a the build directory for your projct. The build path should also be defined in `cluster-vars.env` so that each developer can have their customer path.

So when a pod is compiled and synced to the "cluster", which is just another directory on your laptop that pod can still mount the build directory and be always up to date on changes.

Some service might need to get signalled to properly reload updates, for example when updating a `nginx.conf` file the nginx process needs to get a `SIGHUP`. If the pod has properly configured signals then it is ieasy to do `snt signal podname` to signal a pod.
