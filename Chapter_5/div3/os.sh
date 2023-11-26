#!/bin/sh
nasm -I include/ -o mbr.bin mbr.S
sudo dd if=./mbr.bin of=/usr/local/hd60M.img bs=512 count=1 conv=notrunc
nasm -I include/ -o loader.bin loader.S
sudo dd if=./loader.bin of=/usr/local/hd60M.img bs=512 count=3 seek=2 conv=notrunc

gcc -m32 -c -o kernel/main.o kernel/main.c
ld -m elf_i386 kernel/main.o -Ttext 0xc0001500 -e main -o kernel/kernel.bin
sudo dd if=kernel/kernel.bin of=/usr/local/hd60M.img bs=512 count=200 seek=9 conv=notrunc