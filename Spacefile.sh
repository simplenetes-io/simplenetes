CLUSTER_CREATE()
{
    SPACE_SIGNATURE="cluster"
    SPACE_DEP="PRINT _LOG_C"

    local cluster="${1}"
    shift

    local CLUSTERPATH="${PWD}/${cluster}"

    if [ -e "${CLUSTERPATH}" ]; then
        PRINT "Cluster directory already exists." "error" 0
        return 1
    fi

    mkdir -p "${CLUSTERPATH}"
    touch "${CLUSTERPATH}/cluster-vars.env"
    printf "%s\\n" "${cluster}" >"${CLUSTERPATH}/cluster-id.txt"
    cd "${CLUSTERPATH}"
    git init
    git add .
    git commit -m "Initial"
    _LOG_C "CREATED"
}

_CLUSTER_SYNC_MK_TMP_FILES()
{
    SPACE_SIGNATURE="hosts"
    SPACE_DEP="_GET_TMP_FILE"

    local hosts="${1}"
    shift

    local list=""
    local host=
    for host in ${hosts}; do
        local tmpFile=
        if ! tmpFile="$(_GET_TMP_FILE)"; then
            return 1
        fi
        list="${list}${list:+ }${host}:${tmpFile}"
    done

    printf "%s\\n" "${list}"
}

# If token given then output to logfile
_CLUSTER_SYNC_RM_TMP_FILES()
{
    SPACE_SIGNATURE="list [token]"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="_OUTPUT_HOST_SYNC_INFO PRINT"

    local list="${1}"
    shift

    local token="${1:-}"

    if [ -n "${token}" ]; then
        local ts="$(date +%s)"
        local logDir="${CLUSTERPATH}/_synclogs"
        mkdir -p "${logDir}"
        local logFile="${logDir}/${ts}.${token}.sync.log.txt"
        _OUTPUT_HOST_SYNC_INFO "${list}" >"${logFile}"
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

CLUSTER_SYNC()
{
    SPACE_SIGNATURE="ignoreGitOps forceSync"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="PRINT _IS_CLUSTER_CLEAN _GET_CLUSTER_GIT_COMMIT_CHAIN _GET_CLUSTER_ID _HOST_GET_METADATA _HOST_SYNC _OUTPUT_HOST_SYNC_INFO _HOST_ACQUIRE_LOCK _HOST_RELEASE_LOCK _LOG_C _LIST_HOSTS _KILL_SUBPROCESSES _CLUSTER_SYNC_MK_TMP_FILES _CLUSTER_SYNC_RM_TMP_FILES"

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

    local ignoreGitOps="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local forceSync="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local hosts=
    hosts="$(_LIST_HOSTS "${CLUSTERPATH}" 1)"

    if [ -z "${hosts}" ]; then
        PRINT "No existing active/inactive hosts to sync with." "error" 0
        return 1
    fi

    local list=
    if ! list="$(_CLUSTER_SYNC_MK_TMP_FILES "${hosts}")"; then
        PRINT "Could not create tmp file." "error" 0
        return 1
    fi

    local gitCommitChain=""
    local clusterID=

    if ! clusterID="$(_GET_CLUSTER_ID)"; then
        PRINT "Cannot get the ID for this cluster project." "error" 0
        _CLUSTER_SYNC_RM_TMP_FILES "${list}"
        return 1
    fi

    if [ "${ignoreGitOps}" = "true" ]; then
        PRINT "Ignoring GitOps procedures. This is not recommended in production environments!" "warning" 0
        gitCommitChain="<unknown>"
    else
        # Perform step 1 to 4
        if ! _IS_CLUSTER_CLEAN; then
            PRINT "The cluster git project is not clean and committed. Cannot continue until it is." "error" 0
            _CLUSTER_SYNC_RM_TMP_FILES "${list}"
            return 1
        fi

        if ! gitCommitChain="$(_GET_CLUSTER_GIT_COMMIT_CHAIN)"; then
            PRINT "Cannot get the git commit chain in this cluster project." "error" 0
            _CLUSTER_SYNC_RM_TMP_FILES "${list}"
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
            if ! hostClusterMeta="$(_HOST_GET_METADATA "${host}")"; then
                PRINT "Could not communicate with host: ${host}. If this host is to be out of rotation first disable it, if this is a temporary hickup in the network run this command again in a while." "error" 0
                _CLUSTER_SYNC_RM_TMP_FILES "${list}"
                return 1
            fi

            # Check to remote has the same cluster ID.
            local remoteClusterID="${hostClusterMeta%%[ ]*}"
            if [ "${remoteClusterID}" != "${clusterID}" ]; then
                PRINT "cluster ID of local project and on host ${host} do not match! Aborting. Maybe the host has to be initiated first?" "error" 0
                _CLUSTER_SYNC_RM_TMP_FILES "${list}"
                return 1
            fi

            # Check so that remote git commit chain is behind or on HEAD.
            local remoteChain="${hostClusterMeta#*[ ]}"
            local remainder="${gitCommitChain#${remoteChain}}"
            local remainder2="${remoteChain#${gitCommitChain}}"

            if [ -z "${remoteChain}" ]; then
                # Fall through
                :
            elif [ -n "${remainder2}" ] && [ "${remainder2}" != "${remoteChain}" ]; then
                if [ "${forceSync}" = "true" ]; then
                    PRINT "Force syncing a rollback." "warning" 0 2>>"${tmpFile}"
                    # Fall through
                else
                    PRINT "Host ${host} HEAD is in front of what we are syncing! If this is a rollback you need to force it." "error" 0
                    _CLUSTER_SYNC_RM_TMP_FILES "${list}"
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
                    _CLUSTER_SYNC_RM_TMP_FILES "${list}"
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
    fi

    # Get a lock on all hosts.
    local randomToken="$(awk 'BEGIN{min=1;max=65535;srand(); print int(min+rand()*(max-min+1))}')"
    local lockedHosts=""
    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        if ! _HOST_ACQUIRE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"; then
            PRINT "Could not acquire lock on host ${host}." "error" 0
            _LOG_C "SYNC_LOCK_ACQUIRE_ERROR token:${randomToken} host:${host}"
            # Unlock previously locked
            for host in ${lockedHosts}; do
                _HOST_RELEASE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"
            done
            _CLUSTER_SYNC_RM_TMP_FILES "${list}" "${randomToken}"
            return 1
        fi
        lockedHosts="${lockedHosts}${lockedHosts:+,}${host}"
    done
    unset host

    _LOG_C "SYNC_LOCK_ACQUIRED token:${randomToken} hosts:${lockedHosts}"
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
        if ! pid="$(_HOST_SYNC "${host}" "${gitCommitChain}" 2>"${tmpFile}")"; then
            PRINT "Could not spawn process, aborting. Sync might now be in a halfway state, you should rerun this sync when possible." "error" 0
            # Make it kill any processes immediately.
            timeout=0
            _LOG_C "SYNC_ABORTED_ON_ERROR token:${randomToken} host:${host}"
            break
        fi
        pids="${pids}${pids:+ }${pid}"
    done

    # trap INT and kill all subprocesses.
    trap _KILL_SUBPROCESSES INT

    # Collect and show all output while we wait for pids to finish
    while true; do
        if [ "$(date +%s)" -gt "${timeout}" ]; then
            # Check so actually timeouted, it could also have been forced timeouted on error above.
            if [ "${timeout}" -gt 0 ]; then
                _LOG_C "SYNC_ABORTED_ON_TIMEOUT token:${randomToken}"
            fi
            # Kill all processes
            for pid in ${pids}; do
                PRINT "Kill sub process ${pid} on timeout." "error" 0
                 kill -9 "${pid}" 2>/dev/null
            done
            break
        fi
        # Output to TTY ongoing updates.
        _OUTPUT_HOST_SYNC_INFO "${list}"
        sleep 1
        for pid in ${pids}; do
            if kill -0 "${pid}" 2>/dev/null; then
                continue 2
            fi
        done
        _LOG_C "SYNC_DONE token:${randomToken}"
        break
    done

    local host=
    local tmpFile=
    local tuple=
    for tuple in ${list}; do
        host="${tuple%:*}"
        tmpFile="${tuple#*:}"
        _HOST_RELEASE_LOCK "${host}" "${randomToken}" 2>>"${tmpFile}"
    done

    # Clear trap
    trap - INT

    _LOG_C "SYNC_LOCK_RELEASED token:${randomToken}"

    _CLUSTER_SYNC_RM_TMP_FILES "${list}" "${randomToken}"
}

_KILL_SUBPROCESSES()
{
    SPACE_DEP="_LOG_C PRINT _CLUSTER_SYNC_RM_TMP_FILES"

    _LOG_C "SYNC_ABORTED_BY_USER token:${randomToken}"

    PRINT "Abruptly abort syncing on ctrl-c..." "error" 0
    for pid in ${pids}; do
        PRINT "Kill sub process ${pid}." "info" 0
        kill -9 "${pid}" 2>/dev/null
    done
    _CLUSTER_SYNC_RM_TMP_FILES "${list}" "${randomToken}"
    kill -9 $$ 2>/dev/null
}

_OUTPUT_HOST_SYNC_INFO()
{
    SPACE_SIGNATURE="isFinal list"
    SPACE_DEP="_CLEAR_SCREEN"

    local isFinal="${1}"
    shift

    [ -t 1 ]
    local isTTY=$?

    if [ "${isTTY}" = 0 ]; then
        _CLEAR_SCREEN
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

_CLEAR_SCREEN()
{
    tput clear
}

_GET_TMP_FILE()
{
    mktemp 2>/dev/null || mktemp -t 'sometmpdir'
}

# Connect to host and set the chain.
# Download a complete list of release data for all pods and releases.
# We assume we are holding the lock on the host already.
_HOST_SYNC()
{
    SPACE_SIGNATURE="host gitcommitchain"
    SPACE_DEP="_HOST_SET_CHAIN _HOST_DOWNLOAD_RELEASE_DATA _HOST_BUILD_UPDATE_ARCHIVE _HOST_PERFORM_UPDATES"

    local host="${host}"
    shift

    local gitCommitChain="${1}"
    shift

    local pid=

    # Spawn off subprocess
    (
        if ! _HOST_SET_CHAIN "${host}" "${gitCommitChain}"; then
            PRINT "Could not set the commit id chain on the host." "error" 0
            return 1
        fi

        local hostReleaseData=
        if ! hostReleaseData="$(_HOST_DOWNLOAD_RELEASE_DATA "${host}")"; then
            PRINT "Could not download release data from the host." "error" 0
            return 1
        fi

        local status=
        local tmpDir=
        tmpDir="$(_HOST_BUILD_UPDATE_ARCHIVE "${host}" "${hostReleaseData}")"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            PRINT "Performing updates..." "info" 0
            if ! _HOST_PERFORM_UPDATES "${host}" "${tmpDir}"; then
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

# Look at the release data retrieved from the host and compare it to what is on disk in the cluster project.
# Create a new archive which can be uploaded to the host for it to get in sync.
_HOST_BUILD_UPDATE_ARCHIVE()
{
    SPACE_SIGNATURE="host hostreleasedata"
    SPACE_DEP="_GET_TMP_DIR PRINT _GET_ROUTER_HOSTS STRING_SUBST GET_HOST_STATE"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local releaseData="${1}"
    shift

    local tmpDir=
    if ! tmpDir="$(_GET_TMP_DIR)"; then
        return 1
    fi

    local hostState="$(GET_HOST_STATE "${host}")"

    PRINT "Using tmp dir ${tmpDir}" "debug"

    # Check cluster-hosts.txt
    local hostsRouter="$(_GET_ROUTER_HOSTS)"
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
        for pod in *; do
            if [ ! -d "${pod}/release" ]; then
                continue
            fi

            cd "${pod}/release"

            local release=
            for release in *; do
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

# Given a host and a directory of updates,
# we upload the directory as an archive,
# then we unpack it on the host.
_HOST_PERFORM_UPDATES()
{
    SPACE_SIGNATURE="host tmpDir"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT"

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
        data="$(cd "${tmpDir}" && tar czf - . |_HOST_SSH_CONNECT "${host}" "upload_archive")"
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
        _HOST_SSH_CONNECT "${host}" "unpack_archive" "${data}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done
    return 1
}

_HOST_DOWNLOAD_RELEASE_DATA()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_HOST_SSH_CONNECT"

    local host="${1}"
    shift

    local i=
    local status=
    local data=
    # Try three times before failing
    for i in 1 2 3; do
        data="$(_HOST_SSH_CONNECT "${host}" "pack_release_data")"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            printf "%s\\n" "${data}"
            return 0
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done

    # Failed
    return 1
}

# Produce a comma separated string of all hosts to be in the internal routing.
_GET_ROUTER_HOSTS()
{
    SPACE_SIGNATURE=""
    SPACE_DEP="_LIST_HOSTS STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local hosts=
    hosts="$(_LIST_HOSTS "${CLUSTERPATH}" 2)"

    local routerHosts=""

    local host=
    for host in ${hosts}; do
        local hostEnv="${CLUSTERPATH}/${host}/host.env"
        local varname=
        local value=
        local ROUTERADDRESS=
        for varname in ROUTERADDRESS; do
            value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
            value="${value#*${varname}=}"
            STRING_TRIM "value"
            eval "${varname}=\"\${value}\""
        done
        if [ -n "${ROUTERADDRESS}" ]; then
            routerHosts="${routerHosts}${routerHosts:+;}${ROUTERADDRESS}"
        fi
    done

    printf "%s\\n" "${routerHosts}"
}

# user pub key comes on stdin
_REMOTE_CREATE_SUPERUSER()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome user]"
    SPACE_DEP="_OS_CREATE_USER OS_MKSUDO_USER"

    local hosthome="${1}"
    shift

    local user="${1}"
    shift

    _OS_CREATE_USER "${user}" &&
    OS_MKSUDO_USER "${user}"
}

_REMOTE_DISABLE_ROOT()
{
    SPACE_SIGNATURE=""
    SPACE_DEP="OS_DISABLE_ROOT"

    OS_DISABLE_ROOT
}

_REMOTE_INIT_HOST()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome clusterID force]"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local clusterID="${1}"
    shift

    local force="${1}"
    shift

    local file="${HOSTHOME}/cluster-id.txt"
    if [ -f "${file}" ]; then
        local id="$(cat "${file}")"
        if [ "${id}" != "${clusterID}" ] && [ "${force}" != "true" ]; then
            return 2
        fi
    fi

    mkdir -p "${HOSTHOME}/pods"

    printf "%s\\n" "${clusterID}" >"${file}"

    # This tells the Daemon where to find our pods.
    local file2="${HOME}/.simplenetes-daemon.conf"
    printf "%s\\n" "${HOSTHOME}" >"${file2}"

    PRINT "Host now belongs to ${clusterID}" "ok" 0
}

