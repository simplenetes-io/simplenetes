# All CLUSTER SYNC functionality
#
_SYNC_RUN()
{
    SPACE_SIGNATURE="forceSync quite"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="PRINT _PRJ_IS_CLUSTER_CLEAN _PRJ_GET_CLUSTER_GIT_COMMIT_CHAIN _PRJ_GET_CLUSTER_ID _SYNC_GET_METADATA _SYNC_RUN2 _SYNC_OUTPUT_INFO _SYNC_ACQUIRE_LOCK _SYNC_RELEASE_LOCK _PRJ_LOG_C _PRJ_LIST_HOSTS _SYNC_KILL_SUBPROCESSES _SYNC_MK_TMP_FILES _SYNC_RM_TMP_FILES"

    # The sync does the following:

    #   2.  Get the git commit chain of IDs.
    #   For each host:
    #   3.  Check so that no other sync is already in progress.
    #   4.  Check on each host that our HEAD is in the same chain as on the host.
    #           If it is behind host HEAD then warn that we are rolling back and require a force flag to continue.
    #           If it is on another branch then warn that we have branched and require a force flag to continue.
    #   For each host again, now in parallel:
    #   5.  Set the HEAD and chain on host to match our local cluster, mark as "syncing".
    #   6.  Download a list of metadata for all pods and releases on host.
    #   7.  For each existing release on the host which does not exist in the cluster project, set it's state to: removed (this will remove everything but keep volumes for the pod.)
    #           This is detached pods or deleted releases. To remove the volumes for a pod a separate garbage collection action need to be performed.
    #   8.  For all releases existing in cluster project but not on host, check if state is "running", if so add it to sync queue.
    #   9.  For all releases existing on both sides:
    #           i) check if config files have changed, if so sync them.
    #           ii) For all releases existing on both sides check if state file has changed, is so sync them.
    #   11.  Mark host as "synced ready".

    local forceSync="${1:-false}"
    shift

    local quite="${1:-false}"
    shift

    local hosts=
    hosts="$(_PRJ_LIST_HOSTS 1)"

    if [ -z "${hosts}" ]; then
        PRINT "No existing active/inactive hosts to sync with." "error" 0
        return 1
    fi

    local list=
    if ! list="$(_SYNC_MK_TMP_FILES "${hosts}")"; then
        PRINT "Could not create tmp file." "error" 0
        return 1
    fi

    local gitCommitChain=""
    local clusterID=

    if ! clusterID="$(_PRJ_GET_CLUSTER_ID)"; then
        PRINT "Cannot get the ID for this cluster project." "error" 0
        _SYNC_RM_TMP_FILES "${list}"
        return 1
    fi

    # Perform step 1 to 4
    if ! _PRJ_IS_CLUSTER_CLEAN; then
        PRINT "The cluster git project is not clean and committed. Cannot continue until it is." "error" 0
        _SYNC_RM_TMP_FILES "${list}"
        return 1
    fi

    if ! gitCommitChain="$(_PRJ_GET_CLUSTER_GIT_COMMIT_CHAIN)"; then
        PRINT "Cannot get the git commit chain in this cluster project." "error" 0
        _SYNC_RM_TMP_FILES "${list}"
        return 1
    fi

    # Get the cluster metadata for each host.
    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        local hostClusterMeta=
        if ! hostClusterMeta="$(_SYNC_GET_METADATA "${host}")"; then
            PRINT "Could not communicate with host: ${host}. If this host is to be out of rotation first disable it, if this is a temporary hickup in the network run this command again in a while." "error" 0
            _SYNC_RM_TMP_FILES "${list}"
            return 1
        fi

        # Check to remote has the same cluster ID.
        local remoteClusterID="${hostClusterMeta%%[ ]*}"
        if [ "${remoteClusterID}" != "${clusterID}" ]; then
            PRINT "cluster ID of local project and on host ${host} do not match! Aborting. Maybe the host has to be initiated first?" "error" 0
            _SYNC_RM_TMP_FILES "${list}"
            return 1
        fi

        # Check so that remote git commit chain is behind or on HEAD.
        local remoteChain="${hostClusterMeta#*[ ]}"
        local remainder="${gitCommitChain#${remoteChain}}"
        local remainder2="${remoteChain#${gitCommitChain}}"
        PRINT "Remainder: ${remainder}" "debug" 0

        if [ -z "${remoteChain}" ]; then
            # Fall through
            :
        elif [ -n "${remainder2}" ] && [ "${remainder2}" != "${remoteChain}" ]; then
            if [ "${forceSync}" = "true" ]; then
                PRINT "Force syncing a rollback." "warning" 0 2>>"${tmpFile}"
                # Fall through
            else
                PRINT "Host ${host} HEAD is in front of what we are syncing! If this is a rollback you need to force it." "error" 0
                _SYNC_RM_TMP_FILES "${list}"
                return 1
            fi
        elif [ -z "${remainder}" ]; then
            # We are on HEAD.
            PRINT "Host already on HEAD, checking for updates anyways (idempotent)." "info" 0 2>>"${tmpFile}"
            # Fall through
        elif [ "${remainder}" = "${gitCommitChain}" ]; then
            # This is a branch, throw error
            if [ "${forceSync}" = "true" ]; then
                PRINT "Force syncing a branch onto host." "warning" 0 2>>"${tmpFile}"
                # Fall through
            else
                PRINT "You are trying to sync a branched commit chain to host ${host}. You could force this update to reset the commit chain on host, but it can be dangerous." "error" 0
                PRINT "Local chain: ${gitCommitChain}" "debug" 0
                PRINT "Remote chain: ${remoteChain}" "debug" 0
                PRINT "Remainder: ${remainder}" "debug" 0
                _SYNC_RM_TMP_FILES "${list}"
                return 1
            fi
        else
            local previousCommit="${remoteChain##*[ ]}"
            local head="${gitCommitChain##*[ ]}"
            PRINT "Syncing host up from commit \"${previousCommit}\" to the following HEAD: \"${head}\"" "info" 0 2>>"${tmpFile}"
            # Fall through
        fi
        unset hostClusterMeta
    done
    unset host

    # Get a lock on all hosts.
    local randomToken="$(awk 'BEGIN{min=1;max=65535;srand(); print int(min+rand()*(max-min+1))}')"
    local lockedHosts=""
    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        if ! _SYNC_ACQUIRE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"; then
            PRINT "Could not acquire lock on host ${host}." "error" 0
            _PRJ_LOG_C "SYNC_LOCK_ACQUIRE_ERROR token:${randomToken} host:${host}"
            # Unlock previously locked
            for host in ${lockedHosts}; do
                _SYNC_RELEASE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"
            done
            _SYNC_RM_TMP_FILES "${list}" "${randomToken}"
            return 1
        fi
        lockedHosts="${lockedHosts}${lockedHosts:+,}${host}"
    done
    unset host

    _PRJ_LOG_C "SYNC_LOCK_ACQUIRED token:${randomToken} hosts:${lockedHosts}"
    unset lockedHosts

    ## Now we are all setup to run the sync on all hosts.
    ## We will do this in parallel and if any host fails at this stage
    ## that will not abort the overall process but will be reported in the output.
    ## If a host fails then this sync should be run again or that host should be taken out of rotation.
    ## Syncs are alwaus idempotent, can be run multiple times.


    local timeout="$(($(date +%s)+1200))"
    local pid=
    local pids=""
    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        if ! pid="$(_SYNC_RUN2 "${host}" "${gitCommitChain}" 2>"${tmpFile}")"; then
            PRINT "Could not spawn process, aborting. Sync might now be in a halfway state, you should rerun this sync when possible." "error" 0
            # Make it kill any processes immediately.
            timeout=0
            _PRJ_LOG_C "SYNC_ABORTED_ON_ERROR token:${randomToken} host:${host}"
            break
        fi
        pids="${pids}${pids:+ }${pid}"
    done

    # trap INT and kill all subprocesses.
    trap _SYNC_KILL_SUBPROCESSES INT

    # Collect and show all output while we wait for pids to finish
    while true; do
        if [ "$(date +%s)" -gt "${timeout}" ]; then
            # Check so actually timeouted, it could also have been forced timeouted on error above.
            if [ "${timeout}" -gt 0 ]; then
                _PRJ_LOG_C "SYNC_ABORTED_ON_TIMEOUT token:${randomToken}"
            fi
            # Kill all processes
            for pid in ${pids}; do
                PRINT "Kill sub process ${pid} on timeout." "error" 0
                 kill -9 "${pid}" 2>/dev/null
            done
            break
        fi
        # Output to TTY ongoing updates.
        if [ "${quite}" != "true" ]; then
            _SYNC_OUTPUT_INFO "${list}"
        fi
        sleep 1
        for pid in ${pids}; do
            if kill -0 "${pid}" 2>/dev/null; then
                continue 2
            fi
        done
        _PRJ_LOG_C "SYNC_DONE token:${randomToken}"
        break
    done

    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        _SYNC_RELEASE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"
    done

    # Clear trap
    trap - INT

    _PRJ_LOG_C "SYNC_LOCK_RELEASED token:${randomToken}"

    _SYNC_RM_TMP_FILES "${list}" "${randomToken}"
}

