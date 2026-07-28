#!/bin/bash

#########################################################
#
#   Script variables
#
#########################################################
VERSION=1.1
PVE_ISO_NAME="proxmox-ve_8.4-1.iso"
PVE_AUTO_NAME="proxmox-ve_8.4-1-auto-from-iso.iso"
PVE_MOD_NAME="proxmox-ve_8.4-1-auto-from-iso-MOD.iso"
ANSWER_FILE="answer.toml"
MBR_FILE="proxmox.mbr"
SQUASHFS_BASE="pve-base.squashfs"
SQUASHFS_INSTALLER="pve-installer.squashfs"
PATH_TO_BLOCK_FUNCTION="usr/share/perl5/Proxmox/Sys/Block.pm"
WORKDIR="/workdir"
CONFIG="/config"


#########################################################
#
#   feedback functions
#
#########################################################
Warning () {
  echo "[WARNING] $1"
}

Info () {
  echo "[INFO] $1"
}

Error () {
  echo "[ERROR] $1"
  echo ""
  exit 1
}


#########################################################
#
#   Download official ISO and create auto-install ISO
#
#########################################################
echo ""
echo "=================================================================="
Info " PVE AUTO PXE V$VERSION                                           "
echo "=================================================================="
echo ""

# check if answer file exists and is valid
if [ -f $CONFIG/$ANSWER_FILE ]; then
    Info "found $ANSWER_FILE, checking it..."
    proxmox-auto-install-assistant validate-answer $CONFIG/$ANSWER_FILE
    echo ""
else
    Error "no $ANSWER_FILE found in $CONFIG"
fi

# download official ISO if needed
if [ -f $WORKDIR/$PVE_ISO_NAME ]; then
    Info "Found $PVE_ISO_NAME file"
else
    Info "Start downloading $PVE_ISO_NAME"
    wget -O "$WORKDIR/$PVE_ISO_NAME" "https://enterprise.proxmox.com/iso/$PVE_ISO_NAME" 
    echo ""
fi

# create automatic install iso
if [ -f $WORKDIR/$PVE_AUTO_NAME ]; then
    Info "Found $PVE_AUTO_NAME file, auto-install preparation skipped !"
    echo ""
else
    Info "start building automated install ISO..."
    proxmox-auto-install-assistant prepare-iso $WORKDIR/$PVE_ISO_NAME --fetch-from iso --answer-file $CONFIG/$ANSWER_FILE
    echo ""
fi


#########################################################
#
#   Extract PXE ISO for customization
#
#########################################################

# extract mbr (first 512byte)
Info "Extract MBR to $WORKDIR/$MBR_FILE"
dd if=$WORKDIR/$PVE_AUTO_NAME bs=512 count=1 of=$WORKDIR/$MBR_FILE

# mount iso and copy the content to a RW location
Info "Mount ISO and copy content to a RW location"
mkdir -p $WORKDIR/mnt
mkdir -p $WORKDIR/tmp
mknod /dev/loop2 -m0660 b 7 2

mount -t iso9660 -o loop $WORKDIR/$PVE_AUTO_NAME $WORKDIR/mnt
if [ $? -ne 0 ]; then
    Error "Unable to mount $PVE_AUTO_NAME"
fi

tar cf - -C $WORKDIR/mnt . | tar xfp - -C $WORKDIR/tmp
if [ $? -ne 0 ]; then
    Error "Unable to copy mount ISO to tmp dir"
fi

Info "Inject custom grub configuration"
cat > $WORKDIR/tmp/boot/grub/grub.cfg <<'EOF'
set default=0
set timeout=0

search --no-floppy --file /pve-base.squashfs --set=root

menuentry "Proxmox Auto Install" {
    linux /boot/linux26 ramdisk_size=16777216 ro proxmox-start-auto-installer
    initrd /boot/initrd.img
}
EOF

umount $WORKDIR/mnt



#########################################################
#
#   Modify pve root file system to inject custom
#   network interfaces and rc.local files
#
#########################################################

# extract pve root filesystem
Info "extract PVE root squashfs image"
cd $WORKDIR/tmp

unsquashfs $WORKDIR/tmp/$SQUASHFS_BASE
if [ $? -ne 0 ]; then
    Error "Unable to extract $SQUASHFS_BASE"
fi
cd /

# add rc.local
if [ -f $CONFIG/rc.local ]; then
    Info "Found rc.local: adding it to PVE filesystem"
    cp $CONFIG/rc.local $WORKDIR/tmp/squashfs-root/etc/
    chmod 755 $WORKDIR/tmp/squashfs-root/etc/rc.local
    echo ""
