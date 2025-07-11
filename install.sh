#!/bin/sh

# Pure Bourne-shell script to install Ansible and the EPFL-SI devops
# tool suite into a self-contained directory
#
# Environment variables:
#
# $SUITCASE_DIR (mandatory)       Where to install the goods to
#
# $SUITCASE_ANSIBLE_VERSION       The precise version of Ansible to use.
# (mandatory)
#
# $SUITCASE_PYTHON_VERSIONS       Obsolete, do not use.
#
# $SUITCASE_RUBY_VERSIONS         Obsolete, do not use.
#
# $SUITCASE_PIP_EXTRA             Additional modules to install with `pip install`
#                                 (separated with spaces)
#
# $SUITCASE_PIP_SHIMS             Additional shell wrappers (shims) to create
#                                 for scripts installed by Pip (under
#                                 python-libs/bin). Wildcards are
#                                 allowed. The default is to make shims
#                                 for `ansible*` scripts only.
#
# $SUITCASE_ANSIBLE_REQUIREMENTS  If set, shall point to a requirements.yml
#                                 file
#
# $SUITCASE_WITH_KEYBASE          1 (the default) means to check for Keybase being
#                                 present (we obviously can't just install it). 0 means
#                                 that the calling Ansible project doesn't require Keybase.
#
# $SUITCASE_WITH_KBFS             1 (the default) means to check for the /keybase
#                                 directory (we obviously can't just install
#                                 it). 0 means that the calling Ansible project
#                                 uses `keybase fs read` and doesn't use
#                                 /keybase directly.
#
# $SUITCASE_WITH_EYAML            1 means to install EYAML (which requires Ruby). 0 (the
#                                 default) means that the calling Ansible project doesn't
#                                 require EYAML nor Ruby.
#
# $SUITCASE_WITH_HELM             1 means to install the helm command-line tool. 0 (the
#                                 default) means your project doesn't require
#                                 helm or any of the `kubernetes.core.helm*`
#                                 tasks.
#
# $SUITCASE_HELM_VERSION          The version of Helm to use if SUITCASE_WITH_HELM=1.
#                                 By default, install the latest release in major version 3.
#
# $SUITCASE_WITH_KUBECTL          1 means to install the kubectl
#                                 command-line tool. 0 (the default)
#                                 means your project doesn't require
#                                 kubectl (or any of the
#                                 `kubernetes.core.kustomize*` tasks).
#
# $SUITCASE_KUBECTL_VERSION       The version of kubectl to use if
#                                 SUITCASE_WITH_KUBECTL=1. By
#                                 default, install the latest stable
#                                 release.
#
# $SUITCASE_NO_KEYBASE            Obsolete alias for SUITCASE_WITH_KEYBASE=0
# $SUITCASE_NO_EYAML              Obsolete alias for SUITCASE_WITH_EYAML=0
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
#                             be installed there.
#
#   pyenv/                    Various support directories
#   pyenv/bin/
#   python/
#   python/bin/
#   eyaml/
#
# Additional checks and requirements:
#
# - Keybase - The script will test for it (unless [ $SUITCASE_WITH_KEYBASE = 0 ]),
#   but obviously will not install it in your stead.

: ${SUITCASE_WITH_EYAML:=0}
: ${SUITCASE_WITH_KEYBASE:=1}
: ${SUITCASE_WITH_KBFS:=1}
: ${SUITCASE_WITH_HELM:=0}
: ${SUITCASE_WITH_KUBECTL:=0}

if [ -n "$SUITCASE_NO_EYAML" ]; then SUITCASE_WITH_EYAML=0; fi
if [ -n "$SUITCASE_NO_KEYBASE" ]; then SUITCASE_WITH_KEYBASE=0; fi

set -e

satisfied=
unsatisfied=