_SYNC_MK_TMP_FILES()
{
    SPACE_SIGNATURE="hosts"
    SPACE_DEP="_UTIL_GET_TMP_FILE"

    local hosts="${1}"
    shift

    local list=""
    local host=
    for host in ${hosts}; do
        local tmpFile=
        if ! tmpFile="$(_UTIL_GET_TMP_FILE)"; then
            return 1
        fi
        list="${list}${list:+ }${host}:${tmpFile}"
    done

    printf "%s\\n" "${list}"
}

_SYNC_KILL_SUBPROCESSES()
{
    SPACE_DEP="_PRJ_LOG_C PRINT _SYNC_RM_TMP_FILES"

    _PRJ_LOG_C "SYNC_ABORTED_BY_USER token:${randomToken}"

    PRINT "Abruptly abort syncing on ctrl-c..." "error" 0
    for pid in ${pids}; do
        PRINT "Kill sub process ${pid}." "info" 0
        kill -9 "${pid}" 2>/dev/null
    done
    _SYNC_RM_TMP_FILES "${list}" "${randomToken}"
    kill -9 $$ 2>/dev/null
}

# If token given then output to logfile
_SYNC_RM_TMP_FILES()
{
    SPACE_SIGNATURE="list [token]"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="_SYNC_OUTPUT_INFO PRINT"

    local list="${1}"
    shift

    local token="${1:-}"

    if [ -n "${token}" ]; then
        local ts="$(date +%s)"
        local logDir="${CLUSTERPATH}/_synclogs"
        mkdir -p "${logDir}"
        local logFile="${logDir}/${ts}.${token}.sync.log.txt"
        _SYNC_OUTPUT_INFO "${list}" >"${logFile}"
        PRINT "Logfile stored at: ${logFile}" "info" 0
    fi

    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        rm "${tmpFile}"
    done
}

