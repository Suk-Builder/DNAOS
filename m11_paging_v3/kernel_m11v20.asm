; ============================================================================
; DNAOS v3.5 M11 v20 — hardware TSS + ljmp 切任务 (Linux 0.01 switch_to 修法)
;
; v17/v18/v19 撞穿: scheduler 切任务没用 hardware TSS + ljmp
; v20 修法: 装 GDT[4] = TSS0 descriptor (task_A) + GDT[6] = TSS1 descriptor (task_B)
;           scheduler 入口 ltr 装当前 TSS, 切任务 ljmp 到新 TSS descriptor
;
; 关键: x86 32-bit 切任务**只能**用 ljmp TSS descriptor (CPU 自动保存/恢复 task state)
; ============================================================================

BITS 16

org 0x10000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

; 装 PGD[0] + 9 PTE
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw

    mov word [es:0], 0x2003
    mov word [es:2], 0x0001
    mov word [es:0x1040], 0x0003
    mov word [es:0x1042], 0x0001
    mov word [es:0x12E0], 0xB803
    mov word [es:0x12E2], 0x000B
    mov word [es:0x123C], 0xF003
    mov word [es:0x123E], 0x0008
    mov word [es:0x1240], 0x0003
    mov word [es:0x1242], 0x0009
    mov word [es:0x1244], 0x0003
    mov word [es:0x1246], 0x0009
    mov word [es:0x1280], 0x0003
    mov word [es:0x1282], 0x000A
    mov word [es:0x12C0], 0x0003
    mov word [es:0x12C2], 0x000B
    mov word [es:0x127C], 0x0003
    mov word [es:0x127E], 0x0009

; 装 GDT 段 (5 段: null, code, data, TSS0, TSS1)
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+8],  0x0000FFFF    ; GDT[1] code 32 @ 0x08
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF    ; GDT[2] data 32 @ 0x10
    mov dword [bx+20], 0x00CF9200

    ; GDT[3] @ 0x18: TSS0 descriptor (TSS 32-bit 不可用段)
    ; TSS descriptor = [limit_low, base_low, base_mid, type, granularity, base_high]
    ; type 0x89 = 0b10001001 = present(1) + DPL(0) + type(9=32-bit TSS available)
    ; granularity 0x40 = 0b01000000 = G(0=byte) + D(0=16-bit ops) + AVL(0) + limit_high(0100=0x1)
    ; limit = 103 (TSS 26 long = 104 bytes, 0x68)
    ; base = tss0_phys
%define TSS0_PHYS (0x10200 + (tss0 - gdt_start))
%define TSS1_PHYS (0x10200 + (tss1 - gdt_start))

    mov word [bx+24], 0x0068            ; limit low 0x68 (104 bytes)
    mov word [bx+26], (TSS0_PHYS & 0xFFFF)
    mov byte [bx+28], ((TSS0_PHYS >> 16) & 0xFF)
    mov byte [bx+29], 0x89              ; type 0x89 (TSS available 32-bit)
    mov byte [bx+30], 0x40              ; granularity 0x40
    mov byte [bx+31], ((TSS0_PHYS >> 24) & 0xFF)

    ; GDT[4] @ 0x20: TSS1 descriptor
    mov word [bx+32], 0x0068
    mov word [bx+34], (TSS1_PHYS & 0xFFFF)
    mov byte [bx+36], ((TSS1_PHYS >> 16) & 0xFF)
    mov byte [bx+37], 0x89
    mov byte [bx+38], 0x40
    mov byte [bx+39], ((TSS1_PHYS >> 24) & 0xFF)

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

