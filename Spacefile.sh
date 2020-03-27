##
# Public entry point functions for command line and for direct space invocation.
# Functions here are wrappers to other functions.

CLUSTER_CREATE()
{
    SPACE_SIGNATURE="clusterName"
    SPACE_DEP="_PRJ_CLUSTER_CREATE"

    local clusterName="${1}"
    shift

    _PRJ_CLUSTER_CREATE "${PWD}" "${clusterName}"
}

CLUSTER_SYNC()
{
    SPACE_SIGNATURE="forceSync quite"
    SPACE_DEP="_SYNC_RUN"

    _SYNC_RUN "$@"
}

HOST_CREATE()
{
    SPACE_SIGNATURE="host [jumphost expose]"
    SPACE_DEP="_PRJ_HOST_CREATE"

    local host="${1}"
    shift

    local jumphost="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local expose="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_HOST_CREATE "${host}" "${jumpHost}" "${expose}"
}

HOST_INIT()
{
    SPACE_SIGNATURE="host [force]"
    SPACE_DEP="_PRJ_HOST_INIT"

    local host="${1}"
    shift

    local force="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_HOST_INIT "${host}" "${force}"
}

HOST_DISABLE_ROOT()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_PRJ_HOST_DISABLE_ROOT"

    local host="${1}"
    shift

    _PRJ_HOST_DISABLE_ROOT "${host}"
}

# Looging in as root, create a new super user on the host.
HOST_CREATE_SUPERUSER()
{
    SPACE_SIGNATURE="host keyfile:0"
    SPACE_DEP="_PRJ_HOST_CREATE_SUPERUSER"

    local host="${1}"
    shift

    local keyfile="${1}"
    shift

    _PRJ_HOST_CREATE_SUPERUSER "${host}" "${keyfile}"
}

# Run as superuser
HOST_SETUP()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_PRJ_HOST_SETUP"

    local host="${1}"
    shift

    _PRJ_HOST_SETUP "${host}"
}

CLUSTER_STATUS()
{
    :
    # TODO
}

LIST_PODS()
{
    SPACE_DEP="_PRJ_LIST_PODS"

    _PRJ_LIST_PODS
}

LIST_HOSTS()
{
    SPACE_SIGNATURE="[all showState]"
    SPACE_DEP="_PRJ_LIST_HOSTS"

    local all="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local showState="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local filter="1"
    if [ "${all}" = "true" ]; then
        filter="0"
    fi

    _PRJ_LIST_HOSTS "${filter}" "${showState}"
}

ATTACH_POD()
{
    SPACE_SIGNATURE="podTuple"
    SPACE_DEP="_PRJ_ATTACH_POD"

    local podTuple="${1}"
    shift

    _PRJ_ATTACH_POD "${podTuple}"
}

DETACH_POD()
{
    SPACE_SIGNATURE="podTuple"
    SPACE_DEP="_PRJ_DETACH_POD"

    local podTuple="${1}"
    shift

    _PRJ_DETACH_POD "${podTuple}"
}

CLUSTER_IMPORT_POD_CFG()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="_PRJ_CLUSTER_IMPORT_POD_CFG"

    local pod="${1}"
    shift

    _PRJ_CLUSTER_IMPORT_POD_CFG "${pod}"
}

# Compiles a pod to all hosts it is attached to.
COMPILE_POD()
{
    SPACE_SIGNATURE="podTuple [verbose expectedPodVersion]"
    SPACE_DEP="_PRJ_COMPILE_POD"

    _PRJ_COMPILE_POD "$@"
}

# Copy configs from general cluster pod config store into this version of the pod.
UPDATE_POD_CONFIG()
{
    SPACE_SIGNATURE="podTriple"
    SPACE_DEP="_PRJ_UPDATE_POD_CONFIG"

    local podTriple="${1}"
    shift

    _PRJ_UPDATE_POD_CONFIG "${podTriple}"
}

LIST_HOSTS_BY_POD()
{
    SPACE_SIGNATURE="pod"
    SPACE_DEP="_PRJ_LIST_ATTACHEMENTS"

    local pod="${1}"
    shift

    _PRJ_LIST_ATTACHEMENTS "${pod}"
}

