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
    SPACE_SIGNATURE="forceSync:0 quite:0"
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
    SPACE_SIGNATURE="host strictUserKeys:0 strictSuperUserKeys:0 [skipFirewall skipSystemd skipPodman]"
    SPACE_DEP="_PRJ_HOST_SETUP"

    _PRJ_HOST_SETUP "$@"
}

CLUSTER_STATUS()
{
    SPACE_DEP="_PRJ_GET_CLUSTER_STATUS"

    _PRJ_GET_CLUSTER_STATUS
}

LIST_HOSTS()
{
    SPACE_SIGNATURE="[all showState pod]"
    SPACE_DEP="_PRJ_LIST_HOSTS"

    local all="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local showState="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local pod="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local filter="1"
    if [ "${all}" = "true" ]; then
        filter="0"
    fi

    _PRJ_LIST_HOSTS "${filter}" "${showState}" "${pod}"
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

POD_INGRESS_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_POD_INGRESS_STATE PRINT"

    local state="${1}"
    shift

    if [ -z "${state}" ] || [ "${state}" = "active" ] || [ "${state}" = "inactive" ]; then
        # All good, fall through
        :
    else
        PRINT "State must be active, inactive or empty" "error" 0
        return 1
    fi

    _PRJ_POD_INGRESS_STATE "${state}" "$@"
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
POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="state podTriples"
    SPACE_DEP="_PRJ_SET_POD_RELEASE_STATE _PRJ_GET_POD_RELEASE_STATES"

    if [ "${1}" = "" ]; then
        shift
        _PRJ_GET_POD_RELEASE_STATES "$@"
    else
        _PRJ_SET_POD_RELEASE_STATE "$@"
    fi
}

