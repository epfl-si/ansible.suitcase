#!/bin/bash

set -e -x

warn () {
    if [ -n "$1" ]; then
        echo "$@" >&2
    else
        cat >&2
    fi
}

fatal () {
    echo >&2; echo >&2
    warn "$@"
    exit 1
}

## Example uname's (as of March 2021):
##
## WSL v1: `uname -r` -> 4.4.0-18362-Microsoft
##         `uname -v` -> #1049-Microsoft Thu Aug 14 12:01:00 PST 2020
## WSL v2: `uname -r` -> 5.4.72-microsoft-standard-WSL2
##         `uname -v` -> #1 SMP Wed Oct 28 23:40:43 UTC 2020
wsl_version() {
    case "$(uname -r)" in
        *icrosoft*WSL2*)
            echo "2" ;;
        *icrosoft*)
            echo "1" ;;
        *)
            echo "" ;;
    esac
}

main() {
    case "$(wsl_version)" in
        "") fatal "This does not appear to be a WSL Linux. Bailing out" ;;
        1)  fatal "Only WSL v2 is supported (on account of Keybase-specific requirements)" ;;
    esac
}


##############################################################
main
exit 0
