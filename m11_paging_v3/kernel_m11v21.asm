; ============================================================================
; DNAOS v3.5 M11 v21 — scheduler 极简 pushad+切栈+popad+ret (OSDev 修法)
;
; v17-v20 撞穿真根因: 我用 iret (CPU 限制 ring 0↔0 不可用), 或用 ljmp TSS (TSS 物理算错)
; v21 修法 (OSDev 极简): 用 callee-saved regs (EBX, ESI, EDI, EBP) 不用 iret
;
; 关键: x86 32-bit ring 0↔0 切任务 极简方案 = 用 **ret** 跳新任务 EIP (不 iret)
;
; 设计:
;   IRQ0 触发时: task_A 跑 jmp task_A 死循环, PIT 触发 scheduler
;   scheduler 入口: CPU push EFLAGS+CS+EIP (12 字节) 到 task_A 栈
;   scheduler 跑: pushad (32 字节) + 装 ESP = [task_esp_A_save]  (保存 task_A ESP)
;   不切任务: popad + ret 还原 (ret 跳回 task_A 死循环)
;   切任务: 装 ESP = task_B 栈 + popad (还原 task_B 状态) + ret (跳 task_B 死循环)
;   task_B 跑 jmp task_B 死循环, PIT 触发 scheduler, scheduler 切回 task_A
;
; 关键: 切任务前 scheduler **必须** 装 kernel 段寄存器 (ds/es/fs/gs=0x10) 然后 popad 还原新任务段寄存器
; 关键: task 栈 预装 saved EIP (scheduler 切回时 ret 跳)
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
    mov al, 0xFE
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
; 初始化 2 任务栈
%define TASK_A_PHYS (0x10000 + (task_A - 0x10000))
%define TASK_B_PHYS (0x10000 + (task_B - 0x10000))

; task_A 栈布局 (从高到低):
;   0xA0F00: ESP 初始值 (scheduler 入口 push 12 字节 EFLAGS+CS+EIP 后 ESP=0xA0EF4)
;   0xA0EFC: 装 saved EIP (= task_A 物理) — scheduler 切回时 ret 跳
;   0xA0EF8: 装 saved CS (= 0x08) — 不需要, scheduler 不 ret 切
;
; 简化: scheduler 极简用 pushad (32 字节) + 装 kernel 段 (8 字节 = 4 段寄存器)
;       切任务: 装 esp = task_esp_B, popad + 还原 kernel 段 (mov ds=0x10 等)
;               然后 jmp 切任务 (不用 ret, 简化)
;
; 关键设计: scheduler 切任务直接 jmp label 跳到新任务入口
;   task_A 跑 jmp task_A 死循环, task_B 跑 jmp task_B 死循环
;   切任务: scheduler 装 ESP=task_esp, popad (8 dword, 还原 GPR)
;           切任务不**用 iret, 直接 jmp label 跳到新任务

; 初始化 task_A 栈 (task_esp_A = 0xA0F00, pushad 32 字节后 = 0xA0EE0)
;   0xA0EE0: EDI (装 0)
;   0xA0EE4: ESI (装 0)
;   0xA0EE8: EBP (装 0)
;   0xA0EEC: ESP (saved, 装 task_esp_A) — 不重要
;   0xA0EF0: EBX (装 0)
;   0xA0EF4: EDX (装 0)
;   0xA0EF8: ECX (装 0)
;   0xA0EFC: EAX (装 0)
;   然后 ESP 装 0xA0EE0, popad 还原 GPR 全 0, 跳到 task_A (用 jmp task_A, 不 ret)
;
; 等等, popad 8 dword 不**含段寄存器! 段寄存器没保存!**
; 关键: scheduler 装 ESP=task_esp 时, 也**要装**段寄存器 (ds/es/fs/gs) — 但切到 task_A 时 task_A 用什么段寄存器?
;
; 简化: 切到 task_A 之前 scheduler 装 kernel 段 (ds=es=fs=gs=0x10, ss=0x10)
;       task_A 跑 jmp task_A 死循环, PIT 触发 scheduler, scheduler 装 ESP=task_esp_A
;       装 kernel 段 (ds=es=fs=gs=0x10), popad 还原 (popad 装 ds? 不, popad 只装 GPR 8 个)
;       然后 jmp task_A — task_A 跑 jmp task_A 死循环
;
; 关键: scheduler 切任务**不**装段寄存器 (ds=es=fs=gs 已经=0x10, task 也用 0x10)
;       简化设计: task 只用 ds=es=fs=gs=0x10 (kernel 段), 切任务不用装段