else
    Warning "no rc.local found in $CONFIG, continue building ISO without it"
fi

# add interfaces config file
if [ -f $CONFIG/interfaces ]; then
    Info "Found interfaces file: adding it to PVE filesystem"
    cp $CONFIG/interfaces $WORKDIR/tmp/squashfs-root/etc/network/interfaces.install
    echo ""
else
    Warning "interfaces no file found in $CONFIG, continue building ISO without it"
fi

# remove original sqashfs and rebuild a new one
Info "Rebuild squashfs..."
rm $WORKDIR/tmp/$SQUASHFS_BASE
cd $WORKDIR/tmp

mksquashfs squashfs-root/ $SQUASHFS_BASE
if [ $? -ne 0 ]; then
    Error "Unable to create new $SQUASHFS_BASE"
fi

rm -rf $WORKDIR/tmp/squashfs-root
cd /



#########################################################
#
#   modify pve installer to allow installing on emmc
#
#########################################################

# extract pve installer filesystem
Info "extract PVE installer squashfs image"
cd $WORKDIR/tmp

unsquashfs $WORKDIR/tmp/$SQUASHFS_INSTALLER
if [ $? -ne 0 ]; then
    Error "Unable to extract $SQUASHFS_INSTALLER"
fi

# change installer file so emmc disks are accepted
Info "Patching installer to accept emmc disks (/dev/mmcblk*)"
sed -i 's/die "unable to get device for partition $partnum on device $dev\\n";/if ($dev =~ m|^\/dev\/mmcblk\\d+$|) {\n\t\treturn "${dev}p$partnum";\n\t} else {\n\t\tdie "unable to get device for partition $partnum on device $dev\\n";\n\t}/g' $WORKDIR/tmp/squashfs-root/$PATH_TO_BLOCK_FUNCTION

if [ $? -ne 0 ]; then
    Error "Unable to modify $WORKDIR/tmp/squashfs-root/$PATH_TO_BLOCK_FUNCTION"
fi

# remove original sqashfs and rebuild a new one
Info "Rebuild installer squashfs..."
rm $WORKDIR/tmp/$SQUASHFS_INSTALLER
cd $WORKDIR/tmp

mksquashfs squashfs-root/ $SQUASHFS_INSTALLER
if [ $? -ne 0 ]; then
    Error "Unable to create new $SQUASHFS_INSTALLER"
fi

rm -rf $WORKDIR/tmp/squashfs-root
cd /



#########################################################
#
#   Create new ISO as well as PXE boot files
#
#########################################################

# create a new bootable iso
CREATE_DATE=$(xorriso -indev "$WORKDIR/$PVE_ISO_NAME" -pvd_info | awk -F ': ' '/Creation Time/ {print $2}')

Info "Generate a new ISO in $WORKDIR/$PVE_MOD_NAME with ID $CREATE_DATE"
xorriso -as mkisofs \
-o $WORKDIR/$PVE_MOD_NAME \
-r -V 'PVE' \
--modification-date="$CREATE_DATE" \
--grub2-mbr $WORKDIR/$MBR_FILE \
--protective-msdos-label \
-partition_cyl_align off \
-partition_offset 0 \
-partition_hd_cyl 94 \
-partition_sec_hd 32 \
-apm-block-size 2048 \
-hfsplus \
-efi-boot-part --efi-boot-image \
-c '/boot/boot.cat' \
-b '/boot/grub/i386-pc/eltorito.img' \
-no-emul-boot \
-boot-load-size 4 \
-boot-info-table \
--grub2-boot-info \
-eltorito-alt-boot \
-e '/efi.img' \
-no-emul-boot \
$WORKDIR/tmp

if [ $? -ne 0 ]; then
    Error "Unable to generate a new ISO image"
fi

# create PXE image
Info "Converting ISO to PXE files..."
/opt/pve-iso-2-pxe/pve-iso-2-pxe.sh $WORKDIR/$PVE_MOD_NAME
echo ""

# copy autoexec.ipxe in PXE folder if exists
if [ -f $CONFIG/autoxec.ipxe ]; then
    Info "Found autoexec.ipxe, copy it"
    cp $CONFIG/autoxec.ipxe $WORKDIR/pxeboot
fi

# cleanup
Info "Cleaning up..."
rm -rf $WORKDIR/tmp $WORKDIR/mnt

echo ""
echo ""
echo "=================================================================="
Info "DON'T FORGET TO RENAME INIRD FILE REGARDING YOUR AUTOEXE.IPXE FILE"
echo "=================================================================="