LIST_PODS_BY_HOST()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_PRJ_LIST_PODS_BY_HOST"

    local host="${1}"
    shift

    _PRJ_LIST_PODS_BY_HOST "${host}"
}

SET_POD_INGRESS_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_SET_POD_INGRESS_STATE PRINT"

    local state="${1}"
    shift

    if [ "${state}" = "active" ] || [ "${state}" = "inactive" ]; then
        # All good, fall through
        :
    else
        PRINT "State must be active or inactive" "error" 0
        return 1
    fi

    _PRJ_SET_POD_INGRESS_STATE "${state}" "$@"
}

SIGNAL_POD()
{
    SPACE_SIGNATURE="podTriple [container]"
    SPACE_DEP="_PRJ_SIGNAL_POD"

    local podTriple="${1}"
    shift

    _PRJ_SIGNAL_POD "${podTriple}" "$@"
}

# Set the pod.version.state file
SET_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_SET_POD_RELEASE_STATE"

    local state="${1}"
    shift

    _PRJ_SET_POD_RELEASE_STATE "${state}" "$@"
}

LS_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="filterState:0 quite:0 podTriple"
    SPACE_DEP="_PRJ_LS_POD_RELEASE_STATE"

    _PRJ_LS_POD_RELEASE_STATE "$@"
}

# Return the pod.version.state file
GET_POD_RELEASE_STATES()
{
    SPACE_SIGNATURE="podTriple [quite]"
    SPACE_DEP="_PRJ_GET_POD_RELEASE_STATES"

    local podTriple="${1}"
    shift

    local quite="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_GET_POD_RELEASE_STATES "${podTriple}" "${quite}"
}

# Connect to the cluster and retrieve logs for a pod instance.
DAEMON_LOG()
{
    SPACE_SIGNATURE="[host]"
    SPACE_DEP="_PRJ_GET_DAEMON_LOG"

    _PRJ_GET_DAEMON_LOG "$@"
}

# Connect to the cluster and retrieve logs for a pod instance.
LOGS()
{
    SPACE_SIGNATURE="timestamp limit streams podTriple"
    SPACE_DEP="_PRJ_GET_POD_LOGS"

    _PRJ_GET_POD_LOGS "$@"
}

# Generate config for haproxy
GEN_INGRESS_CONFIG()
{
    SPACE_SIGNATURE="[podTuple excludeClusterPorts]"
    SPACE_DEP="_PRJ_GEN_INGRESS_CONFIG"

    _PRJ_GEN_INGRESS_CONFIG "$@"
}

SET_HOST_STATE()
{
    SPACE_SIGNATURE="state host"
    SPACE_DEP="_PRJ_SET_HOST_STATE"

    _PRJ_SET_HOST_STATE "$@"
}

GET_HOST_STATE()
{
    SPACE_SIGNATURE="host"
    SPACE_DEP="_PRJ_GET_HOST_STATE"

    _PRJ_GET_HOST_STATE "$@"
}

# Check if a specific pod version's instances are ready
GET_POD_STATUS()
{
    SPACE_SIGNATURE="readiness:0 quite:0 podTriple"
    SPACE_DEP="_PRJ_GET_POD_STATUS"

    _PRJ_GET_POD_STATUS "$@"
}

RELEASE()
{
    SPACE_DEP="_RELEASE"

    _RELEASE "$@"
}