main () {
    ensure_suitcase_ansible_version_set
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
    if [ -n "$SUITCASE_PIP_SHIMS" ]; then
        ensure_pip_shims "$SUITCASE_PIP_SHIMS"
    fi
    ensure_ansible || unsatisfied ansible

    if [ "$SUITCASE_WITH_KEYBASE" != 0 ]; then
      ensure_keybase || unsatisfied keybase
    fi
    if [ "$SUITCASE_WITH_EYAML" != 0 ]; then
      case "$unsatisfied" in
          ruby|"ruby "*|*" ruby"|*" ruby "*)
              warn "No Ruby available; skipping eyaml installation" ;;
          *) ensure_eyaml || unsatisfied eyaml ;;
      esac
    fi

    if [ "$SUITCASE_WITH_HELM" != 0 ]; then
        ensure_helm || unsatisfied helm
    fi
    if [ "$SUITCASE_WITH_KUBECTL" != 0 ]; then
        ensure_kubectl || unsatisfied kubectl
    fi

    ensure_lib_sh

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

ensure_suitcase_ansible_version_set () {
    # https://github.com/epfl-si/ansible.suitcase/issues/7
    if [ -z "$SUITCASE_ANSIBLE_VERSION" ]; then
        case "/$0" in
            */botsible)
                # https://github.com/SaphireVert/gitlabot/issues/10
                SUITCASE_ANSIBLE_VERSION=3.4.0 ;;
            */ictsible)
                # https://github.com/ponsfrilus/ict-bot/issues/55
                SUITCASE_ANSIBLE_VERSION=3.4.0 ;;
            */presensible)
                # https://github.com/epfl-fsd/presence_bot/issues/30
                SUITCASE_ANSIBLE_VERSION=3.4.0 ;;
            *)
                fatal <<'PLEASE_SET_SUITCASE_ANSIBLE_VERSION'
Please set SUITCASE_ANSIBLE_VERSION upon invoking the suitcase, e.g.

curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/install.sh | \
   SUITCASE_ANSIBLE_VERSION=3.4.0 sh -x
      
PLEASE_SET_SUITCASE_ANSIBLE_VERSION
                ;;
        esac
    fi
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

ensure_pyenv () {
    local pyenv_root="$SUITCASE_DIR/pyenv"
    if [ ! -x "$pyenv_root/bin/pyenv" ]; then
        rm -rf "$pyenv_root"
        curl https://pyenv.run | PYENV_ROOT="$pyenv_root" bash
    fi

    check_version pyenv "$(set +x; run_pyenv 2>&1 | head -1 |cut -d' ' -f2)"
}

ensure_ansible_requirements () {
    if grep "^roles:" "$1"; then
      ensure_dir "$SUITCASE_DIR/roles"
      "$SUITCASE_DIR"/bin/ansible-galaxy role install --force -p "$SUITCASE_DIR/roles" -i -r "$1"
    fi
    if grep '^collections:' "$1"; then
        "$SUITCASE_DIR"/bin/ansible-galaxy collection install --force -p "$SUITCASE_DIR" -i -r "$1"
    fi
}

run_pyenv () {
    env PYENV_ROOT="$SUITCASE_DIR/pyenv" PATH="$SUITCASE_DIR/pyenv/bin:$PATH" \
        "$SUITCASE_DIR"/pyenv/bin/pyenv "$@"
}

is_python_compatible_with_ansible () {
    local python_binary="$1"
    local version="$("$python_binary" --version | sed 's/Python //')"
    case "$version/$SUITCASE_ANSIBLE_VERSION" in
        3.12*/[45]*) warn <<BLACKLISTED_PYTHON ; return 1 ;;
===================================================================================

Fatal: Python 3.12 is *not* compatible with old Ansibles. Please downgrade to 3.11,
or upgrade Ansible.

See: https://github.com/ansible/ansible/issues/81946


===================================================================================
BLACKLISTED_PYTHON
    esac
    return 0
}


windows_python () {
    local python
    for python in python3 python; do
        python="$(which "$python" 2>/dev/null)"
        if [ -n "$python" ] && is_python_compatible_with_ansible "$python"; then
            echo "$python"
            return 0
        fi
    done

    fatal <<'PLEASE_INSTALL_PYTHON_YOURSELF'
Python 3 is required for ansible-suitcase.

Please install it with e.g.

   choco install python3


PLEASE_INSTALL_PYTHON_YOURSELF
}


