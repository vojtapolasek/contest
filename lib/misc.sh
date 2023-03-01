[[ $_LIB_MISC_DEFINED ]] && return
_LIB_MISC_DEFINED=1
[[ -z $_LIB_LIBDIR ]] && _LIB_LIBDIR=$(dirname "${BASH_SOURCE[0]}")

. "$_LIB_LIBDIR/tmt.sh"

# simply print out a msg to stderr, for non-fatal errors
function error {
    printf 'error: %s\n' "$*" >&2
}

# save/restore the xtrace flag, to save on log size in certain tests
function set_x_disable {
    [[ $- = *x* ]] && set_x_disabled=1
    { set +x; } 2>/dev/null
}
function set_x_restore {
    if [ -n "$set_x_disabled" ]; then
        unset set_x_disabled
        { set -x; } 2>/dev/null
    fi
}

# return 0 if the passed first v/r is related to second v/r according to sign
# _rpm_ver_cmp first_v first_r sign second_v second_r
# _rpm_ver_cmp 1.1 1-el9 '<' 1.2 1-el9
# _rpm_ver_cmp 2 '' == 2 ''
function rpm_ver_cmp {
    python3 <<EOF
import sys,rpm
r = rpm.labelCompare((None,'$1','$2'),(None,'$4','$5'))
sys.exit(0 if r $3 0 else 1)
EOF
}

# compare current RHEL version against a sign and a value,
# behave like beakerlib's rlIsRHEL and its sign-based comparison
# rhel '==8'    # true on 8.0, 8.1, etc.
# rhel '>7'     # true on any 8, 9, etc.
# rhel '==8.3'  # true only on 8.3
# rhel '<=8.3'  # true on 8.3, 8.2, but false on 7.9 or older 7, 6, etc.
# rhel '>7.5'   # true on 7.5, 7.6, but false on any 8, 9, etc.
function rhel {
    local sign=${1%%[0-9]*} tgt=${1##*[><=]} rc=0
    # rare sanity check to guard against old rlIsRHEL syntax
    [[ $sign ]] || exit_error "rhel() must always be used with a sign"

    local os_release=$(</etc/os-release)
    local osname=$(eval "$os_release"; echo "$ID")
    [[ $osname == rhel ]] || return 1
    local cur=$(eval "$os_release"; echo "$VERSION_ID")

    local tgt_major=${tgt%%.*} tgt_minor=${tgt#*.}
    local cur_major=${cur%%.*} cur_minor=${cur#*.}

    # if target has only major, compare majors
    if [[ $tgt_major == $tgt ]]; then
        rpm_ver_cmp "$cur_major" '' "$sign" "$tgt_major" '' || rc=$?
        return $rc
    fi

    # else compare only minors
    [[ $tgt_major == $cur_major ]] || return 1
    rpm_ver_cmp "$cur_minor" '' "$sign" "$tgt_minor" ''
}

# return 0 if the current system has support for creating virtual machines
function has_virt {
    grep -q -E ' (vmx|svm)' /proc/cpuinfo
}

# verify that a program is reachable in PATH
function assert_in_path {
    # try builtin first
    local path=$(command -v "$1" 2>/dev/null) || true
    # resolve manually if alias (bash cannot do this natively)
    if [[ $path && ${path::1} != / ]]; then
        # avoid crazy Fedora/RH aliases in profile.d
        path=$(/usr/bin/which "$1" 2>/dev/null) || true
    fi
    [[ $path ]] || exit_error "$1 not in PATH"
}
# wait for a child PID and exit the current shell with non-zero
# if the child failed
# first arg: cmdline that failed
# other (optional) args: allowed / expected exit codes
function assert_child_success {
    local msg=$1 code= rc=0
    wait $! || rc=$?
    shift
    if [[ $# -gt 0 ]]; then
        for code in "$@"; do
            [[ $rc -eq $code ]] && return 0
        done
    else
        [[ $rc -eq 0 ]] && return 0
    fi
    exit_error "$msg failed, exitcode: $rc"
}
