# SlientOS
OS

nasm -I include/ -o mbr.bin mbr.S

nasm -I include/ -o loader.bin loader.S

sudo dd if=./loader.bin of=/usr/local/hd60M.img bs=512 count=2 seek=2  conv=notrunc

sudo dd if=./mbr.bin of=/usr/local/hd60M.img bs=512 count=1 conv=notrunc

sudo bin/bochs -f bochsrc.disk

