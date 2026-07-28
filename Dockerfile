FROM debian:bookworm

RUN apt update && apt -y install wget

# from https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_12_Bookworm
RUN echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
RUN wget "http://download.proxmox.com/debian/proxmox-release-bookworm.gpg" -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
RUN chmod +r /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
RUN apt update

# from https://pve.proxmox.com/wiki/Automated_Installation
RUN apt install -y proxmox-auto-install-assistant git

# from https://github.com/morph027/pve-iso-2-pxe
RUN git clone --depth 1 https://github.com/morph027/pve-iso-2-pxe /opt/pve-iso-2-pxe
RUN apt install -y cpio file zstd gzip genisoimage mkisofs squashfs-tools gdisk

ADD ./generate-pxe.sh /opt/generate-pxe.sh
RUN chmod +x /opt/generate-pxe.sh

ENTRYPOINT ["/opt/generate-pxe.sh"]