# PROJECT specific
#

# Generate registry login config.json files.
_PRJ_REGISTRY_CONFIG()
{
    SPACE_SIGNATURE="[host]"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="_PRJ_DOES_HOST_EXIST"

    if [ -n "${host}" ] && [ "${host}" != '-' ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi
    fi

    local lines=
    local line=
    local comma=""
    lines="$(
        while IFS='' read line; do
            local registry="${line%%:*}"
            local password="${line##*:}"
            local user="${line#*:}"
            user="${user%:*}"

            local auth="$(printf "%s:%s" "${user}" "${password}" | base64)"
            printf "    ${comma}\"%s\": { \"auth\": \"%s\" }\\n" "${registry}" "${auth}"
            comma=','
        done
    )"

    local output="$(
        printf "{\\n  \"auths\": {\\n"
        printf "${lines}\\n"
        printf "  }\\n}\\n"
    )"

    if [ "${host}" = "-" ]; then
        printf "%s\\n" "${output}"
    elif [ -z "${host}" ]; then
        printf "%s\\n" "${output}" >"${CLUSTERPATH}/registry-config.json"
    else
        printf "%s\\n" "${output}" >"${CLUSTERPATH}/${host}/registry-config.json"
    fi
}

# Connect to the cluster and retrieve logs for a pod instance.
_PRJ_GET_POD_LOGS()
{
    SPACE_SIGNATURE="timestamp limit streams details showProcessLog podTriple [containers]"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_GET_POD_LOGS2 _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE STRING_IS_NUMBER"
    SPACE_ENV="CLUSTERPATH"

    local timestamp="${1:-0}"
    shift

    local limit="${1:-0}"
    shift

    local streams="${1:-stdout,stderr}"
    shift

    local details="${1:-}"
    shift

    local showProcessLog="${1:-}"
    shift

    if ! STRING_IS_NUMBER "${timestamp}" "1"; then
        PRINT "timeout must be number (positive is seconds since epoch, negative is age as seconds from now)" "error" 0
        return 1
    fi

    if ! STRING_IS_NUMBER "${limit}" "1"; then
        PRINT "limit must be a number" "error" 0
        return 1
    fi

    if [ "${streams}" = "stdout" ] || [ "${streams}" = "stderr" ] || [ "${streams}" = "stdout,stderr" ] || [ "${streams}" = "stderr,stdout" ]; then
        # All good, fall through
        :
    else
        PRINT "streams must be: stdout, stderr or \"stdout,stderr\"" "error" 0
        return 1
    fi

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod is not attached to any host." "warning" 0
        return
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            continue
        fi

        PRINT "Get logs for ${pod}:${podVersion}@${host} $*" "info" 0
        _PRJ_GET_POD_LOGS2 "${host}" "${pod}" "${podVersion}" "${timestamp}" "${limit}" "${streams}" "${details}" "${showProcessLog}" "$@"
    done
}

_PRJ_GET_POD_LOGS2()
{
    SPACE_SIGNATURE="host pod podVersion timestamp limit streams details showProcessLogs [containers]"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local timestamp="${1}"
    shift

    local limit="${1}"
    shift

    local streams="${1}"
    shift

    local details="${1}"
    shift

    local showProcessLogs="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local i=
    local status=
    _REMOTE_EXEC "${host}" "logs" "${pod}" "${podVersion}" "${timestamp}" "${limit}" "${streams}" "${details}" "${showProcessLog}" "$@"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    else
        PRINT "Could not get logs from host." "error" 0
        return "${status}"
    fi
}