ensure_python3_shim () {
    ensure_dir "$SUITCASE_DIR/bin"

    if is_windows; then
        make_python3_shim "$(windows_python)"
        return 0
    fi

    if [ ! -x "$SUITCASE_DIR"/bin/python3 ]; then

        # Prefer already-installed version, if available
        for already_installed in $(which -a python3) /usr/local/bin/python3 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.11 /usr/bin/python3; do
            if [ ! -x "$already_installed" ]; then continue; fi
            case "$already_installed" in
                *pyenv*) continue ;;
            esac
            version="$($already_installed --version 2>&1)"
            case "$version" in
                Python*)
                    is_python_compatible_with_ansible "$already_installed" 2>/dev/null || continue

                    make_python3_shim "$already_installed"
                    
                    return 0 ;;
            esac
        done

        # System-provided Python 3 is absent or defective; download one
        ensure_python_build_deps
        ensure_pyenv
        run_pyenv install --list
        run_pyenv install $(run_pyenv install --list | grep '^ *3[0-9.]*$' | tail -1)

        make_python3_shim "../python/bin/python3"
    fi

    # Re-check unconditionnally (and this time, show the error message and
    # bail out in case of failure):
    is_python_compatible_with_ansible "$SUITCASE_DIR"/bin/python3
}

make_python3_shim () {
    cat > "$SUITCASE_DIR"/bin/python3 <<PYTHON3_SHIM
#!/bin/sh

export PYTHONPATH='$(pip_install_dir "$1"| as_os_path)$(os_path_sep)'
export SSL_CERT_FILE='$$SUITCASE_DIR'/python-libs/lib/python/site-packages/certifi/cacert.pem
exec "$1" "\$@"

PYTHON3_SHIM
    chmod a+x "$SUITCASE_DIR"/bin/python3
}

python_user_base () {
    # This is something we decide, and that we try to tell Pip to obey (see
    # ensure_pip() below);
    echo "$SUITCASE_DIR"/python-libs
}

pip_install_dir () {
    # Unlike python_user_base(), we must second-guess the suffix part.
    # Do so like pip/_internal/locations/_distutils.py does (which is
    # itself based on distutils.command.install from Python's standard
    # library):
    local python
    if [ -n "$1" ] ;  then
        # For when the caller (i.e. `make_python3_shim`) is the one telling us
        # which Python to use:
        python="$1"
    elif is_windows; then
        python="$(windows_python)"
    else
        python="$SUITCASE_DIR/bin/python3"
    fi
    "$python" -c "import site; suffix=site.USER_SITE[len(site.USER_BASE):]; print('''$(python_user_base)''' + suffix)"
}

suitcase_pythonpath () {
    pip_install_dir | as_os_path
}

as_os_path () {
    if is_windows; then
        sed -E 's|^/([a-zA-Z])/|\U\1:/|; s|/|\\|g'
    else
        cat
    fi
}

os_path_sep () {
    if is_windows; then
        echo ";"
    else
        echo ":"
    fi
}

ensure_pip () {
    ensure_python3_shim
    ensure_dir "$(pip_install_dir)"
    if ! "$SUITCASE_DIR"/bin/python3 -m pip >/dev/null 2>&1; then
        fatal <<EOF
Please install Pip for Python 3 using your distribution's package manager.
EOF
    fi
    # We want to upgrade pip first e.g. because of
    # https://stackoverflow.com/a/67631115/435004
    if [ ! -e "$SUITCASE_DIR"/bin/pip3 ]; then
        # Older pip3's don't honor PYTHONUSERBASE. Lame
        env PYTHONPATH="$(suitcase_pythonpath)$(os_path_sep)" "$SUITCASE_DIR"/bin/python3 -m pip install -t "$(pip_install_dir)" pip
    fi

    cat > "$SUITCASE_DIR"/bin/pip3 <<PIP_SHIM
#!/bin/sh

export PATH="$(echo "$(python_user_base)/bin" | as_os_path)"$(os_path_sep)"\$PATH"
export PYTHONPATH='$(suitcase_pythonpath)$(os_path_sep)'
export PYTHONUSERBASE="$(python_user_base | as_os_path)"
# We actually don't, as we install into PYTHONUSERBASE:
export PIP_BREAK_SYSTEM_PACKAGES=1

case "\$1" in
  install)
    exec "$SUITCASE_DIR/bin/python3" -m pip "\$@" --user -I ;;
  *)
    exec "$SUITCASE_DIR/bin/python3" -m pip "\$@" ;;
esac

