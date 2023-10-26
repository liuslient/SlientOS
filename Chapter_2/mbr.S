;主引导程序
;----------------------------
SECTION MBR vstart=0x7c00   ;起始地址为0x7c00
    mov ax,cs
    mov ds,ax               ;由于BIOS通过 0:0x7c00跳转MBR，所以此时cs为0,因此借他来初始化寄存器
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00

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

;;;;;;;;;;;下面三行获取光标位置 ;;;;;;;;;;;
;.get_cursor获取当前光标位置，并在光标位置打印字符
    mov ah,3
    mov bh,0

    int 0x10

;;;;;;;;;;;获取光标位置结束 ;;;;;;;;;;;

;;;;;;;;;;;打印字符串 ;;;;;;;;;;;
    ;还是用10h中断，不过这次调用13号子功能打印字符串
    mov ax,message
    mov bp,ax   ;es:bp为串首地址，es此时同cs一致
                ;开头时已经为sreg初始化
    
    ;光标位置要用到dx寄存器中内容，cx中的光标位置可忽略
    mov cx,5
    mov ax,0x1301

    mov bx,0x2

    int 0x10

;;;;;;;;;;;;   打印字符串结束   ;;;;;;;;;;;;;;;
    jmp $

    message db "1 MBR"
    times 510-($-$$) db 0   ;填充mbr使其最后两个字节是0x55和0xaa
    db 0x55,0xaa