# Generate config for haproxy
_PRJ_GEN_INGRESS_CONFIG()
{
    SPACE_SIGNATURE="[podTuple excludeClusterPorts]"
    SPACE_DEP="PRINT _PRJ_SPLIT_POD_TRIPLE _UTIL_GET_TMP_DIR _PRJ_LIST_HOSTS _PRJ_LIST_PODS_BY_HOST _PRJ_EXTRACT_INGRESS _PRJ_GET_POD_RUNNING_RELEASES STRING_ITEM_INDEXOF _PRJ_GEN_INGRESS_CONFIG2 TEXT_EXTRACT_VARIABLES TEXT_VARIABLE_SUBST TEXT_FILTER STRING_IS_ALL STRING_SUBST"
    SPACE_ENV="CLUSTERPATH"

    local podTuple="${1:-ingress}"
    shift $(($# > 0 ? 1 : 0))

    local excludeClusterPorts="${1:-}"
    shift $(($# > 0 ? 1 : 0))

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

    local podVersion="${version}"
    local ingressPod="${pod}"


    STRING_SUBST "excludeClusterPorts" ',' ' ' 1

    local ingressTplDir="${CLUSTERPATH}/_config/${ingressPod}/_tpl"
    local ingressConfDir="${CLUSTERPATH}/_config/${ingressPod}/conf"

    if [ ! -d "${ingressTplDir}" ]; then
        PRINT "Ingress pod ${ingressPod} has no tpl configs in the cluster. Maybe you need to import configs for the ingress pod first?" "error" 0
        return 1
    fi

    # For each host and each running pod release:
    # extract all ingress objects from the pod file,
    # merge and translate into haproxy config format.

    local tmpDir=
    if ! tmpDir="$(_UTIL_GET_TMP_DIR)"; then
        PRINT "Could not create temporary directory." "error" 1
        return 1;
    fi

    PRINT "Using temporary directory: ${tmpDir}" "debug" 0

    local hosts=
    hosts="$(_PRJ_LIST_HOSTS 2)"

    # To keep track of pod:releases we already have generated ingress for.
    # Since it doesn't matter what host a pod is on when we generate ingress we
    # only need to do it once for every specific pod release.
    doneReleases=""

    local newline="
"
    # We need a global count of rules numbering for the ingress.
    local RULE_COUNT=0

    local host=
    for host in ${hosts}; do
        PRINT "Processing pods on host ${host}" "debug" 0

        local pods="$(_PRJ_LIST_PODS_BY_HOST "${host}")"
        local pod=
        for pod in ${pods}; do
            if [ "${pod}" = "${ingressPod}" ]; then
                continue
            fi
            local versions="$(_PRJ_GET_POD_RUNNING_RELEASES "${host}" "${pod}")"
            if [ "${versions}" = "" ]; then
                PRINT "Pod ${pod} on ${host} has no running releases, skipping." "info" 0
                continue
            fi
            STRING_SUBST "versions" "${newline}" ' ' 1
            PRINT "Pod ${pod} on ${host} has running releases: ${versions}" "debug" 0
            local version=
            for version in ${versions}; do
                local podFile="${CLUSTERPATH}/${host}/pods/${pod}/release/${version}/pod"
                if [ ! -f "${podFile}" ]; then
                    PRINT "Pod ${pod} release:${version} executable on ${host} is missing." "error" 0
                    return 1
                fi

                # Check if we already done this pod:release on another host,
                # ingress and cluster ports are the same so we don't have to process it again.
                if STRING_ITEM_INDEXOF "${doneReleases}" "${pod}:${version}"; then
                    PRINT "Release ${version} already processed, moving on." "debug" 0
                    continue
                fi
                doneReleases="${doneReleases} ${pod}:${version}"

                PRINT "Generating ingress for ${pod}:${version} on ${host}" "info" 0

                if ! _PRJ_EXTRACT_INGRESS "${podFile}" "${tmpDir}" "${host}" "${pod}" "${version}" "${excludeClusterPorts}"; then
                    return 1
                fi
            done
        done
    done

    local haproxyConf=
    if ! haproxyConf="$(_PRJ_GEN_INGRESS_CONFIG2 "${tmpDir}" "${ingressTplDir}")"; then
        PRINT "Could not generate ingress conf. Debug output is in ${tmpDir}." "error" 0
        return 1
    fi

    # Perform variable substitution on conf.
    local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${haproxyConf}")"

    # First sweep
    # Go over all variable names and for those who are not all CAPS we prefix the variables
    # names with podname and underscore.
    local newline="
"
    local variablesToSubst2=""
    local variablesAll=""
    local values=""
    local varname=
    for varname in ${variablesToSubst}; do
        if ! STRING_IS_ALL "${varname}" "A-Za-z0-9_" || [ "${varname#[_0-9]}" != "${varname}" ]; then
            PRINT "Variable name '${varname}' contains illegal characters. Only [A-Za-z0-9_] are allowed, and cannot begin with underscore or digit." "error" 0
            return 1
        fi
        if STRING_IS_ALL "${varname}" "A-Z0-9_"; then
            # All CAPS, just substitute it with it's value from cluster-vars.env (added later).
            variablesAll="${variablesAll}${variablesAll:+ }${varname}"
        else
            # Not all caps, prefix the variable name with "podname_", as it is defined in cluster-vars.env
            # The actual value substituation will happen in the second sweep.
            values="${values}${values:+${newline}}${varname}=\$\{${ingressPod}_${varname}\}"
            # Save the variable name to subst for the second sweep
            variablesToSubst2="${variablesToSubst2}${variablesToSubst2:+ }${ingressPod}_${varname}"
            variablesAll="${variablesAll}${variablesAll:+ }${ingressPod}_${varname}"
        fi
    done

    PRINT "Variable names extracted from haproxy.conf which could be defined in cluster-vars.env: ${variablesAll}" "info" 0

    local clusterConfig="${CLUSTERPATH}/cluster-vars.env"
    values="${values}${newline}$(cat "${clusterConfig}")"
    haproxyConf="$(TEXT_VARIABLE_SUBST "${haproxyConf}" "${variablesToSubst}" "${values}")"

    # Second and final sweep
    local values2="$(cat "${clusterConfig}")"
    haproxyConf="$(TEXT_VARIABLE_SUBST "${haproxyConf}" "${variablesToSubst2}" "${values2}")"
    haproxyConf="$(printf "%s\\n" "${haproxyConf}" |TEXT_FILTER)"

    # Save conf in ingress pod cfg, if changed.
    mkdir -p "${ingressConfDir}"
    local haproxyConfPath="${ingressConfDir}/haproxy.cfg"
    # Diff current haproxy.cfg with newley generated one
    if ! (printf "%s\\n" "${haproxyConf}" |diff "${haproxyConfPath}" - >/dev/null 2>&1); then
        # Different
        PRINT "Updating haproxy.cfg in ${ingressConfDir}" "info" 0
        printf "%s\\n" "${haproxyConf}" >"${haproxyConfPath}"
        # TODO: do this automatically?
        PRINT "Now you need to run 'sns pod updateconfig ${ingressPod}:${podVersion}' and then 'sns cluster sync' to put the updated ingress configuration live" "debug" 0
    else
        PRINT "No changes in ingress to be made." "info" 0
    fi

    rm -rf "${tmpDir}"
}

_PRJ_HOST_SHELL()
{
    SPACE_SIGNATURE="host superUser useBash [commands]"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST _REMOTE_EXEC"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local superUser="${1}"
    shift

    local useBash="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist" "error" 0
        return 1
    fi

    if [ "${superUser}" = "true" ]; then
        PRINT "Enter superuser shell of host ${host}" "info" 0
        local hostEnv="${CLUSTERPATH}/${host}/host-superuser.env"
        if [ ! -f "${hostEnv}" ]; then
            PRINT "host-superuser.env file does not exist for this host" "error" 0
            return 1
        fi
        _REMOTE_EXEC "${host}:${hostEnv}" "host_shell" "${useBash}" "$@"
    else
        PRINT "Enter shell of host ${host}" "info" 0
        _REMOTE_EXEC "${host}" "host_shell" "${useBash}" "$@"
    fi

}

_PRJ_POD_SHELL()
{
    SPACE_SIGNATURE="useBash container podTriple [commands]"
    SPACE_DEP="PRINT _PRJ_LIST_ATTACHEMENTS _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE _REMOTE_EXEC"
    SPACE_ENV="CLUSTERPATH"

    local useBash="${1:-false}"
    shift

    local container="${1:-}"
    shift

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod is not attached to any host." "warning" 0
        return
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            PRINT "Pod ${pod}:${version}@${host} does not exist" "warning" 0
            continue
        fi

        PRINT "Enter shell of ${pod}:${podVersion}@${host} ${container}" "info" 0
        _REMOTE_EXEC "${host}" "pod_shell" "${pod}" "${podVersion}" "${container}" "${useBash}" "$@"
        # Error code passed on
    done
}

# Show status about the local cluster and how it compares to the known state of the remote cluster.
# Show:
# - git project dirty or clean
# - list of all hosts and their state
# - list of all pods which have the running state set
_PRJ_GET_CLUSTER_STATUS()
{
    # TODO: what to show here?
    # hosts status' and all pod status'?
    # also implement get-host-status ?
    :
}

# Check if a specific pod version's instances are ready
_PRJ_GET_POD_STATUS()
{
    SPACE_SIGNATURE="readiness:0 quite:0 podTriple"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE _PRJ_GET_POD_STATUS2"
    SPACE_ENV="CLUSTERPATH"

    local readiness="${1:-false}"
    shift

    local quite="${1:-false}"
    shift

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod is not attached to any host." "warning" 0
        return 1
    fi

    local totalCount="0"
    local countReady="0"
    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            continue
        fi
        totalCount="$((totalCount+1))"

        if [ "${readiness}" = "true" ]; then
            local status=
            if status="$(_PRJ_GET_POD_STATUS2 "${host}" "${pod}" "${podVersion}" "readiness")"; then
                if [ "${status}" = "ready" ]; then
                    countReady="$((countReady+1))"
                    if [ "${quite}" = "true" ]; then
                        # We can do an early quit here
                        return 0
                    fi
                fi
            fi
        else
            # Show pod current status
            local status=
            if status="$(_PRJ_GET_POD_STATUS2 "${host}" "${pod}" "${podVersion}" "status")"; then
                printf "host: %s\\n%s\\n" "${host}" "${status}"
            else
                printf "host: %s\\npod: %s\\nstatus: unknown\\n" "${host}" "${pod}-${podVersion}"
            fi
        fi
    done

    if [ "${readiness}" = "true" ]; then
        if [ "${quite}" = "true" ]; then
            if [ "${countReady}" -gt 0 ]; then
                return 0
            else
                return 1
            fi
        fi
        printf "%s/%s\\n" "${countReady}" "${totalCount}"
    fi
}

# Get pod static info
_PRJ_GET_POD_INFO()
{
    SPACE_SIGNATURE="podTriple"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE _PRJ_GET_POD_INFO2"
    SPACE_ENV="CLUSTERPATH"

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist" "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod is not attached to any host." "warning" 0
        return 1
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            PRINT "Pod ${pod} release:${version} executable on ${host} is missing." "error" 0
            continue
        fi

        local podFile="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}/pod"
        if [ ! -f "${podFile}" ]; then
            PRINT "Pod ${pod} release:${podVersion} executable on ${host} is missing." "error" 0
            continue
        fi

        printf "host: %s\\n" "${host}"
        ${podFile} info
    done
}

_PRJ_GET_HOST_STATE()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host does not exist" "error" 0
        return 1
    fi

    local dir="${CLUSTERPATH}/${host}"
    local file="${dir}/host.state"

    local state="active"  # active is the default if no state file exists
    if [ -f "${file}" ]; then
        state="$(cat "${file}")"
    fi

    printf "%s\\n" "${state}"
}

_PRJ_SET_HOST_STATE()
{
    SPACE_SIGNATURE="state host"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local state="${1}"
    shift

    if [ "${state}" != "active" ] && [ "${state}" != "inactive" ] && [ "${state}" != "disabled" ]; then
        PRINT "Unknown state. Try active/inactive/disabled." "error" 0
        return 1
    fi

    local host="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host does not exist" "error" 0
        return 1
    fi

    local file="${CLUSTERPATH}/${host}/host.state"

    printf "%s\\n" "${state}" >"${file}"
}

_PRJ_GET_POD_STATUS2()
{
    SPACE_SIGNATURE="host pod podVersion query"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local query="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local status=
    _REMOTE_EXEC "${host}" "pod_status" "${pod}" "${podVersion}" "${query}"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not get pod status from host." "error" 0

    # Failed
    return "${status}"
}

_PRJ_GET_POD_INFO2()
{
    SPACE_SIGNATURE="host pod podVersion"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local status=
    _REMOTE_EXEC "${host}" "pod_info" "${pod}" "${podVersion}"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not get pod info from host." "error" 0

    # Failed
    return "${status}"
}

_PRJ_GET_DAEMON_LOG2()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    hostEnv2="${CLUSTERPATH}/${host}/host-superuser.env"
    if [ ! -f "${hostEnv2}" ]; then
        PRINT "${hostEnv2} file does not exist, trying for regular user" "warn" 0
        hostEnv2="${CLUSTERPATH}/${host}/host.env"
    fi

    local status=
    _REMOTE_EXEC "${host}:${hostEnv2}" "daemon_log"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not get daemon log from host" "error" 0

    # Failed
    return "${status}"
}

# Connect to the cluster and retrieve logs for a pod instance.
_PRJ_GET_DAEMON_LOG()
{
    SPACE_SIGNATURE="[host]"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST _PRJ_GET_DAEMON_LOG2 _PRJ_LIST_HOSTS"
    SPACE_ENV="CLUSTERPATH"

    local host="${1:-}"
    shift

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi
        hosts="${host}";
    else
        hosts="$(_PRJ_LIST_HOSTS 1)"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "No hosts active" "warning" 0
        return 0
    fi

    local host=
    for host in ${hosts}; do
        printf "Daemon logs for host '%s':\\n" "${host}"
        _PRJ_GET_DAEMON_LOG2 "${host}"
    done
}

# Return the pod.version.state file of one or many pod releases.
_PRJ_GET_POD_RELEASE_STATES()
{
    SPACE_SIGNATURE="podTriples"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_GET_POD_RELEASE_STATE _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local podTriples="${1}"
    shift

    local podtriple=

    for podTriple in ${podTriples}; do
        local pod=
        local version=
        local host=
        if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
            return 1
        fi

        local hosts=
        if [ -n "${host}" ]; then
            if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
                PRINT "Host ${host} does not exist." "error" 0
                return 1
            fi

            hosts="${host}"
        else
            hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
        fi

        if [ -z "${hosts}" ]; then
            if [ -n "${host}" ]; then
                PRINT "Pod is not attached to host ${host}" "error" 0
                return 1
            fi
            continue
        fi

        local podVersion=
        local host=
        for host in ${hosts}; do
            if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
                #PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
                continue
            fi

            local state=
            if ! state="$(_PRJ_GET_POD_RELEASE_STATE "${host}" "${pod}" "${podVersion}")"; then
                #PRINT "Version ${podVersion} state not found on host ${host}. Skipping." "warning" 0
                continue
            fi

            printf "%s:%s@%s %s\\n" "${pod}" "${podVersion}" "${host}" "${state}"
        done
    done | sort
}

_PRJ_LS_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="filterState:0 quite:0 [podTriple]"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST _PRJ_GET_POD_RELEASE_STATE _PRJ_GET_POD_RELEASES _PRJ_LIST_PODS_BY_HOST _PRJ_LIST_HOSTS _PRJ_SPLIT_POD_TRIPLE _PRJ_FIND_POD_VERSION"
    SPACE_ENV="CLUSTERPATH"

    local filterState="${1:-}"
    shift

    local quite="${1:-false}"
    shift

    local podTriple="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local pod=
    local version=
    local host=

    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}" "true"; then
        return 1
    fi

    if [ -n "${filterState}" ]; then
        if [ "${filterState}" = "running" ] || [ "${filterState}" = "stopped" ] || [ "${filterState}" = "removed" ]; then
            # Good, fall through
            :
        else
            PRINT "State must be running, stopped or removed. Leave blank for all" "error" 0
            return 1
        fi
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi
        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_HOSTS 1)"
    fi
    unset host

    local host=
    for host in ${hosts}; do

        local podsByHost="$(_PRJ_LIST_PODS_BY_HOST "${host}")"
        local podOnHost=
        for podOnHost in ${podsByHost}; do
            if [ -n "${pod}" ] && [ "${pod}" != "${podOnHost}" ]; then
                continue
            fi
            local versions="$(_PRJ_GET_POD_RELEASES "${host}" "${podOnHost}")"
            for podVersion in ${versions}; do
                if [ "${version}" = "latest" ]; then
                    local latestVersion=
                    latestVersion="$(_PRJ_FIND_POD_VERSION "${podOnHost}" "latest" "${host}")"
                    if [ "${latestVersion}" != "${podVersion}" ]; then
                        continue
                    fi
                elif [ -n "${version}" ] && [ "${version}" != "${podVersion}" ]; then
                    continue
                fi

                local state="$(_PRJ_GET_POD_RELEASE_STATE "${host}" "${podOnHost}" "${podVersion}")"
                if [ -n "${filterState}" ] && [ "${state}" != "${filterState}" ]; then
                    continue
                fi

                # Output
                if [ "${quite}" = "true" ]; then
                    printf "%s:%s@%s\\n" "${podOnHost}" "${podVersion}" "${host}"
                else
                    printf "%s:%s@%s %s\\n" "${podOnHost}" "${podVersion}" "${host}" "${state}"
                fi
            done
        done
    done 
}

