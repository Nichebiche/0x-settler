#!/usr/bin/env bash

## POSIX Bash implementation of realpath
## Copied and modified from https://github.com/mkropat/sh-realpath and https://github.com/AsymLabs/realpath-lib/
## Copyright (c) 2014 Michael Kropat - MIT License
## Copyright (c) 2013 Asymmetry Laboratories - MIT License

function realpath {
    _resolve_symlinks "$(_canonicalize "$1")"
}

function _directory {
    local out slsh
    slsh=/
    out="$1"
    out="${out//$slsh$slsh/$slsh}"
    if [ "$out" = / ]; then
        echo /
        return
    fi
    out="${out%/}"
    case "$out" in
        */*)
            out="${out%/*}"
        ;;
        *)
            out=.
        ;;
    esac
    if [ "$out" ]; then
        printf '%s\n' "$out"
    else
        echo /
    fi
}

function _file {
    local out slsh
    slsh=/
    out="$1"
    out="${out//$slsh$slsh/$slsh}"
    if [ "$out" = / ]; then
        echo /
        return
    fi
    out="${out%/}"
    out="${out##*/}"
    printf '%s\n' "$out"
}

function _resolve_symlinks {
    local path pattern context
    while [ -L "$1" ]; do
        context="$(_directory "$1")"
        path="$(POSIXLY_CORRECT=y ls -ld -- "$1" 2>/dev/null)"
        pattern='*'"$(_escape "$1")"' -> '
        path="${path#$pattern}"
        set -- "$(_canonicalize "$(_prepend_context "$context" "$path")")" "$@"
        _assert_no_path_cycles "$@" || return 1
    done
    printf '%s\n' "$1"
}

function _escape {
    local out
    out=''
    local -i i
    for ((i=0; i < ${#1}; i+=1)); do
        out+='\'"${1:$i:1}"
    done
    printf '%s\n' "$out"
}

function _prepend_context {
    if [ "$1" = . ]; then
        printf '%s\n' "$2"
    else
        case "$2" in
            /* ) printf '%s\n' "$2" ;;
             * ) printf '%s\n' "$1/$2" ;;
        esac
    fi
}

function _assert_no_path_cycles {
    local target path

    if [ $# -gt 16 ]; then
        return 1
    fi

    target="$1"
    shift

    for path in "$@"; do
        if [ "$path" = "$target" ]; then
            return 1
        fi
    done
}

function _canonicalize {
    local d f
    if [ -d "$1" ]; then
        (CDPATH= cd -P "$1" 2>/dev/null && pwd -P)
    else
        d="$(_directory "$1")"
        f="$(_file "$1")"
        (CDPATH= cd -P "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$f")
    fi
}

## end POSIX Bash implementation of realpath

set -Eeufo pipefail -o posix

declare project_root
project_root="$(_directory "$(_directory "$(realpath "${BASH_SOURCE[0]}")")")"
declare -r project_root
cd "$project_root"

. "$project_root"/sh/common.sh

declare safe_address
safe_address="$(get_config governance.upgradeSafe)"
declare -r safe_address

. "$project_root"/sh/common_safe.sh
. "$project_root"/sh/common_safe_owner.sh
. "$project_root"/sh/common_wallet_type.sh

declare -r -i feature="$1"
shift

declare -r description_file="$1"
shift

declare description
description="$(jq -MRs < "$description_file")"
description="${description:1:$((${#description} - 2))}"
declare -r description

declare -r setDescription_sig='setDescription(uint128,string)(string)'
declare -r authorize_sig='authorize(uint128,address,uint40)(bool)'

function _compat_date {
    declare -r datestring="$1"
    shift

    declare -r datefmt="$1"
    shift

    if date -d '1 second' &>/dev/null ; then
        date -u -d "${datestring:8:4}-${datestring:0:2}-${datestring:2:2}T${datestring:4:2}:${datestring:6:2}:00-00:00" "$datefmt"
    else
        date -u -j "$datestring" "$datefmt"
    fi
}

declare auth_deadline_datestring
# one year from the start of this month
# MMDDhhmmCCYY
auth_deadline_datestring="$(date -u '+%m')010000$(($(date -u '+%Y') + 1))"
declare -r auth_deadline_datestring
declare -i auth_deadline
# convert to UNIX timestamp
auth_deadline="$(_compat_date "$auth_deadline_datestring" +%s)"
declare -r -i auth_deadline

declare -a calls=()

declare setDescription_call
setDescription_call="$(cast calldata "$setDescription_sig" $feature "$description")"
declare -r setDescription_call

calls+=(
    "$(
        cast concat-hex                                                  \
        0x00                                                             \
        "$deployer_address"                                              \
        "$(cast to-uint256 0)"                                           \
        "$(cast to-uint256 $(( (${#setDescription_call} - 2) / 2 )) )"   \
        "$setDescription_call"
    )"
)

declare authorize_call
authorize_call="$(cast calldata "$authorize_sig" $feature "$(get_config governance.deploymentSafe)" "$auth_deadline")"
declare -r authorize_call

calls+=(
    "$(
        cast concat-hex                                             \
        0x00                                                        \
        "$deployer_address"                                         \
        "$(cast to-uint256 0)"                                      \
        "$(cast to-uint256 $(( (${#authorize_call} - 2) / 2 )) )"   \
        "$authorize_call"
    )"
)

declare new_feature_calldata
new_feature_calldata="$(cast calldata "$multisend_sig" "$(cast concat-hex "${calls[@]}")")"
declare -r new_feature_calldata

declare struct_json
struct_json="$(eip712_json "$new_feature_calldata" 1)"
declare -r struct_json

declare signature
signature="$(sign_call "$struct_json")"
declare -r signature

save_signature new_feature "$new_feature_calldata" "$signature" 1
