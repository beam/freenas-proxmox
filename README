# FreeNAS ZFS over iSCSI interface

Please be aware that this enhancment uses the FreeNAS API's and NOT the ssh/scp like the other interface provide.

1. First use the following commands to patch the needed files forthe FreeNAS Interface
    ```bash
    patch /usr/share/pve-manager/js/pvemanagerlib.js < pve-manager/js/pvemanagerlib.js.patch
    patch /usr/share/perl5/PVE/Storage/ZFSPlugin.pm < perl5/PVE/Storage/ZFSPlugin.pm.patch
    patch /usr/share/pve-docs/api-viewer/apidoc.js < pve-docs/api-viewer/apidoc.js.patch
    ```

1. Use the following commands to copy the needed files for the FreeNAS 
    ```bash
    mkdir -p /usr/share/perl5/REST
    cp perl5/REST/Client.pm /usr/share/perl5/REST/Client.pm
    cp perl5/PVE/Storage/LunCmd/FreeNAS.pm /usr/share/perl5/PVE/Storage/LunCmd/FreeNAS.pm
    ```

1. Edit /usr/bin/pvedaemon and remove the '-T' from the perl command line.
    ```bash
    sed -E -i.orig 's|^(#!/usr/bin/perl) -T|\1|' /usr/bin/pvedaemon
    ```

    Not really sure about 'why' this is do I need to do some research on this PERL directive option.

1. Execute the following at a console command prompt to active the above
    ```bash
    systemctl restart pvedaemon
    ```

1. Either goto the URL for the Proxmox GUI in your favorite browser
   or
   If you are already logged in via the GUI just refresh your browser to receive
   the new Javascript code. 
