# SlientOS

## 命令

mkdir OS

cd OS

vim mbr.S

nasm -I include/ -o loader.bin loader.S

sudo dd if=./mbr.bin of=/usr/local/hd60M.img bs=512 count=1 conv=notrunc

cd /usr/local

sudo bin/bochs -f bochsrc.disk