# Delete a pod release which is in the "removed" state.
_PRJ_DELETE_POD()
{
    SPACE_SIGNATURE="podTriples"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_LOG_P _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local podTriple=
    for podTriple in "$@"; do
        local pod=
        local version=
        local host=
        if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
            return 1
        fi

        local hosts=
        if [ -n "${host}" ]; then
            if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
                PRINT "Host ${host} does not exist." "error" 0
                return 1
            fi

            hosts="${host}"
        else
            hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
        fi
        unset host

        if [ -z "${hosts}" ]; then
            PRINT "Pod '${pod}' is not attached to any host." "warning" 0
            continue
        fi

        local podVersion=
        local host=
        for host in ${hosts}; do
            if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
                PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
                continue
            fi

            local stateFile="pod.state"
            local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"
            local targetPodDir2="${CLUSTERPATH}/${host}/pods/${pod}/release/.${podVersion}.$(date +%s)"
            local targetPodStateFile="${targetPodDir}/${stateFile}"

            if [ ! -f "${targetPodStateFile}" ]; then
                PRINT "Pod ${pod}:${podVersion} not found on host ${host}. Skipping." "warning" 0
                continue
            fi

            local state="$(cat "${targetPodStateFile}")"
            if [ "${state}" != "removed" ]; then
                PRINT "Pod ${pod}:${podVersion} on host ${host} is not in the 'removed' state. Skipping." "warning" 0
                continue
            fi

            mv "${targetPodDir}" "${targetPodDir2}"

            PRINT "Delete release ${podVersion} on host ${host}" "info" 0

            _PRJ_LOG_P "${host}" "${pod}" "DELETE_RELEASE ${podVersion}"
        done
    done
}


# Set the pod.version.state file of one or many pod releases.
_PRJ_SET_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS _PRJ_ENUM_STATE PRINT _PRJ_LOG_P _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local state="${1}"
    shift

    if ! _PRJ_ENUM_STATE "${state}"; then
        PRINT "Given state is not a valid state: ${state}. Valid states are: running, stopped and removed" "error" 0
        return 1
    fi

    local podTriple=
    for podTriple in "$@"; do
        local pod=
        local version=
        local host=
        if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
            return 1
        fi

        local hosts=
        if [ -n "${host}" ]; then
            if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
                PRINT "Host ${host} does not exist." "error" 0
                return 1
            fi

            hosts="${host}"
        else
            hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
        fi
        unset host

        if [ -z "${hosts}" ]; then
            PRINT "Pod '${pod}' is not attached to any host." "warning" 0
            continue
        fi

        local podVersion=
        local host=
        for host in ${hosts}; do
            if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
                PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
                continue
            fi

            local stateFile="pod.state"
            local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"
            local targetPodStateFile="${targetPodDir}/${stateFile}"

            if [ ! -d "${targetPodDir}" ]; then
                PRINT "Pod ${pod}:${podVersion} not found on host ${host}. Skipping." "warning" 0
                continue
            fi

            PRINT "Set state of release ${podVersion} on host ${host} to ${state}." "info" 0

            printf "%s\\n" "${state}" >"${targetPodStateFile}"

            _PRJ_LOG_P "${host}" "${pod}" "SET_POD_RELEASE_STATE release:${podVersion}=${state}"
        done
    done
}

_PRJ_ACTION_POD()
{
    SPACE_SIGNATURE="podTriple action"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE _PRJ_ACTION_POD2"
    SPACE_ENV="CLUSTERPATH"

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod '${pod}' is not attached to any host." "error" 0
        return 1
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
            continue
        fi
        PRINT "Send action to ${pod}:${podVersion}@${host}: $@" "info" 0
        _PRJ_ACTION_POD2 "${pod}" "${podVersion}" "$@"
    done
}

_PRJ_ACTION_POD2()
{
    SPACE_SIGNATURE="pod podVersion action"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local status=
    _REMOTE_EXEC "${host}" "action" "${pod}" "${podVersion}" "$@"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not send action to pod on host." "error" 0

    # Failed
    return "${status}"
}

_PRJ_SIGNAL_POD()
{
    SPACE_SIGNATURE="podTriple [container]"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE _PRJ_SIGNAL_POD2 _PRJ_GET_POD_RELEASE_STATE"
    SPACE_ENV="CLUSTERPATH"

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod '${pod}' is not attached to any host." "error" 0
        return 1
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
            continue
        fi
        local state="$(_PRJ_GET_POD_RELEASE_STATE "${host}" "${pod}" "${podVersion}")"
        if [ "${state}" = "running" ]; then
            PRINT "Signal ${pod}:${podVersion}@${host} $@" "info" 0
            _PRJ_SIGNAL_POD2 "${pod}" "${podVersion}" "$@"
        else
            PRINT "Pod ${pod}:${podVersion} is not in the running state" "warning" 0
        fi
    done
}

_PRJ_SIGNAL_POD2()
{
    SPACE_SIGNATURE="pod podVersion [container]"
    SPACE_DEP="_REMOTE_EXEC PRINT"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local status=
    _REMOTE_EXEC "${host}" "signal" "${pod}" "${podVersion}" "$@"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not signal pod on host." "error" 0

    # Failed
    return "${status}"
}

# Get or set the pod.ingress.conf file active/inactive
# state=active|inactive
# Multiple podTriples can be provided
_PRJ_POD_INGRESS_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS PRINT _PRJ_LOG_P _PRJ_DOES_HOST_EXIST _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local state="${1}"
    shift

    local podTriple=
    for podTriple in "$@"; do
        local pod=
        local version=
        local host=
        if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
            return 1
        fi

        local hosts=
        if [ -n "${host}" ]; then
            if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
                PRINT "Host ${host} does not exist." "error" 0
                return 1
            fi

            hosts="${host}"
        else
            hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
        fi
        unset host

        if [ -z "${hosts}" ]; then
            PRINT "Pod '${pod}' is not attached to any host." "warning" 0
            continue
        fi

        local podVersion=
        local host=
        for host in ${hosts}; do
            if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
                PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
                continue
            fi

            local ingressConfFile="pod.ingress.conf"
            local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"
            local targetPodIngressConfFile="${targetPodDir}/${ingressConfFile}"

            if [ ! -d "${targetPodDir}" ]; then
                PRINT "Pod ${pod}:${podVersion} not found on host ${host}. Skipping." "warning" 0
                continue
            fi

            if [ -z "${state}" ]; then
                # Output state
                local currentState="none"
                if [ -f "${targetPodIngressConfFile}.inactive" ]; then
                    currentState="inactive"
                elif [ -f "${targetPodIngressConfFile}" ]; then
                    currentState="active"
                fi
                printf "%s:%s@%s %s\\n" "${pod}" "${podVersion}" "${host}" "${currentState}"
                continue
            fi

            PRINT "Set ingress state of release ${podVersion} on host ${host} to ${state}." "info" 0

            if [ "${state}" = "active" ]; then
                if [ -f "${targetPodIngressConfFile}.inactive" ]; then
                    mv "${targetPodIngressConfFile}.inactive" "${targetPodIngressConfFile}"
                fi
            else
                if [ -f "${targetPodIngressConfFile}" ]; then
                    mv "${targetPodIngressConfFile}" "${targetPodIngressConfFile}.inactive"
                fi
            fi

            _PRJ_LOG_P "${host}" "${pod}" "SET_POD_INGRESS_STATE release:${podVersion}=${state}"
        done
    done
}

_PRJ_LIST_PODS_BY_HOST()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    (cd "${CLUSTERPATH}" && find . -maxdepth 4 -mindepth 4 -regex "^./${host}/pods/[^.][^/]*/log\.txt$" |cut -d/ -f4)
}

# Copy configs from general cluster pod config store into this version of the pod.
_PRJ_UPDATE_POD_CONFIG()
{
    SPACE_SIGNATURE="podTriple"
    SPACE_DEP="PRINT _UTIL_GET_TAG_DIR _PRJ_DOES_HOST_EXIST _PRJ_LIST_ATTACHEMENTS _PRJ_LOG_P _PRJ_COPY_POD_CONFIGS _PRJ_CHKSUM_POD_CONFIGS _PRJ_FIND_POD_VERSION _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local podTriple="${1}"
    shift

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTriple}"; then
        return 1
    fi

    if [ ! -d "${CLUSTERPATH}/_config/${pod}" ]; then
        PRINT "_config/${pod} does not exist in cluster, maybe import them first?" "error" 0
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
            PRINT "Host ${host} does not exist." "error" 0
            return 1
        fi

        hosts="${host}"
    else
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    fi
    unset host

    if [ -z "${hosts}" ]; then
        PRINT "Pod ${pod} is not attached to any host." "warning" 0
        return 0
    fi

    local configCommit=
    if ! configCommit="$(_UTIL_GET_TAG_DIR "${CLUSTERPATH}/_config/${pod}")"; then
        return 1
    fi

    local podVersion=
    local host=
    for host in ${hosts}; do
        if ! podVersion="$(_PRJ_FIND_POD_VERSION "${pod}" "${version}" "${host}")"; then
            #PRINT "Version ${version} not found on host ${host}. Skipping." "info" 0
            continue
        fi
        if [ -d "${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}" ]; then
            PRINT "Copy ${pod} configs from cluster into release ${podVersion} on host ${host}." "info" 0
            rm -rf "${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}/config"
            if ! _PRJ_COPY_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                return 1
            fi
            if ! _PRJ_CHKSUM_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                return 1
            fi
        else
            PRINT "Release ${podVersion} does not exist on host ${host}, skipping." "info" 0
            continue
        fi

        _PRJ_LOG_P "${host}" "${pod}" "UPDATE_CONFIG release:${podVersion} cfg:${configCommit}"
    done
}

