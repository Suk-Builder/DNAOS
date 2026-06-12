[BITS 16]
org 0x0000

; DNAOS kernel v19 — WORKING BOOT
; Loaded to 0x10000 by MBR (via INT 13h retry)
; 
; Memory layout (when loaded to 0x10000):
;   0x10000: entry_16 (real mode)            <-- MBR jumps here
;   0x10070: GDTR (limit + base of GDT)
;   0x10078: GDT (3 entries: null, code, data)
;   0x10100: entry_32 (32-bit protected mode)
;
; The GDT base value 0x10076 (0x10000 + 0x76) is fixed manually in the binary
; because NASM's `dd gdt_start` returns the file offset (0x76), not the physical
; address. The build script patches this in.

entry_16:
    mov al, '1'
    mov dx, 0x3F8          ; COM1 serial port
    out dx, al

    mov ax, 0x1000         ; kernel is loaded at 0x1000:0x0000 = physical 0x10000
    mov ds, ax             ; DS=0x1000 so DS:0x70 = physical 0x10070 (where GDTR is)

    mov al, '2'
    mov dx, 0x3F8
    out dx, al

    in al, 0x92            ; A20 gate enable via port 0x92
    or al, 0x02
    out 0x92, al

    cli                    ; disable interrupts

    mov al, '3'
    mov dx, 0x3F8
    out dx, al

    lgdt [0x70]            ; load GDTR from DS:0x70 (physical 0x10070)

    mov al, '4'
    mov dx, 0x3F8
    out dx, al

    mov eax, cr0
    or eax, 1              ; set CR0.PE = 1
    mov cr0, eax

    mov al, '5'
    mov dx, 0x3F8
    out dx, al

    ; Far jump to flush prefetch queue and switch CS to GDT[1] (32-bit code segment)
    ; 32-bit operand size prefix needed to make offset a full 32-bit value
    db 0x66                ; operand size prefix (makes far jmp 32-bit form)
    db 0xEA                ; far jmp opcode
    dd 0x00010100          ; 32-bit offset = 0x10100 (entry_32)
    dw 0x0008              ; 16-bit segment = 0x08 (GDT code selector)

.halt:
    hlt
    jmp .halt

; Pad to offset 0x70 for GDTR
times 0x70 - ($ - $$) db 0x90

; === GDTR at offset 0x70 (physical 0x10070) ===
gdt_ptr:
    dw 0x0017              ; GDT limit = 23 (3 entries * 8 bytes - 1)
    dd 0x00010076          ; GDT base = 0x10000 (kernel load) + 0x76 (gdt_start offset)
                           ; *** HARD-CODED: see build script to fix this ***

; === GDT at offset 0x78 (physical 0x10078) ===
gdt_start:
    dq 0                   ; null descriptor (index 0, selector 0x00)

    ; Code segment: selector 0x08
    ; Base=0x00000000, Limit=0xFFFFFFFF (4GB with G=1), D=1 (32-bit), G=1
    dw 0xFFFF              ; limit 0-15
    dw 0x0000              ; base 0-15
    db 0x00                ; base 16-23
    db 10011010b           ; P=1, DPL=0, S=1, Type=Code/E/R/A
    db 11001111b           ; G=1, D=1, L=0, AVL=0, limit 16-19=0xF
    db 0x00                ; base 24-31

    ; Data segment: selector 0x10
    ; Base=0x00000000, Limit=0xFFFFFFFF, D=1, G=1
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b           ; P=1, DPL=0, S=1, Type=Data/R/W
    db 11001111b
    db 0x00

; Pad to 0x100 for entry_32
times 0x100 - ($ - $$) db 0x90
