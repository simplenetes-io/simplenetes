# About Management Projects

**WORK IN PROGRESS**

A management project is a parent directory of one or many cluster projects.
The benefits of using a management cluster is that one can work with both a dev cluster, staging cluster and a prod cluster in the same place where the same pods can easily be accessed.

Using a management project SSH keys can be extracted out of the cluster projects, which has the benefit so that different operators do not need to share the same keys.

When wanting to setup an automatic CI/CD process for the release of new pods, that can be achieved without needed to let pod developers have access to any sensitive keys for the actual release to the cluster.

To leverage management projects, put your cluster project inside of it (git clone).
Then extract keys into `./keys` from the cluster project, and modify the `host.env` file search path for keys.

Important note, do not commit a cluster project until you have moved out the keys, since the keys will be in the git history.
