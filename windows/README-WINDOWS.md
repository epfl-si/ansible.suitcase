# Windows®-specific instructions for projects using the Ansible suitcase

## Pre-prerequisites

<ul>
<li><p><b>The instructions therein require Windows® 10 or later.</b></p>

<p>It may or may not be technically possible to run the Ansible suitcase on Windows® 7. Unfortunately this requires some serious arcana with names such as <a href="https://chocolatey.org/>chocolatey</a>, <a href="https://chocolatey.org/packages/git">git bash</a> and <a href="https://chocolatey.org/packages/python3">python3</a>. **Also, this mode of operating the suitcase is untested and unmaintained**. Kindly consider upgrading to Windows® 10 instead.</p></li>

<li><p><b>You need administrator access to the Windows® machine you will be working from.</b></p>

<li><p><b>You will be using the terminal a lot</b>: first PowerShell running as an administrator, and then the WSL Linux terminal prompt.</p></li>
</ul>


## Install and set up WSL

Just [follow the official documentation](https://docs.microsoft.com/en-us/windows/wsl/install-win10)

💡 Some tips:
- Start by running a PowerShell session as an administrator (click the Windows® icon on the bottom right → type `powershell` in the search box → right-click on the “Windows PowerShell” app (not PowerShell ISE[¹](#footnote-ise)) → Run as administrator)
- Copy the commands from the Microsoft web site (use the Copy button from there), and paste them into the Powershell session (right-click the title bar → Edit → Paste). <br/> ⚠ **Do not** click inside the blue window — That would trash your cut buffer and you would have to start over.
- **After step 1 you must reboot.** I mean, there is some wiggle room that that is what the instructions say, but they are sybilline about it at best.

<a name="footnote-ise">¹</a> I'm pretty sure that PowerShell ISE can be made to work, but you don't need it (and this tutorial won't cover it).

### Make sure you are running WSL version 2

This is required by Keybase (see below), and therefore the suitcase doesn't support WSL version 1.

1. From an unprivileged PowerShell window type <pre>wsl --set-default-version 2</pre>
1. If you don't have any Linuxes installed yet, you're good; go to the next paragraph. If, however, you got ahead of yourself and already installed one or more Linux distributions, keep reading
1. Check the versions of your existing Linux (or Linuxes) from an unprivileged PowerShell window with <pre>wsl -l -v</pre>
1. If `VERSION` says 2, you are all set; skip to the next paragraph
1. Delete your v1 instance: <pre>wsl --unregister Ubuntu-20.04</pre>
1. Change default version to 2: <pre>wsl --set-default-version 2</pre>
1. Continue reading

### Install Ubuntu 20.04 LTS from the Microsoft Store

💡 **Do yourself a favor and steer clear of CentOS**, regardless of the opinion of your corporate IT department on the matter. You can thank me later.

### Test it

1. Run Ubuntu 20.04 from your Start menu. Wait for installation to complete
1. When prompted, pick a user name and password
1. When you see the green prompt that ends with $, you are all set. If you can spare the time, you may want to [watch a tutorial](https://www.youtube.com/watch?v=n9_tZKKzAHw) for your first steps using the Linux command line.

## Install and configure ssh and the Windows® 10 ssh agent

Regardless of whether you already have an [ssh public / private key pair](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys), you will want to use an [ssh agent](https://www.digitalocean.com/community/tutorials/ssh-essentials-working-with-ssh-servers-clients-and-keys#adding-your-ssh-keys-to-an-ssh-agent-to-avoid-typing-the-passphrase) for the following benefits:

- you will only have to type your passphrase once (when loading your key into the agent)
- you will be able to “double-jump” into e.g. clusters (ssh to head node, then ssh to one of the workers on an internal network) instead of copying your private key around (which would be insecure, to put it mildly) or using multiple keys (clunky)

The following steps will let you use the same agent (and therefore, the same key(s)) under both “worlds” (Linux and Windows®) in your workstation.

### Prepare your public / private key pair in the Windows® world


| 🎯 Goal for this paragraph |
|-----|
| You know you are done with this step when you can use the Windows®-provided `ssh` command-line tool (from an unprivileged PowerShell session) into at least one remote host without using the remote password. |

(At this stage you might still have to type your private key's passphrase, so it might look like we haven't gained much. We'll address that in the next paragraph.)


1. Open a “normal” (unprivileged) PowerShell session and ensure you have the `ssh` command available. If not, [follow the official instructions](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse#installing-openssh-with-powershell).
1. Create a public / private key pair or export the one you were previously using (e.g. with PuTTY / WinSCP) and save it in a `.ssh` directory under your Windows® home directory
   - If you never had a public key or don't know what an ssh public key is, just open an unprivileged PowerShell session, type <pre>ssh-keygen</pre> and follow the instructions
   - If you were using PuTTY previously and you already have a private / public key in PuTTY / Pageant, you will need to export it into your `.ssh` directory in Windows®. [Follow the instructions here.](https://aws.amazon.com/premiumsupport/knowledge-center/convert-pem-file-into-ppk/)
   - Pick a UNIX server you have access to and copy your public key onto it: from the unprivileged PowerShell session you opened previously, type <pre>ssh-copy-id <i>USER</i>@</i>UNIXSERVER</i></pre>
   - Type the exact same command once more. If you were successful, you won't be prompted for a password this time around. (Although, as mentioned above, you might still get prompted for your private key's passphrase.)

💡 If the remote UNIX server already knew about your public key (for instance, because you already did the required changes back when you were setting up PuTTY), you might succeed at password-less authentication the first time around. That's obviously fine, and indicates success just as well. Please proceed to the next paragraph.


### Prepare the ssh agent in the Windows® world and have it load your private key

| 🎯 Goal for this paragraph |
|-----|
| You know you are done with this step when (still from an unprivileged PowerShell session) you can type<pre>ssh-add -l</pre> and your public key's details are shown; **and** it happens again after you reboot and log back in. |


💡 We'll be using Windows® 10's `ssh-agent` — **The Pageant ssh agent is not helpful for WSL.** Been there, tried that. Sorry.

1. Ensure that the `ssh-agent` Windows® service is running at all times: in a PowerShell window with administrator privileges, type<pre>
Set-Service -StartupType Automatic ssh-agent
Start-Service ssh-agent
</pre>⚠ Mind the order of the commands (some tutorials on the Internet have it wrong)
2. Type <pre>ssh-add</pre> If you did the previous step right, this command will find your private key at the default place and prompt for your passphrase. If your private key is somewhere else, no biggie, just pass on the full path to `ssh-add`, e.g. <pre>ssh-add C:\Path\To\Your\id_rsa</pre>
3. Control with <pre>ssh-add -l</pre> This should show your public key's details, including its cryptographic fingerprint (a string of gibberish that starts with `SHA256:`)
4. ... There is no step 4. Unlike what happens on Mac OS or Linux, Windows®'s `ssh-add` is a *persistent* operation; that is, your passphrase was stored into the operating system's password store and will be retrieved to load your key again transparently the next time you log in.

### Make your ssh agent accessible from the Linux world

| 🎯 Goal for this paragraph |
|-----|
| You know you are done with this step when <pre>ssh-add -l</pre> works from a WSL Linux command-line prompt like it does in PowerShell, **and** that too survives a reboot. |

This part is not supported by Microsoft (yet) and therefore requires using a third-party piece of software aptly named [wsl-ssh-agent](https://github.com/rupor-github/wsl-ssh-agent), along with a special-purpose script that the Ansible suitcase provides.

1. Head over to the [latest release](https://github.com/rupor-github/wsl-ssh-agent/releases/latest) and download the Zip file there (you won't need the source code)
1. Extract the Zip file somewhere on the Windows® side and take note of where you installed the contents
1. Download the [script that Ansible suitcase provides](https://raw.githubusercontent.com/epfl-si/ansible.suitcase/master/windows/setup-wsl-ssh-agent.sh) for this purpose (browse the link, right-click, Save as...), and save it in the very same directory where you extracted wsl-ssh-agent previously (alongside `wsl-ssh-agent-gui` and `npiprelay`)
1. Run the `wsl-ssh-agent-gui` program, which should appear as a key chain icon in your system tray
1. Ensure that that same program automatically runs again when you log out and back in (follow [these instructions from Microsoft](https://support.microsoft.com/en-us/windows/add-an-app-to-run-automatically-at-startup-in-windows-10-150da165-dcd9-7230-517b-cf3c295d89dd) if you have never done that before — TL;DR: Windows-R; `shell:startup`; an Explorer window pops up; Alt+drag or otherwise create a link to `wsl-ssh-agent-gui` there)
1. Test that last part by logging out of Windows® and back in; the key chain icon should be back in your system tray
1. Open a Linux command-line terminal and execute the suitcase script from within it with `bash`. You will have to convert the Windows® path to a Linux path; so for example, if you installed `wsl-ssh-agent-gui` (and the script) into `C:\Users\Paul\MyStuff\wsl-ssh-agent`, you need to type<pre>bash /mnt/c/Users/Paul/MyStuff/wsl-ssh-agent/setup-wsl-ssh-agent.sh</pre> 💡 You can type in the first few characters of each directory name along that path, then press the Tab key to have the Linux shell guess the remainder on your behalf. This feature is called [command-line completion](https://en.wikipedia.org/wiki/Command-line_completion).
1. Control with <pre>ssh-add -l</pre> This should still work if you log out and back in.

## Keybase for WSL

| 🎯 Goal for this paragraph |
|-----|
| This step is about making KBFS accessible from WSL; that is, `ls /keybase/team/` (from a Linux prompt) should show the Keybase teams you are a member of. |

Most projects that use the Ansible suitcase, also require Keybase as a way to exchange secrets among DevOps team members.

1. Review the [instructions in the main README](../README.md#keybase) to get Keybase going within the Windows® world, and preferably also another, physically distinct device (e.g., your phone)
1. Install Keybase within WSL: run a WSL Linux terminal and type<pre>
curl --remote-name https://prerelease.keybase.io/keybase_amd64.deb
sudo dpkg -i keybase_amd64.deb
 ## You can safely ignore  errors at this step, as the next two lines are intent on fixing them up
sudo apt -y update
sudo apt -yf install
</pre>
1. Run Keybase by typing <pre>run_keybase</pre>
1. Log into your Keybase account with <pre>keybase login</pre>
1. When prompted for a device name, **be sure to use a versioning suffix** because you won't be able to re-use the name in case you decide to destroy and recreate your WSL instance; for instance, type something like `mycorppc12345-WSL2-1`
1. You can ignore the freedesktop business in yellow (caused by there not being a GUI on your WSL Linux)
1. When Keybase says you are logged in, double check with <pre>ls /keybase/team/</pre>

## Congratulations!

Wow! That's an achievement which carries a lot of command-line XP points (no pun intended on the XP part). Pat yourself on the back and enjoy your newly-minted superpowers.

## [Back to the main README](../README.md)