USAGE()
{
    printf "%s\\n" "Usage:
    help
        Show this help

    version
        Show the version of snt

    create-cluster name
        Creates a cluster project with the given name in the current directory.

    sync [-f] [-q]
        Sync the cluster project in the current directory with the Cluster
        -f switch set then a force sync is performed. This is useful when performing a rollback
            or if restoring a previous branch-out.
        -q set to be more quite.

    status
        Show status of the Cluster

    import-config pod
        Import config templates from pod repo into the cluster project

    create-host host [-j jumphost] [-e expose]
        Create a host in the cluster repo by the name 'host'.
        -j jumphost is an optional host to do SSH jumps via, often used for worker machines which are not exposed directly to the public internet.
            If jumphost is set to 'local' then that dictates this host is not SSH enabled but targets local disk instead.
        -e expose can be a comma separated list of ports we want to expose to the public internet. If not provided then the host will be accessible internally only.

    init-host host
        Initialize a host to be part of the cluster and configure the Daemon to manage it's pods

    setup-host host
        Setup the host using the superuser
        Creates the regular user, installs podman, configures firewalld, etc.

    create-superuser host [-k keyfile]
        Login as root on the host and create the super user as defined in the host.env file.
        rootkeyfile is optional, of not set then password is required to login as root.

    disable-root host
        Use the super user account to disable the root login on a host

    ls-hosts [-a] [-s]
        List active and inactive hosts in this cluster project
        -a if set then also list disabled hosts
        -s if set then add a status column to the output

    ls-pods
        List all known pods in the PODPATH

    ls-hosts-by-pod pod
        List all hosts who have a given pod attached

    ls-pods-by-host host
        List all pods attached to a specific host

    attach-pod pod@host
        Attach a Pod to a host, this does not deploy anything nor release anything
        host must exist in the cluster project
        pod must exist on PODPATH

    detach-pod pod[@host]
        Remove a pod from one or all hosts

    compile pod[@host] [-v]
        Compile the current pod version to all (or one) host(s) which it is already attached to.
        If host is left out then compile on all hosts which have the pod attached.
        If -v option set then output the pod version to stdout

    update-config pod[:version][@host]
        Re-copy the pod config in the cluster to a specific pod release.
        If host is left out then copy configs to all hosts which have the pod attached.
        If version is left out the 'latest' version is searched for.

    set-pod-ingress pod[:version][@host] -s active|inactive
        Set ingress active or inactive of a specific pod version on one/all attached hosts.
        If version is left out the 'latest' version is searched for.
        If host is left out then set state for pod on all hosts which the pod is attached to.
        Multiple pods can be given on cmd line.

    set-pod-state pod[:version][@host] -s running|stopped|removed
        Set the desired state of a specific pod version on one/all attached hosts.
        If version is left out the 'latest' version is searched for.
        If host is left out then set state for pod on all hosts which the pod is attached to.
        Multiple pods can be given on cmd line.

    get-pod-state pod[:version][@host]
        Get the desired state of a specific pod version on one/all attached hosts.
        If host is left out then get state of pod for all hosts which the pod is attached to.
        If version is left out the 'latest' version is searched for.

    ls-pod-state pod[@host] [-q] [-s running|stopped|removed]
        Output the desired state for all pod version on all or just the specified host.
        -q, if set then do not output the state column
        -s, if set then filter for the provided state

    get-pod-status pod[:version][@host] [-q] [-r]
        Get the actual status of a pod (not the desired state).
        If host is left out then get status of the pod for all hosts which the pod is attached to.
        If version is left out the 'latest' version is searched for.
        -r option set means to only get the 'readiness' of the pod.
        -q option set means to not output but to return 1 if not healthy.

    generate-ingress [ingresspod[:version]] [-x excludeClusterPorts]
        Update the ingress load balancers config by looking at the ingress of all active pod instances on all hosts.
        ingressPod
            name of the ingress pod, defaults to 'ingress'.
            If version is left out the 'latest' version is searched for.
        -x excludeClusterPorts
            Comma separated string of clusterPorts to exclude from the Ingress configuration

    set-host-state host -s active|inactive|disabled

    get-host-state host
        Get the state of a host

    logs pod[:version][@host] [-t timestamp] [-l limit] [-s stdout|stderr]
        Get logs for a pod on one or all attached hosts.
        If version is left out the 'latest' version is searched for.
        If host is left out then get logs for all attached hosts.
        -t timestamp is UNIX timestamp to get from, 0 get's all.
        -l limit is the maximum number of lines to get, negative gets from bottom (newest)
        -s streams is to get stdout, stderr or both, as: -s stdout | -s stderr | -s stdout,stderr (default)

    signal pod[:version][@host] [container]
        Signal a pod on a specific host or on all attached hosts.
        Optionally specify which containers to signal, defualt is all containers in the pod.

    release pod[:version] [-p] [-m soft|hard] [-f]
        Perform the compilation and release of a new pod version.
        This operation expects there to be an Ingress Pod names 'ingress'.
        If 'version' is not provided (or set to 'latest') then compile a new version, if no new version is available quit.
        If 'version' is defined then re-release that version (which is expected have been compiled already).
        -m mode is either soft or hard. Default is hard (quickest).
        -p if set then perform 'git push' operations after each 'git commit'.
        -f if set will force sync changes to cluster

    daemon-log [host]
        Get the systemd unit daemon log
" >&2
}

