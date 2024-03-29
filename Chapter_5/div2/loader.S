%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR  ;起始地址按照之前约定一样
LOADER_STACK_TOP equ LOADER_BASE_ADDR ;loader在实模式下的栈指针地址
;这里注意删掉了之前的jmp loader_start,转而对mbr.S进行了修改
;构建gdt及其内部描述符
GDT_BASE: dd 0x00000000             ;低4字节
          dd 0x00000000             ;高4字节，无效描述符，防止选择子未初始化
CODE_DESC: dd 0x0000FFFF            ;dd是伪指令，表示define double-word,也就是定义双字变量,这里的0xFFFF表示段界限
            dd DESC_CODE_HIGH4      ;代码段描述符
DATA_STACK_DESC: dd 0x0000FFFF      
                  dd DESC_DATA_HIGH4    ;栈段描述符，也就是数据段描述符,这俩共用一个段是因为方便，至于为什么这里栈的P位为什么不是1,也就是向下扩展，这是因为段描述符是由CPU检查的，而CPU并不知道这个段的作用，程序员若要实现栈向下扩展只需要使得其esp在push时减小即可
VIDEO_DESC: dd 0x80000007;limit=(0xbffff-0xb8000)/4k=0x7，这里的0xb8000~0xbffff是实模式下文本模式显存适配器的内存地址，因此段界限即为上述方程
            dd DESC_VIDEO_HIGH4 ;此时dpl为0，此乃显存段描述符
;-------- 以上共填充了3个段描述符 + 1个首段无效描述符-------------
GDT_SIZE equ $ - GDT_BASE           ;计算当前GDT已经填充的大小
GDT_LIMIT equ GDT_SIZE - 1          ;
times 60 dq 0           ;此处预留60个描述符空位，这里跟上面一致，表示define quad-word ,也就是定义60个以0填充的段描述符,这里的times是循环次数

;------ 这里定义选择子------------
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0   ;相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0   ;同上类似
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0   ;同上类似
  
  ;total_mem_bytes用于保存内存容量，以字节为单位，此位置比较好记
  ;当前偏移loader.bin 文件头0x200个字节
  ;loader.bin的加载地址是0x900 
  ;故total_mem_byte内存中的地址是0xb00
  ;将来在内核中我们会引用到这个地址
  total_mem_bytes dd 0
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;-------------- 以下定义gdt的指针，前2字节是gdt的界限，后4字节是gdt的起始地址 ---------
gdt_ptr dw GDT_LIMIT    ;define word
        dd GDT_BASE

;人工对齐：total_mem_bytes4+gdt_ptr6+ards_buf244+ards_nr2,共256字节,0x100
ards_buf times 244 db 0
ards_nr dw 0        ;用于记录ARDS结构体的数量

loader_start:
;------ int 15H eax = 0000E820,edx = 534D4150('SMAP') 获取内存布局-------
  xor ebx, ebx      ;第一次调用时，ebx置0
  mov edx, 0x534d4150 ;edx只赋值一次，循环体中不会改变
  mov di, ards_buf ;ards结构缓冲区,这里由于es我们在mbr.S中已经初始化，为0,所以这里我们不需要修改es，只需要对di赋值即可
.e820_mem_get_loop:
  mov eax, 0x0000e820   ;每次执行int 0x15之后，eax会变成0x534d4150,所以每次执行int之前都要更新为子功能号
  mov ecx, 20
  int 0x15
  jc .e820_failed_so_try_e801   ;若cf位为1则说明有错误发生，尝试下一个0xe801方法
  add di, cx            ;使di增加20字节指向缓冲区中新的ARDS结构位置
  inc word[ards_nr]     ;记录ARDS数量
  cmp ebx,0             ;若ebx为0且cf不为1,这说明ards全部返回
  jnz .e820_mem_get_loop
