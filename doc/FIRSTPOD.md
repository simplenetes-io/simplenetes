# Creating your first pod with Simplenetes
A Pod is described in a _YAML_ file and is compiled into single executable, which can be run as long as podman (version >=1.8.1) is installed.

In this HOWTO we will create our first pod and see how easy it is to compile it and manage it's lifecycle using the standalone executable.

We will learn all there is to know about pods.

## Installing
See [INSTALLING.md](INSTALLING.md) for instructions on installing `podc` and Podman.

## Create a website pod
A very common scenario is to create a website. Let's do that.

We will see how to create such a pod, how to work with it in _development mode_ and how to prepare it for release.

When developing a website, one can use many different technologies, be it nginx, nodejs, hugo, expressjs, etc.

It is often the case that developers run their projects without using containers when in development mode. But using Simplenetes it is very straight forward to always run in containers.

Simplenetes has a simple way of distincting between things such as _development_ and _production_ mode for when working with pods using a basic preprocessor.
As we will see in the `pod.yaml` below.

This is our pod YAML. Copy it and save it as `pod.yaml` (instructions below).  

```pod.yaml
apiVersion: 1.0.0-beta1
podVersion: 0.0.1
podRuntime: podman
volumes:
#ifdef ${DEVMODE}
    - name: nginx-content
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
          - volume: nginx-content
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

Save this as `pod.env`:  
```pod.env
DEVMODE=true
```

The blocks inside the _YAML_ between `#iftrue ${DEVMODE} / #endif` will only be present when `DEVMODE=true` in the `pod.env` file. The reverse is fo course true for the _if not true_ `#ifntrue` directive.  

Using these simple preprocessor directives we can easily switch our pod between dev and production mode.  
When attaching a pod to a cluster project and compiling it, this local `pod.env` file is ignored (values are instead read from a cluster-wide `.env` file) so there is no need in changing the `DEVMODE` value from `true` to `false` in the `pod.env` file.

Create a pod dir a `pod.yaml` and a `pod.env` file:  
```sh
mkdir mypod
cd mypod
cat >pod.yaml
<ctrl-v to paste the YAML you copied from above, hit enter>
<ctrl-d>

echo "DEVMODE=true" >pod.env
```

The pod (in devmode) will mount the `./build` directory. This directory is expected to have _nginx_ content files.  

The generation of the nginx content files are at the discretion of the website projects build process. We will manually create the files in this example.

Create these two files in `./build/ and `./build/public`, respectively:  

```./build/nginx.conf
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
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

    access_log  /var/log/nginx/access.log  main;

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

```./build/public/index.html
Hello world!
```

Now our project is ready and the pod can be compiled.  

```sh
podc
```

`podc` will generate an executable file called simply `pod`.

Let's try and interact with the executable:  
```sh
./pod help
```

Let's run the pod:  
```sh
./pod run

# Curl it
curl 127.0.0.1:8080
```

If you get the output `Hello World!` then the pod is running as expected.

Check the logs:  
```sh
./pod logs
```

Now you can update the contents of the `./build` directory at your development process's discretion. In this case using `nginx`, if you update the `nginx.conf` file the nginx process needs to be signalled. This is easy to do:  
```sh
./pod signal
```
This will signal nginx to reload the configuration.

## Prepare for release

    1.  Create a Dockerfile to build the image
    2.  Build the content into `./build`
    3.  Build, tag and push the image
    4.  Update the pod.yaml to reflect the new image version.
        Note that you cannot put the image version in the `pod.env` file, it has to be "hardcoded" into the `pod.yaml` file.
        This is because the `pod.env` file does not tag along into the cluster project when the pod is compiled.
    5.  Git commit and push the changes.
    6.  In your cluster or management project (attach and) compile the pod.
