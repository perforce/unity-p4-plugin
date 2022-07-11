#!/usr/bin/env bash
#
# Configuration script for Helix Authentication Service.
#
# Copyright 2020, Perforce Software Inc. All rights reserved.
#
DEBUG=false
MONOCHROME=false
AUTH_TRIGGER=''
AUTH_EMAIL=''
AUTH_USER=''
AUTH_HOST=''
AUTH_METHOD=''
AUTH_SCHEME=''
AUTH_TOKEN=''

# Print arguments to STDERR and exit.
function die() {
    error "FATAL: $*" >&2
    exit 1
}

# Print the first argument in red text on STDERR.
function error() {
    $MONOCHROME || echo -e "\033[31m$1\033[0m" >&2
    $MONOCHROME && echo -e "$1" >&2 || true
}

# Print the first argument in blue text on STDERR.
function debug() {
    $DEBUG || return 0
    $MONOCHROME || echo -e "\033[33m$1\033[0m" >&2
    $MONOCHROME && echo -e "$1" >&2 || true
}

# Print the usage text to STDOUT.
function usage() {
    cat <<EOS

Usage:

    mfa-trigger.sh [-t] [-e] [-d] ...

Description:

    Test trigger playing with MFA and HAS on the same instance.

    Most of these options are not implemented (yet).

    -t <trigger>
        Trigger to run: pre-2fa, init-2fa, or check-2fa

    -e <user-email>
        Email address of the Perforce user authenticating.

    -u <user-name>
        Name of the Perforce user authenticating.

    -h <host-addr>
        Host address of the client system.

    -m <method>
        The authentication method from list-methods.

    -s <scheme>
        The authentication scheme set by init-auth.

    -k <token>
        The stashed token from the last init-auth.

    -d
        Enable debugging output for this configuration script.

    no-arguments
        Display this help message.

EOS
}

function read_arguments() {
    if (( $# == 0)); then
        usage
        exit 0
    fi

    # getopt MacOS 'built-in' version does not support any advanced option, so simplifying it as much as possible
    local PARSED_ARGS=$(getopt dt:e:u:h:m:s:k: $*)
    # If getopt accepted all of the input, it will return a status code of zero (0) to indicate success
    local VALID_ARGS=$?
    if (( "$VALID_ARGS" != "0" )); then
        echo "Not all input arguments were accepted."
        usage
        exit 1
    fi

    # Re-inject the arguments from getopt, so now we know they are valid and in
    # the expected order.
    eval set -- "$PARSED_ARGS"
    while true; do
        case "$1" in
            -t)
                AUTH_TRIGGER=$2
                shift 2
                ;;
            -e)
                AUTH_EMAIL=$2
                shift 2
                ;;
            -u)
                AUTH_USER=$2
                shift 2
                ;;
            -h)
                AUTH_HOST=$2
                shift 2
                ;;
            -m)
                AUTH_METHOD=$2
                shift 2
                ;;
            -s)
                AUTH_SCHEME=$2
                shift 2
                ;;
            -k)
                AUTH_TOKEN=$2
                shift 2
                ;;
            -d)
                DEBUG=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                die "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if ("$DEBUG") then
        echo "AUTH_TRIGGER  :   $AUTH_TRIGGER"
        echo "AUTH_EMAIL    :   $AUTH_EMAIL"
        echo "AUTH_USER     :   $AUTH_USER"
        echo "AUTH_HOST     :   $AUTH_HOST"
        echo "AUTH_METHOD   :   $AUTH_METHOD"
        echo "AUTH_SCHEME   :   $AUTH_SCHEME"
        echo "AUTH_TOKEN    :   $AUTH_TOKEN"
        echo "DEBUG         :   $DEBUG"
        echo "Parameters remaining are: $@"
    fi

    # spurious arguments that are not supported by this script
    if (( $# != 0 )); then
        usage
        exit 1
    fi
}

function run_pre_2fa() {
    cat <<'EOT'
{
    "status" : 0,
    "message" : "A message for the caller",
    "methodlist" : [
        [ "challenge", "type something in response to a challenge" ],
    ]
}
EOT
}

function run_pre_2fa_noauth() {
    cat <<'EOT'
{
    "status":2,
    "message" : "Second factor authentication not required"
}
EOT
}

function run_init_2fa() {
    cat <<EOT
{
    "status": 0,
    "scheme": "challenge",
    "message": "Please enter your response",
    "challenge": "ABBACD",
    "token": "REQID:20003339189"
}
EOT
}

function run_check_2fa() {
    cat <<EOT
{
    "status": 0
}
EOT
}

function main() {
    set -e
    read_arguments "$@"
    if [[ "${AUTH_TRIGGER}" == 'pre-2fa' ]]; then
        if [[ "${AUTH_USER}" == 'noauth' ]]; then
            run_pre_2fa_noauth
        else
            run_pre_2fa
        fi
    elif [[ "${AUTH_TRIGGER}" == 'init-2fa' ]]; then
        run_init_2fa
    elif [[ "${AUTH_TRIGGER}" == 'check-2fa' ]]; then
        run_check_2fa
    else
        error "Unknown trigger type: <<${AUTH_TRIGGER}>>"
        usage
        exit 1
    fi
    exit 0
}

main "$@"
