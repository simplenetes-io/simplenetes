#!/bin/env sh
# Temporary script to test syncing, this should be done by the regular tests instead.
set -e

HOST=my-laptop
HOSTHOME=/home/bashlund/cluster-host
export CLUSTERPATH=/home/bashlund/tmp/simplenetes-testing/dev-cluster

# Get an understanding what the remote host has right now.
releaseData="$(space / -e RUN=_SYNC_REMOTE_PACK_RELEASE_DATA -- "${HOSTHOME}")"

printf "Release data:\\n%s\\n" "${releaseData}" >&2

# Create an archive with the diff of remote host and local host dir
dir=$(space / -e RUN=_SYNC_BUILD_UPDATE_ARCHIVE -- "${HOST}" "${releaseData}")

printf "Archive dir: %s\\n" "${dir}" >&2

# Apply the diff onto the remote host directory
space / -e RUN=_SYNC_REMOTE_UNPACK_ARCHIVE2  -- "${HOSTHOME}" "${dir}"
