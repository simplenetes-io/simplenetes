# POD RELEASE SPECIFIC FUNCTIONALITY
#

# Perform the release of a new pod version and removed other running version of the same pod.
# A release can be done "soft" or "hard".
# A "soft" release has many steps in order to have zero downtime, while a "hard" release is simpler and faster but could results in a glimpse of downtime.
# To perform a perfect "soft" release all ingress enabled clusterPorts must be configured using ${CLUSTERPORTAUTOxyz}. This is to prevent two different pod version serving traffic at the same time.
# If that is not an issue then they can have static clusterPorts, but do avoid a site being skewed between two version during the process then the safe way is to use auto assignment of cluster ports for ingress enabled cluster ports.
_RELEASE()
{
    SPACE_SIGNATURE="podTuple [mode push force]"
    SPACE_DEP="_PRJ_COMPILE_POD PRINT _PRJ_LOG_C _PRJ_GET_POD_RELEASE_STATE _RELEASE_HARD _RELEASE_SOFT _PRJ_LS_POD_RELEASE_STATE STRING_SUBST _PRJ_IS_CLUSTER_CLEAN _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local podTuple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTuple}"; then
        return 1
    fi

    if [ -n "${host}" ]; then
        PRINT "Do not provide @host, only pod[:version]" "error" 0
        return 1
    fi

    local mode="${1:-hard}"
    local push="${2:-false}"
    local force="${3:-false}"

    if [ "${mode}" = "soft" ] || [ "${mode}" = "hard" ]; then
        # All good, fall through
        :
    else
        PRINT "Mode must be soft or hard" "error" 0
        return 1
    fi

    if ! _PRJ_IS_CLUSTER_CLEAN; then
        PRINT "The cluster git project is not clean and committed. Cannot continue until it is." "error" 0
        return 1
    fi

    isCompiled="false"
    local podVersion=
    if [ "${version}" = "latest" ]; then
        # Compile new version
        if ! podVersion="$(_PRJ_COMPILE_POD "${pod}" "true")"; then
            return 1
        fi
        isCompiled="true"
    else
        # Either pod version exists or is to be compiled
        local lines=
        lines="$(_PRJ_GET_POD_RELEASE_STATE "${pod}:${version}")"
        if [ -n "${lines}" ]; then
            PRINT "${pod}:${version} does exist, re-release it" "info" 0
            podVersion="${version}"
        else
            # Compile it for the specified version
            if ! podVersion="$(_PRJ_COMPILE_POD "${pod}" "true" "${version}")"; then
                return 1
            fi
            isCompiled="true"
        fi
    fi

    if [ -z "${podVersion}" ]; then
        PRINT "Nothing to do. To re-release this pod, run the release again and specifiy the version, as: ${pod}:version" "error" 0
        return 1
    fi

    # Get a list of the current running versions of the pod.
    local otherVersions="$(_PRJ_LS_POD_RELEASE_STATE "running" "true" "${pod}")"

    local otherVersions2="$(printf "%s\\n" "${otherVersions}" |grep -v "\<${podVersion}\>")"

    if [ "${otherVersions2}" = "${otherVersions}" ]; then
        _PRJ_LOG_C "RELEASE ${pod}:${podVersion}"
    else
        _PRJ_LOG_C "RE-RELEASE ${pod}:${podVersion}"
    fi

    local newline="
"
    STRING_SUBST "otherVersions2" "${newline}" " " 1

    local dir="${PWD}"
    cd "${CLUSTERPATH}"
    local status=
    if [ "${mode}" = "hard" ]; then
        _RELEASE_HARD "${pod}" "${podVersion}" "${otherVersions2}" "${force}" "${isCompiled}"
        status="$?"
    else
        _RELEASE_SOFT "${pod}" "${podVersion}" "${otherVersions2}" "${force}" "${isCompiled}"
        status="$?"
    fi

    cd "${dir}"

    if [ "${status}" -gt 0 ]; then
        PRINT "There was an error releasing. The cluster might be in a incoherent state right now. To resume the release process perform the release again refering to this specific pod version: ${podVersion}" "error" 0
    fi

    return "${status}"
}

