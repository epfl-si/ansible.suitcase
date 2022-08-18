# Putting the Ansible Suitcase to Work in your Project: A Cookbook

## Preramble

**Proficiency in bash shell scripting is assumed from here on below.** It is assumed you know what the closing keywords for `if` and `case` are; what `$#` or `$(foo)` mean; in which kind of (perhaps nested) quotes they do or do not work; and so on. Employing [bash arrays](https://gist.github.com/magnetikonline/0ca47c893de6a380c87e4bdad6ae5cf7) is fair game, as this is not 1998 anymore.

## Starter Kit

**💡 One does not simply fork or copy the suitcase source into one's own Git project.**

The recommended way to use the suitcase is through a `foosible` shell wrapper that downloads the suitcase (once) and executes it (every time). Here is an annotated example:

```
#!/bin/bash

set -e  # ①
cd "$(cd "$(dirname "$0")"; pwd)"  #  ②

help () {  # ③
    fatal <<HELP_MSG
Usage:

  $0 [ -t sometag ] [ ... ]
HELP_MSG
}

ensure_ansible () {    # ④
    if ! test -f ansible-deps-cache/.versions 2>/dev/null; then  # ⑤
        curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/install.sh | \
            SUITCASE_DIR=$PWD/ansible-deps-cache \
            SUITCASE_ANSIBLE_VERSION=3.4.0 \
            bash -x
    fi
    export PATH="$PWD/ansible-deps-cache/bin:$PATH"  # ⑥
    export ANSIBLE_ROLES_PATH="$PWD/ansible-deps-cache/roles"
    export ANSIBLE_COLLECTIONS_PATHS="$PWD/ansible-deps-cache"

    . ansible-deps-cache/lib.sh  #  ⑦
}

ensure_ansible
[ "$1" == "--help" ] && help
# ⑧
ansible-playbook -i inventory.yml playbook.yml "$@"
```

①
: This tells bash to apply modern error management. [See above](#preramble) about proficiency required, not 1998 anymore.

②
: The first thing the wrapper script does is to `chdir()` into the directory it lives in, so that lines such as ⑦ below work without further ado. It is important to do so in a single `cd` command (so that if you wish to remember the caller's working directory for any reason, you can use `$OLDPWD`); and to [portably bypass any symlink shenanigans](https://stackoverflow.com/a/60625224/435004) (avoiding the use of the `realpath` command, which may not exist on vanilla Mac OS X).

③
: This is where you put the minimum amount of info for the intern to figure out how to use the `foosible` script. Although that is a matter of taste, keeping the `help()` function as close as possible to the top of the script will also help people who don't run unknown commands to see what they do, even with `--help`. If you wonder where the `fatal` function comes from, see ⑦.

④
: The `ensure_ansible()` function, as the name implies, ensures that Ansible is up and running in `./ansible-deps-cache`. There is an install-time (once) part to that job (⑤, see below) and a run-time (everytime) part (⑥).<br/>💡 Feel free to search-n'replace the `ansible-deps-cache` path to suit your preferences e.g. `tmp/ansible`; but do not attempt to use e.g. `$HOME/.suitcase`, as the Ansible suitcase doesn't support sharing (even parts of) its runtime between projects.

⑤
: This `if` ... `fi` block is the idempotent operation that installs the suitcase by running it as a shell script downloaded from GitHub on-the-spot. That is, unless `ansible-deps-cache/.versions` already exists, which is the stamp file that the suitcase creates upon successful installation. One can configure a variety of parameters through environment variables, as documented in the comments [at the top of the suitcase's `install.sh`](./install.sh).

⑥
: In order to use the installed suitcase, a couple of environment variables must be set, most notably `$PATH` so that the wrapper script picks up the right `ansible`, `ansible-playbook` etc. executables. The other two variables only matter for the `SUITCASE_ANSIBLE_REQUIREMENTS` feature, but it doesn't hurt to throw them in even if you don't (yet) have a [`requirements.yml` file](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html#installing-roles-and-collections-from-the-same-requirements-yml-file).

⑦
: The suitcase comes with [a small run-time shell library](./lib.sh) with a few handy functions such as `fatal` (but also `warn`, `read_interactive` and more), which your wrapper script may want to call.

⑧
: ... And that's pretty much it.

## A `--prod` flag

If you still don't trust Ansible enough to let the intern mess with production through it (until such time that you reveal the secret flag to them!), here's something you could do:

1. Teach your `foosible` wrapper to parse the command line, for instance: <pre>
declare -a ansible_args
inventory_mode="test"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help)
      help ;;
    --prod)
      inventory_mode="test-and-prod"
      shift ;;
    *)
      ansible_args+=("$1")
      shift ;;
  esac
done</pre>
2. Change `-i inventory.yml` on the last line into a function invocation (and `"$@"` into `"${ansible_args[@]}"`), e.g.<pre>
ansible-playbook -i $(inventories) playbook.yml "${ansible_args[@]}"</pre>
3. Write `inventories` as a shell function e.g. like this:<pre>
inventories () {
  case "$inventory_mode" in
    test)          echo "-i inventory/test.yml" ;;
    test-and-prod) echo "-i inventory/test.yml -i inventory/prod.yml" ;;
  esac
}</pre>
4. Rearrange your Ansible inventory by splitting it into `inventory/test.yml` and `inventory/prod.yml`

## Using the suitcase's Python for your local tasks

If one (or more) of your inventory targets is something like a Kubernetes cluster (not a “real” host that Ansible reaches over ssh), you will probably want to use the `local` [connection plugin](https://docs.ansible.com/ansible/latest/plugins/connection.html#plugin-list), which you can do right from the `inventory.yml` file like this:

```
all:
  hosts:
    # Arguably not a host, but it plays one on TV
    my-kubernetes:
      ansible_connection: local
```

In such a case, you will want to exert control on [`ansible_python_interpreter`](https://docs.ansible.com/ansible/latest/reference_appendices/interpreter_discovery.html) so that the “remote” Python that Ansible invokes for tasks is the one inside the suitcase, it being conveniently guaranteed to have access to the `SUITCASE_PIP_EXTRA` packages (like, typically, [`kubernetes`](https://pypi.org/project/kubernetes/)):

```
all:
  hosts:
    # Arguably not a host, but it plays one on TV
    my-kubernetes:
      ansible_connection: local
      ansible_python_interpreter: "{{ foosible_suitcase_dir }}/bin/python3"
```

If you have INI-style inventory, and despite the lack of a text quoting feature in that case, you could make it work by squeezing out all the whitespace from inside the mustaches, like this:

```
[all]
my-kubernetes      ansible_connection=local  ansible_python_interpreter={{foosible_suitcase_dir}}/bin/python3
```

Naturally, in both cases you will need to teach the wrapper script to pass a suitably set `foosible_suitcase_dir` variable into Ansible: either

```
ansible-playbook -i inventory.yml playbook.yml -e foosible_suitcase_dir="$PWD/ansible-deps-cache" "$@"
```

or (if you have `ansible_args` as per the previous recipe)

```
declare -a ansible_args
ansible_args=(-e "foosible_suitcase_dir=$PWD/ansible-deps-cache")
```

should do the trick.