PIP_SHIM
    chmod a+x "$SUITCASE_DIR"/bin/pip3

    check_version pip "$("$SUITCASE_DIR"/bin/pip3 --version | sed 's/^pip \([^ ]*\).*/\1/')"
}

ensure_pip_deps () {
    ensure_pip
    # https://stackoverflow.com/questions/74981558: be sure to upgrade
    # pyOpenSSL even if all we want is the cryptography module. Also,
    # preferring binaries affords the suitcase a chance to work on
    # workstations without OpenSSL's development kit.
    ensure_pip_dep pyOpenSSL -U --prefer-binary

    for dep in $SUITCASE_PIP_EXTRA; do
        ensure_pip_dep "$dep"
    done
}

ensure_pip_dep () {
    if check_pip_dep "$1"; then
        satisfied "pip-$1"
        return
    fi
    if "$SUITCASE_DIR"/bin/pip3 install "$@"; then
        satisfied "pip-$1"
    else
        unsatisfied "pip-$1"
    fi
}

check_pip_dep () {
    local requirement=$1
    case "$requirement" in
        *==*)
            local pkg="$(echo "$requirement" | cut -f1 -d=)"
            local version="$(echo "$requirement" | cut -f3- -d=)"
            "$SUITCASE_DIR"/bin/pip3 show "$pkg" | grep -q "Version: $version"
            ;;
        *)
            "$SUITCASE_DIR"/bin/pip3 show "$1" >/dev/null
            ;;
    esac
}

ensure_pip_shims () {
    local executable

    if [ -d "$SUITCASE_DIR"/python-libs/bin ]; then     # Linux, Mac OS
        for executable in $(cd "$SUITCASE_DIR"/python-libs/bin; ls -1 $*); do
            ensure_pip_shim "$executable" "$SUITCASE_DIR"/python-libs/bin/"$executable"
        done
    elif [ -d "$SUITCASE_DIR"/python-libs/*/Scripts ]; then     # Windows (Git bash)
        local targetdir="$(echo "$SUITCASE_DIR"/python-libs/*/Scripts)"
        for executable in $(cd "$targetdir"; ls -1 $*.exe); do
            ensure_pip_shim "$(basename "$executable" ".exe")" "$targetdir/$executable"
        done
    else
        fatal "Don't know how to make Pip shims!"
    fi
}

ensure_pip_shim () {
    local shim_path="$SUITCASE_DIR/bin/$1"
    cat > "$shim_path" <<PIP_SCRIPT_SHIM
#!/bin/sh

export PYTHONPATH='$(suitcase_pythonpath)$(os_path_sep)'
exec "$SUITCASE_DIR"/bin/python3 "$2" "\$@"
PIP_SCRIPT_SHIM

    chmod a+x "$shim_path"
}

ensure_ansible () {
    if [ ! -x "$(readlink "$SUITCASE_DIR/bin/ansible")" -o \
         ! -x "$(readlink "$SUITCASE_DIR/bin/ansible-playbook")" ]; then
        ANSIBLE_SKIP_CONFLICT_CHECK=1 ensure_pip_dep ansible=="${SUITCASE_ANSIBLE_VERSION}" --upgrade
        ensure_dir "$SUITCASE_DIR/bin"
    fi

    ensure_ansible_shims "ansible*"
    check_version ansible "$("$SUITCASE_DIR/bin/ansible" --version | head -1 | sed 's/ansible //')"
}

ensure_ansible_shims () {
    local executable

    if [ -d "$SUITCASE_DIR"/python-libs/bin ]; then     # Linux, Mac OS
        for executable in $(cd "$SUITCASE_DIR"/python-libs/bin; ls -1 $*); do
            ensure_ansible_shim "$executable" "$SUITCASE_DIR"/python-libs/bin/"$executable"
        done
    elif [ -d "$SUITCASE_DIR"/python-libs/*/Scripts ]; then     # Windows (Git bash)
        local targetdir="$(echo "$SUITCASE_DIR"/python-libs/*/Scripts)"
        for executable in $(cd "$targetdir"; ls -1 $*.exe); do
            ensure_ansible_shim "$(basename "$executable" ".exe")" "$targetdir/$executable"
        done
    else
        fatal "Don't know how to make Ansible shims!"
    fi
}