_SYNC_OUTPUT_INFO()
{
    SPACE_SIGNATURE="isFinal list"
    SPACE_DEP="_UTIL_CLEAR_SCREEN"

    local isFinal="${1}"
    shift

    [ -t 1 ]
    local isTTY=$?

    if [ "${isTTY}" = 0 ]; then
        _UTIL_CLEAR_SCREEN
        :
    else
        # Output is redirected.
        # don't clear screen,
        # only output when final.
        if [ "${isFinal}" = 0 ]; then
            return 0
        fi
    fi

    local tuple=
    for tuple in ${list}; do
        local host="${tuple%:*}"
        local tmpFile="${tuple#*:}"
        printf "%s\\n" "[SYNC]  Host: ${host}"
        cat "${tmpFile}"
        printf "\\n"
    done
}

# Connect to host and set the chain.
# Download a complete list of release data for all pods and releases.
# We assume we are holding the lock on the host already.
_SYNC_RUN2()
{
    SPACE_SIGNATURE="host gitcommitchain"
    SPACE_DEP="_SYNC_SET_CHAIN _SYNC_DOWNLOAD_RELEASE_DATA _SYNC_BUILD_UPDATE_ARCHIVE _SYNC_PERFORM_UPDATES"

    local host="${host}"
    shift

    local gitCommitChain="${1}"
    shift

    local pid=

    # Spawn off subprocess
    (
        if ! _SYNC_SET_CHAIN "${host}" "${gitCommitChain}"; then
            PRINT "Could not set the commit id chain on the host." "error" 0
            return 1
        fi

        local hostReleaseData=
        if ! hostReleaseData="$(_SYNC_DOWNLOAD_RELEASE_DATA "${host}")"; then
            PRINT "Could not download release data from the host." "error" 0
            return 1
        fi

        local status=
        local tmpDir=
        tmpDir="$(_SYNC_BUILD_UPDATE_ARCHIVE "${host}" "${hostReleaseData}")"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            PRINT "Performing updates..." "info" 0
            if ! _SYNC_PERFORM_UPDATES "${host}" "${tmpDir}"; then
                PRINT "Could not build update archive." "error" 0
                rm -rf "${tmpDir}"
                return 1
            fi
            rm -rf "${tmpDir}"
        elif [ "${status}" -eq 1 ]; then
            # Error
            PRINT "Could not build update archive." "error" 0
            return 1
        else
            # No updates to bring
            PRINT "No updates to be made." "info" 0
            return 0
        fi
    )&
    pid=$!

    printf "%s\\n" "${pid}"
}

