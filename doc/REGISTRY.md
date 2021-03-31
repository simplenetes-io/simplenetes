# Configuring image registries

Podman is compatible with the Docker style `config.json` file.

Each host will be configured when running the `sns host init` command.

You can configure each host separately by placing a file with the same format but named as `registry-config.json` inside the host directory.

If no file is found in the host directory then ns will look in the cluster project base directory for the file and upload it for the host.

The `registry-config.json` file will be uploaded to the host as `$HOME/.docker/config.json`. Podman will pick this up when pulling images from private registries.

If changing the `registry-config.json` for a host (or all) you need to rerun `sns host init`.

## Generate the conf file
If you already have a `config.json` file you can copy it into `cluster-dir/registry-config.json`.

If you need to create a new registry config file, follow these steps:  
```sh
printf "docker.pkg.github.com:user:passwdOrtoken\\n" | sns cluster registry [host]
```
