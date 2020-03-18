# Developing Simplenetes

## Running the Simplenetes Space Module
When developing the module, we can run it without having to create new releases for each change.

Set the `CLUSTERPATH` variable and optionally the `PODPATH` variable when running this space module.  
The `PODPATH` variable defaults to `${CLUSTERPATH}/../pods`.

```sh
export CLUSTERPATH=...
space /
```

## Create a new release of the snt executable
Simplenetes is built using [https://space.sh](Space) and requires Space to be installed to be built as a final standalone executable.

First install Space then run:  
```sh
./make.sh
```

The new release is saved to `./release/snt`.