%define GDT_START_PHYS (0x10200 + gdt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0027                ; limit = 0x27 = 39 (5 entries × 8 - 1)
    mov word [bx+2], (GDT_START_PHYS & 0xFFFF)
    mov word [bx+4], (GDT_START_PHYS >> 16)

    lgdt [bx]

; 16→32 切
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    db 0x66, 0xEA
    dd pm_entry_phys
    dw 0x0008

; ============================================================================
; 32-bit PM 段
; ============================================================================
BITS 32

pm_entry_phys equ 0x10000 + (pm_entry - 0x10000)

pm_entry:
    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

; 32-bit 段设
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    mov dx, 0x3F8
    mov al, 'X'
    out dx, al

; 分页开
    mov eax, 0x11000
    mov cr3, eax

    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov dx, 0x3F8
    mov al, '!'
    out dx, al

; IDT 装 scheduler + PS2 handler
    mov edi, 0x10186

%define SCHED_PHYS (0x10000 + (scheduler - 0x10000))
%define PS2_PHYS   (0x10000 + (ps2_handler - 0x10000))

    mov eax, SCHED_PHYS
    mov word [edi + 0x100 + 0], ax
    mov word [edi + 0x100 + 2], 0x0008
    mov word [edi + 0x100 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x100 + 6], ax

    mov eax, PS2_PHYS
    mov word [edi + 0x108 + 0], ax
    mov word [edi + 0x108 + 2], 0x0008
    mov word [edi + 0x108 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x108 + 6], ax

    mov eax, 0x10186
    mov word [0x10986 + 2], ax
    shr eax, 16
    mov word [0x10986 + 4], ax
    mov word [0x10986 + 0], 0x07FF
    mov word [0x10986 + 6], 0

    lidt [0x10986]

    mov dx, 0x3F8
    mov al, 'I'
    out dx, al

; 8259 PIC 重映射
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    mov dx, 0x3F8
    mov al, 'A'
    out dx, al

; PIT 100Hz
    mov al, 0x36
    out 0x43, al
    mov al, 0x87
    out 0x40, al
    mov al, 0x2D
    out 0x40, al

; ----------------------------------------------------------------------------
; 装 task_A TSS0 + task_B TSS1
;   TSS0: esp0=0xA0F00, eip=task_A_phys, cs=0x08, ss=0x10, ds=es=fs=gs=0x10
;   TSS1: esp0=0xB0F00, eip=task_B_phys, cs=0x08, ss=0x10, ds=es=fs=gs=0x10
%define TASK_A_PHYS (0x10000 + (task_A - 0x10000))
%define TASK_B_PHYS (0x10000 + (task_B - 0x10000))

    mov edi, TSS0_PHYS
    mov dword [edi + 4], 0x000A0F00      ; esp0
    mov dword [edi + 8], 0x00000010      ; ss0
    mov dword [edi + 12], 0x000A0F00     ; esp
    mov dword [edi + 56], 0x00000010     ; ss
    mov dword [edi + 60], 0x00000010     ; ds
    mov dword [edi + 64], 0x00000010     ; es
    mov dword [edi + 68], 0x00000010     ; fs
    mov dword [edi + 72], 0x00000010     ; gs
    mov dword [edi + 76], TASK_A_PHYS    ; eip
    mov dword [edi + 80], 0x00000008     ; cs
    mov dword [edi + 84], 0x00000202     ; eflags (IF=1)

    mov edi, TSS1_PHYS
    mov dword [edi + 4], 0x000B0F00      ; esp0
    mov dword [edi + 8], 0x00000010      ; ss0
    mov dword [edi + 12], 0x000B0F00     ; esp
    mov dword [edi + 56], 0x00000010     ; ss
    mov dword [edi + 60], 0x00000010     ; ds
    mov dword [edi + 64], 0x00000010     ; es
    mov dword [edi + 68], 0x00000010     ; fs
    mov dword [edi + 72], 0x00000010     ; gs
    mov dword [edi + 76], TASK_B_PHYS    ; eip
    mov dword [edi + 80], 0x00000008     ; cs
    mov dword [edi + 84], 0x00000202     ; eflags

    mov dword [0x90050], 0            ; tick_count
    mov byte [0x90060], 0             ; current_task

; ltr 装当前 TSS (TSS0 @ GDT[3] = selector 0x18)
    mov ax, 0x18
    ltr ax

    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; 32-bit VGA 写
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; 跳到 task_A (用 ljmp TSS0 selector 0x18)
    db 0xEA
    dd 0x00000000
    dw 0x0018                       ; TSS0 selector

.wait:
    hlt
    jmp .wait

; ============================================================================
; scheduler (IRQ0, INT 0x20) — ljmp 切任务
;   跑: tick_count++ + 'C' marker + 切任务 ljmp
;   ljmp %TSS_descriptor — CPU 自动保存当前 task state 到 current TSS,
;   装新 task state 从新 TSS, 跳到新 task EIP
; ============================================================================
scheduler:
    ; 还原 esp (PIT IRQ0 触发时 CPU push EIP/CS/EFLAGS)
    add esp, 12

    ; EOI
    mov al, 0x20
    out 0x20, al

    ; tick_count++
    mov eax, [0x90050]
    inc eax
    mov [0x90050], eax

    ; 串口 'C'
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    ; VGA tick 数字
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl
    mov byte [0xB8005], 0x07

    ; 10 ticks 切任务
    mov eax, [0x90050]
    and eax, 0x0F
    jz .switch_task
    iret                               ; 不切任务 iret

.switch_task:
    mov al, [0x90060]
    xor al, 1
    mov [0x90060], al

    ; 写 'A'/'B' marker
    test al, 1
    jz .mark_A
    mov al, 'B'
    jmp .mark
.mark_A:
    mov al, 'A'
.mark:
    mov byte [0xB8006], al
    mov byte [0xB8007], 0x0E

    ; ljmp 切任务
    test al, 1
    jz .ljmp_A
    db 0xEA
    dd 0x00000000
    dw 0x0020                       ; TSS1 selector (GDT[4])
.ljmp_A:
    db 0xEA
    dd 0x00000000
    dw 0x0018                       ; TSS0 selector (GDT[3])

; ============================================================================
; task_A
; ============================================================================
task_A:
    mov byte [0xB8008], 'a'
    mov byte [0xB8009], 0x0A
    jmp task_A

; ============================================================================
; task_B
; ============================================================================
task_B:
    mov byte [0xB800A], 'b'
    mov byte [0xB800B], 0x0C
    jmp task_B

; ============================================================================
; PS/2 键盘 handler
; ============================================================================
ps2_handler:
    in al, 0x60
    mov ah, al
    mov al, 0x20
    out 0x20, al
    mov dx, 0x3F8
    mov al, 'K'
    out dx, al
    mov al, ah
    shr al, 4
    cmp al, 10
    jb .ps2_hex1
    add al, 'a' - 10
    jmp .ps2_hex1_out
.ps2_hex1:
    add al, '0'
.ps2_hex1_out:
    mov dx, 0x3F8
    out dx, al
    mov al, ah
    and al, 0xF
    cmp al, 10
    jb .ps2_hex2
    add al, 'a' - 10
    jmp .ps2_hex2_out
.ps2_hex2:
    add al, '0'
.ps2_hex2_out:
    mov dx, 0x3F8
    out dx, al
    mov al, ' '
    out dx, al
    iret

; ============================================================================
; BSS
; ============================================================================
gdt_start:     times 40 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0
tss0:          times 104 db 0
tss1:          times 104 db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
