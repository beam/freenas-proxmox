# FreeNAS ZFS over iSCSI interface

Please be aware that this enhancment uses the FreeNAS APIs and NOT the ssh/scp like the other interface provides.

1. First use the following commands to patch the needed files forthe FreeNAS Interface
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

1. Remove the `-T` taint directive from `/usr/bin/pvedaemon`. Not sure why this is needed. I need to do some research on this PERL directive option.
    ```bash
    sed -E -i.orig 's|^(#!/usr/bin/perl) -T|\1|' /usr/bin/pvedaemon
    ```

1. Execute the following at a console command prompt to active the above
    ```bash
    systemctl restart pvedaemon
    ```

1. Refresh the Proxmox GUI in your browser to load the new Javascript code. 
