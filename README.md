crypt-gen
=========

A systemd-generator for setting up encrypted devices in initrd.

Unlike the stock systemd-cryptsetup-generator, this is intended to support more uncommon, and/or more advanced setups.

## Examples

```sdl
device "keyfile_device" dev="/encrypted_keyfile"
keyfile "keyfile1" dev="keyfile_device"
device "root" dev="/dev/sda1" keyfile="keyfile1"
device "home" dev="/dev/sda2" keyfile="keyfile1"
```

This example unlocks 2 encrypted device with a common keyfile, which in turn is stored encrypted in a LUKS image.

This kind of setup is currently not supported by systemd.

## Configuration

This generator only works when run inside initrd.

It reads configuration from `/etc/crypttab.sdl`. The configuration is written in [SDLang](https://sdlang.org/).

### `device` tag

A device tag defines an encrypted device that has to be unlocked. Value of this tag will be used as the name of the unlocked device.

This tag can have these attributes:

* `dev`: string, required. The device to unlock.
* `keyfile`: string, optional. The name of the keyfile. The keyfile must be defined in the same configuration file. When omitted, password has to be manually entered during boot.
* `options`: string, optional. Options that will be passed to `systemd-cryptsetup`. Refer to `crypttab(5)` for a list of options.
* `teardown`: boolean, optional. If true, this device will be closed before we leave initrd. If the source device is a file, it will be removed.
* `blob`: boolean, optional. Should be set to true if this device doesn't have a file system on it. systemd normally requires a file system or partition table to be found on the device before it will consider the device ready. This causes keyfile devices to never become ready. This option is meant to workaround that problem. This option is automatically set to true for devices used as keyfile.

### `keyfile` tag

A keyfile tag defines a keyfile. Value of this tag is the name of the keyfile entry.

This tag can have these attributes:

* `dev`: string, optional. Name of a device that will be used as keyfile. The device must be defined in the same configuration file, using a `device` tag. Be careful to not create circular dependencies.
* `file`: string, optional. Path to the keyfile.

Either `dev` or `file` must be specified.

## Build

You need to have a D compiler, and its associated tools (`dub`) to build this project.

You also need to have a systemd-enabled initrd for this to function.

If you are using Arch Linux, you can run `sudo install.sh` to build and install this to your system. Replace `sd-encrypt` hook with the `crypt-gen` hook in your `/etc/mkinitcpio.conf`.

## Contribution

This little project is intended to bring support for more storage encryption setups to systemd-enabled initrds. For example, support for unlocking devices with YubiKey could be added.

You are welcomed to open PRs if you want to add support for unsupported setups. Bug fixes and general improvements are welcome too.
