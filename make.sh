#!/usr/bin/env sh
# Script to export a release
set -e
REMOTE_SET_COMMITCHAIN="$(space /_remote_plumbing/set_commit_chain/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_ACQUIRE_LOCK="$(space /_remote_plumbing/acquire_lock/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_RELEASE_LOCK="$(space /_remote_plumbing/release_lock/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_GET_HOSTMETADATA="$(space /_remote_plumbing/get_host_metadata/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_UPLOAD_ARCHIVE="$(space /_remote_plumbing/upload_archive/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_UNPACK_ARCHIVE="$(space /_remote_plumbing/unpack_archive/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_INIT_HOST="$(space /_remote_plumbing/init_host/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_CREATE_SUPERUSER="$(space /_remote_plumbing/create_superuser/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_DISABLE_ROOT="$(space /_remote_plumbing/disable_root/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_HOST_SETUP="$(space /_remote_plumbing/setup_host/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_LOGS="$(space /_remote_plumbing/logs/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_SIGNAL="$(space /_remote_plumbing/signal/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_DAEMON_LOG="$(space /_remote_plumbing/daemon_log/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_PACK_RELEASEDATA="$(space /_remote_plumbing/pack_release_data/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_POD_STATUS="$(space /_remote_plumbing/pod_status/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_POD_SHELL="$(space /_remote_plumbing/pod_shell/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
REMOTE_HOST_SHELL="$(space /_remote_plumbing/host_shell/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d)"
export REMOTE_PACK_RELEASEDATA REMOTE_SET_COMMITCHAIN REMOTE_ACQUIRE_LOCK REMOTE_RELEASE_LOCK REMOTE_GET_HOSTMETADATA REMOTE_UPLOAD_ARCHIVE REMOTE_UNPACK_ARCHIVE REMOTE_INIT_HOST REMOTE_HOST_SETUP REMOTE_LOGS REMOTE_DAEMON_LOG REMOTE_CREATE_SUPERUSER REMOTE_DISABLE_ROOT REMOTE_SIGNAL REMOTE_POD_STATUS REMOTE_POD_SHELL REMOTE_HOST_SHELL
space /cmdline/ -e SPACE_MUTE_EXIT_MESSAGE=1 -d >./release/snt
chmod +x ./release/snt
