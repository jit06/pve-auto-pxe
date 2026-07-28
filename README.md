# Generate PXE and ISO files for automated PVE installation
The aim of pve-auto-pxe is to generate PXE ready files for fully automated Proxmox provisioning with no human action.
It uses Proxmox official ISO and [the dedicated tool](https://pve.proxmox.com/wiki/Automated_Installation) as well as [pve-iso-2-pxe](https://github.com/morph027/pve-iso-2-pxe) to create an unattended bootable ISO installer and convert It to PXE files.

As a side effect, it also create a bootable ISO image with the exact same content as the generated PXE image.

It also allows to
- inject a custom rc.local
- inject a custom network interfaces file as /etc/interfaces.install
- allows to install on emmc disks (/dev/mmcblk*)

Note that as PVE overwrite /etc/interfaces file during the process, you have to manage it in rc.local. For example:
```
rm /etc/network/interfaces
mv /etc/network/interfaces.install /etc/network/interfaces
systemctl restart networking
```

## Build command example
sudo docker build --no-cache --rm --force-rm -t pve-auto-pxe pve-auto-pxe

## usage
It is advised to run the container interactively to view all messages. The container just stop when the job is done or has failed.

sudo docker run --rm -it -v ./pve-auto-pxe/workdir:/workdir -v ./pve-auto-pxe/config:/config --privileged pve-auto-pxe

volume workdir is mounted as /workdir. It will be used to build ISO and will contain the following at the end of the process: 
- Proxmox iso if not yet present
- Generated auto install iso
- Generated auto install iso modded with /config/rc.local, /config/interfaces and patched for emmc 
- "pxeboot" folder with pxe ready files (linux26 and initrd)

# Example of rc.local file to inject
```
#!/bin/sh -e
#
# rc.local
# This script is executed at the end of each multiuser runlevel.
# any non 0 exit will be reported as failure by systemd

# set new interfaces file if any
if [ -f /etc/network/interfaces.install ]; then
    echo "found a network interfaces file to install"
    rm /etc/network/interfaces
    mv /etc/network/interfaces.install /etc/network/interfaces
    systemctl restart networking
fi

# remove enterprise repo and enable the commnunity one's
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    echo "Enterprise repository found: disable it and enable commnunity repo"
    rm /etc/apt/sources.list.d/pve-enterprise.list
    rm /etc/apt/sources.list.d/ceph.list
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >> /etc/apt/sources.list

    echo "Trigger update and full upgrade"
    apt update && apt -y full-upgrade
fi

# remove the subscription NAG uppon login
if [ ! -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak ]; then 
    echo "subscription NAG found, removing it"
    sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    systemctl restart pveproxy.service
fi
```

# Versions History
- V1.0 - working concept, no customization, not pubished
- V1.1 - allows emmc disks, rc.local and interfaces files injection
- V1.2 - Generated final ISO image is now bootable and has the same content as the PXE image
