##
# Utility functions

_UTIL_CLEAR_SCREEN()
{
    tput clear
}

_UTIL_GET_TMP_DIR()
{
    mktemp -d 2>/dev/null || mktemp -d -t 'sometmpdir'
}

_UTIL_GET_TMP_FILE()
{
    mktemp 2>/dev/null || mktemp -t 'sometmpdir'
}

_UTIL_GET_TAG_DIR()
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

# For a given file, return the tag or commit in which it was last changed.
# Will error out if the file is not in a git repo or if it is currently dirty.
_UTIL_GET_TAG_FILE()
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
