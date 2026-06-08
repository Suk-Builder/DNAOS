#!/bin/bash
# DNAOS Build Script
# Compiles all .dna files → NASM → ELF64 → bootable kernel
# boot.S is assembled separately to preserve section declarations

set -e
export PATH=$HOME/.local/bin:$PATH

export WORKDIR=/tmp/dnaos_build_$(date +%s)
mkdir -p "$WORKDIR"

echo "=== DNAOS Build ==="
echo "Work dir: $WORKDIR"

# Step 1: Assemble boot.S separately (preserves section declarations)
echo "[1/5] Assembling boot.S → boot.o..."
nasm -f elf64 -w-all kernel/boot.S -o "$WORKDIR/boot.o"

# Step 2: Generate combined NASM from all .dna files (without boot.S)
echo "[2/5] Compiling DNAsm → NASM..."
python3 << 'PYEOF'
import re, struct, subprocess, os
from pathlib import Path

def compile_dna(f):
    result = subprocess.run(['python3', 'dasm/dasm.py', '-n', str(f)],
                          capture_output=True, text=True)
    return result.stdout

def f2h(v):
    packed = struct.pack('!f', v)
    return f'0x{struct.unpack("!I", packed)[0]:08x}'

text_lines = []
bss_lines = []

# Equ section — collect all equ definitions from .dna files
all_equs = {}
for f in sorted(Path('.').rglob('*.dna')):
    nasm_src = compile_dna(f)
    for line in nasm_src.split('\n'):
        m = re.match(r'^(\w+)\s+equ\s+(.+)$', line.strip())
        if m and m.group(1) not in all_equs:
            all_equs[m.group(1)] = m.group(2)

for name, val in all_equs.items():
    try:
        if '.' in val:
            fv = float(val)
            packed = struct.pack('!f', fv)
            hv = struct.unpack('!I', packed)[0]
            text_lines.append(f'{name} equ 0x{hv:08x}')
            continue
    except: pass
    text_lines.append(f'{name} equ {val}')
text_lines.append("")

# All .dna files (NOT boot.S — it's assembled separately)
text_lines.append("section .text")
seen_labels = set()
for f in sorted(Path('.').rglob('*.dna')):
    nasm_src = compile_dna(f)
    text_lines.append(f"; ====== {f} ======")
    for line in nasm_src.split('\n'):
        s = line.strip()
        if s.startswith('section ') or s.startswith('global ') or s.startswith('extern ') or ' equ ' in s:
            continue
        # Fix inline float constants in mov dword
        m2 = re.match(r'\s+mov dword \[rel (\w+)\], (-?\d+\.\d+)', s)
        if m2:
            try:
                fv = float(m2.group(2))
                packed = struct.pack('!f', fv)
                hv = struct.unpack('!I', packed)[0]
                text_lines.append(f'    mov dword [rel {m2.group(1)}], 0x{hv:08x}')
                continue
            except: pass
        # Skip duplicate labels
        lm = re.match(r'^(\w+):$', s)
        if lm and lm.group(1) in seen_labels: continue
        if lm: seen_labels.add(lm.group(1))
        text_lines.append(line)

# Stubs — functions referenced by .dna code but not yet implemented
text_lines.append("")
text_lines.append("; ====== STUBS ======")
stubs = [
    'scheduler_tick', 'worldgen_init', 'scriptvm_init',
    'ar_live_start', 'ar_set_mode_real_only', 'ar_set_mode_blend',
    'ar_sunrise_enhance', 'ar_hologram_iroha', 'ar_hologram_kaguya',
    'opening_run', 'launch_run',
    'consciousness_create', 'consciousness_update',
    'ecs_create_entity', 'ecs_destroy_entity',
    'fb_clear', 'fb_print_str', 'console_print',
    'lyrics_render', 'lyrics_update',
    'kaguya_update', 'iroha_update', 'yachiyo_update',
    'input_update', 'audio_update', 'particle_update',
    'voice_update', 'voice_map_to_world',
    'arch_update', 'holo_update', 'kassen_update', 'live_update',
    'sky_update', 'shadow_update', 'water_update',
    'rast_render', 'post_update', 'veg_update',
    'phys_update', 'ecs_update', 'ui_update',
    'vm_execute', 'vm_load_program',
    'atcg_result', 'mat4_multiply', 'scene_cull', 'sky_render',
]
for s in stubs:
    if s not in seen_labels:
        text_lines.append(f'{s}:')
        text_lines.append(f'    ret')

