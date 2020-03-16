#!/usr/bin/env sh
# Script to export a release
set -e
REMOTE_SET_COMMITCHAIN="$(space /_remote_plumbing/set_commit_chain/ -d)"
REMOTE_ACQUIRE_LOCK="$(space /_remote_plumbing/acquire_lock/ -d)"
REMOTE_RELEASE_LOCK="$(space /_remote_plumbing/release_lock/ -d)"
REMOTE_GET_HOSTMETADATA="$(space /_remote_plumbing/get_host_metadata/ -d)"
REMOTE_UPLOAD_ARCHIVE="$(space /_remote_plumbing/upload_archive/ -d)"
REMOTE_UNPACK_ARCHIVE="$(space /_remote_plumbing/unpack_archive/ -d)"
REMOTE_INIT_HOST="$(space /_remote_plumbing/init_host/ -d)"
REMOTE_CREATE_SUPERUSER="$(space /_remote_plumbing/create_superuser/ -d)"
REMOTE_DISABLE_ROOT="$(space /_remote_plumbing/disable_root/ -d)"
REMOTE_HOST_SETUP="$(space /_remote_plumbing/setup_host/ -d)"
REMOTE_LOGS="$(space /_remote_plumbing/logs/ -d)"
REMOTE_DAEMON_LOG="$(space /_remote_plumbing/daemon_log/ -d)"
REMOTE_PACK_RELEASEDATA="$(space /_remote_plumbing/pack_release_data/ -d)"
export REMOTE_PACK_RELEASEDATA REMOTE_SET_COMMITCHAIN REMOTE_ACQUIRE_LOCK REMOTE_RELEASE_LOCK REMOTE_GET_HOSTMETADATA REMOTE_UPLOAD_ARCHIVE REMOTE_UNPACK_ARCHIVE REMOTE_INIT_HOST REMOTE_HOST_SETUP REMOTE_LOGS REMOTE_DAEMON_LOG REMOTE_CREATE_SUPERUSER REMOTE_DISABLE_ROOT
space /cmdline/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d >./release/snt
chmod +x ./release/snt