_RELEASE_HARD()
{
    SPACE_DEP="_PRJ_SET_POD_RELEASE_STATE _PRJ_GEN_INGRESS_CONFIG _PRJ_UPDATE_POD_CONFIG _SYNC_RUN _PRJ_GET_POD_RELEASE_STATE"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local otherVersions="${1}"
    shift

    local force="${1}"
    shift

    PRINT "********* Perform hard release of ${pod}:${podVersion} *********" "info" 0

    if [ -n "${otherVersions}" ]; then
        PRINT "********* Retire other versions of the pod." "info" 0
        # Remove the other running pod versions
        if ! _PRJ_SET_POD_RELEASE_STATE "removed" ${otherVersions}; then
            return 1
        fi
    fi

    local currentState="$(_PRJ_GET_POD_RELEASE_STATE "${pod}:${podVersion}" "true")"
    if [ "${currentState}" != "running" ]; then
        PRINT "Set pod version ${podVersion} to be 'running'" "info" 0
        if ! _PRJ_SET_POD_RELEASE_STATE "running" "${pod}:${podVersion}"; then
            return 1
        fi
    else
        PRINT "Pod version already in the 'running' state" "info" 0
    fi

    PRINT "********* GENERATE INGRESS *********" "info" 0
    if ! _PRJ_GEN_INGRESS_CONFIG; then
        PRINT "Could not generate ingress" "error" 0
        return 1
    fi

    if ! _PRJ_UPDATE_POD_CONFIG "ingress"; then
        PRINT "Could not update ingress pod config" "error" 0
        return 1
    fi

    if ! { git add . && git commit -q -m "Hard release ${pod}:${podVersion}, retire other versions, update ingress"; } then
        PRINT "Could not commit changes" "error" 0
        return 1
    fi

    PRINT "********* GENERATE INGRESS DONE *********" "info" 0

    if [ "${push}" = "true" ]; then
        if ! git push -q; then
            PRINT "Could not push repo to remote" "error" 0
            return 1
        fi
    fi

    PRINT "********* SYNCING *********" "info" 0

    if ! _SYNC_RUN "${force}" "true"; then
        return 1
    fi

    if ! { git add . && git commit -q -m "Update sync log after releasing ${pod}:${podVersion}"; } then
        PRINT "Could not commit changes" "error" 0
        return 1
    fi

    if [ "${push}" = "true" ]; then
        if ! git push -q; then
            PRINT "Could not push repo to remote" "error" 0
            return 1
        fi
    fi

    PRINT "********* RELEASE DONE *********" "info" 0
}

