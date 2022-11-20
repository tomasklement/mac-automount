# Mac network drives automount

Mounts and unmounts network drives on Mac. Easy to install and configure. Checks drives availability on background. Uses keychain for storing passwords.

## Installation
You need to have installed git. See [git installation guide](https://github.com/git-guides/install-git#install-git-on-mac).

Go to the installation directory where you store your executables, i.e.:
```bash
cd ~./local/bin
```
Run:
```bash
git clone https://github.com/tomasklement/mac-automount.git && git -C mac-automount submodule update --init --recursive
```
This will create directory "mac-automount" and clone the latest version with its submodules from github.

Check the content of newly created dir:
```bash
cd mac-automount
```

## Configuration
See file `mounts_config/sample.conf`

```bash
# Host name or IP address
HOST="192.168.0.1"
# (optional) Port, default = 139
PORT="139"
# (optional) Host MAC address, enables to ensure connecting to proper machine
HOST_MAC="1A:2B:3C:4D:5E:6F"
# Login username
USERNAME="foo"
# Network share name
SHARE_NAME="documents"
# Local mount point
MOUNT_POINT="/Users/john.doe/mounts/documents"
```
Copy configuration file for each of your share and change the values. The name of the configuration file is up to you.
```bash
cd mac-automount/mounts_config/
cp sample.conf my_share_1.conf
cp sample.conf my_share_2.conf
```

## Installation
```bash
./install
```
The script will try to collect passwords for the configured shares and save them to keychain. Creates daemon and starts it.

## Upgrade
```bash
./upgrade
```
This will pull the latest version with its submodules from github and restarts the daemon.

## Uninstallation
```bash
./uninstall
```
This will stop and remove daemon. Leaves all shares mounted and doesn't delete passwords in keychain

## Manual run
```bash
./mount
```
Will mount or unmount configured shares based on their availability.
## Restart daemon
```bash
./restart
```
Unloads and loads daemon.