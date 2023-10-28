%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR

    mov byte [gs:0x00],'H'
    mov byte [gs:0x01],0x94

    mov byte [gs:0x02],'E'
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'L'
    mov byte [gs:0x05],0xA4

    mov byte [gs:0x06],'L'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'O'
    mov byte [gs:0x09],0x94

    mov byte [gs:0x0a],'!'
    mov byte [gs:0x0b],0xA4

jmp $