_REMOTE_DAEMON_LOG()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome]"

    # TODO: add limits and time windows.
    journalctl -u sntd
}

_REMOTE_LOGS()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome pod podVersion tail since]"
    SPACE_DEP="_GET_TMP_FILE STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local tail="${1:-}"
    local since="${2:-}"

    local podFile="${HOSTHOME}/pods/${pod}/release/${podVersion}/pod"

    if [ ! -f "${podFile}" ]; then
        PRINT "Missing pod: ${pod}:${podVersion}" "error" 0
        return 1
    fi

    ${podFile} logs "" "${tail}" "${since}"
}

# Public key of new user must come on stdin
_REMOTE_HOST_SETUP()
{
    # Actually not optional arguments
    SPACE_SIGNATURE="[hosthome user ports internals]"
    SPACE_DEP="PRINT OS_INSTALL_PKG _OS_CREATE_USER"

    local hosthome="${1}"
    shift

    local user="${1}"
    shift

    local ports="${1}"
    shift

    local internals="${1}"
    shift

    if [ $(id -u) != 0 ]; then
        PRINT "This needs to be run as root." "error" 0
        return 1
    fi

    # Create regular user
    # pub key on stdin
    if ! _OS_CREATE_USER "${user}"; then
        PRINT "Could not create user ${user}" "error" 0
        return 1
    fi

    # Install podman
    if ! OS_INSTALL_PKG "podman"; then
        PRINT "Could not install podman" "error" 0
    fi
    local podmanVersion="$(podman --version)"
    PRINT "Installed ${podmanVersion}" "ok" 0

    # Check /etc/subgid /etc/subuid
        
    if ! grep -q "^${user}:" "/etc/subgid"; then
        PRINT "Adding user to /etc/subgid" "info" 0
        printf "%s:90000:9999\\n" "${user}" >>"/etc/subgid"
        podman system migrate
    fi

    if ! grep -q "^${user}:" "/etc/subuid"; then
        PRINT "Adding user to /etc/subuid" "info" 0
        printf "%s:90000:9999\\n" "${user}" >>"/etc/subuid"
        podman system migrate
    fi

    # Allow for users to bind from port 1 and updwards
    sysctl net.ipv4.ip_unprivileged_port_start=1

    # Configure firewalld
    # TODO: this is tailored for use with how Linode does it on CentOS atm.
    # We might want to add another "internal" zone, instead of adding the rich rule for internal networking onto the default zone.
    if ! command -v firewall-cmd >/dev/null 2>/dev/null; then
        PRINT "firewall-cmd not existing, cannot configure firewall to expose/hide ports. You need to make sure that worker machines are not exposed to the internet, but only to the local network and that the loadbalancers are properly exposed. This problem can go away if you choose a CentOS image." "security" 0
        # Best way to catch users interest is to stall the terminal.
        sleep 3
    else
        local port=
        for port in $(firewall-cmd --list-ports); do
            PRINT "Remove port ${port}" "info" 0
            firewall-cmd --permanent --remove-port "${port}"
        done
        if [ -n "${ports}" ]; then
            local port=
            for port in ${ports}; do
                PRINT "Open port ${port}/tcp" "info" 0
                firewall-cmd --permanent --add-port=${port}/tcp
            done
        fi
        # Remove any preadded ssh service, we do everything using port numbers.
        if firewall-cmd --list-services |grep -q "\<ssh\>"; then
            PRINT "Trim services of firewalld" "info" 0
            firewall-cmd --permanent --remove-service ssh
        fi
        local rules=
        rules="$(firewall-cmd --list-rich-rules)"
        local _ifs="$IFS"
        IFS="
"
        local rule=
        for rule in ${rules}; do
            PRINT "Remove current rich rule: ${rule}" "info" 0
            firewall-cmd --permanent --remove-rich-rule "${rule}"
        done
        IFS="${_ifs}"

        # Add a rule to allow all traffic from internal IPs
        # Without this rule only the specific ports opened are available to the internal networking.
        local network=
        for network in ${internals}; do
            PRINT "Add rich rule for: ${network}" "info" 0
            if ! firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="'${network}'" accept'; then
                PRINT "Could not add internal networking, adding some for rescue mode" "error" 0
                # TODO: not sure this is the correct way of setting the internal networks
                firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" accept'
                firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" accept'
                break
            fi
        done

        PRINT "Reload firewall" "info" 0
        firewall-cmd --reload
    fi

    return

    # TODO
    # Download the simplenetes daemon

    # Make sure the bin is managed by systemd.
    local file="/etc/systemd/system/simplenetes.service"
    local unit="[Unit]
Description=Simplenetes Daemon managing pods and ramdisks
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/bin/simplenetesd
Restart=always

[Install]
WantedBy=multi-user.target"

    printf "%s\\n" "${unit}" >"${file}"

    #systemctl daemon-reload
    systemctl enable simplenetes
    systemctl start simplenetes
}

_REMOTE_ACQUIRE_LOCK()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome token seconds]"
    SPACE_DEP="PRINT STRING_SUBST FILE_STAT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local token="${1}"
    shift

    local seconds="${1}"
    shift

    if [ ! -d "${HOSTHOME}/pods" ]; then
        PRINT "Host is not initialized." "error" 0
        return 1
    fi

    local file="${HOSTHOME}/lock-token.txt"

    if [ -f "${file}" ]; then
        local currentToken="$(cat "${file}")"
        if [ "${currentToken}" = "${token}" ]; then
            # Pass through
            :
        else
            # Check timestamp
            local ts="$(FILE_STAT "${file}" "%Y")"
            local now="$(date +%s)"
            local age="$((now-ts))"
            if [ "${age}" -lt "${seconds}" ]; then
                # Lock busy
                return 2
            fi
        fi
    fi

    printf "%s\\n" "${token}" >"${file}"
}

_REMOTE_SET_COMMITCHAIN()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome gitCommitChain]"
    SPACE_DEP="STRING_SUBST"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local chain="${1}"
    shift

    printf "%s\\n" "${chain}" >"${HOSTHOME}/commit-chain.txt"
}

_REMOTE_RELEASE_LOCK()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome token]"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local token="${1}"
    shift

    local file="${HOSTHOME}/lock-token.txt"

    if [ -f "${file}" ]; then
        local currentToken="$(cat "${file}")"
        if [ "${currentToken}" = "${token}" ]; then
            rm "${file}"
        else
            PRINT "Cannot release lock, because it does not belong to us." "error" 0
            return 2
        fi
    fi
}

# This is run on host and gets the cluster metadata
_REMOTE_GET_HOST_METADATA()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome]"
    SPACE_DEP="STRING_SUBST"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local clusterID="$(cat "${HOSTHOME}/cluster-id.txt" 2>/dev/null)"
    local chain="$(cat "${HOSTHOME}/commit-chain.txt" 2>/dev/null)"
    printf "%s %s\\n" "${clusterID}" "${chain}"
}

# This is run on the host and puts together a list of the current state of the releases of pods.
# From the host download a list of all pods,
# their releases, their states and their configs hashes.
_REMOTE_PACK_RELEASE_DATA()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome]"
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
    for pod in *; do
        if [ ! -d "${pod}/release" ]; then
            continue
        fi
        cd "${pod}/release"

        local release=
        for release in *; do
            if [ ! -d "${release}" ]; then
                continue
            fi
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
            for config in *; do
                if [ ! -d "${config}" ]; then
                    continue
                fi
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

# This is run on the host.
# It retrieves a tar.gz file.
_REMOTE_UPLOAD_ARCHIVE()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome]"
    SPACE_DEP="_GET_TMP_FILE STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    local file="$(_GET_TMP_FILE)"

    PRINT "Receive archive on host to file ${file}" "info" 0

    # Tell the caller what the tmpfilename is.
    printf "%s\\n" "${file}"

    # Receive tar.gz content on stdin and store it to file.
    cat >"${file}"
}

# After sending a tar.gz file to the server we run this
# function on the server to unpack that file.
# It unpacks the file into a tmp directory.
# It will then take each file from tmp dir and mv it to the
# corresponding place in the structure in the pods dir (overwriting).
# If it is a config directory it will delete all files from
# the config and then mv the new files into that same config dir.
# We must keep the config dir because it's inode is mounted into a container
# and creating a new dir will not work unless tearing down the container.
_REMOTE_UNPACK_ARCHIVE()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome targzfile]"
    SPACE_DEP="_GET_TMP_DIR PRINT STRING_SUBST"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local archive="${1}"
    shift

    local tmpDir="$(_GET_TMP_DIR)"

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    PRINT "Unpack archive on host to ${HOSTHOME}" "info" 0

    if ! tar xzf "${archive}" -C "${tmpDir}"; then
        PRINT "Could not unpack archive." "error" 0
        return 1
    fi
    rm "${archive}"

    if ! cd "${tmpDir}"; then
        PRINT "Could not unpack archive as expected." "error" 0
        return 1
    fi

    # Check the cluster-hosts.txt file
    if [ -f "cluster-hosts.txt" ]; then
        PRINT "Update cluster-hosts.txt" "info" 0
        mv -f "cluster-hosts.txt" "${HOSTHOME}"
    fi

    if [ ! -d "pods" ]; then
        # No pods to update
        rm -rf "${tmpDir}"
        PRINT "No pods to update, done unpacking updates." "info" 0
        return 0
    fi

    cd "pods"

    local livePods="${HOSTHOME}/pods"

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    # Start moving files
    local pod=
    for pod in *; do
        if [ ! -d "${pod}/release" ]; then
            continue;
        fi
        cd "${pod}/release"
        local release=
        for release in *; do
            if [ ! -d "${release}" ]; then
                continue
            fi
            cd "${release}"

            PRINT "Update pod ${pod}:${release}" "info" 0

            # Move sh and state files inside release dir
            local dir="${livePods}/${pod}/release/${release}"
            mkdir -p "${dir}"
            local file=
            for file in *; do
                if [ -f "${file}" ]; then
                    # This would be a pod or pod.state file, just move it over to the live location.
                    mv -f "${file}" "${dir}"
                fi
            done

            # Step inside config dir
            if [ ! -d "config" ]; then
                continue
            fi

            # Update the configs in the config dir
            cd "config"
            local config=
            for config in *; do
                if [ ! -d "${config}" ]; then
                    continue
                fi
                # This is a config directory.
                # First empty the current directory,
                # then mv all files over.
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
                for file2 in $(ls -A); do
                    mv -f "${file2}" "${dir}"
                done
                cd ..  # step out of config dir
            done

            # Move checksum files, important to do this after we have moved over config files.
            local dir="${livePods}/${pod}/release/${release}/config"
            local file2=
            for file2 in *; do
                if [ -f "${file2}" ]; then
                    # This would be a chk sum file, move it over.
                    mv -f "${file2}" "${dir}"
                fi
            done
            cd ..  # Step out of "config" dir
            cd .. # Step of out of release version dir
        done
        cd ..  # Step out of "release" dir.
    done
    cd ../.. # Step out of tmpDir
    rm -rf "${tmpDir}"

    PRINT "Done unpacking updates." "info" 0
}

