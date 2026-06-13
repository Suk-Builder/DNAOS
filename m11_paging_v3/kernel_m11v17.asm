; ============================================================================
; DNAOS v3.5 M11 v17 — 极简, 2 任务 context switch (PIT IRQ0 切换)
;
; 万丈高楼平地起:
;   v16 = + PS/2 IRQ1 装好 ✓
;   v17 = + 2 任务 context switch (PIT 每 N ticks 切任务, 跑 A B A B A B)
;   (不用 ring 3, 不用 TSS, 不用 syscall, 只保存/恢复 ESP + EIP, 极简 kernel-only 调度)
;
; v17 极简:
;   1-15. (跟 v16 一样, 跑通基础)
;   16. 装 IDT[0x20] = scheduler (PIT handler 做调度)
;   17. 装 IDT[0x21] = PS2 handler (跟 v16 一样)
;   18. scheduler 跑:
;       - 保存 task_A.esp → 切到 task_B → 恢复 task_B.esp
;       - 切任务时 PIT tick 计数 >= 100 ticks 才切
;       - 任务切换写 'A' 或 'B' marker 到 VGA 0xB8006
;   19. task_A 跑: VGA 写 'A' 循环 (用 task_A.esp = 0xA0000)
;   20. task_B 跑: VGA 写 'B' 循环 (用 task_B.esp = 0xB0000)
;
; markers (v17):
;   H K G P X 3 ! I A S V + C (PIT tick) + A/B (任务切换)
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

; ----------------------------------------------------------------------------
; 装 PGD[0] + PGT#0[0x10] + PGT#0[0xB8] + PGT#0[0x8F] + PGT#0[0x90] + PGT#0[0xA0] + PGT#0[0xB0]
; ----------------------------------------------------------------------------
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
    mov word [es:0x1244], 0x0003    ; PGT#0[0x91] = 0x00091003 (scheduler 内部数据 @ 0x9102C, 0x90050, 0x90060)
    mov word [es:0x1246], 0x0009
    mov word [es:0x1280], 0x0003    ; PGT#0[0xA0] = 0x000A0003 (task_A 栈 @ PGT#0+0xA0*4=0x12280, [es:0x1280])
    mov word [es:0x1282], 0x000A
    mov word [es:0x12C0], 0x0003    ; PGT#0[0xB0] = 0x000B0003 (task_B 栈 @ PGT#0+0xB0*4=0x122C0, [es:0x12C0])
    mov word [es:0x12C2], 0x000B

; ----------------------------------------------------------------------------
; 装 GDT 段
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; 16→32 切
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; 32-bit 段 IDT 装 scheduler (INT 0x20) + PS2 handler (INT 0x21)
; ----------------------------------------------------------------------------
    mov edi, 0x10186

%define SCHED_PHYS (0x10000 + (scheduler - 0x10000))
%define PS2_PHYS   (0x10000 + (ps2_handler - 0x10000))
%define TASK_A_PHYS (0x10000 + (task_A - 0x10000))
%define TASK_B_PHYS (0x10000 + (task_B - 0x10000))

    ; IDT[0x20] = scheduler
    mov eax, SCHED_PHYS
    mov word [edi + 0x100 + 0], ax
    mov word [edi + 0x100 + 2], 0x0008
    mov word [edi + 0x100 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x100 + 6], ax

    ; IDT[0x21] = PS2 handler
    mov eax, PS2_PHYS
    mov word [edi + 0x108 + 0], ax
    mov word [edi + 0x108 + 2], 0x0008
    mov word [edi + 0x108 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x108 + 6], ax

    ; idt_desc
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

; ----------------------------------------------------------------------------
; 8259 PIC 重映射
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; PIT 通道 0 = 100Hz
; ----------------------------------------------------------------------------
    mov al, 0x36
    out 0x43, al
    mov al, 0x87
    out 0x40, al
    mov al, 0x2D
    out 0x40, al

; ----------------------------------------------------------------------------
; 初始化任务
;   task_A: 0xA0000 栈底, esp_init = 0xA0F00 (push 初始 EIP)
;   task_B: 0xB0000 栈底, esp_init = 0xB0F00
;   current_esp @ 0x90020 存当前 esp
;   task_a_esp @ 0x90030
;   task_b_esp @ 0x90040
; ----------------------------------------------------------------------------
    mov dword [0x90030], 0x000A0F00  ; task_A esp
    mov dword [0x90040], 0x000B0F00  ; task_B esp
    mov dword [0x90030 + 0xFFC], TASK_A_PHYS  ; task_A 栈 push eip (调 task_A)
    mov dword [0x90040 + 0xFFC], TASK_B_PHYS  ; task_B 栈 push eip
    mov dword [0x90050], 0            ; tick_count
    mov byte [0x90060], 0             ; current_task (0=A, 1=B)

    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; ----------------------------------------------------------------------------
; 32-bit 段 VGA 写 'P'
; ----------------------------------------------------------------------------
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

.wait:
    hlt
    jmp .wait

; ============================================================================
; scheduler (IRQ0, INT 0x20) — 每 100 ticks 切任务
; ============================================================================
scheduler:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp

    mov al, 0x20
    out 0x20, al

    ; tick_count++
    mov eax, [0x90050]
    inc eax
    mov [0x90050], eax

    ; VGA 写 tick 数字 (0xB8004 cell)
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl
    mov byte [0xB8005], 0x07

    ; 串口写 'C' (PIT 跑过)
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    ; 100 ticks 才切
    mov eax, [0x90050]
    and eax, 0x80        ; 0x80 = 128 = 0.8 秒 @ 100Hz
    jz .sched_done

    ; 切任务
    mov al, [0x90060]
    xor al, 1
    mov [0x90060], al

    ; 写 'A' 或 'B' marker 到 VGA 0xB8006
    mov al, [0x90060]
    test al, 1
    jz .sched_a
    mov al, 'B'
    jmp .sched_mark
.sched_a:
    mov al, 'A'
.sched_mark:
    mov byte [0xB8006], al
    mov byte [0xB8007], 0x0E          ; 黄色 attr

    ; 切 esp
    mov eax, cr3                       ; 保持 cr3 不变 (共享 page table)
    mov al, [0x90060]
    test al, 1
    jz .sched_load_a
    mov esp, [0x90040]                 ; 切到 task_B
    jmp .sched_switch
.sched_load_a:
    mov esp, [0x90030]                 ; 切到 task_A
.sched_switch:
    ; iret 时会从栈 pop eip/cs/eflags, 但我们手动 pop 寄存器再 ret
    ; 简化: iret 之前, 我们把 esp 保存到 task_esp[current] 然后装 task_esp[new]
    ; 这里 esp 已经是新任务的, iret 会跳新任务

.sched_done:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    iret

; ============================================================================
; task_A — 写 'a' 到 VGA 0xB8008
; ============================================================================
task_A:
    mov byte [0xB8008], 'a'
    mov byte [0xB8009], 0x0A          ; 绿色 attr
    jmp task_A

; ============================================================================
; task_B — 写 'b' 到 VGA 0xB800A
; ============================================================================
task_B:
    mov byte [0xB800A], 'b'
    mov byte [0xB800B], 0x0C          ; 红色 attr
    jmp task_B

; ============================================================================
; PS/2 键盘 handler (IRQ1, INT 0x21)
; ============================================================================
ps2_handler:
    push eax
    push edx

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

    pop edx
    pop eax
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