# Compiles a pod to all hosts it is attached to.
_PRJ_COMPILE_POD()
{
    SPACE_SIGNATURE="podTuple [verbose expectedPodVersion]"
    SPACE_DEP="PRINT _PRJ_LIST_ATTACHEMENTS _PRJ_LOG_P _UTIL_GET_TAG_FILE _PRJ_DOES_HOST_EXIST STRING_SUBST STRING_TRIM _UTIL_GET_TAG_DIR STRING_ESCAPE _PRJ_GET_FREE_HOSTPORT TEXT_FILTER TEXT_VARIABLE_SUBST TEXT_EXTRACT_VARIABLES _PRJ_COPY_POD_CONFIGS _PRJ_CHKSUM_POD_CONFIGS FILE_REALPATH _PRJ_LIST_ATTACHEMENTS STRING_ITEM_INDEXOF STRING_IS_ALL _PRJ_SPLIT_POD_TRIPLE _PRJ_GET_FREE_CLUSTERPORT"
    SPACE_ENV="CLUSTERPATH PODPATH"

    local podTuple="${1}"
    shift

    local verbose="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local expectedPodVersion="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTuple}"; then
        return 1
    fi


    local attachedHosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"

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
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
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
        PRINT "Pod ${pod} is not attached to any host." "warning" 0
        return 0
    fi

    # Check so that pod repo is git repo. Possibly clone it if missing.
    local podDir="$(FILE_REALPATH "${PODPATH}/${pod}")"
    if [ ! -d "${podDir}" ]; then
        # For each host check if git.url is provided then match it against the pod repo.
        # If not existing, create it.
        local gitUrl=
        local host=
        for host in ${hosts}; do
            local hostPodGitFile="${CLUSTERPATH}/${host}/pods/${pod}/git.url"
            if [ -f "${hostPodGitFile}" ]; then
                gitUrl="$(cat "${hostPodGitFile}")"
                if [ -n "${gitUrl}" ]; then
                    break
                fi
            fi
        done
        # Check if to clone
        if [ -n "${gitUrl}" ]; then
            if ! git clone "${gitUrl}" "${podDir}"; then
                PRINT "Could not git clone pod ${gitUrl}" "error" 0
                return 1
            fi
        else
            PRINT "Pod does not exist as ${podDir}. You need to clone it there." "error" 0
            return 1
        fi
    else
        # Pod dir does exist
        if [ ! -d "${podDir}/.git" ]; then
            PRINT "Cannot compile pod when pod is not a git repo: ${podDir}." "error" 0
            return 1
        fi
    fi

    local url=
    url="$(cd "${podDir}" && git config --get remote.origin.url)"

    local podSpec="$(FILE_REALPATH "${PODPATH}/${pod}/pod.yaml")"

    local podCommit=
    if ! podCommit="$(_UTIL_GET_TAG_FILE "${podSpec}")"; then
        return 1
    fi

    local clusterCommit=
    if ! clusterCommit="$(_UTIL_GET_TAG_FILE "${clusterConfig}")"; then
        return 1
    fi

    local configCommit="<none>"
    if [ ! -d "${CLUSTERPATH}/_config/${pod}" ]; then
        PRINT "No configs exist in the cluster for this pod" "info" 0
    else
        if ! configCommit="$(_UTIL_GET_TAG_DIR "${CLUSTERPATH}/_config/${pod}")"; then
            return 1
        fi
    fi

    if ! command -v podc >/dev/null 2>/dev/null; then
        PRINT "podc not available on path, cannot compile pod." "error" 0
        return 1
    fi

    PRINT "Compiling pod ${pod}" "info" 0

    ## Now everything is setup for us to compile the pod onto each host it is attached to.

    # Check for auto assignments of cluster ports.
    # and do sanity check on variable names.
    local text="$(cat "${podSpec}")"
    local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${text}")"
    local newClusterPorts=""    # To keep track of already assigned cluster ports
    local valuesClusterPorts=""
    local varname=
    for varname in ${variablesToSubst}; do
        # Do sanity check on the variable name extracted.
        # underscored variables pass through here, but are ignored later.
        if ! STRING_IS_ALL "${varname}" "A-Za-z0-9_" || [ "${varname#[0-9]}" != "${varname}" ]; then
            PRINT "Variable name '${varname}' contains illegal characters. Only [A-Za-z0-9_] are allowed, and cannot begin with a digit." "error" 0
            return 1
        fi
        if [ "${varname#CLUSTERPORTAUTO}" != "${varname}" ]; then
            # This is an auto cluster port assignment.
            # we need to find a free port and assign the variable.
            local newport=
            if ! newport="$(_PRJ_GET_FREE_CLUSTERPORT "${newClusterPorts}")"; then
                PRINT "Could not acquire a free cluster port." "error" 0
                return 1
            fi
            newClusterPorts="${newClusterPorts}${newClusterPorts:+ }${newport}"
            valuesClusterPorts="${valuesClusterPorts}${valuesClusterPorts:+${newline}}${varname}=${newport}"
        fi
    done

    if [ -n "${newClusterPorts}" ]; then
        PRINT "Cluster (wide) ports auto generated: ${newClusterPorts}" "info" 0
    fi

    local status=0  # Status flag checked after the for-loop.
    local podsCompiled=""  # Keep track of all pods compiled so we can remove them if we encounter an error.
    local host=
    for host in ${hosts}; do
        PRINT "Begin compile pod ${pod} for host ${host}" "info" 0

        # For each host check if git.url is provided then match it against the pod repo.
        # If not existing, create it.
        local hostPodGitFile="${CLUSTERPATH}/${host}/pods/${pod}/git.url"
        local url2=
        if [ -f "${hostPodGitFile}" ]; then
            url2="$(cat "${hostPodGitFile}")"
        fi
        if [ -n "${url}" ]; then
            if [ -n "${url2}" ]; then
                # Make https://domain and git@domain: be comparable.
                local urlStripped="${url#*@}"
                urlStripped="${urlStripped#*://}"
                urlStripped="${urlStripped%.git}"
                STRING_SUBST "urlStripped" ":" "/" 1
                local url2Stripped="${url2#*@}"
                url2Stripped="${url2Stripped#*://}"
                url2Stripped="${url2Stripped%.git}"
                STRING_SUBST "url2Stripped" ":" "/" 1

                if [ "${urlStripped}" != "${url2Stripped}" ]; then
                    PRINT "Git url \"${url}\" of pod does not match the attached pod git url \"${url2}\" on host: ${host}" "error" 0
                    status=1
                    break
                fi
            fi
            if [ -z "${url2}" ]; then
                # Create git.url file
                PRINT "Set git.url of ${host}/pods/${pod}, since it was missing." "info" 0
                printf "%s\\n" "${url}" >"${hostPodGitFile}"
            fi
        else
            if [ -n "${url2}" ]; then
                PRINT "Git url \"${url}\" of pod does not match the attached pod git url \"${url2}\" on host: ${host}" "error" 0
                status=1
                break
            fi
        fi

        # Perform variable substitution
        ## 1. Extract variables used in pod.yaml file
        ## 2. Inspect those to see if any are ${HOSTPORTAUTOxyz}, then for each 'xyz' we find a free host port on the host to assign that variable.
        ## 3. Prefix any variables names in pod.yaml with "podname_".
        ## 4. Run first sweep of substitution.
        ## 5. Load cluster variables from cluster-vars.env
        ## 6. Run second sweep of variable substituation on pod.yaml

        # We need to get the podspec new for each host iteration becuase the compilation can look different
        # on each host for auto assigned host ports.
        local text="$(cat "${podSpec}")"
        local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${text}")"
        local newline="
"

        local podVersion="$(printf "%s\\n" "${text}" |grep -o "^podVersion:[ ]*['\"]\?\([0-9]\+\.[0-9]\+\.[0-9]\+\(-[-.a-z0-9]\+\)\?\)")"
        podVersion="${podVersion#*:}"
        STRING_SUBST "podVersion" "'" "" 1
        STRING_SUBST "podVersion" '"' "" 1
        STRING_TRIM "podVersion"

        if [ -z "${podVersion}" ]; then
            PRINT "podVersion is missing. Must be on semver format (major.minor.patch[-tag])." "error" 0
            state=1
            break
        fi

        # For each ${HOSTPORTAUTOxyz} we find free host ports and substitute that.
        local variablesAll=""       # For show, all variables read from cluster-vars.env
        local variablesToSubst2=""  # Use this to save variable names for the second sweep of substitutions.
        local values="${valuesClusterPorts}"             # Values to substitute in first sweep, start out with any clusterport substitutions.
        local newHostPorts=""       # To keep track of already assigned host ports
        local varname=
        for varname in ${variablesToSubst}; do
            if [ "${varname#_}" != "${varname}" ]; then
                # Skip underscored variables
                continue
            elif [ "${varname}" = "podVersion" ]; then
                # Special case where we substitute podVersion with what is defined in the pod.yaml
                values="${values}${values:+${newline}}${varname}=${podVersion}"
            elif [ "${varname#HOSTPORTAUTO}" != "${varname}" ]; then
                # This is an auto host port assignment,
                # we need to find a free port and assign the variable.
                local newport=
                if ! newport="$(_PRJ_GET_FREE_HOSTPORT "${host}" "${newHostPorts}")"; then
                    PRINT "Could not acquire a free host port on the host ${host}." "error" 0
                    status=1
                    break 2
                fi
                newHostPorts="${newHostPorts}${newHostPorts:+ }${newport}"
                values="${values}${values:+${newline}}${varname}=${newport}"
            elif [ "${varname#CLUSTERPORTAUTO}" != "${varname}" ]; then
                # This is an auto cluster port assignment.
                # This is already taken care of.
                :
            else
                # This is user defined variable, check if it is global or pod specific.
                # Global variables are shared between pods and are all CAPS.
                # Variables which are not all caps are expected to have the pod name as a prefix as defined in cluster-vars.env, because they are pod specific.
                if STRING_IS_ALL "${varname}" "A-Z0-9_"; then
                    # All CAPS, just substitute it with it's value from cluster-vars.env, added later.
                    variablesAll="${variablesAll}${variablesAll:+ }${varname}"
                else
                    # Not all caps, prefix the variable name defined in pod.yaml with "podname_", as it is defined in cluster-vars.env
                    # The actual value substitution will happen in the second sweep.
                    values="${values}${values:+${newline}}${varname}=\$\{${pod}_${varname}\}"
                    # Save the variable name to subst for the second sweep
                    variablesToSubst2="${variablesToSubst2}${variablesToSubst2:+ }${pod}_${varname}"
                    variablesAll="${variablesAll}${variablesAll:+ }${pod}_${varname}"
                fi
            fi
        done

        if [ -n "${newHostPorts}" ]; then
            PRINT "Host ports auto generated on host '${host}': ${newHostPorts}" "info" 0
        fi

        # Check so that all variables are defined in cluster-vars.env, if not issue a warning.
        local varname=
        for varname in ${variablesAll}; do
            # Do not warn about DEVMODE
            if [ "${varname}" = "DEVMODE" ]; then
                continue
            fi
            if ! grep -q -m 1 "^${varname}=" "${clusterConfig}"; then
                PRINT "Pod variable \"${varname}\" is not defined in cluster-vars.env" "warning" 0
            fi
        done

        # For each variable identified in pod.yaml, iterate over it and substitute it for its value
        # Do a first sweep, substituting auto host ports, substituting CAPS global variable for values and adding prefix to all other variables.
        values="${values}${newline}$(cat "${clusterConfig}")"
        text="$(TEXT_VARIABLE_SUBST "${text}" "${variablesToSubst}" "${values}")"

        # Second sweep of substitutions
        local values2="$(cat "${clusterConfig}")"
        text="$(TEXT_VARIABLE_SUBST "${text}" "${variablesToSubst2}" "${values2}")"
        text="$(printf "%s\\n" "${text}" |TEXT_FILTER)"

        if [ -n "${expectedPodVersion}" ] && [ "${expectedPodVersion}" != "${podVersion}" ]; then
            PRINT "Pod source version ${podVersion} does not match the expected version ${expectedPodVersion}" "error" 0
            state=1
            break
        fi

        local targetPodDir="${CLUSTERPATH}/${host}/pods/${pod}/release/${podVersion}"

        if [ -d "${targetPodDir}" ]; then
            PRINT "Pod ${pod} version ${podVersion} already exists on host ${host}. Skipping." "info" 0
            continue
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
            PRINT "Copying pod configs from cluster repo into new pod release when compiling. Note that new/changed configs from the pod repo are not automatically updated into the cluster repo. Run \"sns cluster importconfig\" to import from pod repo to cluster repo, then \"sns pod updateconfig\" to copy those into an existing pod release." "info" 0
            if ! _PRJ_COPY_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                status=1
                break
            fi
        fi

        if ! SPACE_LOG_LEVEL="${SPACE_LOG_LEVEL}" podc "${pod}" -f "${tmpPodSpec}" -o "${targetPodSpec}" -d "${podSpec%/*}" -p false; then
            status=1
            break
        fi

        # Checksum configs, we do this after compiling since comilation can add to configs.
        if [ -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "Checksum configs in release." "debug" 0
            if ! _PRJ_CHKSUM_POD_CONFIGS "${CLUSTERPATH}" "${host}" "${pod}" "${podVersion}"; then
                status=1
                break
            fi
        fi

        # Set state as running.
        local targetpodstate="${targetPodDir}/pod.state"
        printf "%s\\n" "running" >"${targetpodstate}"

        _PRJ_LOG_P "${host}" "${pod}" "COMPILE_POD release:${podVersion} pod.yaml:${podCommit} cluster-vars.env:${clusterCommit} cfg:${configCommit}"
    done

    if [ "${status}" -gt 0 ] && [ -n "${podsCompiled}" ]; then
        PRINT "Removing compiled pods" "info" 0
        local dir=
        for dir in ${podsCompiled}; do
            rm -rf "${dir}"
        done
        return 1
    fi

    if [ -z "${podsCompiled}" ]; then
        PRINT "Pod not compiled." "error" 0
    fi

    if [ "${verbose}" = "true" ] && [ -n "${podsCompiled}" ]; then
        printf "%s\\n" "${podVersion}"
    fi
}

_PRJ_CLUSTER_IMPORT_POD_CFG()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="PRINT _PRJ_LOG_C _UTIL_GET_TAG_DIR FILE_REALPATH _PRJ_LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH PODPATH"

    local pod="${1}"
    shift

    local hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"

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

    local configCommit=
    if ! configCommit="$(_UTIL_GET_TAG_DIR "${podConfigDir}")"; then
        return 1
    fi

    if [ -d "${clusterPodConfigDir}" ]; then
        PRINT "Cluster config for the pod '${pod}' already exists, will overwrite in 3 seconds..." "warning" 0
        sleep 3
    fi

    mkdir -p "${CLUSTERPATH}/_config"

    if ! cp -r "${podConfigDir}/." "${clusterPodConfigDir}"; then
        PRINT "Unexpected disk failure importing configs to cluster project." "error" 0
        return 1
    fi

    PRINT "Configs copied. New pod releases will get these new configs when compiled. To update configs of an existing pod release run \"sns pod updateconfig\"" "info" 0

    _PRJ_LOG_C "IMPORT_POD_CFG ${pod}:${configCommit}"
}