VERSION()
{
    printf "%s\\n" "Simplenetes version 0.1 (GandalfVsHeman)"
}

_GETOPTS()
{
    SPACE_SIGNATURE="simpleSwitches richSwitches minPositional maxPositional [args]"
    SPACE_DEP="PRINT STRING_SUBSTR STRING_INDEXOF STRING_ESCAPE"

    local simpleSwitches="${1}"
    shift

    local richSwitches="${1}"
    shift

    local minPositional="${1:-0}"
    shift

    local maxPositional="${1:-0}"
    shift

    _out_rest=""

    local options=""
    local option=
    for option in ${richSwitches}; do
        options="${options}${option}:"
    done

    local posCount="0"
    while [ "$#" -gt 0 ]; do
        local flag="${1#-}"
        if [ "${flag}" = "${1}" ]; then
            # Non switch
            posCount="$((posCount+1))"
            if [ "${posCount}" -gt "${maxPositional}" ]; then
                PRINT "Too many positional argumets, max ${maxPositional}" "error" 0
                return 1
            fi
            _out_rest="${_out_rest}${_out_rest:+ }${1}"
            shift
            continue
        fi
        local flag2=
        STRING_SUBSTR "${flag}" 0 1 "flag2"
        if STRING_ITEM_INDEXOF "${simpleSwitches}" "${flag2}"; then
            if [ "${#flag}" -gt 1 ]; then
                PRINT "Invalid option: -${flag}" "error" 0
                return 1
            fi
            eval "_out_${flag}=\"true\""
            shift
            continue
        fi

        local OPTIND=1
        getopts ":${options}" "flag"
        case "${flag}" in
            \?)
                PRINT "Unknown option ${1-}" "error" 0
                return 1
                ;;
            :)
                PRINT "Option -${OPTARG-} requires an argument" "error" 0
                return 1
                ;;
            *)
                STRING_ESCAPE "OPTARG"
                eval "_out_${flag}=\"${OPTARG}\""
                ;;
        esac
        shift $((OPTIND-1))
    done

    if [ "${posCount}" -lt "${minPositional}" ]; then
        PRINT "Too few positional argumets, min ${minPositional}" "error" 0
        return 1
    fi
}

