%include "boot.inc" 
section loader vstart=LOADER_BASE_ADDR 
LOADER_STACK_TOP equ LOADER_BASE_ADDR
;构建gdt及其内部的描述符
   GDT_BASE:  dd 0x00000000
              dd 0x00000000
  
   CODE_DESC: dd 0x0000FFFF
              dd DESC_CODE_HIGH4

   DATA_STACK_DESC: dd 0x0000FFFF
                    dd DESC_DATA_HIGH4

VIDEO_DESC: dd 0x80000007        ; limit=(0xbffff-0xb8000)/4k=0x7  故段界限为7
	    dd DESC_VIDEO_HIGH4  ;此时dpl为0

   GDT_SIZE equ $ - GDT_BASE
   GDT_LIMIT equ GDT_SIZE - 1
   times 60 dq 0                 ;此处预留 60 个描述符的空位

   ;total_mem_bytes用于保存内存容量,以字节为单位
   ;当前偏移loader.bin文件头0x200字节
   ;loader.bin加载地址是0x900
   ;故total_mem_bytes代表的内存地址是0xb00
   total_mem_bytes dd 0


   SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0 
   SELECTOR_DATA equ (0x0002<< 3) + TI_GDT + RPL0 
   SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0

   ;以下是 gdt 的指针即GDTR，前2字节是gdt界限，后4字节是gdt起始地址

   gdt_ptr dw GDT_LIMIT 
           dd GDT_BASE 


;人工对齐:total_mem_bytes+gdt_ptr+ards_buf+ards_nr=4+6+244+2=256,共256字节
   ards_buf times 244 db 0 
   ards_nr dw 0 ;用于记录 ARDS 结构体数量

   loader_start: 

; int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP')获取内存布局


	xor ebx, ebx   					; 异或运算，第一次使用0xe820子功能ebx要清0
	mov edx, 0x534d4150 			;edx 只赋值一次，循环体中不会改变
	mov di, ards_buf  				;ards结构缓冲区
.e820_mem_get_loop: 
	mov eax, 0x0000e820 			;执行int Oxl5 后，eax 值变为 Ox534d4150,
; 所以每次执行int前都要更新为子功能号
	mov ecx, 20  				; 1个ards结构体大小为20字节
   int 0x15;
	jc .e820_failed_so_try_e801 
;cf 位为 1则 有错误发生，尝试 Oxe801子功能 
	add di, cx 					;使di 增加 20 字节指向缓冲区中新的 ARDS 结构位置
	inc word [ards_nr] 			;记录 ARDS 数量
   cmp ebx, 0 					;若ebx为0且cf不为1，这说明ards全部返回
	jnz .e820_mem_get_loop

;在所有 ards 结构中
;找出（base_add low + length_low ）的最大值，即内存的容量
	mov cx, [ards_nr] 
;遍历每一个 ARDS 结构体，循环次数是 ARDS 的数量
	mov ebx, ards_buf 
	xor edx, edx   				;ebx为最大容量，在此先清0
.find_max_mem_area: 
;无需判断 type 是否为1，最大的内存块一定是可被使用的 
	mov eax, [ebx] ;缓冲区首地址就是第一个结构体的base_add_low,移了32位 
	add eax, [ebx+8] ;base_add_low+length_low 
   add ebx, 20 ;指向缓冲区中下－个 ARDS 结构
 	cmp edx, eax 
;冒泡排序，找出最大,edx寄存器始终记录最大的内存容量
	jge .next_ards
	mov edx, eax    ;edx为总内存大小
.next_ards: 
   loop .find_max_mem_area
   jmp .mem_get_ok

;--------int 15h ax = EBOlh 获取内存大小，最大支持4G-----------
;返回后， ax ex 一样，以 KB 为单位， bx dx 值一样，以 64KB 为单位
;在 ax ex 寄存器中为低16MB ，在 bx dx 寄存器中为16MB到4GB
.e820_failed_so_try_e801:
   mov ax,0xe801 
   int 0x15 ;调用0xe810子功能
   jc .e801_failed_so_try88   ;cf为1表示出错
 
;1 先算出低 15MB 的内存
;ax ex 中是以 KB 为单位的内存数量，将其转换为以 byte 为单位
   mov cx, 0x400;  cx ax 值一样， cx 用作乘数 0x400字节=1KB
   mul cx
   shl edx,16 
   and eax,0x0000FFFF 
   or edx,eax
   add edx, 0x100000   ;ax只是15MB,故要加1MB
   mov esi,edx  ;低15MB内存容量存入esi

;2 再将 16MB 以上的内存转换为 byte 为单位
;寄存器 bx dx 中是以 64KB 为单位的内存数量
   xor eax, eax 
   mov ax, bx 
   mov ecx, 0x10000 				;0x10000 十进制为64KB
   mul ecx 							; 32 位乘法，默认的被乘数是 eax ，积为 64位
									;高 32 位存入 edx ，低 32 位存入 eax
   add esi, eax 
;由于此方法只能测出 4GB 以内的内存，故 32位eax 足够了
	; edx 肯定为0，只加 eax 便可
   mov edx, esi ;edx 为总内存大小
   jmp .mem_get_ok 

;---------int 15h ah = Ox88 获取内存大小，只能获取 64MB 之内--------
.e801_failed_so_try88: 
	;int 15 后， ax 存入的是以 KB 为单位的内存容量 100 mov ah, Ox88 
   int 0x15 
   jc .error_hlt 
   and eax,0x0000FFFF