_PRJ_DETACH_POD()
{
    SPACE_SIGNATURE="podTuple"
    SPACE_DEP="PRINT STRING_ITEM_INDEXOF _PRJ_DOES_HOST_EXIST _PRJ_IS_POD_ATTACHED _PRJ_LOG_P _PRJ_LIST_ATTACHEMENTS _PRJ_SPLIT_POD_TRIPLE"
    SPACE_ENV="CLUSTERPATH"

    local podTuple="${1}"

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTuple}"; then
        return 1
    fi

    local attachedHosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"

    if [ -z "${attachedHosts}" ]; then
        PRINT "Pod '${pod}' is not attached to this cluster." "error" 0
        return 1
    fi

    local hosts=
    if [ -n "${host}" ]; then
        if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
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

    local host=
    for host in ${hosts}; do
        _PRJ_LOG_P "${host}" "${pod}" "DETACHED"
        local ts="$(date +%s)"
        if ! mv "${CLUSTERPATH}/${host}/pods/${pod}" "${CLUSTERPATH}/${host}/pods/.${pod}.${ts}"; then
            PRINT "Unexpected disk failure when detaching pod." "error" 0
            return 1
        fi

        PRINT "Pod '${pod}' detached from '${host}'" "ok" 0
    done

    # Check if this was the last pod on the hosts, if so suggest to remove any pod configs in the cluster.
    local hosts=
    hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    if [ -z "${hosts}" ]; then
        if [ -d "${CLUSTERPATH}/_config/${pod}" ]; then
            PRINT "There are no more pods of this sort left in this cluster, but there are configs still. You can remove those configs if you want to." "info" 0
        fi
    fi
}

_PRJ_ATTACH_POD()
{
    SPACE_SIGNATURE="podTuple [gitUrl]"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST _PRJ_IS_POD_ATTACHED _PRJ_LOG_P _PRJ_LIST_ATTACHEMENTS STRING_IS_ALL _PRJ_SPLIT_POD_TRIPLE FILE_REALPATH TEXT_EXTRACT_VARIABLES _PRJ_CLUSTER_IMPORT_POD_CFG"
    SPACE_ENV="CLUSTERPATH PODPATH"

    local podTuple="${1}"
    shift

    local gitUrl="${1:-}"

    local pod=
    local version=
    local host=
    if ! _PRJ_SPLIT_POD_TRIPLE "${podTuple}"; then
        return 1
    fi

    if ! STRING_IS_ALL "${pod}" "a-z0-9_" || [ "${pod#[_0-9]}" != "${pod}" ]; then
        PRINT "Invalid pod name. Only 0-9, lowercase a-z and underscore is allowed. Name cannot begin with underscore or digit" "error" 0
        return 1
    fi

    if [ -z "${host}" ]; then
        PRINT "A host must be provided as podname@host" "error" 0
        return 1
    fi

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    if _PRJ_IS_POD_ATTACHED "${CLUSTERPATH}" "${host}" "${pod}"; then
        PRINT "Pod ${pod} already exists on host ${host}." "error" 0
        return 1
    fi

    local podDir="$(FILE_REALPATH "${PODPATH}/${pod}")"
    if [ ! -d "${podDir}" ]; then
        # Check if to clone
        if [ -n "${gitUrl}" ]; then
            if ! git clone "${gitUrl}" "${podDir}"; then
                PRINT "Could not git clone pod ${gitUrl}" "error" 0
                return 1
            fi
        else
            PRINT "Pod does not exist as ${podDir}. Try providing the git url to have it cloned." "error" 0
            return 1
        fi
    else
        # Pod dir does exist
        if [ ! -d "${podDir}/.git" ]; then
            PRINT "Cannot attach pod when pod is not a git repo: ${podDir}." "error" 0
            return 1
        fi
    fi

    local url=
    url="$(cd "${podDir}" && git config --get remote.origin.url)"
    # Check so any provided git url matches
    if [ -n "${gitUrl}" ]; then
        if [ "${url}" != "${gitUrl}" ]; then
            PRINT "Git url provided does not match existing remote.origin.url: \"${url}\"." "error" 0
            return 1
        fi
    fi

    local podSpec="$(FILE_REALPATH "${PODPATH}/${pod}/pod.yaml")"
    if [ ! -f "${podSpec}" ]; then
        PRINT "pod.yaml does not exist as: ${podSpec}" "error" 0
        return 1
    fi

    local text="$(cat "${podSpec}")"
    local variablesToSubst="$(TEXT_EXTRACT_VARIABLES "${text}")"
    local varname=
    for varname in ${variablesToSubst}; do
        # This variable can be referenced in the pod.yaml, but it is automatically
        # provided by the pod compiler.
        if [ "${varname}" = "podVersion" ]; then
            continue
        fi
        if STRING_IS_ALL "${varname}" "A-Z0-9_"; then
            # ALL CAPS global variables
            # Don't show {HOST,CLUSTER}PORTAUTOxyz variable names
            if [ "${varname#HOSTPORTAUTO}" = "${varname}" ] && [ "${varname#CLUSTERPORTAUTO}" = "${varname}" ]; then
                PRINT "Variable ${varname} is defined in pod.yaml, you might want to define it in the cluster-vars.env file" "info" 0
            fi
        else
            # Prefixed variable names.
            PRINT "Variable ${pod}_${varname} is defined in pod.yaml, you might want to define it in the cluster-vars.env file" "info" 0
        fi
    done

    if ! mkdir -p "${CLUSTERPATH}/${host}/pods/${pod}"; then
        PRINT "Could not create directory." "error" 0
        return 1
    fi

    # Remember the git url of the repo, if any.
    if [ -n "${url}" ]; then
        printf "%s\\n" "${url}" >"${CLUSTERPATH}/${host}/pods/${pod}/git.url"
    fi

    # This creates the log.txt file in the attachment dir.
    _PRJ_LOG_P "${host}" "${pod}" "ATTACHED"

    PRINT "Pod is now attached" "ok" 0

    # Check if this was the first pod on the hosts, if so suggest to also add any pod configs into the cluster.
    local podConfigDir="$(FILE_REALPATH "${PODPATH}/${pod}/config")"
    local hosts=
    hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    if [ "${hosts}" = "${host}" ]; then
        if [ ! -d "${CLUSTERPATH}/_config/${pod}" ] && [ -d "${podConfigDir}" ]; then
            PRINT "This was the first attachment of this pod to this cluster, importing template configs from pod into cluster project" "info" 0
            _PRJ_CLUSTER_IMPORT_POD_CFG "${pod}"
        fi
    fi
}