SNT_CMDLINE()
{
    SPACE_SIGNATURE="[action args]"
    SPACE_DEP="USAGE VERSION GET_HOST_STATE SET_HOST_STATE GEN_INGRESS_CONFIG GET_POD_RELEASE_STATES LOGS SET_POD_RELEASE_STATE UPDATE_POD_CONFIG COMPILE_POD DETACH_POD ATTACH_POD LIST_HOSTS_BY_POD LIST_PODS LIST_HOSTS HOST_SETUP HOST_CREATE_SUPERUSER HOST_DISABLE_ROOT HOST_INIT HOST_CREATE CLUSTER_IMPORT_POD_CFG CLUSTER_STATUS CLUSTER_CREATE CLUSTER_SYNC DAEMON_LOG PRINT _GETOPTS LS_POD_RELEASE_STATE SET_POD_INGRESS_STATE SIGNAL_POD RELEASE LIST_PODS_BY_HOST GET_POD_STATUS"
    # It is important that CLUSTERPATH is in front of PODPATH, because PODPATH references the former.
    SPACE_ENV="CLUSTERPATH PODPATH"

    local action="${1:-help}"
    shift $(($# > 0 ? 1 : 0))

    # TODO: check for cluster-id.txt, upwards and cd into that dir so that snt becomes more flexible in where users have their CWD atm.

    if [ "${action}" = "help" ]; then
        USAGE
    elif [ "${action}" = "version" ]; then
        VERSION
    elif [ "${action}" = "create-cluster" ]; then
        local _out_rest=
        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt create-cluster name\\n" >&2
            return 1
        fi
        CLUSTER_CREATE "${_out_rest}"
    elif [ "${action}" = "sync" ]; then
        local _out_f="false"
        local _out_q="false"

        if ! _GETOPTS "f q" "" 0 0 "$@"; then
            printf "Usage: snt sync [-f] [-q]\\n" >&2
            return 1
        fi

        CLUSTER_SYNC "${_out_f}" "${_out_q}"
    elif [ "${action}" = "status" ]; then
        if ! _GETOPTS "" "" 0 0 "$@"; then
            printf "Usage: snt status\\n" >&2
            return 1
        fi
        CLUSTER_STATUS
    elif [ "${action}" = "import-config" ]; then
        local _out_rest=
        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt import-config pod\\n" >&2
            return 1
        fi
        CLUSTER_IMPORT_POD_CFG "${_out_rest}"
    elif [ "${action}" = "create-host" ]; then
        local _out_j=
        local _out_e=
        local _out_rest=
        if ! _GETOPTS "" "j e" 1 1 "$@"; then
            printf "Usage: snt create-host host [-j jumphost] [-e expose]\\n" >&2
            return 1
        fi
        HOST_CREATE "${_out_rest}" "${_out_j}" "${_out_e}"
    elif [ "${action}" = "init-host" ]; then
        local _out_f="false"
        local _out_rest=

        if ! _GETOPTS "f" "" 1 1 "$@"; then
            printf "Usage: snt init-host host [-f]\\n" >&2
            return 1
        fi
        HOST_INIT "${_out_rest}" "${_out_f}"
    elif [ "${action}" = "setup-host" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt setup-host host\\n" >&2
            return 1
        fi
        HOST_SETUP "${_out_rest}"
    elif [ "${action}" = "create-superuser" ]; then
        local _out_k=
        local _out_rest=

        if ! _GETOPTS "" "k" 1 1 "$@"; then
            printf "Usage: snt create-superuser host [-k keyfile]\\n" >&2
            return 1
        fi
        HOST_CREATE_SUPERUSER "${_out_rest}" "${_out_k}"
    elif [ "${action}" = "disable-root" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt disable-root host\\n" >&2
            return 1
        fi
        HOST_DISABLE_ROOT "${_out_rest}"
    elif [ "${action}" = "ls-hosts" ]; then
        local _out_a="false"
        local _out_s="false"

        if ! _GETOPTS "a s" "" 0 0 "$@"; then
            printf "Usage: snt ls-hosts [-a] [-s]\\n" >&2
            return 1
        fi
        LIST_HOSTS "${_out_a}" "${_out_s}"
    elif [ "${action}" = "ls-pods" ]; then
        if ! _GETOPTS "" "" 0 0 "$@"; then
            printf "Usage: snt ls-pods\\n" >&2
            return 1
        fi
        LIST_PODS
    elif [ "${action}" = "ls-hosts-by-pod" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt ls-hosts-by-pod pod\\n" >&2
            return 1
        fi
        LIST_HOSTS_BY_POD "${_out_rest}"
    elif [ "${action}" = "ls-pods-by-host" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt ls-pods-by-host host\\n" >&2
            return 1
        fi
        LIST_PODS_BY_HOST "${_out_rest}"
    elif [ "${action}" = "attach-pod" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt attach-pod pod@host\\n" >&2
            return 1
        fi
        ATTACH_POD "${_out_rest}"
    elif [ "${action}" = "detach-pod" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt detach-pod host[@pod]\\n" >&2
            return 1
        fi
        DETACH_POD "${_out_rest}"
    elif [ "${action}" = "compile" ]; then
        local _out_v="false"
        local _out_rest=

        if ! _GETOPTS "v" "" 1 1 "$@"; then
            printf "Usage: snt compile-pod pod[@host]\\n" >&2
            return 1
        fi
        COMPILE_POD "${_out_rest}" "${_out_v}"
    elif [ "${action}" = "update-config" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt update-config pod[:version][@host]\\n" >&2
            return 1
        fi
        UPDATE_POD_CONFIG "${_out_rest}"
    elif [ "${action}" = "set-pod-ingress" ]; then
        local _out_rest=
        local _out_s=""

        if ! _GETOPTS "" "s" 1 999 "$@"; then
            printf "Usage: snt set-pod-ingress pod[:version][@host] -s active|inactive\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        SET_POD_INGRESS_STATE "${_out_s}" "$@"
    elif [ "${action}" = "set-pod-state" ]; then
        local _out_rest=
        local _out_s=""

        if ! _GETOPTS "" "s" 1 999 "$@"; then
            printf "Usage: snt set-pod-state pod[:version][@host] -s running|stopped|removed\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        SET_POD_RELEASE_STATE "${_out_s}" "$@"
    elif [ "${action}" = "get-pod-state" ]; then
        local _out_rest=
        local _out_q="false"

        if ! _GETOPTS "q" "" 1 1 "$@"; then
            printf "Usage: snt get-pod-state pod[:version][@host] [-q]\\n" >&2
            return 1
        fi
        GET_POD_RELEASE_STATES "${_out_rest}" "${_out_q}"
    elif [ "${action}" = "ls-pod-state" ]; then
        local _out_rest=
        local _out_q="false"
        local _out_s=""

        if ! _GETOPTS "q" "s" 1 1 "$@"; then
            printf "Usage: snt ls-pod-state pod[@host] [-q] [-s running|stopped|removed]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        LS_POD_RELEASE_STATE "${_out_s}" "${_out_q}" "$@"
    elif [ "${action}" = "get-pod-status" ]; then
        local _out_rest=
        local _out_q="false"
        local _out_r="false"

        if ! _GETOPTS "q r" "" 1 1 "$@"; then
            printf "Usage: snt get-pod-status pod[:version][@host] [-q] [-r]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        GET_POD_STATUS "${_out_r}" "${_out_q}" "$@"
    elif [ "${action}" = "signal" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 999 "$@"; then
            printf "Usage: snt signal pod[:version][@host] [container]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        SIGNAL_POD "$@"
    elif [ "${action}" = "logs" ]; then
        local _out_rest=
        local _out_t="0"
        local _out_l="0"
        local _out_s="stdout,stderr"

        if ! _GETOPTS "" "t l s" 1 1 "$@"; then
            printf "Usage: snt logs pod[:version][@host] [-t timestamp] [-l limit] [-s streams]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        LOGS "${_out_t}" "${_out_l}" "${_out_s}" "$@"
    elif [ "${action}" = "daemon-log" ]; then
        local _out_rest=
        if ! _GETOPTS "" "" 0 1 "$@"; then
            printf "Usage: snt daemon-log [host]\\n" >&2
            return 1
        fi
        DAEMON_LOG "${_out_rest}"
    elif [ "${action}" = "generate-ingress" ]; then
        local _out_rest=
        local _out_x=
        if ! _GETOPTS "" "x" 0 1 "$@"; then
            printf "Usage: snt generate-ingress [ingressPod[:version]] [-x excludeClusterPorts]\\n" >&2
            return 1
        fi
        GEN_INGRESS_CONFIG "${_out_rest}" "${_out_x}"
    elif [ "${action}" = "set-host-state" ]; then
        local _out_rest=
        local _out_s=""
        if ! _GETOPTS "" "s" 1 1 "$@"; then
            printf "Usage: snt set-host-state host -s active|inactive|disabled\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        SET_HOST_STATE "${_out_s}" "$@"
    elif [ "${action}" = "get-host-state" ]; then
        local _out_rest=
        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt get-host-state host\\n" >&2
            return 1
        fi
        GET_HOST_STATE "${_out_rest}"
    elif [ "${action}" = "release" ]; then
        local _out_rest=
        local _out_m="hard"
        local _out_p="false"
        local _out_f="false"

        if ! _GETOPTS "p f" "m" 1 1 "$@"; then
            printf "Usage: snt release pod[:version] [-p] [-m soft|hard] [-f]\\n" >&2
            return 1
        fi
        RELEASE "${_out_rest}" "${_out_m}" "${_out_p}" "${_out_f}"
    else
        PRINT "Unknown command" "error" 0
        return 1
    fi
}
