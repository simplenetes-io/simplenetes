# All REMOTELY EXECUTED functionality
#

# Return 10 on internal error which is pointless retrying.
_REMOTE_EXEC()
{
    SPACE_SIGNATURE="host action [args]"
    # This env variable can be baked in at compile time if we want this module to be standalone
    SPACE_ENV="CLUSTERPATH REMOTE_PACK_RELEASEDATA=$ REMOTE_SET_COMMITCHAIN=$ REMOTE_ACQUIRE_LOCK=$ REMOTE_RELEASE_LOCK=$ REMOTE_GET_HOSTMETADATA=$ REMOTE_UPLOAD_ARCHIVE=$ REMOTE_UNPACK_ARCHIVE=$ REMOTE_INIT_HOST=$ REMOTE_HOST_SETUP=$ REMOTE_LOGS=$ REMOTE_DAEMON_LOG=$ REMOTE_CREATE_SUPERUSER=$ REMOTE_DISABLE_ROOT=$ REMOTE_SIGNAL=$ REMOTE_POD_STATUS=$"
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
        "pod_status")
            if [ -n "${REMOTE_POD_STATUS}" ]; then
                RUN="${REMOTE_POD_STATUS}"
            fi
            ;;
        "signal")
            if [ -n "${REMOTE_SIGNAL}" ]; then
                RUN="${REMOTE_SIGNAL}"
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

    PRINT "Host now belongs to ${clusterID}" "info" 0
}

_REMOTE_DAEMON_LOG()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome]"

    # TODO: add limits and time windows.
    journalctl -u sntd
}

_REMOTE_SIGNAL()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome pod podVersion container]"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local podFile="${HOSTHOME}/pods/${pod}/release/${podVersion}/pod"

    if [ ! -f "${podFile}" ]; then
        PRINT "Missing pod: ${pod}:${podVersion}" "error" 0
        return 1
    fi

    ${podFile} signal "$@"
}

_REMOTE_POD_STATUS()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome pod podVersion query]"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    local pod="${1}"
    shift

    local podVersion="${1}"
    shift

    local query="${1}"
    shift

    local podFile="${HOSTHOME}/pods/${pod}/release/${podVersion}/pod"

    if [ ! -f "${podFile}" ]; then
        PRINT "Missing pod: ${pod}:${podVersion}" "error" 0
        return 10
    fi

    if [ "${query}" = "readiness" ]; then
        if ${podFile} readiness; then
            printf "ready\\n"
        else
            printf "not-ready\\n"
        fi
    else
        ${podFile} status
    fi
}

_REMOTE_LOGS()
{
    # Arguments are actually not optional, but we do this so the exporting goes smoothly.
    SPACE_SIGNATURE="[hosthome pod podVersion timestamp limit streams]"
    SPACE_DEP="STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

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
    PRINT "Installed ${podmanVersion}" "info" 0

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
    SPACE_DEP="_UTIL_GET_TMP_FILE STRING_SUBST PRINT"

    local HOSTHOME="${1}"
    shift
    STRING_SUBST "HOSTHOME" '${HOME}' "$HOME" 1

    # Indicate we are still busy
    touch "${HOSTHOME}/lock-token.txt"

    local file="$(_UTIL_GET_TMP_FILE)"

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
