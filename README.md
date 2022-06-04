# TrueNAS ZFS over iSCSI interface  [![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=TCLNEMBUYQUXN&source=url)

### Updates 2022-06-04<br/>  - New Repos available. See [!ATTENTION!](#NewRepo) below.<br/>  - Support for TrueNAS 13 is available<br/>  - Patched for issues with TrueNAS-Scale paths that had more then one level (e.g. Tank/Disk/vDisks) when converting slashes to dashes.
#### Roadmap
* Fix automated builds.
  * Beta - 'testing' repo component.
  * Production - 'main' repo component.
* Change from FreeNAS to TrueNAS.
  * Cleanup the FreeNAS repo and name everything to TrueNAS to be inline with the product.
* Remove the need for SSH keys and use the API.
  * This is tricky because the format needs to be that of the output of 'zfs list' which is not part of the LunCmd but that of the backend Proxmox VE system and the API's do a bunch of JSON stuff.

## Thank you for all that have recently donated to the project - Updated 2022-06-04
    Alexander Finkhäuser - Recurring
    Bjarte Kvamme - Recurring
    Jonathan Schober - Recurring
    Mark Komarinski
    Jesse Bryan
    Maksym Vasylenko
    Daniel Most
    Velocity Host
    Robert Hancock
    
    Clevvi Technology
    Mark Elkins
    Marc Hodler
    Martin Gonzalez

## <a name="NewRepo"></a>!ATTENTION!: New Repo and GPG file
Issue the following on each node to install the repo and get your Proxmox VE updating the TrueNAS patches automatically:
```bash
curl https://ksatechnologies.jfrog.io/artifactory/ksa-repo-gpg/ksatechnologies-release.gpg -o /etc/apt/trusted.gpg.d/ksatechnologies-release.gpg
curl https://ksatechnologies.jfrog.io/artifactory/ksa-repo-gpg/ksatechnologies-repo.list -o /etc/apt/sources.list.d/ksatechnologies-repo.list
```
The above 'should' overwrite the current list and gpg file to bring your system(s) back to using the ```apt``` or Proxmox VE Update subsystem.
You can used the Proxmox VE Repositories menu to enable and disable the 'main' (TBD) or 'testing' (default) component.

If you did use the temporary repo from "Cloudsmith" then issue the following to clean it up:
```
rm /etc/apt/sources.list.d/ksatechnologies-truenas-proxmox.list
rm /usr/share/keyrings/ksatechnologies-truenas-proxmox-archive-keyring.gpg
```

You can either perform an ```apt-get update``` from the command line or issue it from the Proxmox UI on each Node via ```Datacenter->[Node Name]->Updates```

### 'main' repo (Follows a release branch - Current 2.x) Currently unavailable.
Will be production ready code that has been tested (as best as possible) from the 'testing' repo.

### 'testing' repo (Follows the master branch)
Will be 'beta' code for features, bugs, and updates.


### Converting from manual install to using the ```apt``` package manager.

If you wish, you may remove the directory 'freenas-proxmox' where your system is currently
housing the repo and then issue the following to have a clean system before installing the
package.

On Proxmox 5
```bash
apt install --reinstall pve-manager pve-docs libpve-storage-perl
```

On Proxmox 6 and 7
```bash
apt reinstall pve-manager pve-docs libpve-storage-perl
```
Then follow the new installs below

## New Installs.
Issue the following from a command line:
```bash
curl https://ksatechnologies.jfrog.io/artifactory/ksa-repo-gpg/ksatechnologies-release.gpg -o /etc/apt/trusted.gpg.d/ksatechnologies-release.gpg
curl https://ksatechnologies.jfrog.io/artifactory/ksa-repo-gpg/ksatechnologies-repo.list -o /etc/apt/sources.list.d/ksatechnologies-repo.list
```

Then issue the following to install the package
```bash
apt update
apt install freenas-proxmox
```

Then just do your regular upgrade via apt at the command line or the Proxmox Update subsystem; the package will automatically issue all commands to patch the files.
```bash
apt update
apt [full|dist]-upgrade
```

If you wish not to use the package you may remove it at anytime with
```
apt [remove|purge] freenas-proxmox
```
This will place you back to a normal and non-patched Proxmox VE install.

#### NOTE: Please be aware that this plugin uses the TrueNAS APIs but still uses SSH keys due to the underlying Proxmox VE perl modules that use the ```iscsiadm``` command.

You will still need to configure the SSH connector for listing the ZFS Pools because this is currently being done in a Proxmox module (ZFSPoolPlugin.pm). To configure this please follow the steps at https://pve.proxmox.com/wiki/Storage:_ZFS_over_iSCSI that have to do with SSH between Proxmox VE and TrueNAS. The code segment should start out `mkdir /etc/pve/priv/zfs`.

1. Remember to follow the instructions mentioned above for the SSH keys.

2. Refresh the Proxmox GUI in your browser to load the new Javascript code.

3. Add your new TrueNAS ZFS-over-iSCSI storage using the TrueNAS-API.

4. Thanks for your support.