# Given a host and a directory of updates,
# we upload the directory as an archive,
# then we unpack it on the host.
_SYNC_PERFORM_UPDATES()
{
    SPACE_SIGNATURE="host tmpDir"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local host="${1}"
    shift

    local tmpDir="${1}"
    shift

    # Upload archive
    local i=
    local status=
    local data=
    # Try three times before failing
    PRINT "tmpdir: ${tmpDir}" "debug"
    for i in 1 2 3; do
        data="$(cd "${tmpDir}" && tar czf - . |_REMOTE_EXEC "${host}" "upload_archive")"
        status="$?"
        if  [ "${status}" -eq 0 ] || [ "${status}" -eq 10 ]; then
            break
        fi
    done
    if [ "${status}" -ne 0 ]; then
        # Failed
        return 1
    fi

    # Unpack archive
    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _REMOTE_EXEC "${host}" "unpack_archive" "${data}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done
    return 1
}

# Connect to host and set the current commit chain.
# We expect the host to be up so we do a few retries in case it fails.
_SYNC_SET_CHAIN()
{
    SPACE_SIGNATURE="host gitcommitchain"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local host="${1}"
    shift

    local gitCommitChain="${1}"
    shift

    local status=
    _REMOTE_EXEC "${host}" "set_commit_chain" "${gitCommitChain}"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    elif [ "${status}" -eq 10 ]; then
        return 1
    fi

    # Failed
    PRINT "Could not set chain." "error" 0
    return 1
}

# Connect to host and set the current commit chain.
# We expect the host to be up so we do a few retries in case it fails.
_SYNC_ACQUIRE_LOCK()
{
    SPACE_SIGNATURE="host token"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local host="${1}"
    shift

    local token="${1}"
    shift

    local seconds=10

    PRINT "Acquire lock using token: ${token}" "info" 0

    local status=
    _REMOTE_EXEC "${host}" "acquire_lock" "${token}" "${seconds}"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    elif [ "${status}" -eq 2 ]; then
        PRINT "Could not acquire lock. Some other sync process might be happening simultanously, aborting. Please try again in a few minutes." "error" 0
        return 2
    elif [ "${status}" -eq 10 ]; then
        return 1
    fi

    # Failed
    PRINT "Could not acquire lock." "error" 0
    return 1
}