# Connect to host and set the current commit chain.
# We expect the host to be up so we do a few retries in case it fails.
_HOST_SET_CHAIN()
{
    SPACE_SIGNATURE="host gitcommitchain"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT"

    local host="${1}"
    shift

    local gitCommitChain="${1}"
    shift

    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _HOST_SSH_CONNECT "${host}" "set_commit_chain" "${gitCommitChain}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done

    # Failed
    PRINT "Could not set chain." "error" 0
    return 1
}

# Connect to host and set the current commit chain.
# We expect the host to be up so we do a few retries in case it fails.
_HOST_ACQUIRE_LOCK()
{
    SPACE_SIGNATURE="host token"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT"

    local host="${1}"
    shift

    local token="${1}"
    shift

    local seconds=10

    PRINT "Acquire lock using token: ${token}" "info" 0

    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _HOST_SSH_CONNECT "${host}" "acquire_lock" "${token}" "${seconds}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 2 ]; then
            PRINT "Could not acquire lock. Some other sync process might be happening simultanously, aborting. Please try again in a few minutes." "error" 0
            return 2
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done

    # Failed
    PRINT "Could not acquire lock." "error" 0
    return 1
}

_HOST_RELEASE_LOCK()
{
    SPACE_SIGNATURE="host token"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT"

    local host="${1}"
    shift

    local token="${1}"
    shift

    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _HOST_SSH_CONNECT "${host}" "release_lock" "${token}"
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
_HOST_GET_METADATA()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT"

    local host="${1}"
    shift

    local i=
    local status=
    local data=
    # Try three times before failing
    for i in 1 2 3; do
        data="$(_HOST_SSH_CONNECT "${host}" "get_host_metadata")"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            printf "%s\\n" "${data}"
            return 0
        elif [ "${status}" -eq 10 ]; then
            return 1
        fi
    done

    PRINT "Could not get metadata." "error" 0
    # Failed
    return 1
}

HOST_CREATE()
{
    SPACE_SIGNATURE="host [jumphost expose]"
    SPACE_DEP="PRINT _DOES_HOST_EXIST _LOG_C STRING_TRIM STRING_ITEM_INDEXOF"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local jumphost="${1:-}"
    local expose="${2:-}"

    if _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does already exist." "error" 0
        return 1
    fi

    local dir="${CLUSTERPATH}/${host}"
    if [ -d "${dir}" ]; then
        PRINT "Host dir does already exist." "error" 0
        return 1
    fi

    local port=
    for port in ${expose}; do
        case "${port}" in
            (*[!0-9]*)
                PRINT "Invalid port provided: ${port}" "error" 0
                return 1
                ;;
            *)
                ;;
        esac
    done

    STRING_TRIM "jumphost"

    if [ -z "${jumphost}" ] && ! STRING_ITEM_INDEXOF "${expose}" "22"; then
        PRINT "Port 22 not set to be exposed on this host which does not use a JUMPHOST, meaning it will not be accessible at all. Automatically adding port 22 to the exposed ports list." "warning" 0
        expose="${expose}${expose:+ }22"
    fi

    mkdir -p "${dir}"

    printf "%s\\n" "# Auto generated host.env file to be used with the Space ssh module.
# You can enter this host as USER by running \"space -m ssh /ssh/ -e SSHHOSTFILE=host-superuser.env\".

# HOSTHOME is the directory on the host where this local host sync to.
HOSTHOME=\${HOME}/cluster-host
# ROUTERADDRESS is the the IP:port within the cluster where this host's Proxy service can be reached at. Most often localIP:2222.
ROUTERADDRESS=
# HOST is the public or private IP of the Host. If using a JUMPHOST, then it is likely the internal IP, of not the it is the public IP.
HOST=
# The user on the Host which will be running the pods in rootless mode. This should NOT be the root user.
USER=snt
# The path to the SSH keyfile used for this user on this Host.
KEYFILE=./id_rsa
# Expose these ports to the public internet
EXPOSE=${expose}
# The super user which can administer the host
SUPERUSER=sntsuper
# The keyfile of the super user
SUPERKEYFILE=./id_rsa_super
# SSH port this Host is listening on.
PORT=22
# Networks for internal traffic, these are important and the settings depend on the subnets of your hosts.
INTERNAL=192.168.0.0/16 10.0.0.0/8 172.16.0.0/11
# Worker hosts are often not exposed to the public internet and to connect to them over SSH a JUMPHOST is needed.
JUMPHOST=${jumphost}" >"${dir}/host.env"

    printf "%s\\n" "active" >"${dir}/host.state"

    PRINT "Host ${host} created" "ok" 0
    _LOG_C "CREATE_HOST ${host}"
}

HOST_INIT()
{
    SPACE_SIGNATURE="host [force]"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _GET_CLUSTER_ID _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local force="${1:-false}"

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local clusterID=

    if ! clusterID="$(_GET_CLUSTER_ID)"; then
        PRINT "Cannot get the ID for this cluster project." "error" 0
        return 1
    fi

    local i=
    local status=
    # Try one time before failing
    for i in 1; do
        _HOST_SSH_CONNECT "${host}" "init_host" "${clusterID}" "${force}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 2 ]; then
            PRINT "Host already initiated with other cluster ID." "error" 0
            return 2
        elif [ "${status}" -eq 10 ]; then
            break
        fi
    done

    PRINT "Could not init host to cluster." "error" 0

    # Failed
    return 1
}

HOST_DISABLE_ROOT()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _DOES_HOST_EXIST FILE_REALPATH STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    # Load host env file and create a new temporary one
    hostEnv="${CLUSTERPATH}/${host}/host.env"
    hostEnv2="${CLUSTERPATH}/${host}/.host-superuser.env"
    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    local SUPERUSER=
    local SUPERKEYFILE=
    local HOST=
    local PORT=
    local JUMPHOST=

    local value=
    local varname=
    for varname in SUPERUSER SUPERKEYFILE HOST PORT JUMPHOST; do
        value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
        value="${value#*${varname}=}"
        STRING_TRIM "value"
        eval "${varname}=\"\${value}\""
    done

    if [ -z "${SUPERUSER}" ]; then
        PRINT "SUPERUSER not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${SUPERKEYFILE}" ]; then
        PRINT "SUPERKEYFILE not defined in host.env file" "error" 0
        return 1
    fi

    SUPERKEYFILE="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${SUPERKEYFILE}")"

    if [ ! -f "${SUPERKEYFILE}" ]; then
        PRINT "Super user keyfile is missing: ${SUPERKEYFILE}" "info" 0
        return 1
    fi

    # Create the temporary host.env file
    printf "%s\\n" "HOSTHOME=/
HOST=${HOST}
USER=${SUPERUSER}
KEYFILE=${SUPERKEYFILE}
PORT=${PORT}
JUMPHOST=${JUMPHOST}" >"${hostEnv2}"

    local i=
    local status=
    # Try one time before failing
    for i in 1; do
        _HOST_SSH_CONNECT "${host}:${hostEnv2}" "disable_root"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            rm "${hostEnv2}"
            return 0
        fi
    done
    rm "${hostEnv2}"

    PRINT "Could not disable root." "error" 0

    # Failed
    return 1
}

# Looging in as root, create a new super user on the host.
HOST_CREATE_SUPERUSER()
{
    SPACE_SIGNATURE="host keyfile:0"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _DOES_HOST_EXIST SSH_KEYGEN FILE_REALPATH STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local keyfile="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    # Load host env file and create a new temporary one
    hostEnv="${CLUSTERPATH}/${host}/host.env"
    hostEnv2="${CLUSTERPATH}/${host}/.host-root.env"
    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    local SUPERUSER=
    local SUPERKEYFILE=
    local HOST=
    local PORT=
    local JUMPHOST=

    local value=
    local varname=
    for varname in SUPERUSER SUPERKEYFILE HOST PORT JUMPHOST; do
        value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
        value="${value#*${varname}=}"
        STRING_TRIM "value"
        eval "${varname}=\"\${value}\""
    done

    if [ -z "${SUPERUSER}" ]; then
        PRINT "SUPERUSER not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${SUPERKEYFILE}" ]; then
        PRINT "SUPERKEYFILE not defined in host.env file" "error" 0
        return 1
    fi

    SUPERKEYFILE="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${SUPERKEYFILE}")"

    # If keyfile does not exist, we create it.
    if [ ! -f "${SUPERKEYFILE}" ]; then
        PRINT "Create super user keyfile: ${SUPERKEYFILE}" "info" 0
        if ! SSH_KEYGEN "${SUPERKEYFILE}"; then
            PRINT "Could not genereate keyfile" "error" 0
            return 1
        fi
    fi

    local pubKey="${SUPERKEYFILE}.pub"
    if [ ! -f "${SUPERKEYFILE}" ]; then
        PRINT "Could not find ${pubKey} file" "error" 0
        return 1
    fi

    # Create the temporary host.env file
    printf "%s\\n" "HOSTHOME=/
HOST=${HOST}
USER=root
KEYFILE=${keyfile}
PORT=${PORT}
JUMPHOST=${JUMPHOST}" >"${hostEnv2}"

    local i=
    local status=
    # Try one time before failing
    for i in 1; do
        cat "${pubKey}" |_HOST_SSH_CONNECT "${host}:${hostEnv2}" "create_superuser" "${SUPERUSER}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            rm "${hostEnv2}"
            return 0
        fi
    done
    rm "${hostEnv2}"

    PRINT "Could not create super user." "error" 0

    # Failed
    return 1
}

# Run as superuser
HOST_SETUP()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _DOES_HOST_EXIST SSH_KEYGEN STRING_ITEM_INDEXOF STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    # Load host env file and create a new temporary one
    hostEnv="${CLUSTERPATH}/${host}/host.env"
    hostEnv2="${CLUSTERPATH}/${host}/host-superuser.env"
    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    local USER=
    local KEYFILE=
    local SUPERUSER=
    local SUPERKEYFILE=
    local HOST=
    local PORT=
    local JUMPHOST=
    local EXPOSE=
    local INTERNAL=

    local value=
    local varname=
    for varname in USER KEYFILE SUPERUSER SUPERKEYFILE HOST PORT JUMPHOST EXPOSE INTERNAL; do
        value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
        value="${value#*${varname}=}"
        STRING_TRIM "value"
        eval "${varname}=\"\${value}\""
    done

    if [ -z "${USER}" ]; then
        PRINT "USER not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${KEYFILE}" ]; then
        PRINT "KEYFILE not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${SUPERUSER}" ]; then
        PRINT "SUPERUSER not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${SUPERKEYFILE}" ]; then
        PRINT "SUPERKEYFILE not defined in host.env file" "error" 0
        return 1
    fi

    if [ -z "${INTERNAL}" ]; then
        # TODO: not sure this is the correct way of setting the internal networks
        INTERNAL="192.168.0.0/16 10.0.0.0/8 172.16.0.0/11"
        PRINT "INTERNAL not defined in host.env file. Setting default: ${INTERNAL}" "warning" 0
    fi

    local port=
    for port in ${EXPOSE}; do
        case "${port}" in
            (*[!0-9]*)
                PRINT "Invalid EXPOSE port provided: ${port}" "error" 0
                return 1
                ;;
            *)
                ;;
        esac
    done

    # Check internal networking.
    # If HOST is an internal IP address, then internal network MUST be correctly setup otherwise the host will
    # become unreachable from the jumphost.
    if [ "${HOST#192.168}" != "${HOST}" ]; then
        if ! STRING_ITEM_INDEXOF "${INTERNAL}" "192.168.0.0/16"; then
            PRINT "The INTERNAL networks setting does not match the HOST IP, this will likely make local networking not work and hosts becoming unmanagable. Please set INTERNAL value in host.env to reflect the private IP network." "error" 0
            return 1
        fi
    fi
    if [ "${HOST#172.16}" != "${HOST}" ]; then
        if ! STRING_ITEM_INDEXOF "${INTERNAL}" "172.16.0.0/11"; then
            PRINT "The INTERNAL networks setting does not match the HOST IP, this will likely make local networking not work and hosts becoming unmanagable. Please set INTERNAL value in host.env to reflect the private IP network." "error" 0
            return 1
        fi
    fi
    if [ "${HOST#10.}" != "${HOST}" ]; then
        if ! STRING_ITEM_INDEXOF "${INTERNAL}" "10.0.0.0/8"; then
            PRINT "The INTERNAL networks setting does not match the HOST IP, this will likely make local networking not work and hosts becoming unmanagable. Please set INTERNAL value in host.env to reflect the private IP network." "error" 0
            return 1
        fi
    fi

    if [ -z "${JUMPHOST}" ] && ! STRING_ITEM_INDEXOF "${EXPOSE}" "22"; then
        PRINT "Port 22 not set to be exposed on this host which does not use a JUMPHOST, meaning it will not be accessible at all. Automatically adding port 22 to the exposed ports list." "warning" 0
        EXPOSE="${EXPOSE}${EXPOSE:+ }22"
    fi

    SUPERKEYFILE="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${SUPERKEYFILE}")"
    KEYFILE="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${KEYFILE}")"

    # If user keyfile does not exist, we create it.
    if [ ! -f "${KEYFILE}" ]; then
        PRINT "Create user keyfile: ${KEYFILE}" "info" 0
        if ! SSH_KEYGEN "${KEYFILE}"; then
            PRINT "Could not genereate keyfile" "error" 0
            return 1
        fi
    fi

    local pubKey="${KEYFILE}.pub"
    if [ ! -f "${KEYFILE}" ]; then
        PRINT "Could not find ${pubKey}" "error" 0
        return 1
    fi

    # Create the temporary host.env file
    printf "%s\\n" "# Auto generated host.env file to be used with the Space ssh module.