_RELEASE_SOFT()
{
    SPACE_DEP="_PRJ_SET_POD_RELEASE_STATE _PRJ_GEN_INGRESS_CONFIG _PRJ_UPDATE_POD_CONFIG _SYNC_RUN _PRJ_SET_POD_INGRESS_STATE _PRJ_GET_POD_STATUS _PRJ_GET_POD_RELEASE_STATE"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local otherVersions="${1}"
    shift

    local force="${1}"
    shift

    local isCompiled="${1}"
    shift

    PRINT "********* Perform soft release of ${pod}:${podVersion} *********" "info" 0

    local podStateUpdated="false"
    local currentState="$(_PRJ_GET_POD_RELEASE_STATE "${pod}:${podVersion}" "true")"
    if [ "${currentState}" != "running" ]; then
        PRINT "Set pod version ${podVersion} to be 'running'" "info" 0
        if ! _PRJ_SET_POD_RELEASE_STATE "running" "${pod}:${podVersion}"; then
            return 1
        fi
        podStateUpdated="true"
    else
        PRINT "Pod version already in the 'running' state" "info" 0
    fi

    # Only commit if any changes were made
    if [ "${podStateUpdated}" = "true" ] || [ "${isCompiled}" = "true" ]; then
        if ! { git add . && git commit -q -m "Soft release ${pod}:${podVersion}"; } then
            return 1
        fi

        if [ "${push}" = "true" ]; then
            if ! git push -q; then
                PRINT "Could not push repo to remote" "error" 0
                return 1
            fi
        fi
    fi

    PRINT "********* SYNCING *********" "info" 0
    # If force is set, only force on the first sync, the coming syncs should be in line
    if ! _SYNC_RUN "${force}" "true"; then
        return 1
    fi

    PRINT "********* Wait for new release to run... *********" "info" 0

    # Wait for a while to get the status of the new release
    local podStatus=
    local now="$(date +%s)"
    local timeout="$((now+30))"
    while true; do
        sleep 2
        if _PRJ_GET_POD_STATUS "true" "true" "${pod}:${podVersion}" 2>/dev/null; then
            break
        fi

        now="$(date +%s)"
        if [ "$((now > timeout))" -eq 0 ]; then
            PRINT "Timeout trying to get pod readiness, aborting now. This could be due to a problem with the pod it self or due to network issues" "error" 0
            if [ "${podStateUpdated}" = "true" ] || [ "${isCompiled}" = "true" ]; then
                PRINT "Setting version ${podVersion} as 'removed' and syncing again" "info" 0
                _PRJ_SET_POD_RELEASE_STATE "removed" "${pod}:${podVersion}"
                git add . && git commit -q -m "New release ${pod}:${podVersion} failed to run. Set state to 'removed' and sync"
                if [ "${push}" = "true" ]; then
                    if ! git push -q; then
                        PRINT "Could not push repo to remote" "error" 0
                        return 1
                    fi
                fi
                _SYNC_RUN "" "true"
                return 1
            fi
        fi
    done

    PRINT "New release is now running" "info" 0
    PRINT "Update the ingress" "info" 0

    # New release is up and running, regenerate the ingress
    # Note that if the new version uses the same clusterPorts as the previous version then
    # it will start recieving traffic as soon as it is running.
    # To have a fully isolated handover of traffic a new clusterPort must be used for the new release.
    #
    # This ingress conf regeneration might not change anything in the ingress.
    if ! _PRJ_GEN_INGRESS_CONFIG; then
        PRINT "Could not generate ingress" "error" 0
        return 1
    fi

    if ! _PRJ_UPDATE_POD_CONFIG "ingress"; then
        PRINT "Could not update ingress pod config" "error" 0
        return 1
    fi

    # Even if no ingress conf was changed, there will by new logfiles, so this commit should not fail.
    if ! { git add . && git commit -q -m "Update ingress for ${pod}:${podVersion}"; } then
        PRINT "Could not commit changes" "error" 0
        return 1
    fi

    # TODO: how to know if ingress got updated
    if true; then
        if [ "${push}" = "true" ]; then
            if ! git push -q; then
                PRINT "Could not push repo to remote" "error" 0
                return 1
            fi
        fi

        PRINT "********* SYNCING *********" "info" 0
        if ! _SYNC_RUN "" "true"; then
            return 1
        fi

        # Wait for the new ingress conf to get updated
        PRINT "Waiting for ingress to get updated..." "info" 0
        sleep 20
    fi

    if [ -n "${otherVersions}" ]; then
        # Remove the other version of the pod from the ingress configuration
        if ! _PRJ_SET_POD_INGRESS_STATE "inactive" ${otherVersions}; then
            return 1
        fi
        git add . && git commit -m "Remove other running versions from ingress: ${otherVersions}"
        if [ "${push}" = "true" ]; then
            if ! git push -q; then
                PRINT "Could not push repo to remote" "error" 0
                return 1
            fi
        fi
        PRINT "********* SYNCING *********" "info" 0
        if ! _SYNC_RUN "" "true"; then
            return 1
        fi

        # Wait so that ingress get's updated
        PRINT "Waiting for ingress to get updated..." "info" 0
        sleep 20

        # Remove the other pod versions
        if ! _PRJ_SET_POD_RELEASE_STATE "removed" ${otherVersions}; then
            return 1
        fi
        git add . && git commit -m "Retire other running versions: ${otherVersions}"
        if [ "${push}" = "true" ]; then
            if ! git push -q; then
                PRINT "Could not push repo to remote" "error" 0
                return 1
            fi
        fi
        PRINT "********* SYNCING *********" "info" 0
        _SYNC_RUN "" "true"
    fi

    git add . && git commit -m "Update sync log after releasing ${pod}:${podVersion}"
    if [ "${push}" = "true" ]; then
        if ! git push -q; then
            PRINT "Could not push repo to remote" "error" 0
            return 1
        fi
    fi

    PRINT "********* RELEASE DONE *********" "info" 0
}