_SYNC_RELEASE_LOCK()
{
    SPACE_SIGNATURE="host token"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local host="${1}"
    shift

    local token="${1}"
    shift

    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _REMOTE_EXEC "${host}" "release_lock" "${token}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 2 ]; then
            PRINT "Could not release lock, it might not be our lock." "error" 0
            return 2
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done

    # Failed
    PRINT "Could not release lock." "error" 0
    return 1
}

# Get meta data from the host.
# returns string as "CLUSTERID CommitIDChain"
_SYNC_GET_METADATA()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local host="${1}"
    shift

    local status=
    local data=
    data="$(_REMOTE_EXEC "${host}" "get_host_metadata")"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        printf "%s\\n" "${data}"
        return 0
    elif [ "${status}" -eq 10 ]; then
        return 1
    fi

    PRINT "Could not get metadata." "error" 0
    # Failed
    return 1
}

_SYNC_DOWNLOAD_RELEASE_DATA()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_REMOTE_EXEC"

    local host="${1}"
    shift

    local status=
    local data=
    data="$(_REMOTE_EXEC "${host}" "pack_release_data")"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        printf "%s\\n" "${data}"
        return 0
    fi
    elif [ "${status}" -eq 10 ]; then
        return 1
    fi

    # Failed
    return "${status}"
}

# This is run on the host and puts together a list of the current state of the releases of pods.
# From the host download a list of all pods,
# their releases, their states and their configs hashes.
# return 0 on success
# stdout: string of release data, space separated items
#
_SYNC_REMOTE_PACK_RELEASE_DATA()
{
    SPACE_SIGNATURE="hosthome"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    local data=""

    # Get the host list
    local hostFile="${HOSTHOME}/cluster-hosts.txt"
    local hosts=""
    if [ -f "${hostFile}" ]; then
        hosts="$(cat "${hostFile}")"
        local newline="
"
        STRING_SUBST "hosts" "${newline}" ";" 1
    fi
    data="${data}${data:+ }:hosts:${hosts}"

    local livePods="${HOSTHOME}/pods"

    if ! cd "${HOSTHOME}/pods" 2>/dev/null; then
        printf "%s\\n" "${data}"
        return 0
    fi
    local pod=
    for pod in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*'  |cut -b3-); do
        if [ ! -d "${pod}/release" ]; then
            continue
        fi
        cd "${pod}/release"

        local release=
        for release in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*'  |cut -b3-); do
            cd "${release}"

            # Get the state of the pod
            local state=
            if ! state="$(cat "pod.state" 2>/dev/null)"; then  # There should only be one state file present.
                # No state file, this is treated as removed
                cd ..  # Step out of specific release
                continue
            fi
            data="${data}${data:+ }${pod}:${release}:${state}"

            # Check if this pod has configs
            if [ ! -d "config" ]; then
                cd ..  # Step out of specific release
                continue
            fi

            # Step into config dir and update the configs in the config dir
            cd "config"

            local dir="${livePods}/${pod}/release/${release}/config"
            local config=
            for config in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
                # This could be a config directory.
                local chksumFile="${dir}/${config}.txt"
                if [ -f "${chksumFile}" ]; then
                    # This is the chksum file for the config, read it.
                    local chksum="$(cat "${chksumFile}")"
                    # Sanatize it if it is corrupt, because a space here can ruin the whole thing.
                    STRING_SUBST "chksum" " " "" 1
                    data="${data} ${pod}:${release}:${config}:${chksum}"
                fi
            done

            cd ..  # Step out of "config" dir
            cd ..  # Step out of release version dir
        done
        cd ../..  # Step out of "pod/release" dir
    done
    cd ../..  # Step out of "pods" dir

    printf "%s\\n" "${data}"
}