# Run as superuser
_PRJ_HOST_SETUP()
{
    SPACE_SIGNATURE="host strictUserKeys strictSuperUserKeys [skipFirewall skipSystemd skipPodman]"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST SSH_KEYGEN STRING_ITEM_INDEXOF STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local strictUserKeys="${1:-false}"
    shift

    local strictSuperUserKeys="${1:-false}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    # Load host env file and create a new one
    hostEnv="${CLUSTERPATH}/${host}/host.env"
    hostEnv2="${CLUSTERPATH}/${host}/host-superuser.env"

    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    if [ ! -f "${hostEnv2}" ]; then
        PRINT "${hostEnv2} file does not exist." "error" 0
        return 1
    fi

    local USER=
    local KEYFILE=
    local HOST=
    local PORT=
    local JUMPHOST=
    local EXPOSE=
    local INTERNAL=

    local value=
    local varname=
    for varname in USER KEYFILE HOST PORT JUMPHOST EXPOSE INTERNAL; do
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
    local pubKeysDir="${CLUSTERPATH}/${host}/pubkeys"
    local pubKeys=
    if [ "${strictUserKeys}" = "true" ]; then
        # Only include keys from the pubkeys dir.
        pubKeys="${pubKeysDir}/*.pub"
    else
        # By default also include our current pub key
        pubKeys="${pubKey} ${pubKeysDir}/*.pub"

        if [ ! -f "${KEYFILE}" ]; then
            PRINT "Could not find ${pubKey}" "error" 0
            return 1
        fi
    fi

    local SUPERKEYFILE=
    SUPERKEYFILE="$(grep -m 1 "^KEYFILE=" "${hostEnv2}")"
    SUPERKEYFILE="${SUPERKEYFILE#*KEYFILE=}"
    STRING_TRIM "SUPERKEYFILE"

    SUPERKEYFILE="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${SUPERKEYFILE}")"

    local SUPERUSER=
    SUPERUSER="$(grep -m 1 "^USER=" "${hostEnv2}")"
    SUPERUSER="${SUPERUSER#*USER=}"
    STRING_TRIM "SUPERUSER"

    local superPubKey="${SUPERKEYFILE}.pub"
    local superPubKeysDir="${CLUSTERPATH}/${host}/pubkeys.superuser"
    # By default also include our current super user pub key
    local superPubKeys=
    if [ "${strictSuperUserKeys}" = "true" ]; then
        # Only allow keys in the pubkeys.superuser dir.
        superPubKeys="${superPubKeysDir}/*.pub"
    else
        superPubKeys="${superPubKey} ${superPubKeysDir}/*.pub"
    fi

    local status=
    (cat ${pubKeys} 2>/dev/null | sort | uniq; printf "%s\\n" "---"; cat ${superPubKeys} 2>/dev/null | sort | uniq) | _REMOTE_EXEC "${host}:${hostEnv2}" "setup_host" "${USER}" "${SUPERUSER}" "${EXPOSE}" "${INTERNAL}" "$@"

    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    fi

    PRINT "Could not install setup host" "error" 0

    # Failed
    return "${status}"
}