;16 位乘法，被乘数是 ax ，积为 32 位。积的高 16 位在 dx
;积的低 16 位在 ax
   mov cx, 0x400 
   mul cx
   shl edx, 16 					;把 dx 移到高 16
   or edx, eax 					;把积的低 16 位组合到 edx ，为 32 位的积
   add edx, 0x100000 			; Ox88 子功能只会返回 lMB 以上的内存
				;故实际内存大小要加上 lMB
.error_hlt:
   jmp $
.mem_get_ok: 
   mov [total_mem_bytes ], edx   ;3种子功能均是把最大容量放入edx


;-------- 准备进入保护模式 ----------
;1 打开 A20
;2 加载 gdt
;3 将cr0的pe位置1 


;--------打开A20---------
in al,0x92
or al,0000_0010B
out 0x92,al

;-------加载GDT---------
lgdt [gdt_ptr]


;------cr0第0位置1-----

mov eax, cr0
or eax,0x00000001
mov cr0,eax

jmp dword SELECTOR_CODE:p_mode_start  ;刷新流水线

[bits 32]
p_mode_start:
	mov ax, SELECTOR_DATA 
	mov ds, ax 
	mov es, ax 
	mov ss, ax 
	mov esp, LOADER_STACK_TOP 
	mov ax, SELECTOR_VIDEO 
	mov gs, ax 


; 创建页目录及页表并初始化页内存位图
   call setup_page

   ;要将描述符表地址及偏移量写入内存gdt_ptr,一会用新地址重新加载
   sgdt [gdt_ptr]	      ; 存储到原来gdt所有的位置

   ;将gdt描述符中视频段描述符中的段基址+0xc0000000
   mov ebx, [gdt_ptr + 2]  
   or dword [ebx + 0x18 + 4], 0xc0000000      
   ;视频段是第3个段描述符,每个描述符是8字节,故0x18。
	;段描述符的高4字节的最高位是段基址的31~24位

   ;将gdt的基址加上0xc0000000使其成为内核所在的高地址
   add dword [gdt_ptr + 2], 0xc0000000

   add esp, 0xc0000000        ; 将栈指针同样映射到内核地址

   ; 把页目录地址赋给cr3
   mov eax, PAGE_DIR_TABLE_POS
   mov cr3, eax

   ; 打开cr0的pg位(第31位)
   mov eax, cr0
   or eax, 0x80000000
   mov cr0, eax

   ;在开启分页后,用gdt新的地址重新加载
   lgdt [gdt_ptr]             ; 重新加载

   mov  byte [gs:160], 'V'    ; 视频段段基址已被更新，用v表示virtual addr
   jmp $


;------------- 创建页目录及页表 ---------------
setup_page:
;先把页目录占用的空间逐字节清0
   mov ecx, 4096
   mov esi, 0
.clear_page_dir:
   mov byte [PAGE_DIR_TABLE_POS + esi], 0
   inc esi
   loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:				         ; 创建Page Directory Entry
   mov eax, PAGE_DIR_TABLE_POS
   add eax, 0x1000 			      ; 此时eax为第一个页表的位置及属性
   mov ebx, eax				      ; 此处为ebx赋值，是为.create_pte做准备，ebx为基址。

;   下面将页目录项0和0xc00都存为第一个页表的地址，
;   一个页表可表示4MB内存,这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表，
;   这是为将地址映射为内核地址做准备
   or eax, PG_US_U | PG_RW_W | PG_P	     ; 页目录项的属性RW和P位为1,US为1,表示用户属性,所有特权级别都可以访问.
   mov [PAGE_DIR_TABLE_POS + 0x0], eax       ; 第1个目录项,在页目录表中的第1个目录项写入第一个页表的位置(0x101000)及属性(3)
   mov [PAGE_DIR_TABLE_POS + 0xc00], eax     ; 一个页表项占用4字节,0xc00表示第768个页表占用的目录项,0xc00以上的目录项用于内核空间,
					     ; 也就是页表的0xc0000000~0xffffffff共计1G属于内核,0x0~0xbfffffff共计3G属于用户进程.
   sub eax, 0x1000
   mov [PAGE_DIR_TABLE_POS + 4092], eax	     ; 使最后一个目录项指向页目录表自己的地址

;下面创建页表项(PTE)
   mov ecx, 256				     ; 1M低端内存 / 每页大小4k = 256
   mov esi, 0
   mov edx, PG_US_U | PG_RW_W | PG_P	     ; 属性为7,US=1,RW=1,P=1
.create_pte:				     ; 创建Page Table Entry
   mov [ebx+esi*4],edx			     ; 此时的ebx已经在上面通过eax赋值为0x101000,也就是第一个页表的地址 
   add edx,4096
   inc esi
   loop .create_pte

;创建内核其它页表的PDE
   mov eax, PAGE_DIR_TABLE_POS
   add eax, 0x2000 		     ; 此时eax为第二个页表的位置
   or eax, PG_US_U | PG_RW_W | PG_P  ; 页目录项的属性RW和P位为1,US为0
   mov ebx, PAGE_DIR_TABLE_POS
   mov ecx, 254			     ; 范围为第769~1022的所有目录项数量
   mov esi, 769
.create_kernel_pde:
   mov [ebx+esi*4], eax
   inc esi
   add eax, 0x1000
   loop .create_kernel_pde
   ret
