# Ansible suitcase

Install Ansible and its dependency stack into a temporary directory.
No need to change anything in your `~/.whateverrc`, nor to install
anything as root.

## Usage

From your `foosible` wrapper script:

```
curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/install.sh | SUITCASE_DIR=$PWD/ansible-tmp sh -x
```

Or, if you want to spare the network round-trip after the install
procedure completes:

```
platform_check () {
    test -f ansible-tmp/.versions 2>/dev/null && return 0
    curl https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/install.sh | SUITCASE_DIR=$PWD/ansible-tmp sh -x
}
```

Then, execute Ansible and eyaml from the install directory, e.g.

```
export PATH="$PWD/ansible-tmp/bin:$PATH"
```
