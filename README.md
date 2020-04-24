# Ansible suitcase

Install Ansible and its dependency stack into a temporary directory.
No need to change anything in your `~/.whateverrc`, nor to install
anything as root.

## Usage

From your `foosible` wrapper script, do something like this:

```
platform_check () {
    if ! test -f ansible-tmp/.versions 2>/dev/null; then
        curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/install.sh | \
            SUITCASE_DIR=$PWD/ansible-tmp SUITCASE_ANSIBLE_REQUIREMENTS=requirements.yml sh -x
    fi
    export PATH="$PWD/ansible-tmp/bin:$PATH"
    export ANSIBLE_ROLES_PATH="$PWD/ansible-tmp/roles"
}
```

where

- `$PWD/ansible-tmp` is the directory that `ansible.suitcase` will install into. (You can pick any path you like, even outside your “ops” Git depot if you like.)
- `SUITCASE_DIR` and `SUITCASE_ANSIBLE_REQUIREMENTS` are parameters to the `install.sh` script. See the source code of [`install.sh`](./install.sh) for a list of these.
- `ansible-tmp/.versions` is a file that will only be created when the install is complete; you can use it as a stamp file so as to avoid `curl`ing the script again.
- `PATH` and `ANSIBLE_ROLES_PATH` are altered to hook into the suitcase output directory. Again, look into the source code of `install.sh` for the directory structure below the suitcase directory.
