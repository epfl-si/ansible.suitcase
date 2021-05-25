#!/bin/sh

# Pure Bourne-shell script to install Ansible and the EPFL-SI devops
# tool suite into a self-contained directory
#
# Depending on the specifics, installing a compiler toolchain may be
# required (and also depending on the specifics, install.sh can help
# with that task)
#
# Environment variables:
#
# $SUITCASE_DIR (mandatory)     Where to install the goods to
#
# $SUITCASE_PYTHON_VERSIONS     A list of acceptable Python versions
#                               to use. (A reasonable default value is
#                               provided, which will try and make use of
#                               the system-distributed Python 3)
#
# $SUITCASE_ANSIBLE_VERSION       The precise version of Ansible to use.
#                                 (A reasonable default value is provided)
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
#   ansible_collections/      the Ansible Galaxy roles resp. collections will
#                             be installed there. You should therefore export
#                             ANSIBLE_ROLES_PATH=$SUITCASE_DIR/roles and
#                             ANSIBLE_COLLECTIONS_PATHS=$SUITCASE_DIR
#                             from the wrapper script (mind the extra “S” at the
#                             end of ANSIBLE_COLLECTIONS_PATHS!)
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

if [ -z "$SUITCASE_PYTHON_VERSIONS" ]; then
    if [ -n "$SUITCASE_PYTHON_VERSION" ]; then
        SUITCASE_PYTHON_VERSIONS="$SUITCASE_PYTHON_VERSION"
    else
        # As of May 25th, 2021:
        #
        # - 3.8.5 is the latest version on Ubuntu 20.04 (Focal)
        # - 3.8.2 is the latest version on Mac OS X 11.3.1 (20E241) (Big Sur)
        SUITCASE_PYTHON_VERSIONS="3.8.5 3.8.2"
    fi
fi
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

    ensure_pip_deps
    ensure_ansible  || unsatisfied ansible

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
        *ansible*) fatal "Ansible is **not** installed; please review errors above." ;;
        *)
            fatal "Unsatisfied optional requirements: $unsatisfied";;
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
    echo >&2; echo >&2
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
    "$SUITCASE_DIR"/bin/ansible-galaxy install --force -p "$SUITCASE_DIR/roles" -i -r "$1"
    if grep '^collections:' "$1"; then
        "$SUITCASE_DIR"/bin/ansible-galaxy collection install --force -p "$SUITCASE_DIR" -i -r "$1"
    fi
}

run_pyenv () {
    env PYENV_ROOT="$SUITCASE_DIR/pyenv" PATH="$SUITCASE_DIR/pyenv/bin:$PATH" \
        "$SUITCASE_DIR"/pyenv/bin/pyenv "$@"
}

check_python3_version () {
    check_version python "$("$SUITCASE_DIR"/bin/python3 --version | sed 's/Python //')"
}

ensure_python3 () {
    ensure_dir "$SUITCASE_DIR/bin"

    if [ ! -x "$SUITCASE_DIR"/bin/python3 ]; then

        # Prefer already-installed version, if available
        for already_installed in /usr/local/bin/python3 /usr/bin/python3; do
            if [ -x "$already_installed" ]; then
                version="$($already_installed --version 2>&1)"
                case "$version" in
                    Python*)
                        version="$(echo "$version" |sed 's/Python //')" ;;
                    *) continue ;;
                esac
                for expected_version in $SUITCASE_PYTHON_VERSIONS; do
                    if [ "$version" = "$expected_version" ]; then
                        ensure_symlink "$(dirname $(dirname "$already_installed"))" "$SUITCASE_DIR"/python
                        cat > "$SUITCASE_DIR"/bin/python3 <<PYTHON_WRAPPER
#!/bin/sh

export PYTHONPATH="$SUITCASE_DIR"/python-libs
exec $already_installed "\$@"
PYTHON_WRAPPER
                        chmod a+x "$SUITCASE_DIR"/bin/python3
                        check_python3_version
                        return 0
                    fi
                done
            fi
        done

        # System-provided Python 3 is absent or unsuitable; download one
        ensure_python_build_deps
        ensure_pyenv
        local version="$(set -- $SUITCASE_PYTHON_VERSIONS; echo "$1")"
        if ! run_pyenv versions |grep -w "$version"; then
            run_pyenv install "$version"
        fi

        ensure_symlink "pyenv/versions/$version" "$SUITCASE_DIR"/python
        ensure_symlink "../python/bin/python3" "$SUITCASE_DIR"/bin/python3
    fi

    check_python3_version
}