# Look at the release data retrieved from the host and compare it to what is on disk in the cluster project.
# Create a new archive which can be uploaded to the host for it to get in sync.
# return 0 on success
# stdout: path to tmp dir with all files to sync to host
_SYNC_BUILD_UPDATE_ARCHIVE()
{
    SPACE_SIGNATURE="host hostreleasedata"
    SPACE_DEP="_UTIL_GET_TMP_DIR PRINT _PRJ_GET_ROUTER_HOSTS STRING_SUBST _PRJ_GET_HOST_STATE"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local releaseData="${1}"
    shift

    local tmpDir=
    if ! tmpDir="$(_UTIL_GET_TMP_DIR)"; then
        return 1
    fi

    local hostState="$(_PRJ_GET_HOST_STATE "${host}")"

    PRINT "Using tmp dir ${tmpDir}" "debug"

    # Compare cluster-hosts.txt on host with what we have locally.
    local hostsRouter="$(_PRJ_GET_ROUTER_HOSTS)"
    local updateHosts="0"
    local item=
    for item in ${releaseData}; do
        local hosts="${item#:hosts:}"
        if [ "${hosts}" != "${item}" ]; then
            # Compare list of hosts to current active list.
            if [ "${hosts}" != "${hostsRouter}" ]; then
                updateHosts="1"
            fi
            break
        fi
    done

    if [ "${updateHosts}" = "1" ]; then
        # We want to update this, create file
        PRINT "Add updated list of hosts to the update archive." "info" 0
        local newline="
"
        STRING_SUBST "hostsRouter" ";" "${newline}"
        printf "%s\\n" "${hostsRouter}"  >"${tmpDir}/cluster-hosts.txt"
    fi

    #### PODS
    # First phase, check compared to what is existing on the host,
    # which pod releases to remove, which to update state of,
    # and which configs to update.
    # item is either
    # pod:release:state, or
    # pod:release:config:chksum
    local prefix="${CLUSTERPATH}/${host}/pods"
    local item=
    for item in ${releaseData}; do
        if [ "${item#:hosts:}" != "${item}" ]; then
            # Not relevant for pods
            continue
        fi
        local pod="${item%%:*}"
        local release="${item#*:}"
        release="${release%%:*}"
        local stateOrConfigChksum="${item#*:*:}"
        local chkSum="${stateOrConfigChksum#*:}"
        local state=
        local config=
        if [ "${chkSum}" = "${stateOrConfigChksum}" ]; then
            # This was just state
            state="${stateOrConfigChksum}"
        else
            # This was config and chksum
            config="${stateOrConfigChksum%:*}"
        fi

        # Now either config or chksum is set, and it dictates what to compare for.

        # Are we comparing state?
        if [ -n "${state}" ]; then
            # Compare state
            local setState=
            if [ ! -d "${prefix}/${pod}/release/${release}" ] || [ "${hostState}" != "active" ]; then
                # We do not have this pod release in the cluster project.
                # OR, this host is not set to "active".
                # Set state to removed on host.
                if [ "${state}" = "removed" ]; then
                    # Is already removed, so don't bother.
                    continue
                fi
                PRINT "Set pod ${pod}:${release} in removed state on host." "info" 0
                setState="removed"
            else
                # We need to make an exact comparison of states.
                # Compare states of host pod release and our local state in the cluster project.
                local localState=
                localState="$(cat "${prefix}/${pod}/release/${release}/pod.state" 2>/dev/null)"
                if [ "${localState}" != "${state}" ]; then
                    # If the states differ, then update it. Default to removed state if pod.state file was missing.
                    setState="${localState:-removed}"
                    PRINT "Change state of ${pod}:${release} from ${state} to ${setState}." "info" 0
                fi
            fi

            if [ -n "${setState}" ]; then
                # Create a statefile.
                PRINT "Create state file" "debug"
                if ! mkdir -p "${tmpDir}/pods/${pod}/release/${release}"; then
                    rm -rf "${tmpDir}"
                    PRINT "Could not write to tmp dir." "error" 0
                    return 1
                fi
                printf "%s\\n" "${setState}" >"${tmpDir}/pods/${pod}/release/${release}/pod.state"
            fi
        else
            # We are comparing config checksums
            local configDir="${prefix}/${pod}/release/${release}/config/${config}"
            local chksumFile="${prefix}/${pod}/release/${release}/config/${config}.txt"
            if [ -f "${chksumFile}" ]; then
                local chksumLocal="$(cat "${chksumFile}" 2>/dev/null)"
                if [ "${chksumLocal}" != "${chkSum}" ]; then
                    # Update config
                    PRINT "Update config ${config} for ${pod}:${release}." "info" 0
                    if ! mkdir -p "${tmpDir}/pods/${pod}/release/${release}/config"; then
                        rm -rf "${tmpDir}"
                        PRINT "Could not write to tmp dir." "error" 0
                        return 1
                    fi
                    if ! cp -r "${configDir}" "${tmpDir}/pods/${pod}/release/${release}/config"; then
                        PRINT "Could not copy config files to tmp dir." "error" 0
                        return 1
                    fi
                    if ! cp "${chksumFile}" "${tmpDir}/pods/${pod}/release/${release}/config"; then
                        PRINT "Could not copy config files to tmp dir." "error" 0
                        return 1
                    fi
                fi
            fi
        fi
    done

    ####
    # Second phase, check all pod releases in the cluster project if they do not exist on the host,
    # if not then add them and their configs to the update (unless they are in the removed state then do not add them).
    if [ -d "${prefix}" ]; then
        cd "${prefix}"
        local pod=
        for pod in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
            if [ ! -d "${pod}/release" ]; then
                continue
            fi

            cd "${pod}/release"

            local release=
            for release in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
                if ! cd "${release}" 2>/dev/null; then
                    continue
                fi

                local copy="0"
                # Get state
                local localState=
                localState="$(cat "pod.state" 2>/dev/null)"
                if [ -z "${localState}" ]; then
                    PRINT "Pod ${pod}:${release} has no pod.state file, treating it as in removed state." "warning" 0
                elif [ -n "${localState}" ] && [ "${localState}" != "removed" ]; then
                    copy="1"  # Say we want to copy it
                    # Check if this release is not present on host
                    local item=
                    for item in ${releaseData}; do
                        local pod2="${item%%:*}"
                        local release2="${item#*:}"
                        release2="${release2%%:*}"
                        local stateOrConfigChksum="${item#*:*:}"
                        if [ "${pod}" = "${pod2}" ] && [ "${release}" = "${release2}" ]; then
                            # This release is already present on host, don't add it.
                            # If there was any state change that would have been handled in the logic first phase logic.
                            copy="0"
                            break
                        fi
                    done
                fi

                cd ..  # Step out of release version

                if [ "${copy}" = "1" ]; then
                    PRINT "Copy pod ${pod}:${release} to update archive." "info" 0
                    # Copy pod release and all configs to sync
                    mkdir -p "${tmpDir}/pods/${pod}/release"
                    cp -r "${release}" "${tmpDir}/pods/${pod}/release"
                fi
            done
            cd ../.. # Step out of pod/release
        done

        cd ../../..  # Step out prefix
    fi

    # Check dir is empty
    local count="$(cd "${tmpDir}" && ls |wc -l)"

    if [ "${count}" = "0" ]; then
        # Nothing to sync
        rm -rf "${tmpDir}"
        return 2
    fi

    printf "%s\\n" "${tmpDir}"
    return 0
}