# You can enter this host as USER by running \"space -m ssh /ssh/ -e SSHHOSTFILE=host-superuser.env\".

HOSTHOME=/
HOST=${HOST}
USER=${SUPERUSER}
KEYFILE=${SUPERKEYFILE}
PORT=${PORT}
JUMPHOST=${JUMPHOST}" >"${hostEnv2}"

    local i=
    local status=
    # Try one time before failing
    for i in 1; do
        cat "${pubKey}" |_HOST_SSH_CONNECT "${host}:${hostEnv2}" "setup_host" "${USER}" "${EXPOSE}" "${INTERNAL}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        fi
    done

    PRINT "Could not install setup host" "error" 0

    # Failed
    return 1
}

# Return 10 on internal error which is pointless retrying.
_HOST_SSH_CONNECT()
{
    SPACE_SIGNATURE="host action [args]"
    # This env variable can be baked in at compile time if we want this module to be standalone
    SPACE_ENV="CLUSTERPATH REMOTE_PACK_RELEASEDATA=$ REMOTE_SET_COMMITCHAIN=$ REMOTE_ACQUIRE_LOCK=$ REMOTE_RELEASE_LOCK=$ REMOTE_GET_HOSTMETADATA=$ REMOTE_UPLOAD_ARCHIVE=$ REMOTE_UNPACK_ARCHIVE=$ REMOTE_INIT_HOST=$ REMOTE_HOST_SETUP=$ REMOTE_LOGS=$ REMOTE_DAEMON_LOG=$ REMOTE_CREATE_SUPERUSER=$ REMOTE_DISABLE_ROOT=$"
    SPACE_DEP="SSH PRINT STRING_TRIM"

    local host="${1}"
    shift

    local action="${1}"
    shift

    local hostEnv="${host#*:}"
    if [ "${hostEnv}" != "${host}" ]; then
        host="${host%%:*}"
    else
        hostEnv="${CLUSTERPATH}/${host}/host.env"
    fi

    PRINT "Connect to host ${host} with action: ${action}." "debug"

    # Load host env file
    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 10
    fi

    local HOSTHOME=
    local JUMPHOST=
    local value=
    local varname=
    for varname in HOSTHOME JUMPHOST; do
        value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
        value="${value#*${varname}=}"
        STRING_TRIM "value"
        eval "${varname}=\"\${value}\""
    done

    if [ -z "${HOSTHOME}" ]; then
        PRINT "HOSTHOME must be defined in ${hostEnv}." "error" 0
        return 10
    fi

    if [ "${JUMPHOST}" = "local" ]; then
        PRINT "Connecting directly on local disk using shell" "debug"
    fi

    # Check if we have the script exported already
    local RUN=
    case "${action}" in
        "pack_release_data")
            if [ -n "${REMOTE_PACK_RELEASEDATA}" ]; then
                RUN="${REMOTE_PACK_RELEASEDATA}"
            fi
            ;;
        "set_commit_chain")
            if [ -n "${REMOTE_SET_COMMITCHAIN}" ]; then
                RUN="${REMOTE_SET_COMMITCHAIN}"
            fi
            ;;
        "acquire_lock")
            if [ -n "${REMOTE_ACQUIRE_LOCK}" ]; then
                RUN="${REMOTE_ACQUIRE_LOCK}"
            fi
            ;;
        "release_lock")
            if [ -n "${REMOTE_RELEASE_LOCK}" ]; then
                RUN="${REMOTE_RELEASE_LOCK}"
            fi
            ;;
        "get_host_metadata")
            if [ -n "${REMOTE_GET_HOSTMETADATA}" ]; then
                RUN="${REMOTE_GET_HOSTMETADATA}"
            fi
            ;;
        "upload_archive")
            if [ -n "${REMOTE_UPLOAD_ARCHIVE}" ]; then
                RUN="${REMOTE_UPLOAD_ARCHIVE}"
            fi
            ;;
        "unpack_archive")
            if [ -n "${REMOTE_UNPACK_ARCHIVE}" ]; then
                RUN="${REMOTE_UNPACK_ARCHIVE}"
            fi
            ;;
        "init_host")
            if [ -n "${REMOTE_INIT_HOST}" ]; then
                RUN="${REMOTE_INIT_HOST}"
            fi
            ;;
        "setup_host")
            if [ -n "${REMOTE_HOST_SETUP}" ]; then
                RUN="${REMOTE_HOST_SETUP}"
            fi
            ;;
        "logs")
            if [ -n "${REMOTE_LOGS}" ]; then
                RUN="${REMOTE_LOGS}"
            fi
            ;;
        "daemon-log")
            if [ -n "${REMOTE_DAEMON_LOG}" ]; then
                RUN="${REMOTE_DAEMON_LOG}"
            fi
            ;;
        "create_superuser")
            if [ -n "${REMOTE_CREATE_SUPERUSER}" ]; then
                RUN="${REMOTE_CREATE_SUPERUSER}"
            fi
            ;;
        "disable_root")
            if [ -n "${REMOTE_DISABLE_ROOT}" ]; then
                RUN="${REMOTE_DISABLE_ROOT}"
            fi
            ;;
        *)
            # Unknown action type
            PRINT "Unknown action type: ${action}." "error"
            return 10
            ;;
    esac

    if [ -n "${RUN}" ]; then
        if [ "${JUMPHOST}" = "local" ]; then
            sh -c "${RUN}" "sh" "${HOSTHOME}" "$@"
        else
            SSH "" "" "" "" "" "${hostEnv}" "" "${RUN}" "${HOSTHOME}" "$@"
        fi
    else
        # Run the space target to do this. This is usually only done in dev mode.
        if [ "${JUMPHOST}" = "local" ]; then
            space -L "${SPACE_LOG_LEVEL}" -f "${0}" /_remote_plumbing/${action}/ -- "${HOSTHOME}" "$@"
        else
            space -L "${SPACE_LOG_LEVEL}" -f "${0}" /_remote_plumbing/${action}/ -m ssh /wrap/ -e SSHHOSTFILE="${hostEnv}" -- "${HOSTHOME}" "$@"
        fi
    fi
}

# Get the ID for this cluster.
# The cluster ID is used to verify that when syncing a cluster project to a host the cluster IDs match on both sides.
# This is because only one cluster is allowed per cluster and any attmepts in syncing a second cluster to a host must fail.
_GET_CLUSTER_ID()
{
    SPACE_ENV="CLUSTERPATH"

    local clusterIdFile="${CLUSTERPATH}/cluster-id.txt"

    cat "${clusterIdFile}" 2>/dev/null
}

# Get the list of commit ids for this cluster project.
# output list of short commit ids, leftmost is initial commit, right most is HEAD.
_GET_CLUSTER_GIT_COMMIT_CHAIN()
{
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="STRING_SUBST"

    local chain=
    chain="$(cd "${CLUSTERPATH}" && git log --reverse --oneline --all |cut -d' ' -f1)" 2>/dev/null

    if [ -z "${chain}" ]; then
        return 1
    fi

    local newline="
"
    STRING_SUBST "chain" "${newline}" " " 1

    printf "%s\\n" "${chain}"
}

# Check so that the cluster git project is clean without anything uncommited.
# NOTE: we might want to check so repo is in sync with remote also.
# something like: local txt=$(git log origin/master..HEAD)
_IS_CLUSTER_CLEAN()
{
    SPACE_ENV="CLUSTERPATH"

    local dirtyFiles=
    if ! dirtyFiles="$(cd "${CLUSTERPATH}" && git status -s --porcelain)"; then
        return 1
    fi

    if [ -n "${dirtyFiles}" ]; then
        # Check if it is the log files which are dirty, that we will allow.
        local fileNames="$(printf "%s\\n" "${dirtyFiles}" |awk '{print $NF}')"
        local file=
        for file in ${fileNames}; do
            if [ "${file}" = "log.txt" ]; then
                continue
            fi
            if [ "${file#_synclogs/}" != "${file}" ]; then
                continue
            fi
            if [ "${file#*/*/*/log.txt}" != "${file}" ]; then
                continue
            fi
            return 1
        done
    fi

    return 0
}

CLUSTER_STATUS()
{
    :
    # TODO
}

LIST_PODS()
{
    SPACE_ENV="PODPATH"
    (cd "${PODPATH}" && find . -maxdepth 2 -mindepth 2 -type f -name pod.yaml |cut -d/ -f2)
}

HELP()
{
    local text="Simplenetes version 0.1
Try: /pods/list/
"
    printf "%s" "${text}" >&2
}

LIST_HOSTS()
{
    SPACE_SIGNATURE="[filter]"
    SPACE_DEP="_LIST_HOSTS"
    SPACE_ENV="CLUSTERPATH"

    local filter="${1:-0}"

    _LIST_HOSTS "${CLUSTERPATH}" "${filter}"
}