; 初始化 task_A 栈
    mov edi, 0xA0EE0              ; task_A 栈 0xA0F00 - 32 (pushad 32 字节)
    mov dword [edi+0],  0          ; EDI
    mov dword [edi+4],  0          ; ESI
    mov dword [edi+8],  0          ; EBP
    mov dword [edi+12], 0          ; ESP (saved, 不重要)
    mov dword [edi+16], 0          ; EBX
    mov dword [edi+20], 0          ; EDX
    mov dword [edi+24], 0          ; ECX
    mov dword [edi+28], 0          ; EAX

; 初始化 task_B 栈
    mov edi, 0xB0EE0
    mov dword [edi+0],  0
    mov dword [edi+4],  0
    mov dword [edi+8],  0
    mov dword [edi+12], 0
    mov dword [edi+16], 0
    mov dword [edi+20], 0
    mov dword [edi+24], 0
    mov dword [edi+28], 0

    mov dword [0x90030], 0x000A0EE0  ; task_A esp (pushad 32 字节后)
    mov dword [0x90040], 0x000B0EE0  ; task_B esp
    mov dword [0x90050], 0           ; tick_count
    mov byte [0x90060], 0            ; current_task

    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; 32-bit VGA 写
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; 跳到 task_A
    jmp task_A

.wait:
    hlt
    jmp .wait

; ============================================================================
; scheduler (IRQ0, INT 0x20) — 极简 pushad+切栈+popad+jmp label
;
; 设计: 切任务用 jmp label 跳到新任务入口, 不用 iret
;       入口: CPU push EIP+CS+EFLAGS (12 字节) 到 task 栈
;             scheduler 装 ESP = task_esp_new, popad (32 字节) 还原 GPR
;             jmp task_label 跳
;       简化: scheduler 入口**不**用 pushad, 简化栈布局
;
; 入口: ESP 指向 task 栈 push 12 字节之后 (task 跑时被 PIT 触发, CPU push EIP+CS+EFLAGS)
;       scheduler 装 ESP=task_esp (装 12 字节 CPU push 之前的位置)
;       然后 scheduler 跑: EOI + tick_count + 'C' + 切任务标记
;       切任务: 装 ESP=task_esp_new + popad 还原 + jmp task_label
;
; 简化: scheduler 入口不 pop CPU push (因为 iret 不能用)
;       切任务: 装 ESP = task_esp_new (跟 init 时一样), 然后 jmp task_label
;       task 跑过 PIT 触发时 task 栈 会有 CPU push 的 12 字节, 累积
;       (累积错位, 跟 v17-v20 一样撞穿?)
;
; 极简修正: scheduler 入口 装 ESP=task_esp (还原), 然后跑, 然后 jmp task_label
;           task 跑 PIT 触发时, ESP=task_esp+8 (CPU push 12 字节 = 4 字节 align),
;           scheduler 入口装 ESP=task_esp, 还原, 跑, jmp task_label
; ============================================================================
scheduler:
    ; 1. 还原 ESP = 当前 task_esp (从 0x90060 标记取)
    ;    scheduler 切任务时把 current_task 标记到 0x90060 (A=0 / B=1)
    ;    入口装 ESP = [0x90030] if A else [0x90040]
    cmp byte [0x90060], 0
    je .sched_load_a
    mov esp, [0x90040]
    jmp .sched_loaded
.sched_load_a:
    mov esp, [0x90030]
.sched_loaded:

    ; 2. EOI
    mov al, 0x20
    out 0x20, al

    ; 3. tick_count++
    mov eax, [0x90050]
    inc eax
    mov [0x90050], eax

    ; 4. 串口 'C'
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    ; 5. VGA tick 数字
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl
    mov byte [0xB8005], 0x07

    ; 6. 5 ticks 切任务 (5 × 10ms = 50ms)
    mov eax, [0x90050]
    test eax, 0x04                  ; 5 ticks
    jz .sched_jmp                   ; 不切, jmp task_label

    ; 切任务
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

    ; 切任务: 装 ESP = task_esp_new, popad (还原 GPR), jmp task_label
    test al, 1
    jz .load_A
    mov esp, [0x90040]              ; task_B esp
    popad                            ; 还原 task_B GPR
    jmp task_B
.load_A:
    mov esp, [0x90030]              ; task_A esp
    popad                            ; 还原 task_A GPR
    jmp task_A

.sched_jmp:
    ; 不切任务, 还原当前 task
    popad                            ; 还原当前 task GPR (GPR 在 scheduler 装 ESP 后没被覆盖)
    jmp task_A                       ; (简化: 装 ds=0x10, jmp task_A — 实际不**用装段, ds=0x10)

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
gdt_start:     times 24 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
