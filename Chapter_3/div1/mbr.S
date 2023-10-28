;主引导程序
;
;LOADER_BASE_ADDR equ 0xA000
;LOADER_START_SECTIOR equ 0x2
;----------------------------
SECTION MBR vstart=0x7c00   ;起始地址为0x7c00
    mov ax,cs
    mov ds,ax               ;由于BIOS通过 0:0x7c00跳转MBR，所以此时cs为0,因此借他来初始化寄存器
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00
    mov ax,0xb800       ;使用显卡文本模式，利用ax作为中转站将段基址赋给gs
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
    jmp $

    times 510-($-$$) db 0   ;填充mbr使其最后两个字节是0x55和0xaa
    db 0x55,0xaa