ensure_ansible_shim () {
    local shim_path="$SUITCASE_DIR/bin/$1"
    cat > "$shim_path" <<ANSIBLE_COMMAND_SHIM
#!/bin/sh

export PYTHONPATH='$(suitcase_pythonpath)$(os_path_sep)'
export ANSIBLE_ROLES_PATH="$(echo "$SUITCASE_DIR/roles" | as_os_path)"
export ANSIBLE_COLLECTIONS_PATH="$(echo "$SUITCASE_DIR" | as_os_path)"
exec "$SUITCASE_DIR"/bin/python3 "$2" "\$@"
ANSIBLE_COMMAND_SHIM
        chmod a+x "$shim_path"
}

is_windows () {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
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
    RBENV_ROOT="$SUITCASE_DIR/rbenv" \
              GEM_HOME= GEM_PATH= "$SUITCASE_DIR/rbenv/bin/rbenv" "$@"
}

rbenv_version () {
    ls -1 "$SUITCASE_DIR/rbenv/versions" | head -1
}

rbenv_gem_home () {
    echo "$SUITCASE_DIR/rbenv/versions/$(rbenv_version)"
}

run_gem_install () {
    RBENV_VERSION="$(rbenv_version)" \
                 GEM_HOME="$(rbenv_gem_home)" \
                 GEM_PATH= \
                 "$SUITCASE_DIR/rbenv/shims/gem" install "$@"
}

ensure_ruby () {
    if ! is_windows; then
        ensure_rbenv
    fi

    case "$(ruby --version)" in
        "ruby 3"*) : ;;
        "ruby 2"*) : ;;
        *) fatal <<EOF
Please install Ruby version 3.x into your PATH.
EOF
       ;;
    esac

    if ! is_windows; then

        already_installed_dir="$(which ruby | xargs dirname)"
        rbenv_system_dir="$SUITCASE_DIR"/rbenv/versions/rbenv-system
        ensure_dir "$rbenv_system_dir"/bin
        for cmd in ruby gem; do
            ensure_symlink  "$already_installed_dir/$cmd" "$rbenv_system_dir"/bin/$cmd
        done
        run_rbenv rehash

    fi
}

ensure_symlink () {
    # ⚠ Windows®-unfriendly (obviously)
    local from="$1"
    local to
    case "$2" in
        */) to="$2$(basename $1)" ;;
        *) to="$2" ;;
    esac
    rm -f "$to" 2>/dev/null || true
    ln -s "$from" "$to"
}

ensure_rbenv_shim () {
    local cmd="$1"

    ensure_dir "$SUITCASE_DIR/bin"
    local target="$SUITCASE_DIR"/bin/"$cmd"

    cat > "$target" <<RBENV_CMD_SHIM
#!/bin/sh

export RBENV_VERSION="$(rbenv_version)"
export GEM_HOME="$(rbenv_gem_home)"
export GEM_PATH="$(rbenv_gem_home)"
exec "$(rbenv_gem_home)/bin/ruby" "$(rbenv_gem_home)/bin/$cmd" "\$@"

RBENV_CMD_SHIM

    chmod 0755 "$target"
}

ensure_eyaml () {
    if ! is_windows; then
        if [ ! -x "$(readlink "$SUITCASE_DIR/bin/eyaml")" ]; then
            ensure_ruby

            if [ -z "$SUITCASE_EYAML_VERSION" ]; then
                local ruby_version="$("$SUITCASE_DIR"/rbenv/shims/ruby --version)"
                case "$ruby_version" in
                    "ruby 3"*)
                        SUITCASE_EYAML_VERSION="4.2.0" ;;
                    "ruby 2"*)
                        SUITCASE_EYAML_VERSION="3.2.0" ;;
                    *)
                        warn "Don't know what version of eyaml suits $ruby_version"
                        unsatisfied eyaml
                        return ;;
                esac
            fi

            run_gem_install hiera-eyaml -v "${SUITCASE_EYAML_VERSION}"
            # Temporary — Required for Ruby 3.4.0 and above, which
            # unbundled the `base64` gem (unbeknownst to `hiera-eyaml` as
            # of 2025-03...):
            run_gem_install base64
            ensure_rbenv_shim eyaml
        fi
        check_version eyaml "$("$SUITCASE_DIR/bin/eyaml" --version | sed -n 's/Welcome to eyaml \([a-z0-9.-]*\).*/\1/p')"
    fi
}

