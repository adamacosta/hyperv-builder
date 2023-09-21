#!/bin/sh
parted -s /dev/sda mklabel gpt
parted -s -a optimal /dev/sda mkpart "EFI" fat32 1MiB 261MiB
parted -s /dev/sda set 1 esp on
parted -s -a optimal /dev/sda mkpart "Root" ext4 2GiB 100%

mkfs.fat -F32 /dev/sda1
mkfs.ext4 -G 4096 /dev/sda2

mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

