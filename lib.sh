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
    export KUBECONFIG=$PWD/ansible-deps-cache/kubeconfig/kubeconfig
    mkdir -p "$(dirname "$KUBECONFIG")" 2>/dev/null || true

    if [ "$(kubectl config current-context 2>/dev/null)" != "$clustername" ]; then
        ensure_tkgi_command
        read_interactive "GASPAR username" USERNAME "$(whoami)"
        (set -x; tkgi get-kubeconfig svc0176idevfsdkt0001 \
                      -u $USERNAME -a "$1" --ca-cert "$2")

        kubectl config use-context "$clustername"
    fi

    if [ "$(kubectl config current-context)" != "$clustername" ]; then
        fatal "Unable to retrieve credentials for $clustername"
    fi
}

ensure_tkgi_command () {
    which tkgi >/dev/null 2>&1 || \
        fatal 'Please install the `tkgi` command in your PATH.'
}

ensure_oc_login () {
  if ! oc projects >/dev/null 2>&1; then
    echo "Please login to openshift:"
    oc login
  fi
}
