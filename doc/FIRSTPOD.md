# Creating your first pods using Simplenetes

A Pod is described in a _YAML_ file and is compiled into a single executable, which can be run as long as podman (version >=1.8.1) is installed.

In this HOWTO we will create our first pods and see how easy it is to manage their lifecycles using the standalone executable.

This is a crash course on how to work with pods, see [https://github.com/simplenetes-io/podc/tree/master/examples](https://github.com/simplenetes-io/podc/tree/master/examples) to learn all about pods.

## Installing
See [INSTALLING.md](INSTALLING.md) for instructions on installing the pod compiler `podc` and `podman`.

## Create a website pod
A very common scenario is to create a website. Let's do that.

First, let us just create the simplest pod possible, before we move on to working with pods in development mode.

### Quick Pod
Cop the below _YAML_ and put it in a file called `pod.yaml`.

```sh
mkdir mypod1
cd mypod1

cat >pod.yaml <<EOF
api: 1.0.0-beta1
podVersion: 0.0.1
runtime: podman
containers:
    - name: webserver
      image: nginx:1.16.1-alpine
      expose:
          - targetPort: 80
            hostPort: 8181
EOF

podc
./pod run
./pod status
curl 127.0.0.1:8181
./pod logs
./pod rm
```

The above is a simple and quick way to create a pod. And could be all we need to do if we just want to use an existing image and run it.

However, we want to see how to develop an application living inside a pod, that's what we are looking at next.




### Pods in development

We will see how to create a pod which we also want to work with in development mode when developing our application locally.

When developing a website, one can use many different backend servers and build technologies, be it nginx, hugo, expressjs, jekyll, Make, webpack, etc.

It is often the case that developers run their projects without using containers when in development mode, but when using Simplenetes it is very straight forward to always run in containers. In this way development resembles production environment much better.

Simplenetes has a simple way of separating between processes such as _development_ and _production_ mode for when working with pods by using a basic _preprocessor_.
As we will see in the `pod.yaml` below.

This is our pod YAML. Copy it and save it as `pod.yaml` (detailed instructions below).  

`pod.yaml`:  
```yaml
api: 1.0.0-beta1
podVersion: 0.0.1
runtime: podman

#ifdef ${DEVMODE}
volumes:
    - name: nginx_content
      type: host
      bind: ./build
#endif

containers:
    - name: webserver
#ifndef ${DEVMODE}
      image: webserver:0.0.1
#endif
      restart: always
      signal:
          - sig: HUP
#ifdef ${DEVMODE}
      image: nginx:1.16.1-alpine
      mounts:
          - volume: nginx_content
            dest: /nginx-content
      command:
          - nginx
          - -c
          - /nginx-content/nginx.conf
          - -g
          - daemon off;
#endif
      expose:
          - targetPort: 80
            hostPort: 8080
```

Save the following as file `pod.env` alongside the `pod.yaml` file:  
```sh
DEVMODE=true
```

The blocks inside the _YAML_ between `#iftrue ${DEVMODE} / #endif` will only be present when `DEVMODE=true` in the `pod.env` file. The reverse is of course true for the _if not true_ `#ifntrue` directive.  

Using these simple preprocessor directives we can easily switch our pod between dev and production mode.  
When attaching a pod to a cluster project and compiling it targeting the cluster, this local `pod.env` file is ignored and values are instead read from a cluster-wide `.env` file, so there is no need in changing the `DEVMODE` value from `true` to `false` in the `pod.env` file.

Create a pod directory, a `pod.yaml` and a `pod.env` file as:  
```sh
mkdir mypod2
cd mypod2

cat >pod.yaml
<ctrl-v to paste the YAML you copied from above, hit enter>
<ctrl-d>

echo "DEVMODE=true" >pod.env
```

The pod (in devmode) will mount the `./build` directory. This directory is expected to have _nginx_ content files.  

The generation of the nginx content files are at the discretion of the website projects build process. We will manually create the files in this example.

Create these two files in `./build/ and `./build/public`, respectively:  

Save as file `./build/nginx.conf`:  

```nginx.conf
user  nginx;
worker_processes  auto;

error_log  /dev/stderr warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    types {
        text/html                   html htm shtml;
        text/css                    css;
        image/gif                   gif;
        image/jpeg                  jpeg jpg;
        application/javascript      js;
        image/png                   png;
    }

    default_type  text/html;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /dev/stdout  main;

    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;

        location / {
            root   /nginx-content/public;
            index  index.html;
        }
    }
}
```

Save as file `./build/public/index.html`:  
```
Hello world!
```

Detailed instructions how to save the files:  

```sh
mkdir -p build/public
cat >./build/nginx.conf
<ctrl-v to paste the nginx.conf you copied from above, hit enter>
<ctrl-d>

