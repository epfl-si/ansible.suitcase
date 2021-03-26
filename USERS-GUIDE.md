
# Common Usage Instructions

**💡 One does not simply clone the suitcase Git project and run it.**

These instructions are for DevOps operators who are using a project
based on the suitcase — Presumably through a shell script with a name
ending in `*sible` in an “ops” repository.

## Prerequisites

The `*sible` script in your project is a UNIX-compatible shell script,
which runs Ansible, which enforces a set of scripted postconditions
(laid out in one or more so-called [Ansible
playbooks](https://docs.ansible.com/ansible/latest/user_guide/playbooks_intro.html))
by connecting over ssh to targets in the project's [inventory](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html). Therefore:

- You must check out the desired your “ops” repository using Git. This assumes you have Git installed and configured;
- you must have a bash-like shell installed. This can be particularly challenging for Windows® users, hence why we provide [specific instructions](./windows/USERS-GUIDE-WINDOWS.md) for Windows® users;
- you must be able to `ssh` directly into all the nodes in the inventory, on a fully automated basis: no password, no passphrase, no prompts to accept server keys for unknown hosts (ditto: Windows® instructions [are provided](./windows/USERS-GUIDE-WINDOWS.md));
- you may need to have Keybase installed and set up, depending on the specifics of your project;
- and you must have Ansible and its dependencies installed. Thankfully, this precisely what the suitcase is for. (The other four points are on you.)

### Streamline public-key based ssh access to the target sytsem(s)

Ansible relies on password-less authentication being already set up onto each and every UNIX server you will be controlling using your project's playbook. Therefore:

1. Ensure that you have access to each server node; if not, request access through appropriate official channels (attaching your ssh public key to the request if appropriate)
1. If all you have is password-based access, use the `ssh-copy-id` command to deploy your public key and therefore avail yourself of password-less access (see [these instructions](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-2#step-three%E2%80%94copy-the-public-key))
1. If some of the nodes in the target system are in a cluster, or otherwise have routing restrictions (e.g. firewall rules preventing ssh access but from specific IPs), read up on [the `~/.ssh/config` file and the `ProxyJump` setting](https://www.redhat.com/sysadmin/ssh-proxy-bastion-proxyjump) and use that knowledge to create a suitable `~/.ssh/config` file on the Linux side
1. Communicate with your colleagues / read up on additional requirements as part of your project's documentation; these may avail you of ready-made `.ssh/config` sections, or other kinds of helpful advice
1. For each `nodeX`, do check that you can access a shell by typing just `ssh nodeX` at the command-line prompt(s) that you will be using (on Windows®, this means both from Powershell and from the WSL Linux command-line). If everything is set up correctly you should need no username, no password, and no additional commands (even for “double-jump” hosts behind some kind of firewall or head node).

### Keybase

A lot of the projects which use the Ansible suitcase also rely on Keybase to exchange secrets (e.g. database passwords) among DevOps teams. You therefore need to

1. [Download and install Keybase](https://keybase.io/download), preferably onto at least two different devices (e.g. your phone and your workstation)
1. Create an account for yourself
1. Interact with your colleagues so as to get enrolled into the appropriate Keybase team(s)
1. Ensure that KBFS (the `/keybase/` directory) works
   - On Mac OS X, this might require [upgrading MacFUSE](https://github.com/keybase/client/issues/24366#issuecomment-777509956)
   - If working from Windows®, review the [specific instructions](./windows/USERS-GUIDE-WINDOWS.md#keybase-for-wsl) to get Keybase going in your WSL instance. (Note that Ansible won't be needing K: from the Windows® world, but there is nothing preventing you from setting it up anyway e.g. so that you can edit secrets with your favorite text editor.)
1. Check that you can see your team's secrets in KBFS: <pre>ls /keybase/team/</pre>

## Check out your project

1. Install git
    - If you are using Windows® and WSL, open a Linux terminal and proceed to the instructions below corresponding to the Linux distribution you have installed
    - On Ubuntu Linux or Debian Linux: type <pre>sudo apt install git</pre>
    - On RedHat Linux or CentOS Linux: ... oh boy. [This is a topic in and of itself](https://serverfault.com/a/1056817/109290)
    - On Mac OS X Big Sur, there should be no need to do anything. (On older versions, [install homebrew](https://brew.sh/) then type `brew install git`)
1. Type the suitable `git checkout ...` command, obtained either from the project's home page on GitHub or Gitlab, or from your colleagues

## Try it!

Within the directory you just checked out using Git, there should be an executable script whose name ends with `*sible`. Run it with `--check` to get a glimpse of all it can do for you.

Now get in touch with the team to learn about tags, `--prod` and other do's and don'ts.