ATTACH_POD()
{
    SPACE_SIGNATURE="host pod"
    SPACE_DEP="PRINT _DOES_HOST_EXIST _IS_POD_ATTACHED _LOG _LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    if _IS_POD_ATTACHED "${CLUSTERPATH}" "${host}" "${pod}"; then
        PRINT "Pod ${pod} already exists on host ${host}." "error" 0
        return 1
    fi

    if ! mkdir -p "${CLUSTERPATH}/${host}/pods/${pod}"; then
        PRINT "Could not create directory." "error" 0
        return 1
    fi

    _LOG "${host}" "${pod}" "ATTACHED"

    PRINT "Pod was attached" "ok" 0

    # Check if this was the first pod on the hosts, if so suggest to also add any pod configs into the cluster.
    local hosts=
    hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    if [ "${hosts}" = "${host}" ]; then
        if [ ! -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "This was the first attachement of this pod to this cluster, if there are configs you might want to import them into the cluster at this point." "info" 0
        fi
    fi
}

DETACH_POD()
{
    SPACE_SIGNATURE="host pod"
    SPACE_DEP="PRINT _DOES_HOST_EXIST _IS_POD_ATTACHED _LOG _LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" "info" 0
        return 1
    fi

    if ! _IS_POD_ATTACHED "${CLUSTERPATH}" "${host}" "${pod}"; then
        PRINT "Pod ${pod} does not exist on host." "error" 0
        return 1
    fi

    local ts="$(date +%s)"

    _LOG "${host}" "${pod}" "DETACHED"

    if ! mv "${CLUSTERPATH}/${host}/pods/${pod}" "${CLUSTERPATH}/${host}/pods/.${pod}.${ts}"; then
        PRINT "Unexpected disk failure when detaching pod." "error" 0
        return 1
    fi

    PRINT "Pod was detached" "ok" 0

    # Check if this was the last pod on the hosts, if so suggest to remove any pod configs in the cluster.
    local hosts=
    hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    if [ -z "${hosts}" ]; then
        if [ -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "There are no more pods of this sort left in this cluster, but there are configs still. You can remove those configs if you want to." "info" 0
        fi
    fi
}

CLUSTER_IMPORT_POD_CFG()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="PRINT _LOG_C _GET_TAG_DIR FILE_REALPATH _LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH PODPATH"

    local pod="${1}"
    shift

    local hosts="$(_LIST_ATTACHEMENTS "${pod}")"

    if [ -z "${hosts}" ]; then
        PRINT "Pod '${pod}' is not attached to this cluster." "error" 0
        return 1
    fi

    local podConfigDir="$(FILE_REALPATH "${PODPATH}/${pod}/config")"

    if [ ! -d "${podConfigDir}" ]; then
        PRINT "Pod '${pod}' has no configs to be imported." "info" 0
        return 0
    fi

    local clusterPodConfigDir="${CLUSTERPATH}/_config/${pod}"
    PRINT "Source: Pod config template dir: ${podConfigDir}" "info" 0
    PRINT "Target: Cluster pod config dir: ${clusterPodConfigDir}" "info" 0

    mkdir -p "${CLUSTERPATH}/_config"

    local configCommit=
    if ! configCommit="$(_GET_TAG_DIR "${podConfigDir}")"; then
        return 1
    fi

    if [ -d "${clusterPodConfigDir}" ]; then
        PRINT "cluster config for the pod '${pod}' already exists, will not overwrite" "error" 0
        return 1
    fi

    if ! cp -r "${podConfigDir}" "${clusterPodConfigDir}"; then
        PRINT "Unexpected disk failure importing configs to cluster project." "error" 0
        return 1
    fi

    PRINT "Configs copied" "ok" 0

    _LOG_C "IMPORT_POD_CFG ${pod}:${configCommit}"
}

# Compiles a pod to all hosts it is attached to.
COMPILE_POD()
{
    SPACE_SIGNATURE="pod host:0"
    SPACE_DEP="PRINT _LIST_ATTACHEMENTS _LOG _GET_TAG_FILE _DOES_HOST_EXIST STRING_SUBST STRING_TRIM UPDATE_POD_CONFIG _GET_TAG_DIR STRING_ESCAPE _GET_FREE_HOSTPORT TEXT_FILTER TEXT_VARIABLE_SUBST TEXT_EXTRACT_VARIABLES _COPY_POD_CONFIGS _CHKSUM_POD_CONFIGS FILE_REALPATH _LIST_ATTACHEMENTS STRING_ITEM_INDEXOF"
    SPACE_ENV="CLUSTERPATH PODPATH"

    local pod="${1}"
    shift

    local host="${1}"
    shift

    local attachedHosts="$(_LIST_ATTACHEMENTS "${pod}")"

    if [ -z "${attachedHosts}" ]; then
        PRINT "Pod '${pod}' is not attached to this cluster." "error" 0
        return 1
    fi

    local clusterConfig="${CLUSTERPATH}/cluster-vars.env"
    if ! [ -f "${clusterConfig}" ]; then
        PRINT "Pod cluster config ${clusterConfig} not found." "error" 0
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi
        if ! STRING_ITEM_INDEXOF "${attachedHosts}" "${host}"; then
            PRINT "Pod '${pod}' is not attached to host '${host}'." "error" 0
            return 1
        fi
        hosts="${host}"
    else
        hosts="${attachedHosts}"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod ${pod} is not attached to any hosts." "warning" 0
        return 0
    fi

    local podSpec="$(FILE_REALPATH "${PODPATH}/${pod}/pod.yaml")"

    local podCommit=
    if ! podCommit="$(_GET_TAG_FILE "${podSpec}")"; then
        return 1
    fi

    local clusterCommit=
    if ! clusterCommit="$(_GET_TAG_FILE "${clusterConfig}")"; then
        return 1
    fi

    local configCommit="<none>"
    if [ ! -d "${CLUSTERPATH}/_config/${pod}" ]; then
        PRINT "No configs exist in the cluster for this pod" "info" 0
    else
        if ! configCommit="$(_GET_TAG_DIR "${CLUSTERPATH}/_config/${pod}")"; then
            return 1
        fi
    fi

    if ! command -v podc >/dev/null 2>/dev/null; then
        PRINT "podc not available on path, cannot compile pod." "error" 0
        return 1
    fi

    ## Now everything is setup for us to compile the pod onto each host it is attached to.

    local status=0  # Status flag checked after the for-loop.
    local podsCompiled=""  # Keep track of all pods compiled so we can remove them if we encounter an error.
    local host=
    for host in ${hosts}; do
        # Perform variable substitution
        ## 1. Extract variables used in pod.yaml file
        ## 2. Inspect those to see if any are ${HOSTPORTAUTOxyz}, then for each 'xyz' we find a free host port on the host to assign that variable.
        ## 3. Load cluster variables from cluster config, apply all HOSTPORTAUTOxyz variables from previous step.
        ## 4. Substitute each variable in pod.yaml with value from variables in step 3.
        ## Note: If wanting to use default values such as ${var:-default}, then such a subsequent step can be added to parse again after the first substitution.

        local text="$(cat "${podSpec}")"
        local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${text}")"
        local newline="
"
        STRING_SUBST "variablesToSubst" "${newline}" " " 1

        # For each ${HOSTPORTAUTOxyz} we define that variable now.
        local variablesToSubst2=""  # Use this to filter out HOSTPORTAUTOx variables, just for display
        local values=""
        local newPorts=""
        local varname=
        for varname in ${variablesToSubst}; do
            local hpindex="${varname#HOSTPORTAUTO}"
            if [ "${varname}" != "${hpindex}" ]; then
                # This is a auto host port assignment,
                # we need to find a port and assign the variable.
                local newport=
                if ! newport="$(_GET_FREE_HOSTPORT "${host}" "${newPorts}")"; then
                    PRINT "Could not acquire a free port on the host ${host}." "error" 0
                    status=1
                    break 2
                fi
                newPorts="${newPorts} ${newport}"
                values="${values}${values:+${newline}}${varname}=${newport}"
            else
                variablesToSubst2="${variablesToSubst2}${variablesToSubst2:+ }${varname}"
            fi
        done

        PRINT "Variable names extracted from pod.yaml and read from cluster-vars.env: ${variablesToSubst2}" "info" 0

        # Note: we could also allow host specific vars, but it might not be needed
        values="${values}${values:+${newline}}$(cat "${clusterConfig}")"

        ## For each variable identified in pod.yaml, iterate over it and substitute it for it's value
        text="$(TEXT_VARIABLE_SUBST "${text}" "${variablesToSubst}" "${values}")"
        text="$(printf "%s\\n" "${text}" |TEXT_FILTER)"

        local podVersion="$(printf "%s\\n" "${text}" |grep -o "^podVersion:[ ]*['\"]\?\([0-9]\+\.[0-9]\+\.[0-9]\+\(-[-.a-z0-9]\+\)\?\)")"
        podVersion="${podVersion#*:}"
        STRING_SUBST "podVersion" "'" "" 1
        STRING_SUBST "podVersion" '"' "" 1
        STRING_TRIM "podVersion"

        if [ -z "${podVersion}" ]; then
            PRINT "podVersion is missing. Must be on semver format (major.minor.patch[-tag])." "error" 0
            return 1
        fi

        local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"

        if [ -d "${targetPodDir}" ]; then
            PRINT "Pod ${pod} version ${podVersion} already exists on host ${host}. Skipping." "info" 0
            continue;
        fi

        if ! mkdir -p "${targetPodDir}"; then
            PRINT "Could not create directory: ${targetPodDir}" "error" 0
            status=1
            break
        fi

        podsCompiled="${podsCompiled} ${targetPodDir}"

        PRINT "Pod ${pod} version ${podVersion} compiling for host ${host}." "info" 0

        local tmpPodSpec="${targetPodDir}/.pod.yaml"
        local targetPodSpec="${targetPodDir}/pod"
        PRINT "Parse yaml for pod ${pod} to host ${host} as ${tmpPodSpec}." "debug" 0

        # Save the preprocessed yaml.
        printf "%s\\n" "${text}" >"${tmpPodSpec}"

        # Copy configs into release
        if [ -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "Copy configs from cluster into pod release." "info" 0
            if ! _COPY_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                status=1
                break
            fi
        fi

        if ! podc "${pod}" "${tmpPodSpec}" "${targetPodSpec}" "${podSpec%/*}" "false"; then
            status=1
            break
        fi

        # Checksum configs, we do this after compiling since comilation can add to configs.
        if [ -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "Checksum configs in release." "info" 0
            if ! _CHKSUM_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                status=1
                break
            fi
        fi

        # Set state as running.
        local targetpodstate="${targetPodDir}/pod.state"
        printf "%s\\n" "running" >"${targetpodstate}"

        _LOG "${host}" "${pod}" "COMPILE_POD release:${podVersion} pod.yaml:${podCommit} cluster-vars.env:${clusterCommit} cfg:${configCommit}"
    done

    if [ "${status}" -gt 0 ] && [ -n "${podsCompiled}" ]; then
        PRINT "Removing compiled pods" "info" 0
        local dir=
        for dir in ${podsCompiled}; do
            rm -rf "${dir}"
        done
        return 1
    fi
}

_GET_FREE_HOSTPORT()
{
    SPACE_SIGNATURE="host reservedPorts:0"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="PRINT"

    local host="${1}"
    shift

    local reservedPorts="${1}"

    local dir="${CLUSTERPATH}/${host}/pods"

    # Extract hostPorts from the proxy config lines.
    local pod_hostports="$(cd "${dir}" && find . -regex "^./[^.][^/]*/release/[^.][^/]*/pod.proxy.conf\$" -exec cat {} \; |cut -d ':' -f2)"
    local usedPorts="${pod_hostports#*[\"]}"
    usedPorts="${usedPorts%[\"]*}"

    local port=29999
    local p=
    while true; do
        port=$((port+1))
        for p in ${usedPorts}; do
            if [ "${p}" -eq "${port}" ]; then
                continue 2
            fi
        done
        for p in ${reservedPorts}; do
            if [ "${p}" -eq "${port}" ]; then
                continue 2
            fi
        done
        break
    done

    if [ "${port}" -gt 32000 ]; then
        PRINT "All ports between 30000-32000 are already claimed on host ${host}." "error" 0
        return 1
    fi

    printf "%s\\n" "${port}"
}

_GET_TAG_DIR()
{
    SPACE_SIGNATURE="dir"
    SPACE_DEP="PRINT"

    local dir="${1}"
    shift

    if [ ! -d "${dir}" ]; then
        PRINT "${dir} does not exist." "error" 0
        return 1
    fi

    local text=
    if ! text="$(cd "${dir}" && git status -s --porcelain -- ./)"; then
        PRINT "${dir} is not a git repo" "error" 0
        return 1
    fi

    if [ -n "${text}" ]; then
        PRINT "${dir} has uncommitted changes." "warning" 0
        printf "%s\\n" "<unknown>"
        return 0
    fi

    local commitId=
    if ! commitId="$(cd "${dir}" && git rev-list -1 HEAD -- ./)"; then
        PRINT "${dir} is not comitted." "warning" 0
        printf "%s\\n" "<unknown>"
        return 0
    fi

    local tag=
    tag="$(cd "${dir}" && git describe "${commitId}" --always --tags 2>/dev/null)"

    tag="${tag:-${commitId}}"

    printf "%s\\n" "${tag}"
}

# Copy configs from general cluster pod config store into this version of the pod.
UPDATE_POD_CONFIG()
{
    SPACE_SIGNATURE="pod version host:0"
    SPACE_DEP="PRINT _GET_TAG_DIR _DOES_HOST_EXIST _LIST_ATTACHEMENTS _LOG _COPY_POD_CONFIGS _CHKSUM_POD_CONFIGS"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local host="${1}"
    shift

    if [ ! -d "${CLUSTERPATH}/_config/${pod}" ]; then
        PRINT "_config/${pod} does not exist in cluster, maybe import them first?" "error" 0
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod ${pod} is not attached to any hosts." "warning" 0
        return 0
    fi

    local configCommit=
    if ! configCommit="$(_GET_TAG_DIR "${CLUSTERPATH}/_config/${pod}")"; then
        return 1
    fi

    local host=
    for host in ${hosts}; do
        if [ -d "${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}" ]; then
            PRINT "Copy ${pod} configs from cluster into release ${podVersion} on host ${host}." "info" 0
            rm -rf "${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}/config"
            if ! _COPY_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                return 1
            fi
            if ! _CHKSUM_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                return 1
            fi
        else
            PRINT "Release ${podVersion} does not exist on host ${host}, skipping." "info" 0
            continue
        fi

        _LOG "${host}" "${pod}" "UPDATE_CONFIG release:${podVersion} cfg:${configCommit}"
    done
}

# Copy config from cluster config store to pod release.
# Do not copy underscore prefixed configs.
_COPY_POD_CONFIGS()
{
    SPACE_SIGNATURE="clusterPath host pod podVersion"
    SPACE_DEP="PRINT"

    local clusterPath="${1}"
    shift

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local config=

    if [ ! -d "${clusterPath}/_config/${pod}" ]; then
        PRINT "Missing ${clusterPath}/_config/${pod}" "error" 0
        return 1
    fi

    if ! ( cd "${clusterPath}/_config/${pod}"
        for config in *; do
            if [ ! -d "${config}" ] || [ "${config#_}" != "${config}" ]; then
                # Not dir or underscore prefixed config, skip it.
                continue
            fi
            if ! mkdir -p "${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config/${config}"; then
                return 1
            fi
            if ! cp -r "${clusterPath}/_config/${pod}/${config}" "${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config"; then
                return 1
            fi
        done
    ); then
        PRINT "Could not copy configs to pod release." "error" 0
        return 1
    fi
}

# Take checksum on each pod config
_CHKSUM_POD_CONFIGS()
{
    SPACE_SIGNATURE="clusterPath host pod podVersion"
    SPACE_DEP="FILE_DIR_CHECKSUM_CONTENT PRINT"

    local clusterPath="${1}"
    shift

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local config=

    if [ ! -d  "${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config/" ]; then
        return 0
    fi

    if ! ( cd "${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config/"
        for config in *; do
            if [ ! -d "${config}" ]; then
                # Not dir, skip it.
                continue
            fi
            # Create checksum
            local dir="${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config/${config}"
            local chksum=
            if ! chksum="$(FILE_DIR_CHECKSUM_CONTENT "${dir}")"; then
                PRINT "Could not take checksum" "error" 0
                return 1
            fi
            local file="${clusterPath}/${host}/pods/${pod}/release/${podVersion}/config/${config}.txt"
            printf "%s\\n" "${chksum}" >"${file}"
        done
    ); then
        PRINT "Could not copy configs to pod release." "error" 0
        return 1
    fi
}

LIST_HOSTS_BY_POD()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="_LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    _LIST_ATTACHEMENTS "${pod}"
}

LIST_PODS_BY_HOST()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="PRINT _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    (cd "${CLUSTERPATH}" && find . -maxdepth 4 -mindepth 4 -regex "^./${host}/pods/[^.][^/]*/log\.txt$" |cut -d/ -f4)
}

# Set the pod.version.state file
SET_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="pod version state host:0"
    SPACE_DEP="_LIST_ATTACHEMENTS _ENUM_STATE PRINT _LOG _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local state="${1}"
    shift

    local host="${1}"
    shift

    if ! _ENUM_STATE "${state}"; then
        PRINT "Given state is not a valid state: ${state}. Valid states are: removed, created, running, stopped" "error" 0
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod is not attached to any hosts." "warning" 0
        return 0
    fi

    local host=
    for host in ${hosts}; do
        local stateFile="pod.state"
        local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"
        local targetPodStateFile="${targetPodDir}/${stateFile}"

        if [ ! -d "${targetPodDir}" ]; then
            PRINT "Pod ${pod}:${podVersion} not found on host ${host}. Skipping." "info" 0
            continue
        fi


        PRINT "Set state of release ${podVersion} on host ${host} to ${state}." "ok" 0

        printf "%s\\n" "${state}" >"${targetPodStateFile}"

        _LOG "${host}" "${pod}" "SET_POD_RELEASE_STATE release:${podVersion}=${state}"
    done
}

# Return the pod.version.state file
GET_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="pod version host:0"
    SPACE_DEP="_LIST_ATTACHEMENTS PRINT _DOES_HOST_EXIST _GET_POD_RELEASE_STATE"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local host="${1}"
    shift

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}";
    else
        hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    [ -z "${hosts}" ] && {
        PRINT "Pod is not attached to any hosts." "warning" 0
        return 0;
    }

    local host=
    for host in ${hosts}; do
        local state=
        if ! state="$(_GET_POD_RELEASE_STATE "${host}" "${pod}" "${podVersion}")"; then
            PRINT "Version ${podVersion} not found on host ${host}. Skipping." "debug" 0
            continue;
        fi
        printf "%s: %s\\n" "${host}" "${state}"
    done
}