# Looging in as root, create a new super user on the host.
_PRJ_HOST_CREATE_SUPERUSER()
{
    SPACE_SIGNATURE="host rootkeyfile:0 [superuser superkeyfile]"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST SSH_KEYGEN FILE_REALPATH STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local rootkeyfile="${1}"
    shift

    local superUser="${1:-snssuper}"
    shift $(($# > 0 ? 1 : 0))

    local superKeyFile="${1:-id_rsa_super}"
    shift $(($# > 0 ? 1 : 0))

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    # Load host env file and create a new temporary one and the new superuser one.
    hostEnv="${CLUSTERPATH}/${host}/host.env"
    hostEnv2="${CLUSTERPATH}/${host}/.host-root.env"
    hostEnv3="${CLUSTERPATH}/${host}/host-superuser.env"

    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    if [ -f "${hostEnv3}" ]; then
        PRINT "${hostEnv3} file does already exist. The superuser should already be available." "error" 0
        return 1
    fi

    local HOST=
    local PORT=
    local JUMPHOST=

    local value=
    local varname=
    for varname in HOST PORT JUMPHOST; do
        value="$(grep -m 1 "^${varname}=" "${hostEnv}")"
        value="${value#*${varname}=}"
        STRING_TRIM "value"
        eval "${varname}=\"\${value}\""
    done

    # make tmp absolut path in regards to host dir
    local superKeyFileAbsolute="$(cd "${CLUSTERPATH}/${host}" && FILE_REALPATH "${superKeyFile}")"

    # If keyfile does not exist, we create it.
    if [ ! -f "${superKeyFileAbsolute}" ]; then
        PRINT "Create super user keyfile: ${superKeyFileAbsolute}" "info" 0
        if ! SSH_KEYGEN "${superKeyFileAbsolute}"; then
            PRINT "Could not genereate keyfile" "error" 0
            return 1
        fi
    fi

    local pubKey="${superKeyFileAbsolute}.pub"
    if [ ! -f "${pubKey}" ]; then
        PRINT "Could not find ${pubKey} file" "error" 0
        return 1
    fi

    # Create the temporary .host-root.env file
    printf "%s\\n" "
HOST=${HOST}
USER=root
KEYFILE=${rootkeyfile}
PORT=${PORT}
JUMPHOST=${JUMPHOST}" >"${hostEnv2}"

    local status=
    cat "${pubKey}" | _REMOTE_EXEC "${host}:${hostEnv2}" "create_superuser" "${superUser}"
    status="$?"
    rm "${hostEnv2}"
    if [ "${status}" -ne 0 ]; then
        PRINT "Could not create superuser." "error" 0
        return "${status}"
    fi

    # Create the host-superuser.env file
    printf "%s\\n" "# Auto generated host.env file which can be used with the Space ssh module.
# You can enter this host as SUPERUSER by running \"space -m ssh /ssh/ -e SSHHOSTFILE=host-superuser.env\".

## SSH specific variables
# HOST is the public or private IP of the Host.
# If using a JUMPHOST, then it is likely the internal IP, if not then it is the public IP.
HOST=${HOST}

# SSH port this Host is listening on.
PORT=${PORT}

# The user on the Host which will be running the pods in rootless mode. This should NOT be the root user.
USER=${superUser}

# The path to the SSH keyfile used for this user to login to this Host.
KEYFILE=${superKeyFile}

# Worker hosts are often not exposed to the public internet and to connect to them over SSH a JUMPHOST is needed.
JUMPHOST=${JUMPHOST}" >"${hostEnv3}"

    PRINT "Super user successfully created." "ok" 0
}

_PRJ_HOST_DISABLE_ROOT()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_DOES_HOST_EXIST STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    hostEnv="${CLUSTERPATH}/${host}/host-superuser.env"

    if [ ! -f "${hostEnv}" ]; then
        PRINT "${hostEnv} file does not exist." "error" 0
        return 1
    fi

    local status=
    _REMOTE_EXEC "${host}:${hostEnv}" "disable_root"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        PRINT "Root account disabled" "ok" 0
        return 0
    fi

    PRINT "Could not disable root." "error" 0

    # Failed
    return "${status}"
}

_PRJ_HOST_INIT()
{
    SPACE_SIGNATURE="host force"
    SPACE_DEP="_REMOTE_EXEC PRINT _PRJ_GET_CLUSTER_ID _PRJ_DOES_HOST_EXIST"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local force="${1}"
    shift

    if ! _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does not exist." "error" 0
        return 1
    fi

    local clusterID=

    if ! clusterID="$(_PRJ_GET_CLUSTER_ID)"; then
        PRINT "Cannot get the ID for this cluster project." "error" 0
        return 1
    fi

    local configJsonContent=""
    if [ -f "${CLUSTERPATH}/${host}/registry-config.json" ]; then
        PRINT "Uploading ${CLUSTERPATH}/${host}/registry-config.json to \$HOME/.docker/config.json" "info" 0
        configJsonContent="$(cat "${CLUSTERPATH}/${host}/registry-config.json")"
    elif [ -f "${CLUSTERPATH}/registry-config.json" ]; then
        PRINT "Uploading ${CLUSTERPATH}/registry-config.json to \$HOME/.docker/config.json" "info" 0
        configJsonContent="$(cat "${CLUSTERPATH}/registry-config.json")"
    else
        PRINT "No registry-config.json found in host dir or cluster dir" "info" 0
    fi

    local status=
    printf "%s\\n" "${configJsonContent}" |_REMOTE_EXEC "${host}" "init_host" "${clusterID}" "${force}"
    status="$?"
    if [ "${status}" -eq 0 ]; then
        return 0
    elif [ "${status}" -eq 2 ]; then
        PRINT "Host already initiated with other cluster ID." "error" 0
        return 2
    fi

    PRINT "Could not init host to cluster." "error" 0

    # Failed
    return "${status}"
}

_PRJ_HOST_CREATE()
{
    SPACE_SIGNATURE="hostName jumphost expose hostHome hostAddress user userKey superUser superUserKey internal routerAddress"
    SPACE_DEP="PRINT _PRJ_DOES_HOST_EXIST _PRJ_LOG_C STRING_TRIM STRING_ITEM_INDEXOF STRING_SUBST STRING_IS_ALL"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local jumphost="${1}"
    shift

    local expose="${1}"
    shift

    local hostHome="${1:-$host}"
    shift

    local hostAddress="${1}"
    shift

    local user="${1}"
    shift

    local userKey="${1}"
    shift

    local superUser="${1}"
    shift

    local superUserKey="${1}"
    shift

    local internal="${1:-192.168.0.0/16 10.0.0.0/8 172.16.0.0/11}"
    shift

    local routerAddress="${1:-}"
    shift

    # Check so host has valid characters
    if ! STRING_IS_ALL "${host}" "A-Za-z0-9_-"; then
        PRINT "Host name can only containe [A-Za-z0-9-_] characters." "error" 0
        return 1
    fi

    if _PRJ_DOES_HOST_EXIST "${CLUSTERPATH}" "${host}"; then
        PRINT "Host ${host} does already exist." "error" 0
        return 1
    fi

    local dir="${CLUSTERPATH}/${host}"
    if [ -d "${dir}" ]; then
        PRINT "Host dir does already exist." "error" 0
        return 1
    fi

    # Split address into IP and port
    if [ -z "${hostAddress}" ]; then
        PRINT "Host address must be provided (-a switch). Set to '-a local' for a simulated host working directly on local disk" "error" 0
        return 1
    fi

    local port="${hostAddress#*:}"
    if [ "${port}" = "${hostAddress}" ]; then
        port="22"
    fi
    port="${port:-22}"
    hostAddress="${hostAddress%:*}"

    if [ "${hostAddress}" = "local" ]; then
        if [ -n "${superUser}" ]; then
            PRINT "Superuser cannot be provided for a 'local' host" "error" 0
            return 1
        fi
    fi

    STRING_SUBST "expose" ',' ' ' 1
    STRING_SUBST "internal" ',' ' ' 1
    STRING_TRIM "jumphost"

    local exposePort=
    for exposePort in ${expose}; do
        case "${exposePort}" in
            (*[!0-9]*)
                PRINT "Invalid port provided: ${exposePort}" "error" 0
                return 1
                ;;
            *)
                ;;
        esac
    done

    if [ "${hostAddress}" != "local" ] && [ -z "${jumphost}" ] && ! STRING_ITEM_INDEXOF "${expose}" "${port}"; then
        PRINT "SSH port ${port} not set to be exposed on this host which does not use a JUMPHOST, meaning it will not be accessible at all. Automatically adding port ${port} to the exposed ports list." "warning" 0
        expose="${expose}${expose:+ }${port}"
    fi

    if [ -n "${userKey}" ] && [ ! -f "${userKey}" ]; then
        PRINT "Provided user key ${userKey} does not exist, it will be generated." "warning" 0
    fi

    if [ -n "${superUserKey}" ] || [ -n "${superUser}" ]; then
        if [ -z "${superUserKey}" ]; then
            superUserKey="id_rsa_super"
        fi
        if [ -z "${superUser}" ]; then
            PRINT "If providing a superUser key you must also provide the superUser name" "error" 0
            return 1
        fi
        if [ ! -f "${superUserKey}" ]; then
            PRINT "Superuser key ${superUserKey} does not exist. Please place key pair at: ${superUserKey}" "warning" 0
        fi
    fi

    # TODO: check $internal to be valid.

    # Create the host directory
    mkdir -p "${dir}"
    printf "%s\\n" "active" >"${dir}/host.state"

    # Create the host.env file
    printf "%s\\n" "# Auto generated host.env file which can be used with the Space ssh module.
# You can enter this host as USER by running \"space -m ssh /ssh/ -e SSHHOSTFILE=host.env\".

## SSH specific variables
# HOST is the public or private IP of the Host.
# If using a JUMPHOST, then it is likely the internal IP, if not then it is the public IP.
HOST=${hostAddress}

# SSH port this Host is listening on.
PORT=${port}

# The user on the Host which will be running the pods in rootless mode. This should NOT be the root user.
USER=${user:-sns}

# Default SSH connect timeout (seconds)
FLAGS=-oConnectTimeout=30

# The path to the SSH keyfile used for this user to login to this Host.
KEYFILE=${userKey:-id_rsa}

# Worker hosts are often not exposed to the public internet and to connect to them over SSH a JUMPHOST is needed.
JUMPHOST=${jumphost}

## Simplenetes host configuration variables
# Expose these ports to the public internet
EXPOSE=${expose}

# Networks for internal traffic, these are important and the settings depend on the subnets of your hosts.
INTERNAL=${internal}

# HOSTHOME is the directory on the host where this local host sync to.
HOSTHOME=${hostHome}

# ROUTERADDRESS is the the IP:port within the cluster where this host's Proxy service can be reached at and also the default interface where pod ports are bound to.
# Format is localIP:32767.
# These addresses will be aggregated and placed and the hosts so that the proxy pod can find the list when it is serving connections.
# The IP address given must be the host's local IP because it is also used
# as the default interface for exposing pod ports.
ROUTERADDRESS=${routerAddress}" >"${dir}/host.env"

    # Possibly create the host-superuser.env file
    if [ -n "${superUser}" ]; then
        printf "%s\\n" "# Auto generated host.env file which can be used with the Space ssh module.
# You can enter this host as SUPERUSER by running \"space -m ssh /ssh/ -e SSHHOSTFILE=host-superuser.env\".

## SSH specific variables
# HOST is the public or private IP of the Host.
# If using a JUMPHOST, then it is likely the internal IP, if not then it is the public IP.
HOST=${hostAddress}

# SSH port this Host is listening on.
PORT=${port}

# The user on the Host which will be running the pods in rootless mode. This should NOT be the root user.
USER=${superUser}

# The path to the SSH keyfile used for this user to login to this Host.
KEYFILE=${superUserKey}

# Worker hosts are often not exposed to the public internet and to connect to them over SSH a JUMPHOST is needed.
JUMPHOST=${jumphost}" >"${dir}/host-superuser.env"

    fi

    PRINT "Host ${host} created at ${dir}" "ok" 0
    _PRJ_LOG_C "CREATE_HOST ${host}"
}

_PRJ_CLUSTER_CREATE()
{
    SPACE_SIGNATURE="basePath clusterName"
    SPACE_DEP="PRINT _PRJ_LOG_C"

    local basePath="${1}"
    shift

    local clusterName="${1}"
    shift

    if [ "${clusterName}" = "pods" ] || [ "${clusterName}" = "keys" ]; then
        PRINT "'pods' and 'keys' are reserved names" "error" 0
        return 1
    fi

    local CLUSTERPATH="${basePath}/${clusterName}"

    # Add random suffix, to avoid possible name clashes when reusing same cluster names.
    local randomToken="$(awk 'BEGIN{min=1;max=65535;srand(); print int(min+rand()*(max-min+1))}')"
    clusterName="${clusterName}-${randomToken}"

    if [ -e "${CLUSTERPATH}" ]; then
        PRINT "Cluster directory already exists" "error" 0
        return 1
    fi

    mkdir -p "${CLUSTERPATH}" &&
    touch "${CLUSTERPATH}/cluster-vars.env" &&
    printf "%s\\n" "${clusterName}" >"${CLUSTERPATH}/cluster-id.txt" &&
    printf "%s\\n" "_pods" >"${CLUSTERPATH}/.gitignore" &&
    cd "${CLUSTERPATH}" &&
    git init &&
    git add . &&
    git commit -m "Initial" &&
    PRINT "Cluster repo successfully created at ${CLUSTERPATH}" "ok" 0 &&
    _PRJ_LOG_C "CREATED-CLUSTER-PROJECT" || return 1
}


# Get the ID for this cluster.
# The cluster ID is used to verify that when syncing a cluster project to a host the cluster IDs match on both sides.
# This is because only one cluster is allowed per cluster and any attmepts in syncing a second cluster to a host must fail.
_PRJ_GET_CLUSTER_ID()
{
    SPACE_ENV="CLUSTERPATH"

    local clusterIdFile="${CLUSTERPATH}/cluster-id.txt"

    cat "${clusterIdFile}" 2>/dev/null
}

# Get the list of commit ids for this cluster project.
# output list of short commit ids, leftmost is initial commit, right most is HEAD.
_PRJ_GET_CLUSTER_GIT_COMMIT_CHAIN()
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
_PRJ_IS_CLUSTER_CLEAN()
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
            if [ "${file#*_synclogs/*sync.log.txt}" != "${file}" ]; then
                continue
            fi
            if [ "${file##*/log.txt}" != "${file}" ]; then
                continue
            fi
            return 1
        done
    fi

    return 0
}

# Go through all pods on all hosts to see if any hostports/clusterports are interfering with each other.
_PRJ_CHECK_PORT_CLASHES()
{
    SPACE_DEP="_PRJ_LIST_HOSTS "
    SPACE_ENV="CLUSTERPATH"

    local err=0
    local host=
    hosts="$(_PRJ_LIST_HOSTS 0)"
    for host in ${hosts}; do
        # Get all cluster ports on host
        local dir="${CLUSTERPATH}/${host}/pods"
        # Extract clusterPorts from the proxy config lines.
        local clusterPorts="$(cd "${dir}" 2>/dev/null && find . -regex "^./[^.][^/]*/release/[^.][^/]*/pod.portmappings.conf\$" -exec cat {} \; |cut -d ':' -f1 |sort)"
        # Extract hostPorts from the proxy config lines.
        local hostPorts="$(cd "${dir}" 2>/dev/null && find . -regex "^./[^.][^/]*/release/[^.][^/]*/pod.portmappings.conf\$" -exec cat {} \; |cut -d ':' -f2 |sort)"

        local duplicateHostPorts="$(printf "%s\\n" "${hostPorts}" |uniq -d)"

        # Check if there are any duplicate host ports in usage on the host.
        if [ -n "${duplicateHostPorts}" ]; then
            local newline="
"
            STRING_SUBST "duplicateHostPorts" "${newline}" " " 1
            PRINT "Duplicate usage of host ports detected on host ${host}: ${duplicateHostPorts}" "error" 0
            err=1
        fi

        # Check if any hostport is interfering with any clusterport
        local clashingPorts="$( { printf "%s\\n" "${hostPorts}" |uniq; printf "%s\\n" "${clusterPorts}" |uniq; } |sort |uniq -d)"
        if [ -n "${clashingPorts}" ]; then
            local newline="
"
            STRING_SUBST "clashingPorts" "${newline}" " " 1
            PRINT "Clashing of cluster and host ports detected on host ${host}: ${clashingPorts}" "error" 0
            err=1
        fi
    done

    return "${err}"
}

# Find first unused cluster port on all hosts, between 61000 to 63999.
# Also take into account any host ports which might be set in the range.
_PRJ_GET_FREE_CLUSTERPORT()
{
    SPACE_SIGNATURE="reservedPorts:0"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="PRINT"

    local reservedPorts="${1}"

    # Extract clusterPorts from the proxy config lines from all pods on all hosts.
    local usedPorts="$(cd "${CLUSTERPATH}" && find . -regex "^./[^.][^/]*/pods/[^.][^/]*/release/[^.][^/]*/pod.portmappings.conf\$" -exec cat {} \; |cut -d ':' -f1-2 |tr ':' '\n')"

    local port=60999
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

    if [ "${port}" -gt "63999" ]; then
        PRINT "All cluster ports between 61000-63999 are already claimed on cluster. You need to delete some old versions of pods to free up claims on cluster ports." "error" 0
        return 1
    fi

    printf "%s\\n" "${port}"
}

# Find first unused host ports on a specific host, between 30000 to 31999.
# Also take into account any clusterPorts which might have been set in the designated range.
_PRJ_GET_FREE_HOSTPORT()
{
    SPACE_SIGNATURE="host reservedPorts:0"
    SPACE_ENV="CLUSTERPATH"
    SPACE_DEP="PRINT"

    local host="${1}"
    shift

    local reservedPorts="${1}"

    local dir="${CLUSTERPATH}/${host}/pods"

    # Extract hostPorts and clusterPorts from the proxy config lines.
    local usedPorts="$(cd "${dir}" && find . -regex "^./[^.][^/]*/release/[^.][^/]*/pod.portmappings.conf\$" -exec cat {} \; |cut -d ':' -f1-2 |tr ':' '\n')"

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

    if [ "${port}" -gt "31999" ]; then
        PRINT "All ports between 30000-31999 are already claimed on host ${host}. You need to delete some old versions of pods to free up claims on host ports." "error" 0
        return 1
    fi

    printf "%s\\n" "${port}"
}

# Copy config from cluster config store to pod release.
# Do not copy underscore prefixed configs.
_PRJ_COPY_POD_CONFIGS()
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
        for config in $(find . -mindepth 1 -maxdepth 1 -not -path './.*'  |cut -b3-); do
            if [ "${config#_}" != "${config}" ]; then
                # Underscore prefixed config, skip it.
                # Such configs are meant for build time operations only, such as for the IngressPod template files.
                PRINT "Not copying underscored directory ${config}" "info" 0
                continue
            fi
            if [ ! -d "${config}" ]; then
                # Not a dir, skip it.
                PRINT "Not copying file ${config}, only directories are copied" "info" 0
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
_PRJ_CHKSUM_POD_CONFIGS()
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
        for config in $(find . -mindepth 1 -maxdepth 1 -type d -not -path './.*'  |cut -b3-); do
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

_PRJ_GET_POD_RELEASES()
{
    SPACE_SIGNATURE="host pod"
    SPACE_ENV="CLUSTERPATH"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    (cd "${CLUSTERPATH}/${host}" && find . -maxdepth 5 -mindepth 5 -regex "^./pods/${pod}/release/[^.][^/]*/pod\$" |cut -d/ -f5)
}

_PRJ_GET_POD_RUNNING_RELEASES()
{
    SPACE_SIGNATURE="host pod"
    SPACE_DEP="_PRJ_GET_POD_RELEASE_STATE _PRJ_GET_POD_RELEASES"

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local versions="$(_PRJ_GET_POD_RELEASES "${host}" "${pod}")"

    for version in ${versions}; do
        local state="$(_PRJ_GET_POD_RELEASE_STATE "${host}" "${pod}" "${version}")"
        if [ "${state}" = "running" ]; then
            printf "%s\\n" "${version}"
        fi
    done
}

_PRJ_GET_POD_RELEASE_STATE()
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

_PRJ_DOES_HOST_EXIST()
{
    SPACE_SIGNATURE="hostsPath host"

    local hostsPath="${1}"
    shift

    local host="${1}"
    shift

    [ -f "${hostsPath}/${host}/host.env" ]
}

# Check so that a state is a valid state
_PRJ_ENUM_STATE()
{
    SPACE_SIGNATURE="state"

    local state="${1}"
    shift

    if [ "${state}" = "removed" ] || [ "${state}" = "running" ] || [ "${state}" = "stopped" ]; then
        return 0
    fi

    return 1
}

# List hosts who has a specific attached pod
# Only list active and inactive hosts.
_PRJ_LIST_ATTACHEMENTS()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="_PRJ_LIST_HOSTS _PRJ_IS_POD_ATTACHED"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    if [ -z "${pod}" ]; then
        return 1
    fi

    _PRJ_LIST_HOSTS "1" | {
        local host=
        while IFS='' read -r host; do
            if _PRJ_IS_POD_ATTACHED "${CLUSTERPATH}" "${host}" "${pod}"; then
                printf "%s\\n" "${host}"
            fi
        done ;
    }
}