# ISR/IRQ handlers (called from boot.S ISR/IRQ stubs)
text_lines.append("")
text_lines.append("isr_handler:")
text_lines.append("    push rax")
text_lines.append("    mov al, 0x20")
text_lines.append("    out 0x20, al")
text_lines.append("    pop rax")
text_lines.append("    ret")
text_lines.append("")
text_lines.append("irq_handler:")
text_lines.append("    push rax")
text_lines.append("    push rcx")
text_lines.append("    push rdx")
text_lines.append("    cmp rax, 0")
text_lines.append("    je .irq_timer")
text_lines.append("    cmp rax, 1")
text_lines.append("    je .irq_keyboard")
text_lines.append("    jmp .irq_done")
text_lines.append(".irq_timer:")
text_lines.append("    call pit_irq_handler")
text_lines.append("    jmp .irq_done")
text_lines.append(".irq_keyboard:")
text_lines.append("    call keyboard_irq_handler")
text_lines.append(".irq_done:")
text_lines.append("    mov al, 0x20")
text_lines.append("    out 0x20, al")
text_lines.append("    cmp rax, 8")
text_lines.append("    jl .no_slave")
text_lines.append("    out 0xA0, al")
text_lines.append(".no_slave:")
text_lines.append("    pop rdx")
text_lines.append("    pop rcx")
text_lines.append("    pop rax")
text_lines.append("    ret")

# Float constants (for functions that use local float vars)
float_consts = {
    'phys_init_grav_x': 0.0, 'phys_init_grav_y': -9.81, 'phys_init_grav_z': 0.0,
    'phys_init_dt_60fps': 0.016667, 'phys_add_body_float_one': 1.0, 'phys_add_body_float_zero': 0.0,
    'phys_step_damping': 0.98, 'phys_step_float_zero': 0.0,
    'phys_raycast_float_max': 3.4028235e38,
    'camera_orbit_math_temp': 0, 'camera_orbit_math_sin': 0, 'camera_orbit_math_cos': 0,
    'camera_orbit_math_sin2': 0, 'camera_orbit_math_cos2': 0,
    'rast_init_float_one': 1.0, 'rast_write_pixel_zero_val': 0, 'rast_write_pixel_max_255': 255,
    'rast_write_pixel_float_255': 255.0,
    'rast_shade_fragment_ambient_strength': 0.001, 'rast_shade_fragment_float_one': 1.0,
    'scene_init_float_zero': 0, 'scene_init_float_one': 1.0,
    'scene_add_node_float_one': 1.0, 'scene_add_node_float_zero': 0.0,
    'tex_sample_nearest_tex_zero': 0, 'tex_sample_nearest_tex_inv_255': 0.003921,
    'tex_sample_bilinear_tex_zero': 0, 'tex_sample_bilinear_tex_half': 0.5,
    'tex_wrap_s_tex_zero_f': 0, 'tex_wrap_s_tex_one_f': 1.0, 'tex_wrap_s_tex_abs_mask': 0x7fffffff,
    'voice_map_to_world_note_g5': 783.99,
    'yachiyo_init_float_half': 0.5, 'yachiyo_init_float_zero': 0.0,
    'tsukuyomi_run_float_1000': 1000.0,
    'tsukuyomi_frame_time_speed': 1.0, 'tsukuyomi_frame_float_one': 1.0,
    'bloom_threshold_float_one': 1.0,
    'post_dof_buf_float_one': 1.0, 'post_bloom_buf_float_one': 1.0,
    'rast_clear_float_one': 1.0, 'rast_clear_depth_float_one': 1.0,
    'rast_transform_vertex_float_half': 0.5, 'rast_transform_vertex_float_one': 1.0,
    'rast_transform_vertex_float_two': 2.0,
    'rast_rasterize_triangle_float_zero': 0, 'rast_rasterize_triangle_zero_val': 0,
    'rast_rasterize_triangle_bb_min_x': 0, 'rast_rasterize_triangle_bb_min_y': 0,
    'rast_rasterize_triangle_bb_max_x': 0, 'rast_rasterize_triangle_bb_max_y': 0,
    'rast_rasterize_triangle_max_x_val': 0,
    'rast_rasterize_triangle_v0_sx': 0, 'rast_rasterize_triangle_v0_sy': 0,
    'worldgen_get_height_noise_scale': 0.01,
    'worldgen_get_terrain_h_beach': 0.3, 'worldgen_get_terrain_h_deep_water': -0.5,
    'worldgen_get_terrain_h_forest': 0.6, 'worldgen_get_terrain_h_grass': 0.4,
    'worldgen_get_terrain_h_mountain': 0.8, 'worldgen_get_terrain_h_water': 0.0,
    'input_get_axis_mouse_sensitivity': 0.002,
    'r0_dx': 0, 'r0_temp': 0,
}

text_lines.append("")
for name, val in float_consts.items():
    if isinstance(val, float):
        text_lines.append(f'{name} equ {f2h(val)}')
    else:
        text_lines.append(f'{name} equ {val}')

# BSS section
bss_lines.append("section .bss")
bss_lines.append("font_data: resb 4096")
bss_lines.append("_multiboot_info: resq 1")
if 'input_buf' not in seen_labels:
    bss_lines.append("input_buf: resb 256")

