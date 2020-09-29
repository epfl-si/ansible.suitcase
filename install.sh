#!/bin/sh

# Pure Bourne-shell script to install Ansible and the EPFL-SI devops
# tool suite into a self-contained directory
#
# Environment variables:
#
# $SUITCASE_DIR (mandatory)     Where to install the goods to
#
# $SUITCASE_PYTHON_VERSION
# $SUITCASE_ANSIBLE_VERSION       The precise versions to use for the
#                                 requirement stack to use.
#                                 (Reasonable defaults are provided)
#
# $SUITCASE_PIP_EXTRA             Additional modules to install with `pip install`
#                                 (separated with spaces)
#
# $SUITCASE_ANSIBLE_REQUIREMENTS  If set, shall point to a requirements.yml
#                                 file
#
# $SUITCASE_NO_KEYBASE            If set, don't check for Keybase, and don't
#                                 attempt to install eyaml nor its dependencies
#
# Directory layout under $SUITCASE_DIR:
#
#   .versions                 Created only after successful installation.
#                             You can use the existence of this file
#                             in a short-circuit test from your
#                             run-time Ansible wrapper script
#
#   bin/ansible               The Ansible executable
#   bin/eyaml                 The eyaml executable
#   roles/                    If you pass $SUITCASE_ANSIBLE_REQUIREMENTS,
#                             the Ansible roles will be installed there.
#                             You should therefore export
#                             ANSIBLE_ROLES_PATH=$SUITCASE_DIR/roles from
#                             the wrapper script
#
#   pyenv/                    Various support directories
#   pyenv/bin/
#   python/
#   python/bin/
#   eyaml/
#
# Additional checks and requirements:
#
# - Keybase - The script will test for it (unless $SUITCASE_NO_KEYBASE is set),
#   but obviously will not install it in your stead.

: ${SUITCASE_PYTHON_VERSION:=3.7.7}
: ${SUITCASE_ANSIBLE_VERSION:=2.9.6}
: ${SUITCASE_RUBY_VERSION:=2.6.3}
: ${SUITCASE_EYAML_VERSION:=3.2.0}

set -e

satisfied=
unsatisfied=

main () {
    ensure_git

    [ -n "$SUITCASE_DIR" ] || fatal "SUITCASE_DIR is not set; don't know where to install"
    ensure_dir "$SUITCASE_DIR"
    if [ ! -f "$SUITCASE_DIR/.versions.tmp" ]; then
        if [ -f "$SUITCASE_DIR/.versions" ]; then
            cp "$SUITCASE_DIR/.versions" "$SUITCASE_DIR/.versions.tmp"
        else
            : >> "$SUITCASE_DIR/.versions.tmp"
        fi
    fi

    ensure_pip     || unsatisfied pip
    ensure_ansible || unsatisfied ansible

    if [ -z "$SUITCASE_NO_KEYBASE" ]; then
      ensure_keybase || unsatisfied keybase
      case "$unsatisfied" in
          ruby|"ruby "*|*" ruby"|*" ruby "*)
              warn "No Ruby available; skipping eyaml installation" ;;
          *) ensure_eyaml || unsatisfied eyaml ;;
      esac
    fi

    case "$satisfied" in
        *ansible*)
            if [ -n "$SUITCASE_ANSIBLE_REQUIREMENTS" ]; then
                ensure_ansible_requirements "$SUITCASE_ANSIBLE_REQUIREMENTS" || \
                    unsatisfied ansible_requirements
            fi ;;
    esac

    case "$unsatisfied" in
        "")
            mv "$SUITCASE_DIR"/.versions.tmp "$SUITCASE_DIR"/.versions
            exit 0 ;;
        *ansible*) exit 2 ;;
        *)
            echo >&2 "Unsatisfied optional requirements: $unsatisfied"
            exit 0 ;;
    esac
}

warn () {
    if [ -n "$1" ]; then
        echo "$@" >&2
    else
        cat >&2
    fi
}

fatal () {
    warn "$@"
    exit 1
}

satisfied () {
    satisfied="$satisfied $1"
    if [ -n "$2" ]; then
        record_version "$1" "$2"
    fi
}

unsatisfied () {
    unsatisfied="$unsatisfied $1"
    record_version "$1"  # Unsets it
}

check_version () {
    local software="$1"
    local version="$2"

    case "$version" in
        "") unsatisfied $software ;;
        *) satisfied $software "$version" ;;
    esac
}

record_version () {
    local version_key="$(echo "$1" | tr 'a-z' 'A-Z')"_VERSION
    local version_val="$2"
    (
        grep -v "^$version_key" "$SUITCASE_DIR"/.versions.tmp || true
        if [ -n "$version_val" ]; then
            echo "$version_key=\"$version_val\""
        fi
    )    > "$SUITCASE_DIR"/.versions.tmp.tmp

    mv "$SUITCASE_DIR"/.versions.tmp.tmp "$SUITCASE_DIR"/.versions.tmp
}

ensure_dir () {
    [ -d "$1" ] || mkdir -p "$1"
}

ensure_symlink () {
    local from="$1"
    local to
    case "$2" in
        */) to="$2$(basename $1)" ;;
        *) to="$2" ;;
    esac
    rm -f "$to" 2>/dev/null || true
    ln -s "$from" "$to"
}

ensure_pyenv () {
    local pyenv_root="$SUITCASE_DIR/pyenv"
    if [ ! -x "$pyenv_root/bin/pyenv" ]; then
        rm -rf "$pyenv_root"
        curl https://pyenv.run | PYENV_ROOT="$pyenv_root" bash
    fi

    check_version pyenv "$(set +x; run_pyenv 2>&1 | head -1 |cut -d' ' -f2)"
}

