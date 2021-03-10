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
    SPACE_SIGNATURE="host [jumphost expose hostHome hostAddress user userKey superUser superUserKey internal routerAddress]"
    SPACE_DEP="_PRJ_HOST_CREATE"

    local host="${1}"
    shift

    local jumpHost="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local expose="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local hostHome="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local hostAddress="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local user="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local userKey="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local superUser="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local superUserKey="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local internal="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local routerAddress="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_HOST_CREATE "${host}" "${jumpHost}" "${expose}" "${hostHome}" "${hostAddress}" "${user}" "${userKey}" "${superUser}" "${superUserKey}" "${internal}" "${routerAddress}"
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

REGISTRY_CONFIG()
{
    SPACE_SIGNATURE="[host]"
    SPACE_DEP="_PRJ_REGISTRY_CONFIG"

    local host="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_REGISTRY_CONFIG "${host}"
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
    SPACE_DEP="_PRJ_GET_CLUSTER_STATUS"

    _PRJ_GET_CLUSTER_STATUS
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
    SPACE_SIGNATURE="podTuple [gitUrl]"
    SPACE_DEP="_PRJ_ATTACH_POD"

    local podTuple="${1}"
    shift

    local gitUrl="${1:-}"

    _PRJ_ATTACH_POD "${podTuple}" "${gitUrl}"
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

DELETE_POD()
{
    SPACE_SIGNATURE="podTriples"
    SPACE_DEP="_PRJ_DELETE_POD"

    _PRJ_DELETE_POD "$@"
}

RERUN_POD()
{
    SPACE_SIGNATURE="podTriple [containers]"
    SPACE_DEP="_PRJ_ACTION_POD"

    local podTriple="${1}"
    shift

    _PRJ_ACTION_POD "${podTriple}" "rerun" "$@"
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
    SPACE_SIGNATURE="timestamp limit streams details showProcessLog podTriple [containers]"
    SPACE_DEP="_PRJ_GET_POD_LOGS"

    # All options are forwarded, the first non positional argument given is expected to be the podTriple.
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

GET_POD_INFO()
{
    SPACE_SIGNATURE="podTriple"
    SPACE_DEP="_PRJ_GET_POD_INFO"

    _PRJ_GET_POD_INFO "$@"
}

RELEASE()
{
    SPACE_DEP="_RELEASE"

    _RELEASE "$@"
}

POD_SHELL()
{
    SPACE_SIGNATURE="useBash podTriple [container]"
    SPACE_DEP="_PRJ_POD_SHELL"

    local useBash="${1:-false}"
    shift

    _PRJ_POD_SHELL "${useBash}" "$@"
}

HOST_SHELL()
{
    SPACE_SIGNATURE="host [superuser useBash]"
    SPACE_DEP="_PRJ_HOST_SHELL"

    local host="${1}"
    shift

    local superUser="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local useBash="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_HOST_SHELL "${host}" "${superUser}" "${useBash}"
}

QUICKSTART()
{
    printf "%s\\n" "Quickstart:
    # Create your management dir
    mkdir mgmt-1
    cd mgmt-1

    # Pull in a pod into your management space
    mkdir pods
    cd pods
    git pull github.com/simplenetes-io/nginx-webserver webserver
    git pull github.com/simplenetes-io/ingress
    cd ..

    # Create a dev cluster for local work
    snt create-cluster dev-cluster

    cd dev-cluster
    snt create-host laptop -a local -d simplenetes/host-laptop -r localhost:32767
    snt init-host laptop

    snt attach-pod webserver@laptop
    snt attach-pod ingress@laptop

    snt compile webserver
    snt generate-ingress
    snt compile ingress

" >&2
}

USAGE()
{
    printf "%s\\n" "Usage:
    help
    -h
        Output this help

    version
    -V
        Output the version of snt

    create-cluster name
        Creates a cluster project with the given name in the current directory.
        A random integer is prefixed to the name to give the cluster its ID.
        This ID is stored in the file cluster-id.txt.

    sync [-f] [-q]
        Sync the cluster project in the current directory with the Cluster.
        -f switch set then a force sync is performed. This is useful when performing a rollback
            or if restoring a previous branch-out.
        -q set to be quite.

    status
        Output status of the Cluster.

    import-config pod
        Import config templates from pod repo into the cluster project.

    create-host host -a address [-j jumpHost -e expose -d hostHome -u username -k userkeyfile -s superusername -S superuserkeyfile -i internal -r routeraddress]
        Create a host directory in the cluster representing the host.
        Note that the physical VM should already have been created before you run this command.

        -a host IP[:PORT] (required)
            IP address of an existing host to provision as a Simplenetes cluster host.
            If PORT is provided that is the SSH port of the host. Default is 22.
            If host is set to 'local' then that dictates this host is not SSH enabled but targets local disk instead,
            which is only useful for when working with a local dev-cluster.

        -j jumphost (optional)
            The name of an already existing host to do SSH jumps via, often used for worker machines which are not exposed directly to the public internet.
            It is allowed to jump multiple times, that is using a jumphost which in its turn is also using a jumphost.

        -e expose (optional)
            Comma separated list of ports we want to expose to the public internet. If not provided then the host will be accessible internally only.
            The ports listed here are automatically exposed in the firewall when running setup-host.
            The list can later be modified in the host.env file, and snt setup-host must be run again.

        -d home directory (optional)
            Optionally specify the host's home dir on the server.
            The default is the host name.

        -u username (optional)
            If set then either the regular user already exists on the host or we just set the desired name of the regular user.

        -k keyfile (optional)
            If user is set and already exists on the host then also the keyfile needs to be set.

        -s superusername (optional)
            If there is already an existing superuser on the host it must be set here.
            Some ISPs provide a superuser instead of root access when creating a VM.
            If setting superuser then also set the superuser keyfile with -S.
            When superuser is set when creating the host then create-superuser does not need to be run.

        -S superuserkeyfile (optional)
            If superuser is set then also the keyfile can be set. If not set it defaults to 'id_rsa_super', which must be placed in the host directory.

        -i internal (optional)
            Comma separated list of networks which are considered local.
            Used for allowing hosts on the same network to connect to each other.
            The networks listed here are automatically configured in the host firewall when running setup-host.
            Default is "192.168.0.0/16,10.0.0.0/8,172.16.0.0/11"
            The list can later be modified in the host.env file, and snt setup-host must be run again.

        -r routeraddress (optional)
            The IP:PORT of the router proxy on the host.
            This address is used internally by the proxies and is is the address
            of the proxy. Usually it is \"internalIP:32767\".
            When working with a local dev-cluster with a single host set it to \"localhost:32767\" or \"127.0.0.1:32767\".

    create-superuser host [-k rootkeyfile]
        Login as root on the host and create the super user.
        rootkeyfile is optional, if not set then password is required to login as root.
        If the superuser was already set in create-host then this command will not run.
        Run this once after create-host.

    disable-root host
        Use the super user account to disable the root login on a host.
        Run this once after create-superuser.

    setup-host host
        Setup the host using the superuser.
        Creates the regular user, installs podman, configures firewalld, installs the daemon, etc.
        Run this command after create-host, create-superuser and disable-root.
        This command is idempotent and is safe to run multiple times.
        If the EXPOSE or INTERNAL variables in host.env are changed then this action need to be run again.
        This command cannot be run for "local" disk based hosts.

    init-host host [-f]
        Initialize a host to be part of the cluster by writing the cluster-id.txt file to hosthome.
        Also upload the registry-config.json file for the host. The file is searched for in the host directory then in the cluster directory.

        This command is idempotent and is safe to run multiple times.
        If the registry-config.json has beej updated then run this command again to get it uploaded to the host.
        -f of the remote host is already inited with a cluster-id.txt that needs to match the cluster ID for the host we are uploading from. However by providing the -f switch you can force change the cluster ID of the remote host.

    ls-hosts [-a] [-s]
        List active and inactive hosts in this cluster project.
        -a if set then also list disabled hosts.
        -s if set then add a status column to the output.

    ls-pods
        List all pods in the PODPATH.
        PODPATH is by default (can be overridden) set to "./_pods" of the cluster directory. However if that directory does not exist then
        PODPATH is set to "../pods" of the parent directory of the cluster.

    ls-hosts-by-pod pod
        List all hosts who have a given pod attached.
        Only provide the pod name, without any version.

    ls-pods-by-host host
        List all pods attached to a specific host.

    attach-pod pod@host [-l giturl]
        Attach a Pod to a host, this does not deploy anything nor release anything.
        Host must exist in the cluster project.
        -l  optional git url for the pod repo.
            If set the repo is cloned into PODPATH if not already existing.
            If not set then pod must already exist on PODPATH.
            If set and pod already exists then the git urls must match.

        If the pod is a git repo the git url will be set in the attachment, so when compiling
        the url is verified against the pod and if not existing the pod will be cloned.

        If this was the first attachment any pod config templates are imported into the cluster project.

    detach-pod pod[@host]
        Remove a pod from one or all hosts.

    compile pod[@host] [-v]
        Compile the current pod version to all (or one) host(s) which it is already attached to.
        If host is left out then compile on all hosts which have the pod attached.
        -v option set then output the new pod version to stdout (porcelain switch used internally).
        Pod configs stored in the cluster (_config/) will automatically be copied into the new release.

    update-config pod[:version][@host]
        Re-copy the cluster pod configs (from _config/) to a specific pod release.
        This operation is typically done when wanting to update configs of a pod but
        not release a new version of the pod (ingress pod uses this to update its routing table).
        If host is left out then copy configs to all hosts which have the pod attached.
        If version is left out the 'latest' version is searched for.

    set-pod-ingress pod[:version][@host] -s active|inactive
        Set ingress active or inactive of a specific pod release on one/all attached hosts.
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

    pod-status pod[:version][@host] [-q] [-r]
        Get the actual status of a pod (not the desired state).
        If host is left out then get status of the pod for all hosts which the pod is attached to.
        If version is left out the 'latest' version is searched for.
        -r option set means to only get the 'readiness' of the pod.
        -q option set means to not output but to return 1 if no pod ready. Only applicable if also -r flag used.

    pod-info pod[:version][@host]
        Get the static information of a pod.
        If host is left out then get status of the pod for all hosts which the pod is attached to.

    generate-ingress [ingresspod[:version]] [-x excludeClusterPorts]
        Update the ingress load balancers config by looking at the ingress of all active pod instances on all hosts.
        ingressPod
            name of the ingress pod, defaults to 'ingress'.
            If version is left out the 'latest' version is searched for.
        -x excludeClusterPorts
            Comma separated string of clusterPorts to exclude from the Ingress configuration

    set-host-state host -s active|inactive|disabled
        Updates the host's host.state file.
        active   - has ingress, internal proxy routing and are synced.
        inactive - no ingress, no internal proxy routing but are still synced.
        disabled - no ingress, no internal proxy routing and not synced. Just ignored.

    get-host-state host
        Get the state of a host

    logs pod[:version][@host] [containers] [-p] [-t timestamp] [-l limit] [-s stdout|stderr] [-d details]
        Output logs for one, many or all [containers] in a pod. If none given then show for all.
        If pod version is left out the 'latest' version is searched for.
        If pod host is left out then get logs for all attached hosts.
        -p Show pod daemon process logs (can also be used in combination with [containers])
        -t timestamp=UNIX timestamp to get logs from, defaults to 0
           If negative value is given it is seconds relative to now (now-ts).
        -s streams=[stdout|stderr|stdout,stderr], defaults to \"stdout,stderr\".
        -l limit=nr of lines to get in total from the top, negative gets from the bottom (latest).
        -d details=[ts|name|stream|none], comma separated if many.
            if \"ts\" set will show the UNIX timestamp for each row.
            if \"age\" set will show age as seconds for each row.
            if \"name\" is set will show the container name for each row.
            if \"stream\" is set will show the std stream the logs came on.
            To not show any details set to \"none\".
            Defaults to \"ts,name\".

    signal pod[:version][@host] [containers]
        Signal a pod on a specific host or on all attached hosts.
        Optionally specify which containers to signal, default is all containers in the pod.

    rerun pod[:version][@host] [containers]
        Rerun a pod or container(s) within a pod.
        Optionally specify which containers to rerun, default is the whole pod.

    delete pod[:version][@host]
        Delete pod releases which are in the \"removed\" state.
        If version is left out the 'latest' version is searched for.
        If host is left out then delete pod release version for all attached hosts.

    release pod[:version] [-p] [-m soft|hard] [-f]
        Perform the compilation and release of a new pod version.
        This operation expects there to be an Ingress Pod names 'ingress'.
        If 'version' is not provided (or set to 'latest') then compile a new version, if no new version is available quit.
        If 'version' is defined then re-release that version (which is expected have been compiled already).
        -m mode is either soft or hard. Default is hard (quickest).
        -p if set then perform 'git push' operations after each 'git commit'.
        -f if set will force sync changes to cluster

    daemon-log [host]
        Get the daemon log.
        This requires superuser privileges.

    pod-shell pod[:version][@host] [container] [-B]
        Step into a shell inside a container of a pod.
        If version is left out the 'latest' version is searched for.
        If host is left out then enter the container on each host, in sequential order.
        Optionally give the container to enter, if not set then the last container of the pod is entered (order as defined in the pod.yaml).
        -B set to force the use of bash as shell, otherwise use sh.

    host-shell host [-s] [-B]
        Step into a shell inside a specific host.
        -s option dictates if to enter as the superuser.
        -B set to force the use of bash as shell, otherwise uses sh.

    registry-config [host]
        Generate a registry-config.json file for a host or the cluster, so that podman can use that when pulling images from private registries.

        If the host argument is left out then generate a default file for the cluster, which is placed in the cluster base directory.
        This file is uploaded to the host when performing \"snt init-host <host>\" and stored as \"\$HOME/.docker/config.json\" (the command should be run whenever the file is updated).
        If no registry-config.json exists in the host dir then use the cluster default in the cluster base dir (if any).

        If you already have an existing \"config.json\" you can place that in in the cluster dir or in a host dir named as registry-config.json.

        If host it set to \"-\" then output the generated file on stdout only. This can be useful when manually appending to already existing files.

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
                PRINT "Too many positional arguments, max ${maxPositional}" "error" 0
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
        PRINT "Too few positional arguments, min ${minPositional}" "error" 0
        return 1
    fi
}

SNT_CMDLINE()
{
    SPACE_SIGNATURE="[action args]"
    SPACE_DEP="USAGE VERSION _SNT_CMDLINE FILE_REALPATH PRINT"

    if [ "${1:-help}" = "help" ]; then
        USAGE
        return
    elif [ "${1:-}" = "-h" ]; then
        USAGE
        return
    elif [ "${1:-}" = "version" ]; then
        VERSION
        return
    elif [ "${1:-}" = "-V" ]; then
        VERSION
        return
    fi

    local oldCwd="${PWD}"

    if [ "${1:-}" != "create-cluster" ]; then
        # Check for cluster-id.txt, upwards and cd into that dir so that snt becomes more flexible in where users execute it from.
        # If we are inside CLUSTERPATH, but there is no cluster-id.txt, then we can conclude that CLUSTERPATH has defaulted to $PWD, and we allow to check upward for a cluster-id.txt
        local dots="./"
        if [ ! -f "cluster-id.txt" ] && [ "${CLUSTERPATH}" = "${PWD}" ]; then
            PRINT "CLUSTERPATH not valid, searching upwards for cluster-id.txt" "debug" 0
            while true; do
                while [ "$(FILE_REALPATH "${dots}")" != "/" ]; do
                    dots="../${dots}"
                    if [ -f "${dots}/cluster-id.txt" ]; then
                        # Found it
                        CLUSTERPATH="$(FILE_REALPATH "${dots}")"
                        PRINT "Setting new CLUSTERPATH: ${CLUSTERPATH}" "debug" 0
                        break 2
                    fi
                done
                PRINT "No cluster project detected, cannot continue" "error" 0
                return 1
            done
        fi
    fi
    if [ ! -d "${PODPATH}" ]; then
        PODPATH="$(FILE_REALPATH "${CLUSTERPATH}/../pods")"
        PRINT "Setting new PODPATH: ${PODPATH}" "debug" 0
    fi

    local status=
    _SNT_CMDLINE "$@"
    status="$?"

    cd "${oldCwd}"
    return "${status}"
}

_SNT_CMDLINE()
{
    SPACE_SIGNATURE="[action args]"
    SPACE_DEP="GET_HOST_STATE SET_HOST_STATE GEN_INGRESS_CONFIG GET_POD_RELEASE_STATES LOGS SET_POD_RELEASE_STATE DELETE_POD UPDATE_POD_CONFIG COMPILE_POD DETACH_POD ATTACH_POD LIST_HOSTS_BY_POD LIST_PODS LIST_HOSTS HOST_SETUP HOST_CREATE_SUPERUSER HOST_DISABLE_ROOT HOST_INIT HOST_CREATE CLUSTER_IMPORT_POD_CFG CLUSTER_STATUS CLUSTER_CREATE CLUSTER_SYNC DAEMON_LOG PRINT _GETOPTS LS_POD_RELEASE_STATE SET_POD_INGRESS_STATE SIGNAL_POD RERUN_POD RELEASE LIST_PODS_BY_HOST GET_POD_STATUS GET_POD_INFO POD_SHELL HOST_SHELL REGISTRY_CONFIG"
    # It is important that CLUSTERPATH is in front of PODPATH, because PODPATH could reference the former.
    SPACE_ENV="CLUSTERPATH PODPATH"

    local action="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    if [ "${action}" = "create-cluster" ]; then
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
        local _out_d=
        local _out_a=
        local _out_u=
        local _out_k=
        local _out_s=
        local _out_S=
        local _out_i=
        local _out_r=
        local _out_rest=
        if ! _GETOPTS "" "j e r d a u k s S i r" 1 1 "$@"; then
            printf "Usage: snt create-host host -a address [-j jumpHost -e expose -d homedir -u username -k userkeyfile -s superusername -S superuserkeyfile -i internal -r routeraddress]\\n" >&2
            return 1
        fi
        HOST_CREATE "${_out_rest}" "${_out_j}" "${_out_e}" "${_out_d}" "${_out_a}" "${_out_u}" "${_out_k}" "${_out_s}" "${_out_S}" "${_out_i}" "${_out_r}"
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
            printf "Usage: snt create-superuser host [-k rootkeyfile]\\n" >&2
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
        local _out_l=

        if ! _GETOPTS "" "l" 1 1 "$@"; then
            printf "Usage: snt attach-pod pod@host [-l giturl]\\n" >&2
            return 1
        fi
        ATTACH_POD "${_out_rest}" "${_out_l}"
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
            printf "Usage: snt compile pod[@host] [-v]\\n" >&2
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
    elif [ "${action}" = "pod-info" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 1 "$@"; then
            printf "Usage: snt pod-info pod[:version][@host]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        GET_POD_INFO "$@"
    elif [ "${action}" = "pod-status" ]; then
        local _out_rest=
        local _out_q="false"
        local _out_r="false"

        if ! _GETOPTS "q r" "" 1 1 "$@"; then
            printf "Usage: snt pod-status pod[:version][@host] [-q] [-r]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        GET_POD_STATUS "${_out_r}" "${_out_q}" "$@"
    elif [ "${action}" = "signal" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 999 "$@"; then
            printf "Usage: snt signal pod[:version][@host] [containers]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        SIGNAL_POD "$@"
    elif [ "${action}" = "rerun" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 999 "$@"; then
            printf "Usage: snt rerun pod[:version][@host] [containers]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        RERUN_POD "$@"
    elif [ "${action}" = "delete" ]; then
        local _out_rest=

        if ! _GETOPTS "" "" 1 999 "$@"; then
            printf "Usage: snt delete pod[:version][@host]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        DELETE_POD "$@"
    elif [ "${action}" = "logs" ]; then
        local _out_rest=
        local _out_p="false"
        local _out_t=
        local _out_s=
        local _out_l=
        local _out_d=

        if ! _GETOPTS "p" "t l s d" 1 999 "$@"; then
            printf "Usage: snt logs pod[:version][@host] [containers] [-p] [-t timestamp] [-l limit] [-s streams] [-d details]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        LOGS "${_out_t}" "${_out_l}" "${_out_s}" "${_out_d}" "${_out_p}" "$@"
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
    elif [ "${action}" = "pod-shell" ]; then
        local _out_rest=
        local _out_B="false"

        if ! _GETOPTS "B" "" 1 2 "$@"; then
            printf "Usage: snt pod-shell pod[:version][@host] [container] [-B]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        POD_SHELL "${_out_B}" "$@"
    elif [ "${action}" = "host-shell" ]; then
        local _out_rest=
        local _out_s="false"
        local _out_B="false"

        if ! _GETOPTS "s B" "" 1 1 "$@"; then
            printf "Usage: snt host-shell host [-s] [-B]\\n" >&2
            return 1
        fi
        set -- ${_out_rest}
        HOST_SHELL "${1}" "${_out_s}" "${_out_B}"
    elif [ "${action}" = "registry-config" ]; then
        # We don't use _GETOPTS here because the argument '-' confuses it.
        local _out_rest=

        if [ "$#" -gt 1 ]; then
            printf "Usage: snt registry-config [host]\\n
registry-url:username:password
etc
<ctrl-d>
" >&2
            return 1
        fi
        REGISTRY_CONFIG "${1:-}"
    else
        PRINT "Unknown command" "error" 0
        return 1
    fi
}
