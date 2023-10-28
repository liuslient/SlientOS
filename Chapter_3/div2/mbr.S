;主引导程序
;----------------------------
%include "boot.inc"
SECTION MBR vstart=0x7c00   ;起始地址为0x7c00
    mov ax,cs
    mov ds,ax               ;由于BIOS通过 0:0x7c00跳转MBR，所以此时cs为0,因此借他来初始化寄存器
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00
    mov ax,0xb800       ;使用显卡文本模，利用ax作为中转站将段基址赋给gs
    mov gs,ax

;清屏利用0x06号子功能，上卷全部行，则可清屏
;------------------------
;INT 0x10     功能号:0x06   功能:上卷窗口
;------------------------
;输入：
;AH 功能号:0x06
;AL = 上卷行数（若为0则表示全部行）
;BH = 上卷行属性
;(CL,CH) = 窗口左上角的(X,Y)位置
;(DL,DH) = 窗口右下角的(X,Y)位置
;无返回值
    mov ax,0x600
    mov bx,0x700
    mov cx,0
    mov dx,0x184f
    int 0x10

    mov byte [gs:0x00],'L'
    mov byte [gs:0x01],0x94

    mov byte [gs:0x02],'i'
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'u'
    mov byte [gs:0x05],0xA4

    mov byte [gs:0x06],'T'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'i'
    mov byte [gs:0x09],0x94

    mov byte [gs:0x0a],'a'
    mov byte [gs:0x0b],0xA4

    mov byte [gs:0x0c],'n'
    mov byte [gs:0x0d],0x94


;;;;;;;;;;;;   打印字符串结束   ;;;;;;;;;;;;;;;
    


    mov eax,LOADER_START_SECTOR    ;起始扇区的lba地址
    mov bx,LOADER_BASE_ADDR         ;写入的地址
    mov cx,1
    call rd_disk_m_16               ;以下读取程序的起始部分（一个扇区）

    jmp LOADER_BASE_ADDR

;--------------------------------
;功能：读取硬盘n个扇区
rd_disk_m_16:
;---------------------------------------
                    ;eax=LBA扇区号
                    ;bx=将数据写入的内存地址
                    ;cx=读入的扇区数
    mov esi,eax     ;备份eax
    mov di,cx       ;备份cx

;读写硬盘
;第一步：设置要读取的扇区数
    mov dx,0x1f2
    mov al,cl
    out dx,al   ;读取的扇区数

    mov eax,esi     ;恢复ax

;第二步：将LBA地址存入0x1f3 ~ 0x1f6

    ;LBA地址7~0位写入端口0x1f3
    mov dx,0x1f3 
    out dx,al

    ;LBA地址15~8位写入端口0x1f4
    mov cl,8
    shr eax,cl
    mov dx,0x1f4
    out dx,al

    ;LBA地址23~16位写入端口0x1f5
    shr eax,cl
    mov dx,0x1f5
    out dx,al

    shr eax,cl
    and al,0x0f     ;lba第24~27位
    or al,0xe0      ;设置7~4位为1110，表示lba模式
    mov dx,0x1f6
    out dx,al

;第3步：向0x1f7端口写入读命令,0x20
    mov dx,0x1f7
    mov al,0x20
    out dx,al

;第四步：检测硬盘状态
  .not_ready:
    ;同一端口，写时表示写入命令字，读时表示读入硬盘状态
    nop
    in al,dx
    and al,0x88 ;第三位为1表示硬盘控制器已准备好数据传输
                ;第七位为1表示硬盘忙

    cmp al,0x08
    jnz .not_ready  ;若为准备好，继续等待

;第5步：从0x1f0端口读数据
    mov ax,di
    mov dx,256
    mul dx
    mov cx,ax
;di为要读取的扇区数，一个扇区有512字节，每次读入一个字，共需di*512/2次，所以di*256
    mov dx,0x1f0
  .go_on_read:
    in ax,dx
    mov [bx],ax
    add bx,2
    loop .go_on_read
    ret

    times 510-($-$$) db 0   ;填充mbr使其最后两个字节是0x55和0xaa
    db 0x55,0xaa