# Connect to the cluster and retrieve logs for a pod instance.
DAEMON_LOG()
{
    SPACE_SIGNATURE="host:0"
    SPACE_DEP="PRINT _DOES_HOST_EXIST _HOST_DAEMON_LOG _LIST_HOSTS"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi
        hosts="${host}";
    else
        hosts="$(_LIST_HOSTS "${CLUSTERPATH}" 1)"
    fi
    unset host

    [ -z "${hosts}" ] && {
        PRINT "No hosts active" "warning" 0
        return 0;
    }

    local host=
    for host in ${hosts}; do
        printf "Daemon logs for host '%s':\\n" "${host}"
        _HOST_DAEMON_LOG "${host}"
    done
}

_HOST_DAEMON_LOG()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local i=
    local status=
    # Try three times before failing
    for i in 1 2 3; do
        _HOST_SSH_CONNECT "${host}" "daemon-log"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 10 ]; then
            break
        fi
    done

    PRINT "Could not get daemon log from host" "error" 0

    # Failed
    return 1
}
# Connect to the cluster and retrieve logs for a pod instance.
LOGS()
{
    SPACE_SIGNATURE="pod version host:0 [tail since]"
    SPACE_DEP="_LIST_ATTACHEMENTS PRINT _DOES_HOST_EXIST _GET_POD_RELEASE_STATE _HOST_LOGS"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local host="${1}"
    shift

    local tail="${1:-}"
    local since="${2:-}"

    local hosts=
    if [ -n "${host}" ]; then
        if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi

        hosts="${host}";
    else
        hosts="$(_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    [ -z "${hosts}" ] && {
        PRINT "Pod is not attached to any hosts." "warning" 0
        return 0;
    }

    local host=
    for host in ${hosts}; do
        local state=
        if ! state="$(_GET_POD_RELEASE_STATE "${host}" "${pod}" "${podVersion}")"; then
            PRINT "Version ${podVersion} not found on host ${host}. Skipping." "debug" 0
            continue;
        fi
        if [ "${state}" = "running" ] || [ "${state}" = "stopped" ]; then
            printf "Logs for pod '%s:%s' on host '%s':\\n" "${pod}" "${podVersion}" "${host}"
            _HOST_LOGS "${host}" "${pod}" "${podVersion}" "${tail}" "${since}"
        else
            PRINT "Pod ${pod}:${podVersion} is not running/stopped on host ${host}, cannot get logs." "info" 0
            continue
        fi
    done
}

_HOST_LOGS()
{
    SPACE_SIGNATURE="host pod podVersion [tail since]"
    SPACE_DEP="_HOST_SSH_CONNECT PRINT _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local tail="${1:-}"
    local since="${2:-}"


    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local i=
    local status=
    # Try one times before failing
    for i in 1; do
        _HOST_SSH_CONNECT "${host}" "logs" "${pod}" "${podVersion}" "${tail}" "${since}"
        status="$?"
        if [ "${status}" -eq 0 ]; then
            return 0
        elif [ "${status}" -eq 10 ]; then
            break
        fi
    done

    PRINT "Could not get logs from host." "error" 0

    # Failed
    return 1
}

_GET_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="host pod podVersion"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"
    local stateFile="pod.state"
    local targetPodStateFile="${targetPodDir}/${stateFile}"

    if [ -f "${targetPodStateFile}" ]; then
        local state="$(cat "${targetPodStateFile}")"
        printf "%s\\n" "${state}"
    else
        return 1
    fi
}

_GET_POD_RELEASES()
{
    SPACE_SIGNATURE="host pod"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    (cd "${CLUSTERPATH}/${host}" && find . -maxdepth 5 -mindepth 5 -regex "^./pods/[^.][^/]*/release/[^.][^/]*/pod\$" |cut -d/ -f5)
}

_GET_POD_RUNNING_RELEASES()
{
    SPACE_SIGNATURE="host pod"
    SPACE_DEP="_GET_POD_RELEASE_STATE _GET_POD_RELEASES"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local versions="$(_GET_POD_RELEASES "${host}" "${pod}")"

    for version in ${versions}; do
        local state="$(_GET_POD_RELEASE_STATE "${host}" "${pod}" "${version}")"
        if [ "${state}" = "running" ]; then
            printf "%s\\n" "${version}"
        fi
    done
}

# Generate config for haproxy
GEN_INGRESS_CONFIG()
{
    SPACE_SIGNATURE="[ingressPod excludeClusterPorts]"
    SPACE_DEP="PRINT _GET_TMP_DIR _LIST_HOSTS LIST_PODS_BY_HOST _EXTRACT_INGRESS _GET_POD_RUNNING_RELEASES STRING_ITEM_INDEXOF _GEN_INGRESS_CONFIG2 TEXT_EXTRACT_VARIABLES TEXT_VARIABLE_SUBST TEXT_FILTER"
    SPACE_ENV="CLUSTERPATH"

    local ingressPod="${1:-ingress}"
    shift

    local excludeClusterPorts="${1:-}"

    local ingressTplDir="${CLUSTERPATH}/_config/${ingressPod}/_tpl"
    local ingressConfDir="${CLUSTERPATH}/_config/${ingressPod}/conf"

    if [ ! -d "${ingressTplDir}" ]; then
        PRINT "Ingress pod ${ingressPod} has no tpl configs in the cluster. Maybe you should import configs for the ingress pod first?" "error" 0
        return 1
    fi

    # For each host and each running pod release:
    # extract all ingress objects from the pod file,
    # merge and translate into haproxy config format.

    local tmpDir=
    if ! tmpDir="$(_GET_TMP_DIR)"; then
        PRINT "Could not create temporary directory." "error" 1
        return 1;
    fi

    PRINT "Using temporary directory: ${tmpDir}" "debug" 0

    local hosts=
    hosts="$(_LIST_HOSTS "${CLUSTERPATH}" 2)"

    # To keep track of pod:releases we already have generated ingress for.
    # Since it doesn't matter what host a pod is on when we generate ingress we
    # only need to do it once for every specific pod release.
    doneReleases=""

    local host=
    for host in ${hosts}; do
        PRINT "Processing pods on host ${host}" "info" 0

        local pods="$(LIST_PODS_BY_HOST "${host}")"
        local pod=
        for pod in ${pods}; do
            if [ "${pod}" = "${ingressPod}" ]; then
                continue
            fi
            local versions="$(_GET_POD_RUNNING_RELEASES "${host}" "${pod}")"
            if [ "${versions}" = "" ]; then
                PRINT "Pod ${pod} on ${host} has no running releases, skipping." "info" 0
                continue
            fi
            PRINT "Pod ${pod} on ${host} has running releases: ${versions}" "info" 0
            local version=
            for version in ${versions}; do
                local podFile="${CLUSTERPATH}/${host}/pods/${pod}/release/${version}/pod"
                if [ ! -f "${podFile}" ]; then
                    PRINT "Pod ${pod} release:${version} executable on ${host} is missing." "error" 0
                    return 1
                fi

                # Check if we already done this pod:release
                if STRING_ITEM_INDEXOF "${doneReleases}" "${pod}:${version}"; then
                    PRINT "Release ${version} already processed, moving on." "info" 0
                    continue
                fi
                doneReleases="${doneReleases} ${pod}:${version}"

                PRINT "Generating ingress for ${pod} release:${version} on ${host}" "info" 0

                if ! _EXTRACT_INGRESS "${podFile}" "${tmpDir}" "${host}" "${pod}" "${excludeClusterPorts}"; then
                    return 1
                fi
            done
        done
    done

    local haproxyConf=
    if ! haproxyConf="$(_GEN_INGRESS_CONFIG2 "${tmpDir}" "${ingressTplDir}")"; then
        PRINT "Could not generate ingress conf. Debug output is in ${tmpDir}." "error" 0
        return 1
    fi

    # Perform variable substitution on conf.
    local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${haproxyConf}")"
    local clusterConfig="${CLUSTERPATH}/cluster-vars.env"
    local values="$(cat "${clusterConfig}")"

    # Check so that all variables are present
    local varname=
    for varname in ${variablesToSubst}; do
        if ! printf "%s\\n" "${values}" |grep -m 1 "^${varname}=" >/dev/null; then
            PRINT "Missing variable definition of ${varname} in cluster-vars.env" "warning" 0
        fi
    done

    haproxyConf="$(TEXT_VARIABLE_SUBST "${haproxyConf}" "${variablesToSubst}" "${values}")"
    haproxyConf="$(printf "%s\\n" "${haproxyConf}" |TEXT_FILTER)"

    # Save conf in ingress pod cfg, if changed.
    mkdir -p "${ingressConfDir}"
    local haproxyConfPath="${ingressConfDir}/haproxy.cfg"
    # Diff current haproxy.cfg with newley generated one
    if ! (printf "%s\\n" "${haproxyConf}" |diff "${haproxyConfPath}" - >/dev/null 2>&1); then
        # Different
        PRINT "Updating haproxy.cfg in ${ingressConfDir}" "ok" 0
        printf "%s\\n" "${haproxyConf}" >"${haproxyConfPath}"
    else
        PRINT "No changes in ingress to be made." "ok" 0
    fi

    rm -rf "${tmpDir}"
}

