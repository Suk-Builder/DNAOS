; ============================================================================
; DNAOS v3.5 M11 v17'' — 修切任务 (jmp label, 不 pop+jmp)
;
; v17 撞穿: scheduler 切任务 ESP 错位
; v17' 修法: pop eax + jmp eax (NASM 32-bit 段不允许 pop eip, 改 pop eax + jmp eax)
; v17' 撞穿: pop eax + jmp eax 时 pop 位置错 (scheduler 栈 vs task 栈)
; v17'' 修法: scheduler 不切任务 esp 后 pop jmp, **改用 jmp label 直接切**
;
; 极简设计:
;   scheduler 跑过 → 写 'A' 或 'B' marker + 改 current_task
;   **真正的切任务 = scheduler 切 esp 后, scheduler 末尾 jmp 到 task_A 或 task_B label**
;   task_A/task_B 跑 hlt, 让 PIT IRQ0 触发再切
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

; 装 PGD[0] + 8 PTE
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
    mov word [es:0x127C], 0x0003    ; PGT#0[0x9F] = 0x0009F003
    mov word [es:0x127E], 0x0009

; 装 GDT 段
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+8],  0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

%define GDT_START_PHYS (0x10200 + gdt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0017
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

; 初始化
    mov dword [0x90050], 0
    mov byte [0x90060], 0

    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; 32-bit VGA 写
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; 跳到 task_A (jmp label 直接跳)
    jmp task_A

.wait:
    hlt
    jmp .wait

; ============================================================================
; scheduler (IRQ0, INT 0x20) — 简化为 jmp label 切任务
;   入口: PIT IRQ0 触发, CPU push EIP/CS/EFLAGS (3 dword = 12 bytes)
;   100 ticks 切任务: 写 'A'/'B' marker, jmp 到 task_A 或 task_B label
;   不切任务: iret 回 task
;
; 简化: scheduler 不**用 push/pop 寄存器, 只改 current_task + jmp label
;   IRQ0 入口时 ESP = task_esp - 12, 装 ESP = task_esp 后 jmp 切任务
; ============================================================================
scheduler:
    ; 还原 task_esp (CPU push 3 dword)
    add esp, 12

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

    ; EOI
    mov al, 0x20
    out 0x20, al

    ; 10 ticks 切任务
    mov eax, [0x90050]
    and eax, 0x0F
    jnz .sched_iret

    ; 切任务
    mov al, [0x90060]
    xor al, 1
    mov [0x90060], al

    test al, 1
    jz .mark_A
    mov al, 'B'
    jmp .mark
.mark_A:
    mov al, 'A'
.mark:
    mov byte [0xB8006], al
    mov byte [0xB8007], 0x0E

    ; jmp 切任务 (直接跳 label, 不动 esp)
    test al, 1
    jz .jump_A
    jmp task_B
.jump_A:
    jmp task_A

.sched_iret:
    ; 不切任务, 还原 task_esp - 12 (CPU iret 会 pop 3 dword 还原)
    sub esp, 12
    iret

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
; PS/2 键盘 handler (简化: 不 push/pop 寄存器, 直接 iret)
;   入口: CPU 已 push EIP/CS/EFLAGS (3 dword = 12 字节)
;   跑: 读 0x60, EOI 0x20, 写 'K' + scancode hex
;   iret: pop 3 dword 还原
; ============================================================================
ps2_handler:
    ; 直接读 + EOI + 写 marker, **不** push/pop (避免栈错位)
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
gdt_start:     times 24 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
