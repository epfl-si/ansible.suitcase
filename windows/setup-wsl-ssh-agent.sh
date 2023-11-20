#!/bin/bash

set -e

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

confirm_sudo() {
    if [ ! -t 0 ]; then
        fatal <<PLEASE_RUN_IT_YOURSELF
Please run the following command to proceed:

  sudo $@

PLEASE_RUN_IT_YOURSELF
    fi

    warn <<PROMPT
Please confirm running the following command:

  sudo $@

Confirm [yN]?
PROMPT

    local answer
    read answer
    case "$answer" in
        y*|Y*) sudo "$@" ;;
        *) return 1 ;;
    esac
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

find_npiperelay() {
    npiperelay="$(which npiperelay.exe || true)"
    case "$npiperelay" in
        "") fatal << 'CANNOT_FIND_NPIPERELAY' ;;
Fatal: npiperelay.exe not found.

Please make sure that this script resides in the same directory as the
npiperelay.exe utility from the wsl-ssh-agent release.

CANNOT_FIND_NPIPERELAY
    esac
}

ensure_socat() {
    if which socat >/dev/null 2>&1; then return 0; fi

    case "$(lsb_release -s -i)" in
        Ubuntu|Debian)
            (
                set -x
                confirm_sudo apt -qy update
                confirm_sudo apt -qy install socat
            ) ;;
        RedHat*|CentOS*)
            (
                # UNTESTED
                set -x
                confirm_sudo yum install socat
            ) ;;
    esac
}

ensure_ssh_add() {
    if which ssh-add >/dev/null 2>&1; then return 0; fi

    fatal <<'NO_SSH_ADD'
Fatal: the `ssh-add` command is missing. Cannot continue.
NO_SSH_ADD
}

ensure_ssh_dir() {
    local ssh_dir="$HOME"/.ssh
    if [ ! -d "$ssh_dir" ]; then mkdir "$ssh_dir"; fi
    chmod 0700 "$ssh_dir"
}

ssh_add_already_works() {
    if ssh_add >/dev/null 2>&1; then
        return 0
    elif [ "$?" = 1 ]; then
        # "The agent has no identities."
        return 0
    else
        return $?
    fi
}

setup_dotprofile() {
    dotprofile="$HOME"/.profile
    if grep SSH_AUTH_SOCK "$dotprofile"; then
        fatal <<U_CANTTOUCHTHIS
Fatal: SSH_AUTH_SOCK configuration already present in $dotprofile
Bailing out
U_CANTTOUCHTHIS
    fi

    cat >> "$dotprofile" <<DOTPROFILE_SNIPPET

export SSH_AUTH_SOCK=\$HOME/.ssh/agent.sock

ss -a | grep -q \$SSH_AUTH_SOCK
if [ \$? -ne 0  ]; then
    rm -f \$SSH_AUTH_SOCK
    ( setsid socat "UNIX-LISTEN:\$SSH_AUTH_SOCK,fork" "EXEC:\"$npiperelay\" -ei -s //./pipe/openssh-ssh-agent",nofork & ) >/dev/null 2>&1
fi

DOTPROFILE_SNIPPET

}

main() {
    case "$(wsl_version)" in
        "") fatal "This does not appear to be a WSL Linux. Bailing out" ;;
        1)  fatal "Only WSL v2 is supported (on account of Keybase-specific requirements)" ;;
    esac

    ensure_ssh_add
    if ssh_add_already_works; then
        warn <<NOTHING_TO_DO
Your ssh agent appears to be functional already; nothing to do:

`ssh-add -l`

NOTHING_TO_DO
        exit 0
    fi

    export PATH="$(dirname "$0"):$PATH"
    find_npiperelay

    ensure_socat
    ensure_ssh_dir
    setup_dotprofile

    cat >&2 <<ALL_DONE
Configuration all done in $dotprofile

Please log out of Windows® and then back in, and try

  ssh-add -l

ALL_DONE
}


##############################################################
main
exit 0