;在所有ards结构体中找出(base_add_low + length_low的最大值，即为内存容量
  mov cx, [ards_nr]     ;遍历每一个ards结构提，循环次数cx就是ards的数量
  mov ebx, ards_buf     ;将ebx中放入我们构造的缓冲区地址
  xor edx, edx          ;edx为最大的内存容量，在此先清0
.find_max_mem_area:     ;这里不需要判断type是否为1,最大的内存块一定是可被使用的
  mov eax, [ebx]
  add eax, [ebx+8]      ;这里ebx和ebx+8代表了BaseAddrLow 和 LengthLow
  add ebx, 20           ;ebx指向下一个ards结构体
  cmp edx, eax          ;冒泡排序，找出最大，edx寄存器始终是最大的内存容量
  jge .next_ards        ;大于或等于
  mov edx, eax          ;edx为总内存大小
.next_ards:
  loop .find_max_mem_area ;循环，以cx为循环次数
  jmp .mem_get_ok


;------ int 15H ax=E801h , 获取内存大小，最大支持4G------
;返回后，ax cx值一样，以KB为单位， bx dx 一样，以64KB为单位
;在ax和cx寄存器中为低16MB，在bx与dx寄存器中为16MB到4GB
.e820_failed_so_try_e801:
  mov ax, 0xe801
  int 0x15
  jc .e801_failed_so_try88  ;若cf位为1则说明有错误发生，尝试下一个88方法
;1 先算出低15MB的内存
; ax和cx中是以KB为单位的内存数量，因此我们将其转换为以byte为单位
  mov cx,0x400  ;这里由于cx和ax一样，所以我们将cx用作乘数，0x400即为1024
  mul cx        ;由于处于实模式，所以我们mul指令的含义是ax × cx，注意mul指令是16位乘法，生成乘数应该是32位，高16位在dx中，低16位存于ax中
  shl edx, 16   ;左移16位,这里也就是将dx保存的高16位转移到edx的高16位上
  and eax, 0x0000FFFF   ;将eax高16位清0
  or edx, eax   ;或后得出乘积，保存至edx中
  add edx, 0x100000     ;最后将差的那1MB加上
  mov esi, edx      ;这里保存一下edx的值，因为在之后的计算过程中他会被破坏

;2 再将16MB以上的内存转换为byte为单位
  xor eax, eax
  mov ax, bx
  mov ecx, 0x10000  ;0x10000为16进制的64K
  mul ecx           ;32位乘法，其高32位和低32位存放在edx和eax中
  add esi, eax      ;由于这里只能最大测出4GB，edx的值肯定为0，所以咱们只需要eax就可以了
  mov edx, esi      ;其中edx为总内存大小
  jmp .mem_get_ok

;----- int 15h ah=0x88 获取内存大小，只能获取64MB之内 -------
.e801_failed_so_try88:
  ;int 15h后，ax存入的是以KB为单位的内存容量
  mov ah, 0x88
  int 0x15
  jc .error_hlt
  and eax, 0x0000FFFF

  ;16位乘法
  mov cx, 0x400
  mul cx
  shl edx, 16
  or edx, eax
  add edx,0x100000  ;0x88子功能只会返回1MB以上的内存，所以最终我们还需要加上1MB

.error_hlt:
  jmp $

.mem_get_ok:
  mov [total_mem_bytes], edx            ;将内存换为bytes为单位然后存入total_mem_bytes中

;---------------- 准备进入保护模式 ------------------
;1 打开A20
;2 加载gdt
;3.将CR0的PE位置0,

  ;------------=- 打开A20 --------------
  in al,0x92
  or al,0000_0010B
  out 0x92,al

  ;------------- 加载GDT --------------
  lgdt [gdt_ptr]

  ;------------- CR0第0位置1 ----------
  mov eax, cr0
  or eax, 0x00000001
  mov cr0, eax

  jmp dword SELECTOR_CODE:p_mode_start ;刷新流水线

[bits 32]
p_mode_start:
  mov ax, SELECTOR_DATA
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov esp, LOADER_STACK_TOP
  mov ax, SELECTOR_VIDEO
  mov gs, ax

  mov byte [gs:160], 'p'

;创建页目录及页表并初始化页内存位图
  call setup_page

;要将描述符表地址及偏移量写入内存gdt_ptr,一会儿用新地址重新加载
  sgdt [gdt_ptr]      ;存储到原来gdt所有的位置

;将gdt描述符中视频段描述符中的段基址+0xc0000000
  mov ebx, [gdt_ptr + 2]        ;加上2是因为gdt_ptr的低2字节是偏移量，高四字节才是GDT地址
  or dword [ebx + 0x18 + 4], 0xc0000000   ;视频段是第3个段描述符，每个描述符是8字节，故为0x18，这里再加上4是因为咱们要的是高4字节，这里或的含义就类似与加，因为目前最高位肯定为0
;段描述符高四字节的最高位是段基址的第31～24位

;将gdt的基址加上0xc0000000使其成为内核所在的高地址
  add dword [gdt_ptr + 2], 0xc0000000
  
  add esp, 0xc0000000   ;将栈指针同样映射到内核地址

  ;把也目录地址附给cr3
  mov eax, PAGE_DIR_TABLE_POS
  mov cr3, eax

  ;打开cr0的pg位（第31位）
  mov eax, cr0
  or eax, 0x80000000
  mov cr0, eax

  ;在开启分页后，用gdt新的地址重新加载
  lgdt [gdt_ptr]    ;重新加载

  mov byte [gs:160], 'L'    ;视频段段基址已经被更新，用字符V表示vitual addr
  mov byte [gs:162], 'I'
  mov byte [gs:164], 'U'    
  mov byte [gs:166], 'T'
  mov byte [gs:168], 'I'
  mov byte [gs:170], 'A'    
  mov byte [gs:172], 'N'
  mov byte [gs:178], 'I'


  jmp $

;-------------  创建页目录以及页表 ------------
setup_page:
;先把页目录占用的空间逐字清0
  mov ecx, 4096     ;表示4K
  mov esi, 0
.clear_page_dir:
  mov byte [PAGE_DIR_TABLE_POS + esi], 0
  inc esi
  loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:    ;创建Page Directory Entry
  mov eax, PAGE_DIR_TABLE_POS
  add eax, 0x1000   ;此时eax为第一个页表的位置以及属性
  mov ebx, eax      ;此处为ebx赋值， 是为.create_pte做准备， ebx为基址
;下面将页目录项0和0xc00都存为第一个页表的地址，每个页表表示4MB内存
;这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表
;这是为将地址映射为内核地址做准备
  or eax, PG_US_U | PG_RW_W | PG_P
  ;页目录项的属性RW和P位为1,US为1表示用户属性，所有特权级都可以访问
  mov [PAGE_DIR_TABLE_POS + 0x0], eax       ;第一个目录项
    ;在页目录表中的地一个目录项写入第一个页表的位置（0x101000）及属性
  mov [PAGE_DIR_TABLE_POS + 0xc00], eax     ;一个页表项占用4字节
  ;0xc00表示第768个页表占用的页表项，0xc00以上的目录项用于内核空间,768用16进制表示为0x300，这个值再加就是刚好属于内核进程了
  ;也就是页表的0xc0000000~0xffffffff供给1G属于内核，0x0~0xbfffffff共计3G属于用户进程
  sub eax, 0x1000
  mov [PAGE_DIR_TABLE_POS + 4092], eax      ;使得最后一个目录项地址指向页目录表自己的地址

;开始创建页表项(PTE)
  mov ecx, 256                  ;1M低端内存/每页大小4K = 256
  mov esi, 0                    ;该页表用来分配0x0~0x3fffff的物理页，也就是虚拟地址0x0～0x3fffff和虚拟地址0xc0000000~0xc03fffff对应的物理页，我们现在只用了低1MB，所以此时虚拟地址是等于物理地址的
  mov edx, PG_US_U | PG_RW_W | PG_P     ;同上面类似
.create_pte:    ;创建Page Table Entry
  mov [ebx + esi*4], edx    ;此时ebx为第一个页表的首地址，这在上面咱们已经赋值了
  add edx, 4096
  inc esi
  loop .create_pte

;创建内核其他页面的PDE
  mov eax, PAGE_DIR_TABLE_POS 
  add eax, 0x2000       ;此时eax为第二个页表的位置
  or eax, PG_US_U | PG_RW_W | PG_P  ;同上
  mov ebx, PAGE_DIR_TABLE_POS 
  mov ecx, 254          ;范围为第769～1022的所有页目录项数量
  mov esi, 769
.create_kernel_pde:
  mov [ebx+esi*4], eax
  inc esi
  add eax, 0x1000
  loop .create_kernel_pde
  ret