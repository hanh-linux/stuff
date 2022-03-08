xorriso -as mkisofs -volid $volid -b syslinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr $isohybrid -c syslinux/boot.cat $1 -o $2