content = '\n'.join(text_lines) + '\n\n' + '\n'.join(bss_lines)

# Post-processing: register alias replacements
for old, new in [('rA_depth','r8'),('rA_temp','r8'),('rT_temp','r9'),('rC_temp','r10'),
                 ('rG_temp','r11'),('rP_out','r13'),('rP_save','r13'),('rS_save','r14'),
                 ('rB_save','r15'),('rG_fb','r11')]:
    content = re.sub(r'\b'+re.escape(old)+r'\b', new, content)

content = content.replace('lock bts [rP + rA*4], rdx', 'lock bts [rdi + rax*4], rdx')
content = content.replace('lock btr [rP + rA*4], rdx', 'lock btr [rdi + rax*4], rdx')

# Deduplicate labels that appear multiple times
for label in ['context_switch', 'syscall_entry', 'syscall_handler']:
    occs = list(re.finditer(r'^'+label+r':', content, re.MULTILINE))
    for i, m in enumerate(occs[1:], 1):
        content = content[:m.start()] + f'{label}_v{i}:' + content[m.end():]

# Remove register-name-only labels (e.g. "rax:")
for reg in ['rax','rbx','rcx','rdx','rsi','rdi','rbp','rsp','r8','r9','r10','r11','r12','r13','r14','r15']:
    content = re.sub(rf'^{reg}:\s*$', '', content, flags=re.MULTILINE)

# Fix inline float constants in mov dword instructions
def fix_float(m):
    prefix = m.group(1)
    val_str = m.group(2)
    try:
        fv = float(val_str)
        packed = struct.pack('!f', fv)
        hv = struct.unpack('!I', packed)[0]
        return f'{prefix}0x{hv:08x}'
    except:
        return m.group(0)

content = re.sub(r'(mov\s+dword\s+\[rel\s+\w+\]\s*,\s*)(-?\d+\.\d+)', fix_float, content)

# Replace local label references [rel .xxx] with [rel func_xxx]
# NASM local labels (.xxx) belong to the nearest non-local label (func)
# We need to replace them because float_consts defines func_xxx equ values
lines_for_local = content.split('\n')
current_func = None
for i, line in enumerate(lines_for_local):
    m = re.match(r'^(\w+):', line)
    if m:
        current_func = m.group(1)
    if current_func:
        lines_for_local[i] = re.sub(
            r'\[rel \.(\w+)\]',
            lambda m: f'[rel {current_func}_{m.group(1)}]',
            line
        )
content = '\n'.join(lines_for_local)

# Writable float variables need BSS allocation, not equ constants
# These are labels that appear in "movss dword [rel xxx], xmm" (write)
writable_floats = set()
for m in re.finditer(r'movss dword \[rel (\w+)\], xmm\d', content):
    writable_floats.add(m.group(1))

# Move BSS allocations from .text to .bss
lines = content.split('\n')
text_out = []
bss_out = ['section .bss']
bss_label_set = set()
current_label = None

# First pass: identify BSS labels (labels followed by resb/resw/resd/resq)
for i, line in enumerate(lines):
    s = line.strip()
    m = re.match(r'^(\w+):$', s)
    if m:
        current_label = m.group(1)
    if m and current_label not in bss_label_set:
        for j in range(i+1, min(i+3, len(lines))):
            ns = lines[j].strip()
            if not ns: continue
            if re.match(r'^res[bwdq]\s+', ns) or re.match(r'^times\s+\d+\s+res[bwdq]', ns):
                bss_label_set.add(current_label)
                break
            break

# Second pass: move BSS items to bss_out
in_bss = False
current_label = None
for line in lines:
    s = line.strip()
    m = re.match(r'^(\w+):$', s)
    if m:
        current_label = m.group(1)
    if s == 'section .bss':
        in_bss = True
        continue
    if s.startswith('section '):
        in_bss = False

    if in_bss:
        # Skip BSS labels that we're moving (they'll be in bss_out)
        if m and m.group(1) in bss_label_set:
            continue
        bss_out.append(line)
        continue

    is_res = re.match(r'^res[bwdq]\s+', s) or re.match(r'^times\s+\d+\s+res[bwdq]', s)
    if is_res and current_label in bss_label_set:
        if current_label not in [l.strip().rstrip(':') for l in bss_out if l.strip().endswith(':')]:
            bss_out.append(f'{current_label}:')
        bss_out.append(f'    {s}')
        text_out.append(f'; BSS: {s}')
        continue

    text_out.append(line)

content = '\n'.join(text_out) + '\n\n' + '\n'.join(bss_out)

