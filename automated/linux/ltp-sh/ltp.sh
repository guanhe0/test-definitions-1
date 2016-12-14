#!/bin/sh

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo "Script path is: ${SCRIPTPATH}"
# List of test cases
TST_CMDFILES=""
# List of test cases to be skipped
SKIPFILE=""
# LTP version
LTP_VERSION="20160920"

LTP_PATH=/opt/ltp

usage() {
    echo "Usage: $0 [-T mm,math,syscalls] [-S skipfile-lsk-juno] [-s <flase>] [-v LTP_VERSION]" 1>&2
    exit 0
}

while getopts "T:S:s:v:h" arg; do
    case "$arg" in
        T)
            TST_CMDFILES="${OPTARG}"
            LOG_FILE=$(echo "${OPTARG}"| sed 's/,/_/')
            ;;
        S)
            if echo "${OPTARG}" | grep "http"; then
                # Download LTP skipfile from speficied URL
                wget "${OPTARG}"
                # Get basename of the URL.
                SKIPFILE="${OPTARG##*/}"
                SKIPFILE="$(pwd)/${SKIPFILE}"
            else
                SKIPFILE="${SCRIPTPATH}/${OPTARG}"
            fi
            ;;
        # SKIP_INSTALL is true in case of Open Embedded builds # SKIP_INSTALL is flase in case of Debian builds
        s)
            SKIP_INSTALL="${OPTARG}"
            ;;
        v)
            LTP_VERSION="${OPTARG}"
            ;;
        *)
            usage
            ;;
    esac
done

# Install LTP test suite
install_ltp() {
    rm -rf /opt/ltp
    mkdir -p /opt/ltp
    cd /opt/ltp || exit
    wget https://github.com/linux-test-project/ltp/releases/download/"${LTP_VERSION}"/ltp-full-"${LTP_VERSION}".tar.xz
    tar --strip-components=1 -Jxf ltp-full-"${LTP_VERSION}".tar.xz
    ./configure
    make -j8 all
    make SKIP_IDCHECK=1 install
}

parse_ltp_summary() {
    for TEST in "Total Tests" "Total Skipped Tests" "Total Failures"; do
        NO_OF_TESTS="$(grep "$TEST" "$1"  | awk '{print $NF}')"
        TEST=$(echo "$TEST" | tr -s ' ' '-')
        add_metric "$TEST" "pass" "${NO_OF_TESTS}" "testcases"
    done
}

# Parse LTP output
parse_ltp_output() {
    egrep "PASS|FAIL|CONF"  "$1" | awk '{print $1" "$2}' | sed s/CONF/SKIP/  >> "${RESULT_FILE}"
}

# Run LTP test suite
run_ltp() {
    cd "${LTP_PATH}" || exit

    ./runltp -p -q -f "${TST_CMDFILES}" \
        -l "${OUTPUT}/LTP_${LOG_FILE}.log" \
        -C "${OUTPUT}/LTP_${LOG_FILE}.failed" -S "${SKIPFILE}" \
        | tee "${OUTPUT}/LTP_${LOG_FILE}.out"

    parse_ltp_summary "${OUTPUT}/LTP_${LOG_FILE}.log"
    parse_ltp_output "${OUTPUT}/LTP_${LOG_FILE}.log"
}

# Test run.
! check_root && error_msg "This script must be run as root"
[ -d "${OUTPUT}" ] && mv "${OUTPUT}" "${OUTPUT}_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUTPUT}"

info_msg "About to run ltp test..."
info_msg "Output directory: ${OUTPUT}"

if [ "${SKIP_INSTALL}" = "True" ] || [ "${SKIP_INSTALL}" = "true" ]; then
    info_msg "install_ltp skipped"
else
    dist_name
    # shellcheck disable=SC2154
    case "${dist}" in
      Debian|Ubuntu)
        pkgs="xz-utils flex bison build-essential wget curl"
        ;;
      CentOS|Fedora)
        pkgs="xz flex bison make automake gcc gcc-c++ kernel-devel wget curl"
        ;;
      *)
        error_msg "Unsupported distribution!"
    esac
    install_deps "${pkgs}" "${SKIP_INSTALL}"
    info_msg "Run install_ltp"
    install_ltp
fi
info_msg "Running run_ltp"
run_ltp