# Useful functions for projects using the Ansible suitcase

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

read_interactive () {
    if [ ! -t 0 ]; then return 0; fi
    local prompt="$1"; shift
    local var_to="$1"; shift
    local default newval

    case "$#" in
        0)  default="$(eval echo '$'"$var_to")" ;;
        1)  default="$1" ;;
    esac
    echo -n "$prompt [$default]: "
    read newval
    if [ -n "$newval" ]; then
        eval "$var_to='$newval'"
    else
        eval "$var_to='$default'"
    fi

    case "$(echo '$'"$var_to")" in
        "") fatal "No value for $var_to" ;;
        *) return 0 ;;
    esac
}


ensure_tkgi () {
    local clustername="$1"; shift

    export KUBECONFIG="$(suitcase_dir)/kubeconfig/kubeconfig"
    mkdir -p "$(dirname "$KUBECONFIG")" 2>/dev/null || true

    if [ "$(kubectl config current-context 2>/dev/null)" != "$clustername" ]; then
        ensure_tkgi_command
        do_login_tkgi "$clustername" -a "$1" --ca-cert "$2"
    fi

    case "$(kubectl get pods -n default 2>&1)" in
        *unauthorized*) do_login_tkgi "$clustername" -a "$1" --ca-cert "$2" ;;
    esac

    if [ "$(kubectl config current-context)" != "$clustername" ]; then
        fatal "Unable to retrieve credentials for $clustername"
    fi
}

ensure_tkgi_command () {
    which tkgi >/dev/null 2>&1 || \
        fatal 'Please install the `tkgi` command in your PATH.'
}

do_login_tkgi () {
    local clustername="$1"; shift
    warn "Please log in to TKGI cluster $clustername using your GASPAR credentials"
    read_interactive "GASPAR username" USERNAME "$(whoami)"
    tkgi get-kubeconfig "$clustername" -u $USERNAME "$@"

    # Tanzu SR 22333578705: the OIDC! It no works!!
    (while IFS= read line; do
         case "$line" in
             *idp-certificate-authority-data*)
                 if (which openssl && which base64) >/dev/null 2>&1; then
                     case "$(echo "$line" | sed 's/.*idp-certificate-authority-data: //' | \
                             base64 -d | openssl x509 -noout -purpose)" in
                         *"SSL server CA : No"*)
                             ;;  # Skip that line
                         *)
                             echo "$line" ;;
                     esac
                 else
                     : # Just skip the line - Itstheonlywaytobesure.png
                 fi ;;
             *)
                 echo "$line" ;;
         esac
     done) < "$KUBECONFIG" > "$KUBECONFIG.cleaned"
    mv "$KUBECONFIG.cleaned" "$KUBECONFIG"

    kubectl config use-context "$clustername"
}

ensure_oc_login () {
  if ! oc projects >/dev/null 2>&1; then
    echo "Please login to openshift:"
    oc login
  fi
}

suitcase_dir () {
    # Careful not to quote $SUITCASE_DIR, as `install.sh` will substitute it
    # at suitcase install time:
    echo $SUITCASE_DIR
}

ensure_ansible_runtime () {
    export PATH="$(suitcase_dir)/bin:$PATH"

    # https://github.com/ansible/ansible/issues/32499, https://bugs.python.org/issue35219
    case "$(uname -s)" in
        Darwin) export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ;;
    esac
}

ensure_confined_helm () {
    export HELM_CACHE_HOME="$(suitcase_dir)"/helm/cache
    export HELM_CONFIG_HOME="$(suitcase_dir)"/helm/config

    for dir in "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
}

ansible_flag_set_var_git_current_branch () {
    git_current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    case "$git_current_branch" in
        "") : ;;
        *) echo "-e git_current_branch=$git_current_branch" ;;
    esac
}

ansible_flag_set_var_caller_pwd () {
   echo "-e $1=$OLDPWD"
}

ansible_flag_set_var_homedir () {
   echo "-e $1=$PWD"
}

ansible_flag_set_var_suitcase_python_interpreter () {
    echo "-e $1=$(suitcase_dir)"/bin/python3-shim
}