LS_POD_RELEASE_STATE()
{
    SPACE_SIGNATURE="filterState:0 quite:0 [podTriple]"
    SPACE_DEP="_PRJ_LS_POD_RELEASE_STATE"

    _PRJ_LS_POD_RELEASE_STATE "$@"
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
    SPACE_SIGNATURE="timestamp:0 limit:0 streams:0 details:0 showProcessLog:0 podTriple [containers]"
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

HOST_STATE()
{
    SPACE_SIGNATURE="state:0 host"
    SPACE_DEP="_PRJ_SET_HOST_STATE _PRJ_GET_HOST_STATE"

    if [ "${1}" = "" ]; then
        shift
        _PRJ_GET_HOST_STATE "$@"
    else
        _PRJ_SET_HOST_STATE "$@"
    fi
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
    SPACE_SIGNATURE="useBash container podTriple [commands]"
    SPACE_DEP="_PRJ_POD_SHELL"

    _PRJ_POD_SHELL "$@"
}

HOST_SHELL()
{
    SPACE_SIGNATURE="host [superuser useBash commands]"
    SPACE_DEP="_PRJ_HOST_SHELL"

    local host="${1}"
    shift

    local superUser="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    local useBash="${1:-false}"
    shift $(($# > 0 ? 1 : 0))

    _PRJ_HOST_SHELL "${host}" "${superUser}" "${useBash}" "$@"
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
    sns create-cluster dev-cluster

    cd dev-cluster
    sns create-host laptop -a local -d simplenetes/host-laptop -r localhost:32767
    sns init-host laptop

    sns attach-pod webserver@laptop
    sns attach-pod ingress@laptop

    sns compile webserver
    sns generate-ingress
    sns compile ingress

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
    Output the version of Simplenetes

sns CONTEXT COMMAND [OBJECT] [OPTIONS] [ARGUMENTS]

Cluster commands:
  cluster create <cluster name>
    Creates a cluster project with the given name in the current directory.
    A random integer is prefixed to the name to give the cluster its ID.
    This ID is stored in the file cluster-id.txt.

  cluster ps
    Output the current status of the cluster.

  cluster sync
    Sync this cluster project to the remote network.

    -f, --force
        Force the sync in case the commit chain does not match.
        This is useful when performing a rollback or if restoring a previous branch-out.

    -q, --quite
        Set to be quite.

  cluster importconfig <pod>
    Import config templates from the pod source repo into the cluster project.

  cluster geningress [<ingressPod>]
    Update the ingress load balancers config by looking at the ingress of all active pod instances on all hosts.

    ingressPod
        name of the ingress pod to generate configs for, defaults to 'ingress'.

    -x, --exclude-cluster-ports=excludeClusterPorts
        Comma separated string of clusterPorts to exclude from the Ingress configuration.

  cluster registry [<host>|-]
    Generate a Docker standard config.json file from data read on stdin.
    This file can be used by Podman on the host to authorize to private image registries.
    This file is stored as registry-config.json either in the cluster dir or in a specific host dir if the host name is provided as argument.
    The file is synced to the host when running 'host setup init', and stored as '~./docker/config.json'.
    If you already have an existing Docker 'config.json' file you can place that in in
    the cluster dir or in a host dir named as registry-config.json.

    If host is set to '-' then output to stdout instead of writing to disk.
    This can be useful when manually appending to already existing files.

    stdin
        Pass data on stdin as (multiple lines allowed):
        registry-url:username:password\\n


Host commands:
  host register <host>
    Register an existing host as part of this cluster.
    Note that the physical VM should already have been created prior to running this command.

    -a, --address=address (required)
        IP[:sshPort] of an existing host.
        sshPort defaults to 22.
        If address is set to 'local' then that dictates this host is not SSH enabled but targets local disk instead,
        which is only useful for when working with a local dev-cluster.

    -j, --jump-host=jumpHost
        Name of already registered host to use as jumphost.
        The name of an already existing host to do SSH jumps via,
        often used for worker machines which are not exposed directly to the public internet.
        It is allowed to jump through multiple hosts.

    -e, --expose=ports
        Comma separated list of ports we want to expose to the public internet.
        If not provided then the host will be accessible internally only.
        The ports listed here are automatically exposed in the firewall when setting up firewall.
        If this list is modified in the host.env file then the setup firewall command must be rerun.

    -d, --dir-home=hostHome
        Directory on host to sync files to.
        The default is the host name.

    -u, --user-name=username
        If set then either the regular user already exists on the host or we set the desired name of the regular user.

    -k, --key-file=userkeyfile (required if --user-name is set)
        If user is set and already exists on the host then also the keyfile needs to be provided.

    -s, --super-user-name=superusername
        If there is already an existing superuser on the host it must be set here.
        Some ISPs provide a superuser instead of root access when creating a VM.
        If setting superuser then also set the superuser keyfile with -S.
        If superuser is set when registering the host then the create superuser command needs not to be run.

    -S, --super-user-key-file=superuserkeyfile (recommended if --super-user-name is set)
        If the super user is set then also the keyfile can be set.
        If not set it defaults to 'id_rsa_super', which must be placed in the host directory.

    -i, --internal-networks=networks
        Comma separated list of networks which are considered internal.
        Used for allowing hosts on the same network to connect to each other.
        The networks listed here are automatically configured in the host when setting up the firewall.
        Default is "192.168.0.0/16,10.0.0.0/8,172.16.0.0/11"
        The list can later be modified in the host.env file and then rerun the setup firewall command.

    -r, --router-address=routeraddress
        The LocalIP:PORT of the router proxy on the host we are registering.
        This address is aggregated into a list which is used internally by all the proxies in the cluster.
        It should be set to 'internalIP:32767'.
        When working with a local dev-cluster with a single host set it to 'localhost:32767' or '127.0.0.1:32767'.

  host setup superuser <host>
    Login as root on the host and create the super user.
    If the superuser was already set when registering the host then this command will not run.
    Run this once after 'host register'.

    -k, --key-file=rootkeyfile
        rootkeyfile is optional, if not set then password is required to login as root.

  host setup disableroot <host>
    Use the super user account to disable the root login on the host.
    Run this once after host supet superuser.

  host setup install <host>
    Use the superuser account to setup the regular user, configure the firewall and install
    the simplenetesd systemd service.
    Run this command after setup superuser and disableroot.
    This command is idempotent and is safe to run multiple times.
    If the EXPOSE or INTERNAL variables in host.env are changed then this action need to be run again.
    Public keys ('pubkeys/\*.pub') are set in the authorized_keys file on the remote host. Also the current pub key from host.env is added.
    Public keys ('pubkeys.superuser/\*.pub') are added to the authorized_keys file on the remote host for the super user. Also the current pub key from host-superuser.env is added.
    This command cannot be run for "local" disk based hosts.
    Note that superuser must have password free access to the sudo command.

    --skip-firewall
        Do not make any changes to the firewall

    --skip-systemd
        Do not (re-)install the simplenetesd systemd unit.
        Note that this option will not remove the unit, just not install it.

    --skip-podman
        Do not install and configure podman.

    --strict-user-keys
        Only allow public keys put in the host's 'pubkeys' directory to connect to the host as regular user.
        Without this option also the current key referenced from host.env is also added.
        Use this option to remove your own user from the authorized_keys file on the remote host.

    --strict-super-user-keys
        Only allow public keys put in the host's 'pubkeys.superuser' directory to connect to the host as the super user.
        Without this option also the current key referenced from host-superuser.env is also added.
        Use this option to remove your own super user from the authorized_keys file on the remote host.

  host init <host>
    Initialize a host to be part of the cluster by writing the cluster-id.txt file to
    the host home directory.
    Also upload the registry-config.json file to the host, which is the Docker config.json
    file used to connect to to private image registries.
    The json file is searched for in the host directory first, and then in the cluster directory.

    Run this command at least once after setup install.
    This command is idempotent and is safe to run multiple times.
    If the registry-config.json has been updated then run this command again to get it uploaded to the host.

    -f, --force
        Force a change of the cluster-id.txt. (ps. this can break things).

  host ls
    List active and inactive hosts in this cluster project.

    -p, --pod=pod
        Filter on hosts who have a specific pod attached.

    -a, --all
        If set then also list disabled hosts.

    -s, --state
        If set then add a host state column to the output.

  host attach <pod@host>
    Attach a Pod to a host, this does not deploy anything nor release anything.
    Host must exist in the cluster project.
    Pod must exist on PODPATH, unless --link is provided.

    -l, --link  optional git url for the pod repo.
        If set the repo is cloned into PODPATH if not already existing.
        If not set then pod must already exist on PODPATH.
        If set and pod already exists then the git urls must match.

    If the pod is a git repo the git url will be set in the attachment, so when compiling
    the url is verified against the pod and if not existing the pod will be cloned.

    If this was the first attachment any pod config templates are imported into the cluster project.

  host detach <pod[@host]>
    Remove a pod from one or all hosts.

  host state <host>
    Get or set state of a host.

    -s, --state=active|inactive|disabled
        If option provided then set the state in the host.state file.
        active   - has ingress, internal proxy routing and is synced.
        inactive - no ingress, no incoming internal proxy routing but is still synced.
                   Pods can still be attached, compiled and released, but will not get any incoming traffic.
                   Use this to phase out a host but let it finish it's current sockets.
        disabled - no ingress, no incoming internal proxy routing and is not synced. Just ignored.

  host logs <host>
    Get the simplenetes systemd daemon logs for one or all hosts.
    This requires superuser privileges.

  host shell <host> [-- <commands>]
    Enter an interactive shell on the given host as tne normal user.

    -s, --super-user
        If set then enter as the superuser.

    -b, --bash
        Set to force the use of bash as shell, otherwise use sh.

    <commands>
        Commands are optional and will be run instead of entering the interactive shell.
        Commands must be places after any option switches and after a pair of dashes '--', so that arguments are not parsed by sns.


Pod commands:
  pod ls [[pod[:version]][@host]]
    List pod releases in the cluster.
    Optionally provide the pod and/or host to filter by.
    If pod is provided without version then all versions are considered. If version is set to 'latest' then only latest releases are considered.

    -s, --state=running|stopped|removed|all
        Filter for pod state. Default is 'running'.

    -q, --quite
        Hide the state column.
        This can be useful when feeding the output into another command and just wanting the pod.

  pod compile <pod[@host]>
    Compile the current pod version to all (or one) host(s) which it is already attached to.
    If host is left out then compile on all hosts which have the pod attached.
    Pod configs stored in the cluster (./_config/) will automatically be copied into the new release.

    -v
        If option set then output the new pod version to stdout.
        This is a porcelain switch used internally.

  pod updateconfig <pod[:version][@host]>
    Re-copy the cluster pod configs (from ./_config/) to a specific pod release.
    This operation is useful when wanting to update configs of an already released pod.
    If host is left out then copy configs to the pod on all attached hosts.
    If version is left out the 'latest' version is searched for.

  pod ingress <pod[:version][@host]>
    Get or set the ingress active or inactive state of a specific pod release on one or all attached hosts.
    If version is left out the 'latest' version is searched for.
    If host is left out then set ingress for pod on all hosts which the pod is attached to.
    Note that the ingress needs to be regenerated and the ingress pod updated for the changes to take effect.
    Multiple pods can be given on cmd line.

    -s, --state=active|inactive
        Set the pod(s) ingress state.
        If this option is not set then get the state instead of setting it.

  pod state <pod[:version][@host]>
    Get or set the desired state of a specific pod version on one or all attached hosts.
    If version is left out the 'latest' version is searched for on each host.
    If host is left out then search all hosts.
    Multiple pods can be given as arguments.
    The cluster needs to be synced for any changes to take effect.

    -s, --state=running|stopped|removed
        Set the pod(s) state.
        If this option is not set then get the state instead of setting it.

  pod ps <pod[:version][@host]>
    Get the live status of a pod from the cluster.
    If host is left out then get status of the pod for all hosts which the pod is attached to.
    If version is left out the 'latest' version is searched for.

    -r, --readiness
        If option set it means to only get the 'readiness' of the pod.

    -q, --quite
        If option set it means to not output but to exit with code 1 if no pod ready.
        Only applicable if also --readiness flag used.

  pod info <pod[:version][@host]>
    Get static information on a pod.
    If host is left out then get info of the pod for all hosts which the pod is attached to.
    If version is left out the 'latest' version is searched for.

  pod logs <pod[:version][@host]> [containers]
    Output pod logs.
    If pod version is left out the 'latest' version is searched for.
    If pod host is left out then get pod logs for each attached host.

    [containers] can be set to show logs for one or many specific containers. Space separated.

    -p, --daemon-process
        Show pod daemon process logs (can also be used in combination with [containers])

    -t, --timestamp=UNIX timestamp
        Time to get logs from, defaults to 0.
        If a negative value is given it is seconds relative to now (now-ts).

    -s, --stream=stdout|stderr|stdout,stderr
        What streams to output.
        Defaults to 'stdout,stderr'

    -l, --limit=lines
        Nr of lines to get in total from the top, negative gets from the bottom (latest).

    -d, --details=ts|name|stream|none
        Comma separated if many arguments.
        if 'ts' set will show the UNIX timestamp for each row.
        if 'age' set will show relative age as seconds for each row.
        if 'name' is set will show the container name for each row.
        if 'stream' is set will show the std stream the logs came on.
        To not show any details set to 'none'.
        Defaults to 'ts,name'.

  pod signal <pod[:version][@host]> [containers]
    Signal a pod on a specific host or on all attached hosts.
    If pod version is left out the 'latest' version is searched for.
    If pod host is left out then get pod logs for each attached host.
    Optionally specify which containers to signal, default is all containers in the pod.

  pod rerun <pod[:version][@host]> [containers]
    Rerun a pod on a specific host or on all attached hosts.
    If pod version is left out the 'latest' version is searched for.
    If pod host is left out then rerun for each attached host.
    Optionally specify which containers to rerun, default is to rerun the whole pod.

  pod release <pod[:version]>
    Perform the compilation and release of a new pod version.
    If 'version' is not provided (or set to 'latest') then compile a new version, if no new version is available quit.
    If 'version' is set then re-release that version (which is expected have been compiled already).
    This operation expects there to be an Ingress Pod named 'ingress' in the cluster.
    A release generates multiple commits in the cluster repo as it proceeds through the stages.

    -m, --mode=soft|hard|safe
        soft - no downtime, have versions briefly exist concurrently (default mode).
        hard - stop old version and start new version in same transaction.
               Quick to sync but can give a small glitch in the uptime.
        safe - Use this for database pods which access specific files and where
               we absolutely do not want them concurrently accessing the same files.
               This mode waits until the old version is shutdown before starting the new version.

    -p, --push
        If set then perform 'git push' operations after each 'git commit'.
        This can be desirable when running in a CI/CD environment and we want to resume an aborted release.

    -f, --force
        If set will force sync changes to cluster even if the commit chain differs.
        Use this for rollbacks, or when restoring from a branch-out.

  pod shell <pod[:version][@host]> [-- <commands>]
    Step into a shell inside a container of a pod.
    If version is left out the 'latest' version is searched for.
    If host is left out then enter the container on each host, in sequential order.

    <commands>
        Commands are optional and will be run instead of entering the interactive shell.
        Commands must be places after any option switches and after a pair of dashes '--', so that arguments are not parsed by sns.

    -c, --container=name
        If set then enter the given container.
        Default is the last container in the pod specification.

    -b, --bash
        Set to force the use of bash as shell, otherwise use sh.

  pod delete pod[:version][@host]
    Delete pod releases which are in the 'removed' state.
    If version is left out the 'latest' version is searched for.
    If host is left out then delete the pod release version on all attached hosts, as long
    as they are in the 'removed' state.
    Multiple pods can be provided as arguments.
"
}

VERSION()
{
    printf "%s\\n" "Simplenetes 0.3.1"
}

# options are on the format:
# "_out_all=-a,--all/ _out_state=-s,--state/arg1|arg2|arg3"
# For non argument options the variable will be increased by 1 for each occurrence.
# The variable _out_arguments is reserved for positional arguments.
# Expects _out_arguments and all _out_* to be defined.
_GETOPTS()
{
    SPACE_SIGNATURE="options minPositional maxPositional [args]"
    SPACE_DEP="_GETOPTS_SWITCH PRINT STRING_SUBSTR STRING_INDEXOF STRING_ESCAPE"

    local options="${1}"
    shift

    local minPositional="${1:-0}"
    shift

    local maxPositional="${1:-0}"
    shift

    _out_arguments=""
    local posCount="0"
    local skipOptions="false"
    while [ "$#" -gt 0 ]; do
        local option=
        local value=
        local _out_VARNAME=
        local _out_ARGUMENTS=

        if [ "${skipOptions}" = "false" ] && [ "${1}" = "--" ]; then
            skipOptions="true"
            shift
            continue
        fi

        if [ "${skipOptions}" = "false" ] && [ "${1#--}" != "${1}" ]; then # Check if it is a double dash GNU option
            local l=
            STRING_INDEXOF "=" "${1}" "l"
            if [ "$?" -eq 0 ]; then
                STRING_SUBSTR "${1}" 0 "${l}" "option"
                STRING_SUBSTR "${1}" "$((l+1))" "" "value"
            else
                option="${1}"
            fi
            shift
            # Fill _out_VARNAME and _out_ARGUMENTS
            _GETOPTS_SWITCH "${options}" "${option}"
            # Fall through to handle option
        elif [ "${skipOptions}" = "false" ] && [ "${1#-}" != "${1}" ] && [ "${#1}" -gt 1 ]; then # Check single dash OG-style option
            option="${1}"
            shift
            if [ "${#option}" -gt 2 ]; then
                PRINT "Invalid option '${option}'" "error" 0
                return 1
            fi
            # Fill _out_VARNAME and _out_ARGUMENTS
            _GETOPTS_SWITCH "${options}" "${option}"
            # Do we expect a value to the option? If so take it and shift it out
            if [ -n "${_out_ARGUMENTS}" ]; then
                if [ "$#" -gt 0 ]; then
                    value="${1}"
                    shift
                fi
            fi
            # Fall through to handle option
        else
            # Positional args
            posCount="$((posCount+1))"
            if [ "${posCount}" -gt "${maxPositional}" ]; then
                PRINT "Too many arguments. Max ${maxPositional} argument(s) allowed." "error" 0
                return 1
            fi
            _out_arguments="${_out_arguments}${_out_arguments:+ }${1}"
            shift
            continue
        fi

        # Handle option argument
        if [ -z "${_out_VARNAME}" ]; then
            PRINT "Unrecognized option: '${option}'" "error" 0
            return 1
        fi

        if [ -n "${_out_ARGUMENTS}" ] && [ -z "${value}" ]; then
            # If we are expecting a option arguments but none was provided.
            STRING_SUBST "_out_ARGUMENTS" " " ", " 1
            PRINT "Option ${option} is expecting an argument like: ${_out_ARGUMENTS}" "error" 0
            return 1
        elif [ -z "${_out_ARGUMENTS}" ] && [ -z "${value}" ]; then
            # This was a simple option without argument, increase counter of occurrences
            eval "value=\"\$${_out_VARNAME}\""
            if [ -z "${value}" ]; then
                value=0
            fi
            value="$((value+1))"
        elif [ "${_out_ARGUMENTS}" = "*" ] || STRING_ITEM_INDEXOF "${_out_ARGUMENTS}" "${value}"; then
            # Value is OK, fall through
            :
        else
            # Invalid argument
            if [ -z "${_out_ARGUMENTS}" ]; then
                PRINT "Option ${option} does not take any arguments" "error" 0
            else
                PRINT "Invalid ${option} argument '${value}'. Valid arguments are: ${_out_ARGUMENTS}" "error" 0
            fi
            return 1
        fi

        # Store arguments in variable
        STRING_ESCAPE "value"
        eval "${_out_VARNAME}=\"\${value}\""
    done

    if [ "${posCount}" -lt "${minPositional}" ]; then
        PRINT "Too few arguments provided. Minimum ${minPositional} argument(s) required." "error" 0
        return 1
    fi
}

# Find a match in options and fill _out_VARNAME and _out_ARGUMENTS
_GETOPTS_SWITCH()
{
    SPACE_SIGNATURE="options option"
    SPACE_DEP="STRING_SUBST STRING_ITEM_INDEXOF STRING_ITEM_GET STRING_ITEM_COUNT"

    local options="${1}"
    shift

    local option="${1}"
    shift

    local varname=
    local arguments=

    local count=0
    local index=0
    STRING_ITEM_COUNT "${options}" "count"
    while [ "${index}" -lt "${count}" ]; do
        local item=
        STRING_ITEM_GET "${options}" ${index} "item"
        varname="${item%%=*}"
        arguments="${item#*/}"
        local allSwitches="${item#*=}"
        allSwitches="${allSwitches%%/*}"
        STRING_SUBST "allSwitches" "," " " 1
        if STRING_ITEM_INDEXOF "${allSwitches}" "${option}"; then
            STRING_SUBST "arguments" "|" " " 1
            _out_VARNAME="${varname}"
            _out_ARGUMENTS="${arguments}"
            return 0
        fi
        index=$((index+1))
    done

    # No such option found
    return 1
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

    if [ "${1:-}" = "cluster" ] && [ "${2:-}" = "create" ]; then
        # When creating a cluster we skip the check about finding the correct working dir.
        :
    else
        # Check for cluster-id.txt, upwards and cd into that dir so that sns becomes more flexible in where users execute it from.
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
                PRINT "No cluster project detected, cannot continue. Type 'sns help' for list of commands." "error" 0
                return 1
            done
        fi
    fi

    if [ -z "${PODPATH}" ]; then
        PODPATH="$(FILE_REALPATH "${CLUSTERPATH}/_pods")"
        PRINT "Setting PODPATH: ${PODPATH}" "debug" 0
    else
        mkdir -p "${PODPATH}"
    fi

    if [ ! -d "${PODPATH}" ]; then
        PODPATH="$(FILE_REALPATH "${CLUSTERPATH}/../pods")"
        mkdir -p "${PODPATH}"
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
    SPACE_SIGNATURE="[context command object options args]"
    SPACE_DEP="HOST_STATE GEN_INGRESS_CONFIG LOGS POD_RELEASE_STATE DELETE_POD UPDATE_POD_CONFIG COMPILE_POD DETACH_POD ATTACH_POD LIST_HOSTS HOST_SETUP HOST_CREATE_SUPERUSER HOST_DISABLE_ROOT HOST_INIT HOST_CREATE CLUSTER_IMPORT_POD_CFG CLUSTER_STATUS CLUSTER_CREATE CLUSTER_SYNC DAEMON_LOG PRINT _GETOPTS LS_POD_RELEASE_STATE POD_INGRESS_STATE SIGNAL_POD RERUN_POD RELEASE GET_POD_STATUS GET_POD_INFO POD_SHELL HOST_SHELL REGISTRY_CONFIG"
    # It is important that CLUSTERPATH is in front of PODPATH, because PODPATH could reference the former.
    SPACE_ENV="CLUSTERPATH PODPATH"

    local context="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    local command="${1:-}"
    shift $(($# > 0 ? 1 : 0))

    if [ "${context}" = "cluster" ]; then
        if [ "${command}" = "create" ]; then
            local _out_arguments=
            if ! _GETOPTS "" 1 1 "$@"; then
                printf "Usage: sns create cluster <cluster name>\\n" >&2
                return 1
            fi
            CLUSTER_CREATE "${_out_arguments}"
        elif [ "${command}" = "ps" ]; then
            if ! _GETOPTS "" 0 0 "$@"; then
                printf "Usage: sns cluster ps\\n" >&2
                return 1
            fi
            CLUSTER_STATUS
        elif [ "${command}" = "sync" ]; then
            local _out_force=
            local _out_quite=
            if ! _GETOPTS "_out_force=-f,--force/ _out_quite=-q,--quite/" 0 0 "$@"; then
                printf "Usage: sns cluster sync [-f|--force] [-q|--quite]\\n" >&2
                return 1
            fi
            CLUSTER_SYNC "${_out_force:+true}" "${_out_quite:+true}"
        elif [ "${command}" = "importconfig" ]; then
            local _out_arguments=
            if ! _GETOPTS "" 1 1 "$@"; then
                printf "Usage: sns cluster importconfig <pod>\\n" >&2
                return 1
            fi
            CLUSTER_IMPORT_POD_CFG "${_out_arguments}"
        elif [ "${command}" = "geningress" ]; then
            local _out_arguments=
            local _out_exclude=
            if ! _GETOPTS "_out_exclude=-x,--exclude-cluster-ports/*" 0 1 "$@"; then
                printf "Usage: sns cluster geningress [ingressPod] [-x|--exclude-cluster-ports=]\\n" >&2
                return 1
            fi
            GEN_INGRESS_CONFIG "${_out_arguments}" "${_out_exclude}"
        elif [ "${command}" = "registry" ]; then
            local _out_arguments=

            if [ "$#" -gt 1 ]; then
                printf "Usage: sns cluster registry [<host>|-]\\n
registry-url:username:password
etc
<ctrl-d>
" >&2
                return 1
            fi
            REGISTRY_CONFIG "${1:-}"
        else
            PRINT "Unknown cluster command '${command}'" "error" 0
            return 1
        fi
    elif [ "${context}" = "host" ]; then
        if [ "${command}" = "register" ]; then
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
            local _out_arguments=

            if ! _GETOPTS "_out_j=-j,--jump-host/* _out_e=-e,--expose/* _out_r=-r,--router-address/* _out_d=-d,--dir-home/* _out_a=-a,--address/* _out_u=-u,--user-name/* _out_k=-k,--key-file/* _out_s=-s,--super-user-name/* _out_S=-S,--super-user-name/* _out_i=-i,--internal-networks/* _out_r=-r,--router-address/*" 1 1 "$@"; then

                printf "Usage: sns host register -a|--address= [-j|--jump-host= -e|--expose= -d|--dir-home= -u|--user-name= -k|--key-file= -s|--super-user-name= -S|--super-use-key-file= -i|--internal-networks= -r|--router-address=]\\n" >&2
                return 1
            fi
            HOST_CREATE "${_out_arguments}" "${_out_j}" "${_out_e}" "${_out_d}" "${_out_a}" "${_out_u}" "${_out_k}" "${_out_s}" "${_out_S}" "${_out_i}" "${_out_r}"
        elif [ "${command}" = "setup" ]; then
            local object="${1:-}"
            shift $(($# > 0 ? 1 : 0))

            if [ "${object}" = "superuser" ]; then
                local _out_k=
                local _out_arguments=

                if ! _GETOPTS "_out_k=-k,--key-file/*" 1 1 "$@"; then
                    printf "Usage: sns host setup superuser <host> [-k|--key-file=]\\n" >&2
                    return 1
                fi
                HOST_CREATE_SUPERUSER "${_out_arguments}" "${_out_k}"
            elif [ "${object}" = "disableroot" ]; then
                local _out_arguments=

                if ! _GETOPTS "" 1 1 "$@"; then
                    printf "Usage: sns host setup disableroot <host>\\n" >&2
                    return 1
                fi
                HOST_DISABLE_ROOT "${_out_arguments}"
            elif [ "${object}" = "install" ]; then
                local _out_strictUserKeys=
                local _out_strictSuperUserKeys=
                local _out_skip_firewall=
                local _out_skip_systemd=
                local _out_skip_podman=
                local _out_arguments=

                if ! _GETOPTS "_out_strictUserKeys=--strict-user-keys/ _out_strictSuperUserKeys=--strict-super-user-keys/ _out_skip_firewall=--skip-firewall/ _out_skip_systemd=--skip-systemd/ _out_skip_podman=--skip-podman/" 1 1 "$@"; then
                    printf "Usage: sns host setup install <host> [--skip-firewall] [--skip-systemd] [--skip-podman] [--strict-user-keys] [--strict-super-user-keys]\\n" >&2
                    return 1
                fi
                HOST_SETUP "${_out_arguments}" "${_out_strictUserKeys:+false}" "${_out_strictSuperUserKeys:+false}" "${_out_skip_firewall:+true}" "${_out_skip_systemd:+true}" "${_out_skip_podman:+true}"
            else
                PRINT "Unknown host setup object '${object}'" "error" 0
                return 1
            fi
        elif [ "${command}" = "init" ]; then
            local _out_f=
            local _out_arguments=

            if ! _GETOPTS "_out_f=-f,--force/" 1 1 "$@"; then
                printf "Usage: sns host init <host> [-f|--force]\\n" >&2
                return 1
            fi
            HOST_INIT "${_out_arguments}" "${_out_f:+true}"
        elif [ "${command}" = "ls" ]; then
            local _out_a=
            local _out_s=
            local _out_p=

            if ! _GETOPTS "_out_a=-a,--all/ _out_s=-s,--state/ _out_p=-p,--pod/*" 0 0 "$@"; then
                printf "Usage: sns host ls [-a|--all] [[-s|--state] [-p|--pod=]\\n" >&2
                return 1
            fi
            LIST_HOSTS "${_out_a:+true}" "${_out_s:+true}" "${_out_p}"
        elif [ "${command}" = "attach" ]; then
            local _out_l=
            local _out_arguments=

            if ! _GETOPTS "_out_l=-l,--link/*" 1 1 "$@"; then
                printf "Usage: sns host attach pod@host [-l|--link giturl]\\n" >&2
                return 1
            fi
            ATTACH_POD "${_out_arguments}" "${_out_l}"
        elif [ "${command}" = "detach" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 1 "$@"; then
                printf "Usage: sns host detach pod[@host]\\n" >&2
                return 1
            fi
            DETACH_POD "${_out_arguments}"
        elif [ "${command}" = "state" ]; then
            local _out_s=
            local _out_arguments=

            if ! _GETOPTS "_out_s=-s,--state/*" 1 1 "$@"; then
                printf "Usage: sns host state <host> [-s|--state=active|inactive|disabled]\\n" >&2
                return 1
            fi
            HOST_STATE "${_out_s}" "${_out_arguments}"
        elif [ "${command}" = "logs" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 0 1 "$@"; then
                printf "Usage: sns host logs [<host>]\\n" >&2
                return 1
            fi
            DAEMON_LOG "${_out_arguments}"
        elif [ "${command}" = "shell" ]; then
            local _out_arguments=
            local _out_s=
            local _out_b=

            if ! _GETOPTS "_out_s=-s,--super-user/ _out_b=-b,--bash/" 1 99999 "$@"; then
                printf "Usage: sns host shell <host> [-s|--super-user] [-b|--bash] -- [<commands>]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            local host="${1}"
            shift
            HOST_SHELL "${host}" "${_out_s:+true}" "${_out_b:+true}" "$@"
        else
            PRINT "Unknown host command '${command}'" "error" 0
            return 1
        fi
    elif [ "${context}" = "pod" ]; then
        if [ "${command}" = "ls" ]; then
            local _out_arguments=
            local _out_s=
            local _out_q=

            if ! _GETOPTS "_out_s=-s,--state/running|stopped|removed|all _out_q=-q,--quite/" 0 1 "$@"; then
                printf "Usage: sns pod ls <[pod[:version]][@host] [-s|--state=running|stopped|removed|all] [-q|--quite]\\n" >&2
                return 1
            fi

            if [ "${_out_s}" = "all" ]; then
                _out_s=""
            fi

            LS_POD_RELEASE_STATE "${_out_s}" "${_out_q:+true}" "${_out_arguments}"
        elif [ "${command}" = "compile" ]; then
            local _out_v=
            local _out_arguments=

            if ! _GETOPTS "_out_v=-v/" 1 1 "$@"; then
                printf "Usage: sns pod compile <pod[@host]> [-v]\\n" >&2
                return 1
            fi
            COMPILE_POD "${_out_arguments}" "${_out_v:+true}"
        elif [ "${command}" = "updateconfig" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 1 "$@"; then
                printf "Usage: sns pod updateconfig pod[:version][@host]\\n" >&2
                return 1
            fi
            UPDATE_POD_CONFIG "${_out_arguments}"
        elif [ "${command}" = "ingress" ]; then
            local _out_arguments=
            local _out_s=

            if ! _GETOPTS "_out_s=-s,--state/active|inactive" 1 999 "$@"; then
                printf "Usage: sns pod ingress pod[:version][@host] -s|--state=active|inactive\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            POD_INGRESS_STATE "${_out_s}" "$@"
        elif [ "${command}" = "state" ]; then
            local _out_arguments=
            local _out_s=

            if ! _GETOPTS "_out_s=-s,--state/running|stopped|removed" 1 999 "$@"; then
                printf "Usage: sns pod state pod[:version][@host] [-s|--state=running|stopped|removed]\\n" >&2
                return 1
            fi

            set -- ${_out_arguments}
            POD_RELEASE_STATE "${_out_s}" "$@"
        elif [ "${command}" = "ps" ]; then
            local _out_arguments=
            local _out_q=
            local _out_r=

            if ! _GETOPTS "_out_q=-q,--quite/ _out_r=-r,--readiness/" 1 1 "$@"; then
                printf "Usage: sns pod ps pod[:version][@host] [-q|--quite] [-r|--readiness]\\n" >&2
                return 1
            fi
            GET_POD_STATUS "${_out_r:+true}" "${_out_q:+true}" "${_out_arguments}"
        elif [ "${command}" = "info" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 1 "$@"; then
                printf "Usage: sns pod info pod[:version][@host]\\n" >&2
                return 1
            fi
            GET_POD_INFO "${_out_arguments}"
        elif [ "${command}" = "logs" ]; then
            local _out_arguments=
            local _out_p=
            local _out_t=
            local _out_s=
            local _out_l=
            local _out_d=

            if ! _GETOPTS "_out_p=-p,--daemon-process/ _out_t=-t,--timestamp/* _out_l=-l,--limit/* _out_s=-s,--stream/* _out_d=-d,--details/*" 1 999 "$@"; then
                printf "Usage: sns pod logs pod[:version][@host] [-p|-daemon-process] [-t|--timestamp=] [-l|--limit=] [-s|--stream=] [-d|--details=] [containers]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            LOGS "${_out_t}" "${_out_l}" "${_out_s}" "${_out_d}" "${_out_p:+true}" "$@"
        elif [ "${command}" = "signal" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 999 "$@"; then
                printf "Usage: sns pod signal pod[:version][@host] [containers]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            SIGNAL_POD "$@"
        elif [ "${command}" = "rerun" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 999 "$@"; then
                printf "Usage: sns pod rerun pod[:version][@host] [containers]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            RERUN_POD "$@"
        elif [ "${command}" = "release" ]; then
            local _out_arguments=
            local _out_m="hard"
            local _out_p=
            local _out_f=

            if ! _GETOPTS "_out_p=-p,--push/ _out_f=-f,--force/ _out_m=-m,--mode/hard|soft|safe" 1 1 "$@"; then
                printf "Usage: sns release pod[:version] [-p|--push] [-m|--mode=soft|hard|safe] [-f|--force]\\n" >&2
                return 1
            fi
            RELEASE "${_out_arguments}" "${_out_m}" "${_out_p:+true}" "${_out_f:+true}"
        elif [ "${command}" = "shell" ]; then
            local _out_arguments=
            local _out_b=
            local _out_c=

            if ! _GETOPTS "_out_b=-b,--bash/ _out_c=-c,--container/*" 1 99999 "$@"; then
                printf "Usage: sns pod shell pod[:version][@host] [-b|--bash] [-c|--container=] -- [<commands>]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            POD_SHELL "${_out_b:+true}" "${_out_c}" "$@"
        elif [ "${command}" = "delete" ]; then
            local _out_arguments=

            if ! _GETOPTS "" 1 999 "$@"; then
                printf "Usage: sns pod delete pod[:version][@host]\\n" >&2
                return 1
            fi
            set -- ${_out_arguments}
            DELETE_POD "$@"
        else
            PRINT "Unknown pod command '${command}'" "error" 0
            return 1
        fi
    else
        PRINT "Unknown context '${context}'" "error" 0
        return 1
    fi
}
