#!/usr/bin/env python3
"""Auto-fix common DNAsm source issues"""
import re, sys, os

def fix_file(path):
    with open(path, 'r') as f:
        content = f.read()
    
    original = content
    
    # Fix: rA_temp → r8, rP_save → r13, etc. (temp registers)
    temp_map = {
        'rA_temp': 'r8', 'rT_temp': 'r9', 'rC_temp': 'r10', 'rG_temp': 'r11',
        'rP_save': 'r13', 'rS_save': 'r14', 'rB_save': 'r15',
    }
    for old, new in temp_map.items():
        content = re.sub(r'\b' + re.escape(old) + r'\b', new, content)
    
    # Fix: in dl, PORT → in al, PORT / mov dl, al
    # Fix: in rC.b, PORT → in al, PORT
    content = re.sub(r'in\s+dl,\s*(0x[0-9a-fA-F]+)', r'in al, \1', content)
    content = re.sub(r'in\s+rC\.b,\s*(0x[0-9a-fA-F]+)', r'in al, \1', content)
    
    # Fix: out rdi, al → out dx, al (need mov dx, rdi first - skip, manual fix)
    # Fix: out rdi, eax → out dx, eax (skip, manual fix)
    # Fix: out rax, dx → out dx, al (skip, manual fix)
    
    # Fix: imul 0xa → imul rax, 0xa (single-operand imul needs register)
    content = re.sub(r'^(\s*)imul\s+(0x[0-9a-fA-F]+)', r'\1imul rax, \2', content, flags=re.MULTILINE)
    
    # Fix: addss xmm0, 0x... → addss xmm0, dword [rel ...] (SSE needs memory operand)
    # This is too complex to auto-fix, skip
    
    # Fix: mov byte [rbx], [rax] → need temp register
    # Too complex, skip
    
    # Fix: comiss xmm0, 0x... → comiss xmm0, dword [rel ...]
    # Skip, needs manual fix
    
    # Add .extern for common cross-file symbols
    common_externs = {
        'scheduler_tick': 'kernel/drivers/pit.dna',
        'pit_ticks': 'kernel/net/tcpip.dna',
        'font_data': 'kernel/drivers/vga.dna',
        'keyboard_getchar': 'kernel/shell/dnasm.dna',
        'pmm_bitmap': 'kernel/mm/pmm.dna',
        'ar_init': 'kernel/engine/launch.dna',
        'worldgen_init': 'kernel/engine/opening.dna',
        'CONSCIOUSNESS_BORN': 'kernel/engine/kaguya.dna',
        'CONSCIOUSNESS_HUMAN': 'kernel/engine/iroha.dna',
        'WM_TITLE_H': 'kernel/engine/ui.dna',
    }
    
    # Check which externs are needed
    needed_externs = []
    for sym in common_externs:
        if re.search(r'\b' + sym + r'\b', content) and f'.extern {sym}' not in content:
            # Check if it's defined in THIS file
            if not re.search(r'^' + sym + r':', content, re.MULTILINE):
                needed_externs.append(sym)
    
    if needed_externs:
        # Find the .code section and add externs after .global declarations
        extern_block = '\n'.join(f'.extern {s}' for s in needed_externs)
        if '.code' in content:
            content = content.replace('.code', extern_block + '\n.code', 1)
        else:
            content = extern_block + '\n' + content
    
    if content != original:
        with open(path, 'w') as f:
            f.write(content)
        return True
    return False

if __name__ == '__main__':
    base = sys.argv[1] if len(sys.argv) > 1 else '.'
    fixed = 0
    for root, dirs, files in os.walk(base):
        for fn in files:
            if fn.endswith('.dna'):
                path = os.path.join(root, fn)
                if fix_file(path):
                    fixed += 1
                    print(f'Fixed: {path}')
    print(f'\nTotal files fixed: {fixed}')
