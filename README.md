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


## List of projects that use `foosible`

* [botsible](https://github.com/SaphireVert/gitlabot/blob/master/ansible/botsible)
* [elasticsible](https://github.com/epfl-si/search_inside/blob/main/ansible/elasticsible)
* [elsible](https://gitlab.epfl.ch/cangiani/esign-ops/-/blob/master/elsible)
* [exportsible](https://github.com/epfl-si/infoscience-exports/blob/master/ansible/exportsible)
* [foresible](https://github.com/epfl-si/idevfsd.foreman/blob/master/foresible)
* [gitsible](https://gitlab.com/epfl-idevfsd/gitlab-docker/-/blob/master/ansible/gitsible)
* [gosible](https://gitlab.com/epfl-idevfsd/go-epfl/-/blob/feature/gosible/ansible/gosible)
* [isasible](https://github.com/epfl-si/isa-monitoring/blob/master/ansible/isasible)
* [lhdsible](https://gitlab.epfl.ch/lhd/ops/-/blob/master/lhdsible)
* [nocsible](https://github.com/epfl-si/external-noc/blob/master/ansible/nocsible)
* [rccsible](https://github.com/epfl-si/rcc/blob/master/ansible/rccsible)
* [tulsible](https://github.com/epfl-si/ops.tuleap/blob/master/tulsible)
* [wisible](https://gitlab.epfl.ch/si-idevfsd/wikijs-ops/-/blob/master/wisible)
* [wpsible](https://github.com/epfl-si/wp-ops/blob/master/ansible/wpsible)


## FAQ

### Q: Is there a simple project that uses this, that I could take a look at?

A: [Here you go.](https://github.com/epfl-si/ops.tuleap/tree/ansible-starterpack)

### Q: How do I operate a suitcase-based project, as a DevOps engineer?

A: [See USERS-GUIDE.md](USERS-GUIDE.md)