# Take all frontend files to create frontends
# and all backend files to create backends,
# to produce a viable haproxy.cfg.
_GEN_INGRESS_CONFIG2()
{
    SPACE_SIGNATURE="tmpDir ingressTplDir"

    local tmpDir="${1}"
    shift

    local ingressTplDir="${1}"
    shift

    # check so that there are frontend and backend files generated before continuing
    local frontends=
    frontends="$( cd "${tmpDir}" && find -regex "^./[0-9]+-[^-]+\.frontend" )"
    local backends=
    backends="$( cd "${tmpDir}" && find -regex "^./[^-]+-.+\.backend" )"

    if [ -z "${frontends}" ] || [ -z "${backends}" ]; then
        PRINT "No ingress has been generated." "warning" 0
        return 1
    fi

    if ! cat "${ingressTplDir}/main.tpl"; then
        return 1
    fi

    # For all .frontend files,
    # sort rows on importance (first column) desc,
    # create frontend line in haproxy.cfg with bind and possble ssl cert params.
    # create a rule for each criterion and use hash as backend
    local frontend=
    for frontend in ${frontends}; do
        local bind=
        bind="${frontend%%-*}"
        bind="${bind#*/}"
        local protocol=
        protocol="${frontend%.frontend}"
        protocol="${protocol#*-}"
        local frontendextra=""
        if [ "${protocol}" = "https" ]; then
            frontendextra=" ssl crt /mnt/haproxy-certs"
        fi
        printf "\\nfrontend %s-%s\\n" "${bind}" "${protocol}"
        printf "    bind :%s%s\\n" "${bind}" "${frontendextra}"
        if ! awk '{$0="    "$0; print}' "${ingressTplDir}/frontend-${protocol}.tpl"; then
            return 1
        fi
        local sortedfile="${tmpDir}/${frontend}.sorted"
        sort "${tmpDir}/${frontend}" -n -r > "${sortedfile}"
        while IFS='' read -r line; do
            local backendName="${line#* }"
            backendName="${backendName%% *}"
            local aclfile="${tmpDir}/${frontend}.${backendName}"
            if ! awk '{$0="    "$0; print}' "${aclfile}"; then
                return 1
            fi
        done < "${sortedfile}"
    done

    # For all .backend files,
    # create backend entries in haproxy.cfg
    # and add all servers to it
    local backend=
    for backend in ${backends}; do
        local name=
        name="${backend%%-*}"
        name="${name#*/}"
        local mode=
        mode="${backend%.backend}"
        mode="${mode#*-}"
        printf "\\nbackend %s\\n" "${name}"
        if ! awk '{$0="    "$0; print}' "${ingressTplDir}/backend-${mode}.tpl"; then
            return 1
        fi
        while IFS='' read -r line; do
            printf "    %s\\n" "${line}"
        done < "${tmpDir}/${backend}"
    done
}

