# FreeNAS ZFS over iSCSI interface

Please be aware that this plugin uses the FreeNAS APIs and NOT the ssh/scp interface like the other plugins use, but...

You will still need to configure the SSH connector for listing the ZFS Pools because this is currently being done in a Proxmox module (ZFSPoolPlugin.pm). To configure this please follow the steps at https://pve.proxmox.com/wiki/Storage:_ZFS_over_iSCSI that have to do with SSH between Proxmox VE and FreeNAS. The code segment should start out ‘mkdir /etc/pve/priv/zfs’.

I am currently in development to remove this depencancy from the ZFSPoolPlugin.pm so it is done in the FreeNAS.pm.

1. First use the following commands to patch the needed files for the FreeNAS Interface
    ```bash
    patch -b /usr/share/pve-manager/js/pvemanagerlib.js < pve-manager/js/pvemanagerlib.js.patch
    patch -b /usr/share/perl5/PVE/Storage/ZFSPlugin.pm < perl5/PVE/Storage/ZFSPlugin.pm.patch
    patch -b /usr/share/pve-docs/api-viewer/apidoc.js < pve-docs/api-viewer/apidoc.js.patch
    ```

1. Install the perl REST Client package from the repository.
    ```bash
    apt-get install librest-client-perl
    ```

1. Use the following command to copy the needed file for the FreeNAS connector.
    ```bash
    cp perl5/PVE/Storage/LunCmd/FreeNAS.pm /usr/share/perl5/PVE/Storage/LunCmd/FreeNAS.pm
    ```

1. Execute the following at a console command prompt to active the above
    ```bash
    systemctl restart pvedaemon
    systemctl restart pveproxy
    systemctl restart pvestatd
    ```

1. Refresh the Proxmox GUI in your browser to load the new Javascript code. 