# After sending a tar.gz file to the server we run this
# function on the server to unpack that file.
# It unpacks the file into a tmp directory.
# It will then take each file from tmp dir and mv it to the
# corresponding place in the structure in the pods dir (overwriting).
# If it is a config directory it will delete all files from
# the config and then mv the new files into that same config dir.
# We must keep the config dir because it's inode is mounted into a container
# and creating a new dir will not work unless recreating the container.
_SYNC_REMOTE_UNPACK_ARCHIVE()
{
    SPACE_SIGNATURE="hosthome targzfile"
    SPACE_DEP="_UTIL_GET_TMP_DIR PRINT STRING_SUBST"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local archive="${1}"
    shift

    local tmpDir="$(_UTIL_GET_TMP_DIR)"

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    PRINT "Unpack archive on host to ${HOSTHOME}" "info" 0

    if ! tar xzf "${archive}" -C "${tmpDir}"; then
        PRINT "Could not unpack archive." "error" 0
        return 1
    fi
    rm "${archive}"

    if [ ! -d "${tmpDir}" ]; then
        PRINT "Could not unpack archive as expected." "error" 0
        return 1
    fi

    _SYNC_REMOTE_UNPACK_ARCHIVE2 "${HOSTHOME}" "${tmpDir}"
    rm -rf "${tmpDir}"
}

