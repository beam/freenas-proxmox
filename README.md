# FreeNAS ZFS over iSCSI interface  [![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=TCLNEMBUYQUXN&source=url)

## Currently trying JFrog for the repo. Just changing the Automation and making sure all works.<br/>I am currently testing an should have at least the repos up for production and testing. You will need to update your repos with the new location and gpg. I will have instructions on this page.

## Also currently developing for TrueNAS-Core 13 to provide fixes to support all the [Free|True]NAS family.

## Thank you for all that have recently donated to the project.
    Daniel Most
    Maksym Vasylenko
    Alexander Finkhäuser - Reoccuring
    Bjarte Kvamme - Reoccuring
    Jonathan Schober - Reoccuring
    
## And thanks to all that have donated to the project in the past.
    Clevvi Technology
    Mark Elkins - Reoccuring
    Marc Hodler
    Martin Gonzalez


I have created a debian repo that holds a package to install scripts into the Proxmox VE system that will automatically do all the necessary patching when one or any combo of the following files are changed in the Proxmox VE stream:
```
/usr/share/pve-manager/js/pvemanagerlib.js    <- From package pve-manager
/usr/share/pve-docs/api-viewer/apidoc.js      <- From package pve-docs
/usr/share/perl5/PVE/Storage/ZFSPlugin.pm     <- From package libpve-storage-perl
```
It will also install the /usr/share/perl5/PVE/Storage/LunCmd/FreeNAS.pm (The FreeNAS API plugin), git and librest-client-perl

If you wish, you may remove the directory 'freenas-proxmox' where your system is currently
housing the repo and then issue the following to have a clean system before installing the
package.

On Proxmox 5
```bash
apt install --reinstall pve-manager pve-docs libpve-storage-perl
```

On Proxmox 6
```bash
apt reinstall pve-manager pve-docs libpve-storage-perl
```

On Proxmox 7
```bash
apt reinstall pve-manager pve-docs libpve-storage-perl
```
## Changing in the near future.
Issue the following to install the repo and get your Proxmox VE updating the FreeNAS patches automatically:
```bash
wget http://repo.ksatechnologies.com/debian/pve/ksatechnologies-release.gpg -O /etc/apt/trusted.gpg.d/ksatechnologies-repo.gpg
echo "deb http://repo.ksatechnologies.com/debian/pve stable freenas-proxmox" > /etc/apt/sources.list.d/ksatechnologies-repo.list
```

### I will be using a 'testing' repo to develop the new phase of the Proxmox VE FreeNAS plugin.
#### This next phase will introduce the following...
* Auto detection of the Proxmox VE version
* Auto detection of the FreeNAS version so it will use the V1 or V2 API's or you can select it manually via the Proxmox VE FreeNAS modal
* Remove the need for SSH keys and use the API
  * This is tricky because the format needs to be that of the output of'zfs list' which is not part of the LunCmd but that of the backend Proxmox VE system and the API's do a bunch of JSON stuff.

#### If you'd like, you may also issue the following commands now or later to use the 'testing' repo.
#### Just comment the 'stable' line and uncomment the 'testing' line in 
#### /etc/apt/sources.list.d/ksatechnologies-repo.list to use. 'testing' is disabled be default.
```bash
echo "" >> /etc/apt/sources.list.d/ksatechnologies-repo.list
echo "# deb http://repo.ksatechnologies.com/debian/pve testing freenas-proxmox" >> /etc/apt/sources.list.d/ksatechnologies-repo.list
```

Then issue the following to install the package
```
apt update
apt install freenas-proxmox
```

Then just do your regular upgrade via apt to your system; the package will automatically
issue all commands to patch the files.
```bash
apt update
apt [full|dist]-upgrade
```

If you wish not to use the package you may remove it at anytime with
```
apt [remove|purge] freenas-proxmox
```
This will place you back to a normal and unpatched Proxmox VE install.

Please be aware that this plugin uses the FreeNAS APIs and NOT the ssh/scp interface like the other plugins use, but...

You will still need to configure the SSH connector for listing the ZFS Pools because this is currently being done in a Proxmox module (ZFSPoolPlugin.pm). To configure this please follow the steps at https://pve.proxmox.com/wiki/Storage:_ZFS_over_iSCSI that have to do with SSH between Proxmox VE and FreeNAS. The code segment should start out `mkdir /etc/pve/priv/zfs`.

1. Remember to follow the instructions mentioned above for the SSH keys.

1. Refresh the Proxmox GUI in your browser to load the new Javascript code.

1. Add your new FreeNAS ZFS-over-iSCSI storage using the FreeNAS-API.

1. Thanks for your support.
