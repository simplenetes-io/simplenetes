# About Management Projects
A management project is a parent directory of one or many cluster projects.
The benefits of using a management cluster is that one can work with both a dev cluster, staging cluster and a prod cluster in the same place where the same pods can easily be accessed.

Using a management project SSH keys can be abstracted aout of the cluster projects, which has the benefit so that different operators do not need to share the same keys.

When wanting to setup an automatic CI/CD process for the release of new pods, that can be achieved without needed to let pod developers have access to any sensitive keys for the actual release to the cluster.