# Remove duplicate labels and equ definitions
# Also: writable float vars need BSS, not equ — convert them
lines = content.split('\n')
defined = set()
output = []
for line in lines:
    s = line.strip()
    m = re.match(r'^(\w+):$', s)
    if m:
        if m.group(1) in defined:
            continue
        defined.add(m.group(1))
    m2 = re.match(r'^(\w+)\s+equ\s+', s)
    if m2 and m2.group(1) in defined:
        continue
    # Writable float vars: skip equ, add BSS allocation instead
    if m2 and m2.group(1) in writable_floats:
        # Will add BSS allocation below
        continue
    if m2:
        defined.add(m2.group(1))
    output.append(line)

# Add writable float BSS allocations
if writable_floats:
    output.append('section .bss')
    for wf in sorted(writable_floats):
        if wf not in defined:
            output.append(f'{wf}: resd 1')
            defined.add(wf)

workdir = os.environ.get('WORKDIR', '/tmp/dnaos_build')
with open(f'{workdir}/kernel.nasm', 'w') as f:
    f.write('\n'.join(output))

print(f'Generated {len(output)} lines')
PYEOF

# Step 3: Assemble kernel.nasm
echo "[3/5] Assembling kernel.nasm → kernel.o..."
nasm -f elf64 -w-all "$WORKDIR/kernel.nasm" -o "$WORKDIR/kernel.o"

# Step 4: Link boot.o + kernel.o
echo "[4/5] Linking..."
cat > "$WORKDIR/linker.ld" << 'LDEOF'
ENTRY(_start)
SECTIONS {
    . = 1M;
    .multiboot ALIGN(4K) : { *(.multiboot) }
    .text ALIGN(4K) : { *(.text.boot) *(.text) *(.text.*) }
    .rodata ALIGN(4K) : { *(.rodata) *(.rodata.*) }
    .data ALIGN(4K) : { *(.data) *(.data.*) }
    .bss ALIGN(4K) : { *(COMMON) *(.bss) *(.bss.*) }
    . = ALIGN(4K); . += 64K;
    /DISCARD/ : { *(.comment) *(.note.*) *(.eh_frame*) }
}
LDEOF

ld -T "$WORKDIR/linker.ld" -o "$WORKDIR/dnaos.elf" -nostdlib "$WORKDIR/boot.o" "$WORKDIR/kernel.o"

# Step 5: Verify multiboot header
echo "[5/5] Verifying multiboot header..."
python3 << 'PYEOF'
import struct, os
workdir = os.environ.get('WORKDIR', '/tmp/dnaos_build')
with open(f'{workdir}/dnaos.elf', 'rb') as f:
    data = f.read()

# Check Multiboot2 header
magic = struct.pack('<I', 0xE85250D6)
pos = data.find(magic)
if pos >= 0:
    length = struct.unpack_from('<I', data, pos + 8)[0]
    checksum = struct.unpack_from('<I', data, pos + 12)[0]
    expected_checksum = -(0xE85250D6 + 0 + length) & 0xFFFFFFFF
    if checksum == expected_checksum:
        print(f'Multiboot2 header OK at offset 0x{pos:x} (length={length}, checksum valid)')
    else:
        print(f'WARNING: Multiboot2 checksum mismatch! Got 0x{checksum:08x}, expected 0x{expected_checksum:08x}')
        data = bytearray(data)
        struct.pack_into('<I', data, pos + 12, expected_checksum)
        with open(f'{workdir}/dnaos.elf', 'wb') as f:
            f.write(data)
        print(f'Fixed checksum at offset 0x{pos:x}')
else:
    print('WARNING: No Multiboot2 header found!')

# Check Multiboot1 header
magic1 = struct.pack('<I', 0x1BADB002)
pos1 = data.find(magic1)
if pos1 >= 0:
    flags = struct.unpack_from('<I', data, pos1 + 4)[0]
    checksum = struct.unpack_from('<I', data, pos1 + 8)[0]
    expected_checksum = -(0x1BADB002 + flags) & 0xFFFFFFFF
    if checksum == expected_checksum:
        print(f'Multiboot1 header OK at offset 0x{pos1:x} (flags=0x{flags:08x}, checksum valid)')
    else:
        print(f'WARNING: Multiboot1 checksum mismatch! Got 0x{checksum:08x}, expected 0x{expected_checksum:08x}')
else:
    print('WARNING: No Multiboot1 header found!')
PYEOF

echo ""
echo "=== Build Complete ==="
ls -la "$WORKDIR/dnaos.elf"
file "$WORKDIR/dnaos.elf"
echo ""
echo "Entry: $(readelf -h $WORKDIR/dnaos.elf | grep 'Entry point' | awk '{print $NF}')"
echo "kernel_main: $(nm $WORKDIR/dnaos.elf | grep ' T kernel_main' | awk '{print $1}')"
echo ""
echo "Sections:"
readelf -S "$WORKDIR/dnaos.elf" | head -30