_EXTRACT_INGRESS()
{
    SPACE_SIGNATURE="podfile tmpDir host pod excludeClusterPorts"
    SPACE_DEP="PRINT CONF_READ FILE_ROW_PERSIST STRING_TRIM STRING_HASH STRING_ITEM_INDEXOF"

    local podfile="${1}"
    shift

    local tmpDir="${1}"
    shift

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local excludeClusterPorts="${1}"
    shift

    local ingressConf="${podfile}.ingress.conf"

    if [ ! -f "${ingressConf}" ]; then
        return
    fi

    # Loop through the conf file and extract each ingress block
    local out_conf_lineno=0
    local rule_count=0
    while [ "${out_conf_lineno}" -gt -1 ]; do
        rule_count=$((rule_count+1))
        local ingress=
        local importance=
        local bind=
        local protocol=
        local host=
        local path_beg=
        local path_end=
        local path=
        local clusterport=
        local redirect_to_https=
        local redirect_location=
        local redirect_prefix=
        local errorfile=
        CONF_READ "${ingressConf}" "ingress importance bind protocol clusterport host path path_end path_beg redirect_to_https redirect_location redirect_prefix errorfile"
        if [ -n "${bind}" ] && [ -n "${protocol}" ]; then
            # Do nothing, fall through
            :
        else
            if [ "${out_conf_lineno}" -eq -1 ]; then
                continue
            fi
            PRINT "Ingress config is not complete." "error" 0
            return 1
        fi

        if [ -n "${clusterport}" ]; then
            # Check if the clusterport is on the ignore list
            if STRING_ITEM_INDEXOF "${excludeClusterPorts}" "${clusterport}"; then
                PRINT "Ignoring ingress for clusterPort ${clusterport}." "warning" 0
                continue;
            fi

            # TODO: Check so that clusterport is within the accepted range.
        fi

        local bindport="${bind%*:}"

        # Check if this bind (port) is already defined and if so that is has the same protocol.
        local file="$(cd "${tmpDir}" && find -name "${bind}-*.frontend")"
        if [ -n "${file}" ]; then
            # It is, now check so that it is defined for the same protocol.
            local proto2="${file#*-}"
            proto2="${proto2%.frontend}"
            if [ "${proto2}" != "${protocol}" ]; then
                PRINT "Mismatching protocols for bind ${bind} (${proto2} and ${protocol}). Only one protocol allowed per bind." "error" 1
                return 1
            fi
        fi

        local frontendfile="${tmpDir}/${bind}-${protocol}.frontend"

        # Check some mutually exclusive rules
        if [ "${protocol}" = "tcp" ]; then
            if [ -n "${path_end}" ] || [ -n "${path_beg}" ] || [ -n "${path}" ]; then
                PRINT "Protocol tcp cannot have path or path_beg rules." "error" 0
                return 1
            fi
            if [ "${redirect_to_https}" = "true" ] || [ -n "${redirect_location}" ] || [ -n "${redirect_prefix}" ] || [ -n "${errorfile}" ]; then
                PRINT "Protocol tcp cannot have redirect rules or errorfiles" "error" 0
                return 1
            fi
        fi

        if [ "${protocol}" = "https" ]; then
            if [ "${redirect_to_https}" = "true" ]; then
                PRINT "Protocol https cannot have redirect_to_https rule" "error" 0
                return 1
            fi
        fi

        if { [ -n "${path_beg}" ] || [ -n "${path_end}" ]; } && [ -n "${path}" ]; then
            PRINT "path_beg and path_end are mutually exclusive to path" "error" 0
            return 1
        fi

        # Calculate criteria ACLs
        ## Do path, path_beg, path_end
        ## path is mutuallay exclusing with path_beg and path_end (checked above),
        ## path_beg and path_end can be evaluated together in the same ACL
        local criteria=""  # Only used to group identical ingress criterias together
        local aclnames=""
        local acls=""

        ## Figure out which ACLs we will have
        if [ -n "${path}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH-${rule_count}"
        fi
        if [ -n "${path_beg}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH_BEG-${rule_count}"
        fi
        if [ -n "${path_end}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH_END-${rule_count}"
        fi
        if [ -n "${host}" ]; then
            aclnames="${aclnames}${aclnames:+ }HOST-${rule_count}"
        fi

        ## Build the matching ACL rules
        if [ -n "${path_beg}" ]; then
            path_beg="$(printf "%s\\n" "${path_beg}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path_beg"
            criteria="${criteria}{ path_beg ${path_beg}}"
            acls="acl PATH_BEG-${rule_count} path_beg ${path_beg}
"
        fi

        if [ -n "${path_end}" ]; then
            path_end="$(printf "%s\\n" "${path_end}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path_end"
            criteria="${criteria}{ path_end ${path_end}}"
            acls="${acls}acl PATH_END-${rule_count} path_end ${path_end}
"
        fi

        if [ -n "${path}" ]; then
            path="$(printf "%s\\n" "${path}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path"
            criteria="${criteria}{ path ${path}}"
            acls="acl PATH-${rule_count} path ${path}
"
        fi

        # We also add the port to hostname if any other port than http/80 or https/443
        local addporttohostname="false"
        if { [ "${protocol}" = "https" ] && [ "${bindport}" != "443" ]; } ||
            { [ "${protocol}" = "http" ] && [ "${bindport}" != "80" ]; }; then
            addporttohostname="true"
        fi

        # Sort host names, this is important so that identical rules are grouped together.
        local host1=""
        local host2=""
        if [ -n "${host}" ]; then
            host="$(printf "%s\\n" "${host}" |tr '[:upper:]' '[:lower:]' |tr ' ' '\n' |sort -f)"
            local hostname=
            local hostnames=""
            for hostname in ${host}; do
                hostnames="${hostnames}${hostname:+ }${hostname}"
                # Check if it is exact match or subdomain wildcard.
                local hostname2="${hostname##*[*]}"
                if [ "${hostname2}" != "${hostname}" ]; then
                    # This is a wildcard
                    host2="${host2}${host2:+ }${hostname2}"
                    if [ "${addporttohostname}" = "true" ]; then
                        host2="${host2} ${hostname2}:${bindport}"
                    fi
                else
                    host1="${host1}${host1:+ }${hostname}"
                    if [ "${addporttohostname}" = "true" ]; then
                        host1="${host1} ${hostname}:${bindport}"
                    fi
                fi
            done
            criteria="${criteria}{ host ${hostnames}}"

            if [ -n "${host1}" ]; then
                if [ "${protocol}" = "tcp" ]; then
                    host1="req.ssl_sni -i ${host1}"
                else
                    host1="hdr(host) -i ${host1}"
                fi
            fi
            if [ -n "${host2}" ]; then
                if [ "${protocol}" = "tcp" ]; then
                    host2="req.ssl_sni,lower -m end ${host2}"
                else
                    host2="hdr(host),lower -m end ${host2}"
                fi
            fi
        fi

        if [ -n "${host1}" ]; then
            acls="${acls}acl HOST-${rule_count} ${host1}
"
        fi
        if [ -n "${host2}" ]; then
            acls="${acls}acl HOST-${rule_count} ${host2}
"
        fi

        local type=
        if [ "${redirect_to_https}" = "true" ] || [ -n "${redirect_location}" ] || [ -n "${redirect_prefix}" ] || [ -n "${errorfile}" ]; then
            type="general"
            if [ -n "${clusterport}" ]; then
                PRINT "clusterport is defined but backend is ignored since there are redirection rules present." "warning" 0
            fi
        else
            type="server"
        fi

        # Take hash on bind, protocol, criterions and importance.
        # This is to uniquely identify and group together backends which have the exact same rules and frontend.
        local hash=
        if ! STRING_HASH "${bind}-${protocol}_${type}-${importance}-${criteria}" "hash"; then
            return 1
        fi

        local backendName="${hash}"
        # Will get sorted on importance when generating config
        local frontendmatch="${importance} ${backendName}"
        # Check in frontend file if hash exists, else add it.
        FILE_ROW_PERSIST "${frontendmatch}" "${frontendfile}"
        local aclfile="${frontendfile}.${backendName}"
        if [ ! -f "${aclfile}" ]; then
            printf "%s" "${acls}" >"${aclfile}"
            printf "%s\\n" "use_backend ${backendName} if ${aclnames}" >>"${aclfile}"
        fi

        # Now add server to backend
        # See what extra configs we have on the server.
        local backendLine=""

        if [ "${redirect_to_https}" = "true" ]; then
            backendLine="redirect scheme https code 301"
        elif [ -n "${redirect_location}" ]; then
            backendLine="redirect location ${redirect_location} code 301"
        elif [ -n "${redirect_prefix}" ]; then
            backendLine="redirect prefix ${redirect_prefix} code 301"
        elif [ -n "${errorfile}" ]; then
            backendLine="errorfile ${errorfile}"
        else
            # proxy must be defined in /etc/hosts to the IP where the proxy process is listening.
            backendLine="server clusterPort-${clusterport} proxy:${clusterport} send-proxy"
        fi

        local backendFile="${tmpDir}/${hash}-${protocol}_${type}.backend"
        FILE_ROW_PERSIST "${backendLine}" "${backendFile}"
    done
}

_GET_TMP_DIR()
{
    mktemp -d 2>/dev/null || mktemp -d -t 'sometmpdir'
}

# For a given file, return the tag or commit in which it was last changed.
# Will error out if the file is not in a git repo or if it is currently dirty.
_GET_TAG_FILE()
{
    SPACE_SIGNATURE="file"
    SPACE_DEP="PRINT"

    local file="${1}"
    shift

    local dir="${file%/*}"
    local file2="${file##*/}"

    if ! [ -f "${file}" ]; then
        PRINT "Could not find file: ${file}" "error" 0
        return 1
    fi

    if ! ( cd "${dir}" && git rev-parse --show-toplevel >/dev/null 2>&1 ); then
        PRINT "File ${file} is not in git repo." "error" 0;
        return 1
    fi

    local commitId=
    commitId="$(cd "${dir}" && git log --oneline -- "${file2}" 2>/dev/null |head -n1 |cut -d' ' -f1)"

    if [ -z "${commitId}" ]; then
        PRINT "Could not get commitId for file ${file}. It should be committed to the repo first." "warning" 0
        return 0
    fi

    local tag=
    tag="$(cd "${dir}" && git describe "${commitId}" --always --tags 2>/dev/null)"

    tag="${tag:-${commitId}}"

    # Check if the file is dirty
    local s=
    s="$(cd "${dir}" && git diff --name-only -- "${file2}" 2>/dev/null)"
    if [ -n "${s}" ]; then
        PRINT "File ${file} has changes, should be committed first." "warning" 0
        printf "%s\\n" "<unknown>"
        return 0
    fi

    s="$(cd "${dir}" && git diff --name-only --cached -- "${file2}" 2>/dev/null)"
    if [ -n "${s}" ]; then
        PRINT "File ${file} has changes, should be committed first." "warning" 0
        printf "%s\\n" "<unknown>"
        return 0
    fi

    printf "%s\\n" "${tag}"
}

_DOES_HOST_EXIST()
{
    SPACE_SIGNATURE="hostsPath host"

    local hostsPath="${1}"
    shift

    local host="${1}"
    shift

    [ -f "${hostsPath}/${host}/host.env" ]
}

# Check so that a state is a valid state
_ENUM_STATE()
{
    SPACE_SIGNATURE="state"

    local state="${1}"
    shift

    if [ "${state}" = "removed" ] || [ "${state}" = "created" ] || [ "${state}" = "running" ] || [ "${state}" = "stopped" ]; then
        return 0
    fi

    return 1;
}

_LIST_ATTACHEMENTS()
{
    SPACE_SIGNATURE="pod"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    (cd "${CLUSTERPATH}" && find . -maxdepth 4 -mindepth 4 -regex "^./[^.][^/]*/pods/${pod}/log\.txt\$" |cut -d/ -f2)
}

_IS_POD_ATTACHED()
{
    SPACE_SIGNATURE="hostsPath host pod"

    local hostsPath="${1}"
    shift

    local host="${1}"
    shift

    local pod="${1}"
    shift

    [ -f "${hostsPath}/${host}/pods/${pod}/log.txt" ]
}

# filter:
#  0=active, inactive and disabled
#  1=active, and inactive
#  2=only active
_LIST_HOSTS()
{
    SPACE_SIGNATURE="path [filter]"
    SPACE_DEP="GET_HOST_STATE"

    local dir="${1}"
    shift

    local filter="${1:-0}"

    local hosts=
    hosts="$(cd "${dir}" && find . -maxdepth 2 -mindepth 2 -type f -regex "^./[^.][^/]*/host\.env\$" |cut -d/ -f2)"

    local host=
    for host in ${hosts}; do
        local state=$(GET_HOST_STATE "${host}")
        if [ "${filter}" = "1" ]; then
            if [ "${state}" = "disabled" ]; then
                continue
            fi
        elif [ "${filter}" = "2" ]; then
            if [ "${state}" != "active" ]; then
                continue
            fi
        fi
        printf "%s\\n" "${host}"
    done
}

SET_HOST_STATE()
{
    SPACE_SIGNATURE="host state"
    SPACE_DEP="PRINT _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local state="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host does not exist" "error" 0
        return 1
    fi

    if [ "${state}" != "active" ] && [ "${state}" != "inactive" ] && [ "${state}" != "disabled" ]; then
        PRINT "Unknown state. Try active/inactive/disabled." "error" 0
        return 1
    fi

    local file="${CLUSTERPATH}/${host}/host.state"

    printf "%s\\n" "${state}" >"${file}"
}

GET_HOST_STATE()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="PRINT _DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host does not exist" "error" 0
        return 1
    fi

    local state="active"

    local dir="${CLUSTERPATH}/${host}"
    local file="${dir}/host.state"

    if [ -f "${file}" ]; then
        state="$(cat "${file}")"
    fi

    printf "%s\\n" "${state}"
}

_LOG()
{
    SPACE_SIGNATURE="host pod action"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local action="${1}"
    shift

    local logFile="${CLUSTERPATH}/${host}/pods/${pod}/log.txt"

    printf "%s %s %s %s\\n" "$(date +"%F %T")" "$(date +%s)" "${USER}" "${action}" >>"${logFile}"
}

# Log for cluster specific operations
_LOG_C()
{
    SPACE_SIGNATURE="action"
    SPACE_ENV="CLUSTERPATH"

    local action="${1}"
    shift

    local logFile="${CLUSTERPATH}/log.txt"

    printf "%s %s %s %s\\n" "$(date +"%F %T")" "$(date +%s)" "${USER}" "${action}" >>"${logFile}"
}

_SHOW_USAGE()
{
    printf "%s\\n" "Usage:
    help
        Show this help

    version
        Show the version of snt

    create-cluster name
        Creates a cluster with the given name in the current directory.

    sync [ignoreGitOps={true|false} forceSync={true|false}]
        Sync the cluster project in the current directory with the Cluster

    status
        Show status of the Cluster

    import-pod-config pod
        Import config templates from pod repo into the cluster project

    create-host host [jumphost expose]
        Create a host in the cluster repo by the name 'host'.
        jumphost is an optional host to do SSH jumps via, often used for worker machines which are not exposed directly to the public internet.
        If jumphost is set to 'local' then that dictates this host is not SSH enabled but targets local disk instead.
        expose can be a list of ports we want to expose to the public internet. If not provided then the host will be accessible internally only.

    init-host host
        Initialize a host to be part of the cluster and configure the Daemon to manage it's pods

    setup-host host
        Setup the host using the superuser
        Creates the regular user, installs podman, configures firewalld, etc.

    ls-hosts [filter={0|1|2}]
        List all hosts in this cluster project
        filter:
            0=active, inactive and disabled
            1=active, and inactive
            2=only active

    ls-pods
        List all known pods in the PODPATH

    ls-hosts-by-pod pod
        List all hosts who have a given pod attached

    ls-pods-by-host host
        List all pods attached to a specific host

    attach-pod host pod
        Attach a Pod to a host, this does not deploy anything nor release anything
        host must exist in the cluster project
        pod must exist on PODPATH

    detach-pod host pod
        Remove a pod from a host

    compile pod [host]
        Compile the current pod version to all (or one) host(s) which it is already attached to.
        If host is left out then compile on all hosts which have the pod attached.

    update-config pod version [host]
        Re-copy the pod config in the cluster to a specific pod release.
        If host is left out then copy configs to all hosts which have the pod attached.

    set-pod-state pod version state [host]
        Set the desired state of a specific pod version on one/all attached hosts.
        state options are:
            removed
            stopped
            running
        If host is left out then set state for pod on all hosts which the pod is attached to.

    get-pod-state pod version [host]
        Get the desired state of a specific pod version on one/all attached hosts.
        If host is left out then set state for pod on all hosts which the pod is attached to.

    generate-ingress [ingresspod excludeClusterPorts]
        Update the ingress load balancers config by looking at the ingress of all active pod instances on all hosts.
        ingressPod
            name of the ingress pod, defaults to 'ingress'.
        excludeClusterPorts
            Space separated string of clusterPorts to exclude from the Ingress configuration

    set-host-state host state
        Mark a specific host as active/inactive/disabled
        state:
            active
            inactive
            disabled

    get-host-state host
        Get a the state of a host

    logs pod version [host tail since]
        tail is number of lines to tail
        since is timestamp to get from, ex: 2006-01-02T15:04:05 or UNIX ts

    daemon-log
        Get the systemd unit daemon log

    create-superuser host [rootkeyfile]
        Login as root on the host and create the super user as defined in the host.env file.
        rootkeyfile is optional, of not set then password is required to login as root.

    disable-root host
        Use the super user account to disable the root login on a host
"
}

_VERSION()
{
    printf "%s\\n" "Simplenetes version 0.1 (GandalfVsHeman)"
}

SNT_CMDLINE()
{
    SPACE_SIGNATURE="action [args]"
    SPACE_DEP="_SHOW_USAGE _VERSION GET_HOST_STATE SET_HOST_STATE GEN_INGRESS_CONFIG GET_POD_RELEASE_STATE LOGS SET_POD_RELEASE_STATE UPDATE_POD_CONFIG COMPILE_POD DETACH_POD ATTACH_POD LIST_PODS_BY_HOST LIST_HOSTS_BY_POD LIST_PODS LIST_HOSTS HOST_SETUP HOST_CREATE_SUPERUSER HOST_DISABLE_ROOT HOST_INIT HOST_CREATE CLUSTER_IMPORT_POD_CFG CLUSTER_STATUS CLUSTER_CREATE CLUSTER_SYNC DAEMON_LOG"
    SPACE_ENV="PODPATH CLUSTERPATH"

    local action="${1:-help}"
    shift $(($# > 0 ? 1 : 0))

    # TODO: check for cluster-id.txt, upwards and cd into that dir so that snt becomes more flexible in where users have their CWD atm.

    if [ "${action}" = "help" ]; then
        _SHOW_USAGE
    elif [ "${action}" = "version" ]; then
        _VERSION
    elif [ "${action}" = "create-cluster" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: name"
            return 1
        fi
        CLUSTER_CREATE "${1}"
    elif [ "${action}" = "sync" ]; then
        CLUSTER_SYNC "${1:-}" "${2:-}"
    elif [ "${action}" = "status" ]; then
        CLUSTER_STATUS
    elif [ "${action}" = "import-pod-config" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: pod"
            return 1
        fi
        CLUSTER_IMPORT_POD_CFG "${1}"
    elif [ "${action}" = "create-host" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        HOST_CREATE "${1}" "${2:-}" "${3:-}"
    elif [ "${action}" = "init-host" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host [force={true|false}]"
            return 1
        fi
        HOST_INIT "${1}" "${2:-}"
    elif [ "${action}" = "setup-host" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        HOST_SETUP "${1}"
    elif [ "${action}" = "create-superuser" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        HOST_CREATE_SUPERUSER "${1}" "${2:-}"
    elif [ "${action}" = "disable-root" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        HOST_DISABLE_ROOT "${1}"
    elif [ "${action}" = "ls-hosts" ]; then
        LIST_HOSTS "${1:-0}"
    elif [ "${action}" = "ls-pods" ]; then
        LIST_PODS
    elif [ "${action}" = "ls-hosts-by-pod" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: pod"
            return 1
        fi
        LIST_HOSTS_BY_POD "${1}"
    elif [ "${action}" = "ls-pods-by-host" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        LIST_PODS_BY_HOST "${1}"
    elif [ "${action}" = "attach-pod" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: host pod"
            return 1
        fi
        ATTACH_POD "${1}" "${2}"
    elif [ "${action}" = "detach-pod" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: host pod"
            return 1
        fi
        DETACH_POD "${1}" "${2}"
    elif [ "${action}" = "compile" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing arguments: pod [host]"
            return 1
        fi
        COMPILE_POD "${1}" "${2:-}"
    elif [ "${action}" = "update-config" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: pod version [host]"
            return 1
        fi
        UPDATE_POD_CONFIG "${1}" "${2}" "${3:-}"
    elif [ "${action}" = "set-pod-state" ]; then
        if [ $# -lt 3 ]; then
            printf "%s\\n" "Missing arguments: pod version state [host]"
            return 1
        fi
        SET_POD_RELEASE_STATE "${1}" "${2}" "${3}" "${4:-}"
    elif [ "${action}" = "get-pod-state" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: pod version [host]"
            return 1
        fi
        GET_POD_RELEASE_STATE "${1}" "${2}" "${3:-}"
    elif [ "${action}" = "logs" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: pod version [host tail since]"
            return 1
        fi
        LOGS "${1}" "${2}" "${3:-}" "${4:-}" "${5:-}"
    elif [ "${action}" = "daemon-log" ]; then
        DAEMON_LOG "${1:-}"
    elif [ "${action}" = "generate-ingress" ]; then
        GEN_INGRESS_CONFIG "${1:-ingress}" "${2:-}"
    elif [ "${action}" = "set-host-state" ]; then
        if [ $# -lt 2 ]; then
            printf "%s\\n" "Missing arguments: host state"
            return 1
        fi
        SET_HOST_STATE "${1}" "${2}"
    elif [ "${action}" = "get-host-state" ]; then
        if [ $# -lt 1 ]; then
            printf "%s\\n" "Missing argument: host"
            return 1
        fi
        GET_HOST_STATE "${1}"
    else
        PRINT "Unknown command" "error" 0
        return 1
    fi
}