_PRJ_IS_POD_ATTACHED()
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
_PRJ_LIST_HOSTS()
{
    SPACE_SIGNATURE="filter [showState pod]"
    SPACE_DEP="_PRJ_GET_HOST_STATE _PRJ_LIST_ATTACHEMENTS"
    SPACE_ENV="CLUSTERPATH"

    local filter="${1:-1}"
    shift

    local showState="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local pod="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local hosts=
    if [ -n "${pod}" ]; then
        hosts="$(_PRJ_LIST_ATTACHEMENTS "${pod}")"
    else
        hosts="$(cd "${CLUSTERPATH}" && find . -maxdepth 2 -mindepth 2 -type f -regex "^./[^.][^/]*/host\.env\$" |cut -d/ -f2)"

    fi

    local host=
    for host in ${hosts}; do
        local state=$(_PRJ_GET_HOST_STATE "${host}")
        if [ "${filter}" = "1" ]; then
            if [ "${state}" = "disabled" ]; then
                continue
            fi
        elif [ "${filter}" = "2" ]; then
            if [ "${state}" != "active" ]; then
                continue
            fi
        fi
        if [ "${showState}" = "true" ]; then
            printf "%s %s\\n" "${host}" "${state}"
        else
            printf "%s\\n" "${host}"
        fi
    done
}

# assigns to:
#   pod
#   version
#   host
_PRJ_SPLIT_POD_TRIPLE()
{
    SPACE_SIGNATURE="podVersionHost [noAuto]"
    SPACE_DEP="PRINT"

    local triple="${1}"
    shift

    local noAuto="${1:-}"

    host="${triple#*@}"
    if [ "${host}" = "${triple}" ]; then
        host=""
    fi

    local rest="${triple%@$host}"
    version="${rest#*:}"
    if [ "${version}" = "${rest}" ]; then
        version=""
    fi
    pod="${rest%:$version}"
    if [ -z "${version}" ] && [ "${noAuto}" != "true" ]; then
        version="latest"
    fi

    if [ -z "${pod}" ] && [ "${noAuto}" != "true" ]; then
        PRINT "Invalid pod format provided, expecting pod[:version][@host]" "error" 0
        return 1
    fi
}

_PRJ_FIND_POD_VERSION()
{
    SPACE_SIGNATURE="pod podVersion host"
    SPACE_ENV="CLUSTERPATH"

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local host="${1}"
    shift

    local dir="${CLUSTERPATH}/${host}/pods/${pod}/release"

    if [ ! -d "${dir}" ]; then
        return 1
    fi

    if [ "${podVersion}" = "latest" ]; then
        podVersion="$(cd "${dir}" && find . -maxdepth 1 -type d |cut -b3- |grep -v "-" |sort -t. -k1,1n -k2,2n -k3,3n |tail -n1)"
    fi

    if [ -z "${podVersion}" ]; then
        return 1
    fi

    if [ ! -d "${dir}/${podVersion}" ]; then
        return 1
    fi

    printf "%s\\n" "${podVersion}"
}

_PRJ_LOG_P()
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
_PRJ_LOG_C()
{
    SPACE_SIGNATURE="action"
    SPACE_ENV="CLUSTERPATH"

    local action="${1}"
    shift

    local logFile="${CLUSTERPATH}/log.txt"

    printf "%s %s %s %s\\n" "$(date +"%F %T")" "$(date +%s)" "${USER}" "${action}" >>"${logFile}"
}

# Take all frontend files to create frontends
# and all backend files to create backends,
# to produce a viable haproxy.cfg.
_PRJ_GEN_INGRESS_CONFIG2()
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
    fi

    if ! cat "${ingressTplDir}/main.conf.fragment"; then
        return 1
    fi

    # For all .frontend files,
    # sort rows on weight (first column) desc,
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
            frontendextra=" ssl crt /mnt/usercerts crt /mnt/autocerts"
        fi
        printf "\\nfrontend %s-%s\\n" "${bind}" "${protocol}"
        printf "    bind :%s%s\\n" "${bind}" "${frontendextra}"
        if ! awk '{$0="    "$0; print}' "${ingressTplDir}/frontend-${protocol}.conf.fragment"; then
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
        if ! awk '{$0="    "$0; print}' "${ingressTplDir}/backend-${mode}.conf.fragment"; then
            return 1
        fi
        while IFS='' read -r line; do
            printf "    %s\\n" "${line}"
        done < "${tmpDir}/${backend}"
    done
}

_PRJ_EXTRACT_INGRESS()
{
    SPACE_SIGNATURE="podfile tmpDir host pod version excludeClusterPorts"
    SPACE_DEP="PRINT CONF_READ FILE_ROW_PERSIST STRING_TRIM STRING_HASH STRING_ITEM_INDEXOF"

    local podfile="${1}"
    shift

    local tmpDir="${1}"
    shift

    local host="${1}"
    shift

    local pod="${1}"
    shift

    local version="${1}"
    shift

    local excludeClusterPorts="${1}"
    shift

    local ingressConf="${podfile}.ingress.conf"

    if [ ! -f "${ingressConf}" ]; then
        if [ -f "${ingressConf}.inactive" ]; then
            PRINT "Pod ${pod}:${version} has an inactive ingress. Run 'sns pod ingress ${pod}:${version} -s active' to reactive it, then regenerate ingress. If you want to." "warning" 0
        fi
        return
    fi

    # Loop through the conf file and extract each ingress block
    local out_conf_lineno=0
    while [ "${out_conf_lineno}" -gt -1 ]; do
        RULE_COUNT=$((RULE_COUNT+1))
        local ingress=
        local weight=
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
        CONF_READ "${ingressConf}" "ingress weight bind protocol clusterport host path path_end path_beg redirect_to_https redirect_location redirect_prefix errorfile"
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
            # Check if cluster port is on the RED list
            if [ "${clusterport}" -ge 64000 ]; then
                PRINT "Cluster ports (${clusterport}) from 64000 and above are forbidden to have public ingress! For pod ${podfile}" "error" 0
                return 1
            fi
            # Check if the clusterport is on the ignore list
            if STRING_ITEM_INDEXOF "${excludeClusterPorts}" "${clusterport}"; then
                PRINT "Ignoring ingress for clusterPort ${clusterport}." "warning" 0
                continue;
            fi
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
        ## path is mutuallay exclusive with path_beg and path_end (checked above),
        ## path_beg and path_end can be evaluated together in the same ACL
        local criteria=""  # Only used to group identical ingress criterias together
        local aclnames=""
        local acls=""

        ## Figure out which ACLs we will have
        if [ -n "${path}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH-${RULE_COUNT}"
        fi
        if [ -n "${path_beg}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH_BEG-${RULE_COUNT}"
        fi
        if [ -n "${path_end}" ]; then
            aclnames="${aclnames}${aclnames:+ }PATH_END-${RULE_COUNT}"
        fi
        if [ -n "${host}" ]; then
            aclnames="${aclnames}${aclnames:+ }HOST-${RULE_COUNT}"
        fi

        ## Build the matching ACL rules
        if [ -n "${path_beg}" ]; then
            path_beg="$(printf "%s\\n" "${path_beg}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path_beg"
            criteria="${criteria}{ path_beg ${path_beg}}"
            acls="acl PATH_BEG-${RULE_COUNT} path_beg ${path_beg}
"
        fi

        if [ -n "${path_end}" ]; then
            path_end="$(printf "%s\\n" "${path_end}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path_end"
            criteria="${criteria}{ path_end ${path_end}}"
            acls="${acls}acl PATH_END-${RULE_COUNT} path_end ${path_end}
"
        fi

        if [ -n "${path}" ]; then
            path="$(printf "%s\\n" "${path}" |tr ' ' '\n' |sort |tr '\n' ' ')"
            STRING_TRIM "path"
            criteria="${criteria}{ path ${path}}"
            acls="acl PATH-${RULE_COUNT} path ${path}
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
            acls="${acls}acl HOST-${RULE_COUNT} ${host1}
"
        fi
        if [ -n "${host2}" ]; then
            acls="${acls}acl HOST-${RULE_COUNT} ${host2}
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

        # Take hash on bind, protocol, criterions and weight.
        # This is to uniquely identify and group together backends which have the exact same rules and frontend.
        local hash=
        if ! STRING_HASH "${bind}-${protocol}_${type}-${weight}-${criteria}" "hash"; then
            return 1
        fi

        local backendName="${hash}"
        # Will get sorted on weight when generating config
        local frontendmatch="${weight} ${backendName}"
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

# Produce a semicolon separated string of all hosts which have ROUTERADDRESS set in their host.env
# If firstHost argument is given then always place that host's router address first in the list.
_PRJ_GET_ROUTER_HOSTS()
{
    SPACE_SIGNATURE="[firstHost]"
    SPACE_DEP="_PRJ_LIST_HOSTS STRING_TRIM"
    SPACE_ENV="CLUSTERPATH"

    local firstHost="${1:-}"

    local hosts=
    hosts="$(_PRJ_LIST_HOSTS 2)"

    if [ -n "${firstHost}" ]; then
        local newList="$(printf "%s\\n" "${hosts}" | grep -v "\<${firstHost}\>")"
        hosts="$(printf "%s\\n%s\\n" "${firstHost}" "${newList}")"
    fi

    local routerHosts=""

    local host=
    for host in ${hosts}; do
        local hostEnv="${CLUSTERPATH}/${host}/host.env"
        local varname=
        local value=
        # Extract ROUTERADDRESS variable
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