ensure_keybase () {
    if ! which keybase; then
        warn <<EOF
Keybase is not installed, cannot decipher and push secrets.
EOF
        unsatisfied keybase
    elif ! keybase whoami; then
        warn <<EOF
Please log into Keybase so as to be able to decipher secrets.
EOF
        unsatisfied keybase
    else
        satisfied keybase
    fi
}

ensure_kbfs () {
    if [ -d /keybase/team/ ]; then
        satisfied keybase
        return
    fi

    unsatisfied kbfs
    if [ "$(uname -s)" = "Darwin" ]; then
        for d in /Volumes/Keybase*; do
            if ! test -d "$d"; then
                warn <<EOF
Keybase is installed, but the $KEYBASE directory is not working.

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
    if ! is_windows; then
        ensure_cc
    fi   # Otherwise hope for the best 🤷
}

# On Ubuntu, libreadline-dev is required to compile the Ruby readline extension.
ensure_ruby_build_deps () {
    case "$(uname -s)" in
        Linux)
            if [ ! -f "/usr/include/readline/readline.h" ]; then
                echo -e "\nError: Please install libreadline-dev (e.g. sudo apt-get install -y libreadline-dev)"
                exit 1
            fi
            if [ ! -f "/usr/include/openssl/ssl.h" ]; then
                echo -e "\nError: Please install libssl-dev (e.g. sudo apt-get install -y libssl-dev)"
                exit 1
            fi ;;
    esac
}


ensure_lib_sh () {
    # Don't test for existence; always download it afresh, to avoid a
    # mismatched-versions hazard.

    local suitcase_dir_quoted
    suitcase_dir_quoted="'"$(echo "$SUITCASE_DIR" | sed "s|\(['/]\)|"'\\\1'"|g")"'"
    curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/lib.sh |
        sed 's/$SUITCASE_DIR/'"$suitcase_dir_quoted"'/g' > "$SUITCASE_DIR"/lib.sh
    if [ -f "$SUITCASE_DIR"/lib.sh ]; then
        satisfied libsh
    else
        unsatisfied libsh
    fi
}

ensure_helm () {
    ensure_dir "$SUITCASE_DIR/bin"
    ensure_dir "$SUITCASE_DIR/helm"

    local helm_args="--no-sudo"
    if [ -n "$SUITCASE_HELM_VERSION" ]; then
        helm_args="$helm_args --version=$SUITCASE_HELM_VERSION"
    fi

    curl --silent https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
        HELM_INSTALL_DIR="$SUITCASE_DIR/helm" \
        PATH="$(echo "$SUITCASE_DIR/helm"|as_os_path)$(os_path_sep)$PATH" \
        bash -x -- /dev/stdin $helm_args

    cat > "$SUITCASE_DIR"/bin/helm <<HELM_SHIM
#!/bin/sh

export HELM_CACHE_HOME="$(echo "$SUITCASE_DIR/helm" | as_os_path)"
export HELM_CONFIG_HOME="$(echo "$SUITCASE_DIR/helm" | as_os_path)"
export HELM_DATA_HOME="$(echo "$SUITCASE_DIR/helm" | as_os_path)"

exec "$SUITCASE_DIR/helm/helm" "\$@"

HELM_SHIM
    chmod a+x "$SUITCASE_DIR"/bin/helm
}

ensure_kubectl () {
    ensure_dir "$SUITCASE_DIR/bin"

    local arch="$(uname -m)"
    case "$arch" in
        x86_64) arch=amd64 ;;
    esac

    local os="$(uname -s | tr 'A-Z' 'a-z')"

    if [ -z "$SUITCASE_KUBECTL_VERSION" ]; then
        SUITCASE_KUBECTL_VERSION="$(curl https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    fi

    curl -o "$SUITCASE_DIR/bin/kubectl" \
         https://storage.googleapis.com/kubernetes-release/release/"$SUITCASE_KUBECTL_VERSION"/bin/"$os"/"$arch"/kubectl
    chmod a+x "$SUITCASE_DIR/bin/kubectl"

    check_version kubectl "$("$SUITCASE_DIR"/bin/kubectl version 2>/dev/null | sed -E -n 's/.*(Client |Git)Version:[ "]v([^"]*)"?.*/\2/p')"
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