cat >./build/public/index.html
<ctrl-v to paste the index.html you copied from above, hit enter>
<ctrl-d>
```

Now our pod is setup and it can be compiled.  

```sh
podc
```

`podc` will generate an executable file called simply `pod`.

At this stage you can observe the resulting _YAML_ from after the preprocessor stage by looking in the file `.pod.yaml`.

Let's try and interact with the executable:  
```sh
./pod help
./pod info
./pod status
```

Let's run the pod:  
```sh
./pod run
```

If you see the error message
```
[ERROR] Host port 8080 is busy, can't create the pod mypod2-0.0.1
```

Then adjust the `expose/hostPort` value in the `pod.yaml` to a free port and recompile.

```sh
# Curl it
curl 127.0.0.1:8080
```

You should now see  
```sh
Hello world!
```

Check the logs:  
```sh
./pod logs
```

Now you can update the contents of the `./build` directory at your development process's discretion. In this case since using `nginx`, if you are updating the `nginx.conf` file the nginx process needs to be signalled so it can reload the workers. This is easy to do:  
```sh
./pod signal
```
This will signal nginx to reload the configuration.

How signals for pods are configured are specified in [https://github.com/simplenetes-io/podc/PODSPEC.md](github.com/simplenetes-io/podc/PODSPEC.md)



#### Pods in development and production
How would we go about moving this Pod from production to release?

We will now see a complete pod setup which can work both with development and release processes.

Let's call this `mypod3`.
```sh
mkdir mypod3
cd mypod3
```

Create the following files inside the directory. It is the same as above, but with some added preprocessing directives and cluster port configurations.

`pod.yaml`:  
```yaml
api: 1.0.0-beta1
podVersion: 0.0.1
runtime: podman

#ifdef ${DEVMODE}
volumes:
    - name: nginx_content
      type: host
      bind: ./build
#endif

containers:
    - name: webserver
#ifndef ${DEVMODE}
      image: webserver:0.0.1
#endif
      restart: always
      signal:
          - sig: HUP
#ifdef ${DEVMODE}
      image: nginx:1.16.1-alpine
      mounts:
          - volume: nginx_content
            dest: /nginx-content
      command:
          - nginx
          - -c
          - /nginx-content/nginx.conf
          - -g
          - daemon off;
#endif
      expose:
          - targetPort: 80
#ifdef ${DEVMODE}
            # This property will be set when compiling in dev mode.
            # The variable will be read from the pod.env file.
            hostPort: ${HTTP_PORT}
#endif
#ifndef ${DEVMODE}
            # These properties are only set when NOT in dev mode.
            # HOSTPORTAUTO and CLUSTERPORTAUTO are port numbers which
            # will be automatically set when releasing in the cluster.
            hostPort: ${HOSTPORTAUTO1}
            clusterPort: ${CLUSTERPORTAUTO1}
            sendProxy: true
            maxConn: 1024
#endif

```

`Dockerfile`:
```Dockerfile
FROM nginx:1.16.1-alpine
COPY ./build

```

With this setup you can have a pod working for local development but also which can be released properly into a cluster.

Your build process should aim at building a docker image which is tagged and pushed properly, then the `pod.yaml` `image` value needs to be set to that new image version.

    1.  Create a Dockerfile to build the image
    2.  Build the content into `./build`
    3.  Build, tag and push the image
    4.  Update the pod.yaml to reflect the new image version.
        Note that you cannot put the image version in the `pod.env` file, it has to be "hardcoded" into the `pod.yaml` file.
        This is because the `pod.env` file does not tag along into the cluster project when the pod is compiled.
    5.  Git commit and push the changes.
    6.  In your cluster or management project (attach and) compile the pod.
