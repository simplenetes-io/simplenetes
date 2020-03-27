# create a project, add hosts, attach pods, compile pods, sync, update pods, sync, etc.
TEST_FULL()
{
    SPACE_SIGNATURE="cwd"
    SPACE_DEP="_TEST_FULL"

    local cwd="${1}"

    local oldPwd="${PWD}"

    cd "${CLUSTERPATH}"
    local dir=
    if ! dir="$(_UTIL_GET_TMP_DIR)"; then
        PRINT "Could not create tmp dir" "error"
        return 1
    fi

    # Copy test pods to new tmp dir
    cp -r "${cwd}/pods" "${dir}"

    local status=
    _TEST_FULL "${dir}"
    status="$?"

    #rm -rf "${dir}"

    cd "${oldPwd}"

    return "${status}"
}

_TEST_FULL()
{
    SPACE_SIGNATURE="tmpDir"

    local dir="${1}"
    shift

    SPACE_DEP="PRINT _PRJ_CLUSTER_CREATE _PRJ_HOST_CREATE _PRJ_HOST_INIT _PRJ_ATTACH_POD _PRJ_COMPILE_POD"

    # Create new cluster project
    if ! _PRJ_CLUSTER_CREATE "${dir}" "test-cluster"; then
        PRINT "Could not creat cluster" "error"
        return 1
    fi

    # Create a fake "remote" environment, to which syncing will be done.
    mkdir -p "${dir}/remote"

    local CLUSTERPATH="${dir}/test-cluster"
    local PODPATH="${dir}/pods"

    # Create a few hosts
    local jumphost="local"
    local expose=""
    local host=
    for host in host1 host2 host3; do
        local hostHome="${dir}/remote/${host}"
        mkdir -p "${hostHome}"
        _PRJ_HOST_CREATE "${host}" "${jumpHost}" "${expose}" "${hostHome}"
        _PRJ_HOST_INIT "${host}"
    done

    # Attach a few pods
    _PRJ_ATTACH_POD "pod1@host1"
    _PRJ_ATTACH_POD "pod1@host2"
    _PRJ_ATTACH_POD "pod1@host3"

    _PRJ_ATTACH_POD "pod2@host2"
    _PRJ_ATTACH_POD "pod2@host3"

    _PRJ_ATTACH_POD "pod3@host3"

    # Compile one pod
    _PRJ_COMPILE_POD "pod3"

    # Sync
    git add .
    git commit -m "Update"
    _SYNC_RUN

    # Check if the pods are synced to the remote/hostX directories as expected
    # TODO
}