_SYNC_REMOTE_UNPACK_ARCHIVE2()
{
    SPACE_SIGNATURE="hosthome archiveDir"
    SPACE_DEP="PRINT"

    local HOSTHOME="${1}"
    shift

    local archiveDir="${1}"
    shift

    cd "${archiveDir}"

    # Check the cluster-hosts.txt file
    if [ -f "cluster-hosts.txt" ]; then
        PRINT "Update cluster-hosts.txt" "info" 0
        mv -f "cluster-hosts.txt" "${HOSTHOME}"
    fi

    if [ ! -d "pods" ]; then
        # No pods to update
        PRINT "No pods to update, done unpacking updates." "info" 0
        return 0
    fi

    cd "pods"

    local livePods="${HOSTHOME}/pods"

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    # Start moving files
    local pod=
    for pod in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
        if [ ! -d "${pod}/release" ]; then
            continue;
        fi
        cd "${pod}/release"
        local release=
        for release in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
            cd "${release}"

            PRINT "Update pod ${pod}:${release}" "info" 0

            # Move sh and state files inside release dir
            local dir="${livePods}/${pod}/release/${release}"
            mkdir -p "${dir}"
            local file=
            for file in $(find . -mindepth 1 -maxdepth 1 -type f -not -path './.*' |cut -b3-); do
                # This would be a pod, pod.state, ingress, etc file, just move it over to the live location.
                mv -f "${file}" "${dir}"
            done

            # Step inside config dir
            if [ ! -d "config" ]; then
                cd ..  # Step out of "release" dir.
                continue
            fi

            # Update the configs in the config dir
            cd "config"
            local config=
            for config in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*' |cut -b3-); do
                # This is a config directory.
                # First empty the current directory on the host,
                # then mv all files over from here.
                # After emptying the dir we then remove the chk sum file
                # which means that we won't empty the dir again on a resumed
                # unpacking.
                local dir="${livePods}/${pod}/release/${release}/config"
                local chksumFile="${dir}/${config}.txt"
                # NOTE: we could make the resume more clever by deciding on this when starting. Samll risk now is that there's a timeout on update and another update comes in and "resumes" when it should reset.
                local isResumed="0"
                if [ ! -f "${chksumFile}" ]; then
                    # This means that this unpacking has been resumed and we
                    # should not delete the target files (again).
                    PRINT "Resuming unpacking of pod config ${pod}:${release}:${config}" "info" 0
                    isResumed="1"
                else
                    PRINT "Unpacking pod config ${pod}:${release}:${config}" "info" 0
                fi
                if ! cd "${config}"; then
                    return 1
                fi
                local dir="${livePods}/${pod}/release/${release}/config/${config}"
                mkdir -p "${dir}"
                if [ "${isResumed}" = "0" ]; then
                    # Empty the live dir
                    ( cd "${dir}" && ls -A |xargs rm -rf )
                    rm "${chksumFile}"
                fi

                # mv new files over
                local file2=
                for file2 in $(find . -mindepth 1 -maxdepth 1 -not -path './.*' |cut -b3-); do
                    mv -f "${file2}" "${dir}"
                done
                cd ..  # step out of config dir
            done

            # Move checksum files, important to do this after we have moved over config files.
            local dir="${livePods}/${pod}/release/${release}/config"
            local file2=
            for file2 in $(find . -mindepth 1 -maxdepth 1 -type f -not -path './.*' |cut -b3-); do
                # This would be a chk sum file, move it over.
                mv -f "${file2}" "${dir}"
            done
            cd ..  # Step out of "config" dir
            cd .. # Step of out of release version dir
        done
        cd ..  # Step out of "release" dir.
    done
    cd ../.. # Step out of archiveDir

    PRINT "Done unpacking updates." "info" 0
}