ensure_ansible_requirements () {
    ensure_dir "$SUITCASE_DIR/roles"
    "$SUITCASE_DIR"/bin/ansible-galaxy install -p "$SUITCASE_DIR/roles" -i -r "$1"
}

run_pyenv () {
    env PYENV_ROOT="$SUITCASE_DIR/pyenv" PATH="$SUITCASE_DIR/pyenv/bin:$PATH" \
        "$SUITCASE_DIR"/pyenv/bin/pyenv "$@"
}

ensure_python3 () {
    if [ ! -x "$SUITCASE_DIR"/bin/python3 ]; then
        ensure_pyenv
        local version="${SUITCASE_PYTHON_VERSION}"
        if ! run_pyenv versions |grep -w "$version"; then
            run_pyenv install "$version"
        fi

        ensure_symlink "pyenv/versions/$version" "$SUITCASE_DIR"/python
        ensure_dir "$SUITCASE_DIR/bin"
        ensure_symlink "../python/bin/python3" "$SUITCASE_DIR"/bin/python3
    fi

    check_version python "$("$SUITCASE_DIR"/bin/python3 --version | sed 's/Python //')"
}

ensure_pip () {
    ensure_python3
    for dep in $SUITCASE_PIP_EXTRA; do
        if "$SUITCASE_DIR"/python/bin/pip3 install "$dep"; then
            satisfied "pip-$dep"
        else
            unsatisfied "pip-$dep"
        fi
    done
}

ensure_ansible () {
    if [ ! -x "$(readlink "$SUITCASE_DIR/bin/ansible")" -o \
         ! -x "$(readlink "$SUITCASE_DIR/bin/ansible-playbook")" ]; then
        ensure_python3
        "$SUITCASE_DIR"/python/bin/pip install ansible=="${SUITCASE_ANSIBLE_VERSION}"
        ensure_dir "$SUITCASE_DIR/bin"
        ensure_symlink ../python/bin/ansible "$SUITCASE_DIR/bin/"
        ensure_symlink ../python/bin/ansible-playbook "$SUITCASE_DIR/bin/"
        ensure_symlink ../python/bin/ansible-galaxy "$SUITCASE_DIR/bin/"
    fi

    check_version ansible "$("$SUITCASE_DIR/bin/ansible" --version | head -1 | sed 's/ansible //')"
}

ensure_rbenv () {
    local rbenv_root="$SUITCASE_DIR/rbenv"

    if [ ! -d "$rbenv_root" ]; then
        ensure_dir "$SUITCASE_DIR"
        git clone https://github.com/rbenv/rbenv.git "$rbenv_root"
        git clone https://github.com/rbenv/ruby-build.git "${rbenv_root}/plugins/ruby-build"
    fi

    check_version rbenv "$(set +x; run_rbenv --version | sed 's/rbenv //')"
}

run_rbenv () {
    env RBENV_ROOT="$SUITCASE_DIR/rbenv" "$SUITCASE_DIR/rbenv/bin/rbenv" "$@"
}

ensure_ruby () {
    local version="${SUITCASE_RUBY_VERSION}"
    local targetdir="$SUITCASE_DIR/ruby"
    if [ ! -x "$targetdir"/bin/ruby ]; then
        ensure_rbenv
        local rbenv_version_dir="rbenv/versions/$version"
        if [ ! -d "$SUITCASE_DIR/$rbenv_version_dir" ]; then
            ensure_libreadline
            run_rbenv install "$version"
        fi
        ensure_symlink "$rbenv_version_dir" "$SUITCASE_DIR/ruby"
    fi

    check_version ruby "$("$targetdir"/bin/ruby --version | cut -d' ' -f2)"
}

ensure_eyaml () {
    if [ ! -x "$(readlink "$SUITCASE_DIR/bin/eyaml")" ]; then
        ensure_ruby 

        "$SUITCASE_DIR/ruby/bin/gem" install hiera-eyaml -v "${SUITCASE_EYAML_VERSION}"
        ensure_symlink ../ruby/bin/eyaml "$SUITCASE_DIR/bin/"

    fi
    check_version eyaml "$("$SUITCASE_DIR/bin/eyaml" --version | sed -n 's/Welcome to eyaml \([a-z0-9.-]*\).*/\1/p')"
}

ensure_keybase () {
    if [ -d /keybase ]; then
        satisfied keybase
        return
    fi

    unsatisfied keybase
    if [ "$(uname -s)" = "Darwin" ]; then
        for d in /Volumes/Keybase*; do
            if -d "$d"; then
                warn <<EOF
Keybase is installed, but the /keybase directory is not working.

Please follow the instructions at
https://github.com/keybase/keybase-issues/issues/3614#issue-509318240
to resolve this issue.
EOF
                return
            fi
        done
    else
        warn <<EOF
Keybase is not installed, cannot decipher and push secrets.
EOF
    fi
}

# On Ubuntu, libreadline-dev is required to compile the Ruby readline extension.
ensure_libreadline () {
    if [ "$(uname -s)" = "Linux" ]; then
        if [ ! -f "/usr/include/readline/readline.h" ]; then
            echo -e "\nError: Please install libreadline-dev (e.g. sudo apt-get install -y libreadline-dev)"
            exit 1
        fi
    fi
}

ensure_git () {
    if ! which git >/dev/null; then
        fatal "Error: git is required to proceed. Please install git and try again."
    fi
}

main