ensure_pip () {
    ensure_python3
    # This is python 3; there is bound to be *a* pip in the same directory.
    # However, we want to upgrade it first e.g. because of
    # https://stackoverflow.com/a/67631115/435004
    if [ ! -e "$SUITCASE_DIR"/python-libs/bin/pip3 ]; then
        "$SUITCASE_DIR"/python/bin/pip3 install -t "$SUITCASE_DIR/python-libs" pip
    fi
    cat > "$SUITCASE_DIR"/bin/pip3 <<PIP_WRAPPER
#!/bin/sh

export PYTHONPATH="$SUITCASE_DIR"/python-libs
case "\$1" in
     install)
       shift
       exec "$SUITCASE_DIR"/python-libs/bin/pip3 install -t "$SUITCASE_DIR"/python-libs "\$@" ;;
     *)
       exec "$SUITCASE_DIR"/python-libs/bin/pip3 "\$@" ;;
esac

PIP_WRAPPER
    chmod a+x "$SUITCASE_DIR"/bin/pip3

    check_version pip "$("$SUITCASE_DIR"/bin/pip3 --version | sed 's/^pip \([^ ]*\).*/\1/')"
}

ensure_pip_deps () {
    ensure_pip_dep cryptography --prefer-binary
    for dep in $SUITCASE_PIP_EXTRA; do
        ensure_pip_dep "$dep"
    done
}

ensure_pip_dep () {
    ensure_pip
    install_dir="$SUITCASE_DIR/python-libs"
    ensure_dir "$install_dir"
    if "$SUITCASE_DIR"/bin/pip3 install "$@"; then
        satisfied "pip-$1"
    else
        unsatisfied "pip-$1"
    fi
}

ensure_ansible () {
    if [ ! -x "$(readlink "$SUITCASE_DIR/bin/ansible")" -o \
         ! -x "$(readlink "$SUITCASE_DIR/bin/ansible-playbook")" ]; then
        ensure_pip_dep ansible=="${SUITCASE_ANSIBLE_VERSION}" --upgrade
        ensure_dir "$SUITCASE_DIR/bin"
        for executable in ansible ansible-playbook ansible-galaxy; do
            sed -e "1 s|.*|#!$SUITCASE_DIR/bin/python3|" < "$SUITCASE_DIR"/python-libs/bin/$executable \
                > "$SUITCASE_DIR/bin/$executable"
            chmod a+x "$SUITCASE_DIR/bin/$executable"
        done
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
        ensure_ruby_build_deps
        ensure_rbenv
        local rbenv_version_dir="rbenv/versions/$version"
        if [ ! -d "$SUITCASE_DIR/$rbenv_version_dir" ]; then
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
    if [ -d /keybase/team/ ]; then
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

ensure_git () {
    if ! which git >/dev/null; then
        fatal "Error: git is required to proceed. Please install git and try again."
    fi
}

ensure_cc () {
    if ! which gcc >/dev/null; then
        echo "Error: a C compiler toolchain is required to proceed. Please install one and try again." >&2
        exit 1
    fi
}

ensure_python_build_deps () {
    local missing_packages install_command

    case "$(uname -s)" in
        Linux)
            # https://github.com/saghul/pythonz#before-installing-python-versions-via-pythonz
            case "$(lsb_release -s -i)" in
                Ubuntu|Debian)
                    install_command="apt install"
                    for pkg in build-essential zlib1g-dev libbz2-dev libssl-dev libreadline-dev libncurses5-dev libsqlite3-dev libgdbm-dev libdb-dev libexpat1-dev libpcap-dev liblzma-dev libpcre3-dev libffi-dev; do
                        if ! dpkg --get-selections |cut -f1|grep $pkg; then
                            missing_packages="$missing_packages $pkg"
                        fi
                    done ;;
                RedHat*|CentOS*)
                    install_command="yum install"
                    for pkg in zlib-devel bzip2-devel openssl-devel readline-devel ncurses-devel sqlite-devel gdbm-devel db4-devel expat-devel libpcap-devel xz-devel pcre-devel libffi-devel; do
                        if ! rpm -q $pkg; then
                            missing_packages="$missing_packages $pkg"
                        fi
                    done;;
            esac ;;
    esac
    if [ -n "$missing_packages" ]; then
        if [ -n "$install_command" ]; then
            warn "Please confirm running the following command to install missing build dependencies:"
            if ! confirm_sudo $install_command $missing_packages; then
                fatal "Please install the missing packages by hand: $missing_packages"
            fi
        else
            fatal "Please install the missing packages: $missing_packages"
        fi
    fi
    ensure_cc
}

# On Ubuntu, libreadline-dev is required to compile the Ruby readline extension.
ensure_ruby_build_deps () {
    case "$(uname -s)" in
        Linux)
            if [ ! -f "/usr/include/readline/readline.h" ]; then
                echo -e "\nError: Please install libreadline-dev (e.g. sudo apt-get install -y libreadline-dev)"
                exit 1
            fi ;;
    esac
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
    case "$(read answer)" in
        y*|Y*) sudo "$@" ;;
        *) return 1 ;;
    esac
}

main
