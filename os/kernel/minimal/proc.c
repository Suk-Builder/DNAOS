#include "proc.h"
#include "pmm.h"
#include "vmm.h"
#include "serial.h"
#include "idt.h"
#include <stdint.h>

/* ============================================================================
 * Process Manager — round-robin scheduler
 * ============================================================================
 * Approach: each process has its own kernel stack. When the timer IRQ fires,
 * we save the full interrupt frame on the current process's stack, switch
 * to the next process's stack, and iretq to resume it.
 *
 * This is the classic "switch stacks in IRQ handler" approach.
 * ============================================================================ */

/* Process table */
static struct proc procs[MAX_PROCS];
static struct proc *current_proc = 0;
static int next_pid = 1;

/* Saved RSP for each process (just the stack pointer) */
/* We store only the RSP — the full register state is on the stack */

/* ---- Process creation ---- */

static struct proc *find_free_proc(void) {
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state == PROC_UNUSED)
            return &procs[i];
    }
    return 0;
}

/* Entry wrapper for new processes — naked, reads entry/arg from stack */
/* After context_switch's ret, RSP points to: [entry] [arg] */
__attribute__((naked)) static void proc_entry_wrapper(void) {
    __asm__ volatile (
        /* Direct serial output to verify we reached here */
        "movw $0x3F8, %dx\n\t"
        "movb $0x57, %al\n\t"     /* 'W' = we reached wrapper */
        "outb %al, %dx\n\t"
        /* Now read entry/arg from stack */
        "movq (%rsp), %rax\n\t"      /* rax = entry function */
        "movq 8(%rsp), %rdi\n\t"     /* rdi = arg (1st C arg) */
        "subq $8, %rsp\n\t"          /* align stack to 16 bytes */
        "call *%rax\n\t"             /* call entry(arg) */
        "addq $8, %rsp\n\t"          /* restore stack */
        "xorq %rdi, %rdi\n\t"        /* exit code = 0 */
        "call proc_exit\n\t"
        "ud2\n\t"
    );
}

/* Debug helper */
static void serial_debug_reached(void) {
    serial_print("[wrapper] ");
}

pid_t proc_create(const char *name, void (*entry)(void *), void *arg) {
    struct proc *p = find_free_proc();
    if (!p) return -1;

    p->pid = next_pid++;
    p->state = PROC_READY;

    /* Copy name */
    for (int i = 0; i < 15 && name[i]; i++) p->name[i] = name[i];
    p->name[15] = 0;

    /* Allocate 2 pages for kernel stack */
    void *stack_bot = pmm_alloc_page();
    void *stack_top_page = pmm_alloc_page();
    if (!stack_bot || !stack_top_page) return -1;

    p->kernel_stack = (uint64_t)stack_bot;
    p->kernel_stack_top = (uint64_t)stack_top_page + PAGE_SIZE;

    /* Use same page table as kernel */
    __asm__ volatile ("movq %%cr3, %0" : "=r"(p->cr3));

    /* Set up initial stack frame.
     * After context_switch pops 6 callee-saved regs and rets,
     * RSP points to [entry] [arg]. The ret jumps to proc_entry_wrapper.
     */
    uint64_t *sp = (uint64_t *)p->kernel_stack_top;

    /* Arguments for proc_entry_wrapper */
    *(--sp) = (uint64_t)arg;           /* arg */
    *(--sp) = (uint64_t)entry;         /* entry function */

    /* Callee-saved registers (initial values) */
    *(--sp) = 0;                       /* r15 */
    *(--sp) = 0;                       /* r14 */
    *(--sp) = 0;                       /* r13 */
    *(--sp) = 0;                       /* r12 */
    *(--sp) = 0;                       /* rbp */
    *(--sp) = 0;                       /* rbx */

    /* Return address — context_switch's ret jumps here */
    *(--sp) = (uint64_t)proc_entry_wrapper;

    /* Save stack pointer */
    p->regs.rsp = (uint64_t)sp;

    p->priority = 0;
    p->wake_tick = 0;
    p->exit_code = 0;

    serial_print("[proc] created pid=");
    serial_print_dec(p->pid);
    serial_print(" '");
    serial_print(p->name);
    serial_print("'\n");

    return p->pid;
}

pid_t proc_create_user(const char *name, void (*entry)(void *), void *arg) {
    return proc_create(name, entry, arg);
}

/* ---- Process exit ---- */

void proc_exit(int code) {
    if (!current_proc) {
        while (1) __asm__ volatile ("cli; hlt");
    }
    current_proc->state = PROC_ZOMBIE;
    current_proc->exit_code = code;
    serial_print("[proc] pid=");
    serial_print_dec(current_proc->pid);
    serial_print(" exited with code ");
    serial_print_dec(code);
    serial_print("\n");

    /* Don't return — schedule another process */
    proc_yield();
    while (1); /* never reached */
}

/* ---- Yield ---- */

void proc_yield(void) {
    if (!current_proc) return;
    if (current_proc->state == PROC_RUNNING)
        current_proc->state = PROC_READY;
    proc_schedule();
}

/* ---- Sleep ---- */

void proc_sleep(uint64_t ticks) {
    if (!current_proc) return;
    current_proc->state = PROC_BLOCKED;
    current_proc->wake_tick = idt_get_ticks() + ticks;
    proc_schedule();
}

/* ---- Current ---- */

struct proc *proc_current(void) {
    return current_proc;
}

/* ---- Scheduler ---- */

/* Context switch: save callee-saved regs, swap RSP, restore, ret
 * This MUST be a naked function — we control the ret ourselves.
 * Stack layout for new process (first switch):
 *   [r15] [r14] [r13] [r12] [rbp] [rbx] [return_addr = proc_entry_wrapper] [entry] [arg]
 * After popping 6 regs, ret pops return_addr and jumps there.
 */
__attribute__((naked)) static void context_switch(uint64_t *old_rsp, uint64_t new_rsp) {
    (void)old_rsp; (void)new_rsp;
    __asm__ volatile (
        /* Save callee-saved registers */
        "pushq %rbx\n\t"
        "pushq %rbp\n\t"
        "pushq %r12\n\t"
        "pushq %r13\n\t"
        "pushq %r14\n\t"
        "pushq %r15\n\t"
        /* Save old RSP (arg1 = rdi) */
        "movq %rsp, (%rdi)\n\t"
        /* Load new RSP (arg2 = rsi) */
        "movq %rsi, %rsp\n\t"
        /* Restore callee-saved registers */
        "popq %r15\n\t"
        "popq %r14\n\t"
        "popq %r13\n\t"
        "popq %r12\n\t"
        "popq %rbp\n\t"
        "popq %rbx\n\t"
        /* Return — pops return address from new stack */
        "ret\n\t"
    );
}

void proc_schedule(void) {
    if (!current_proc) return;

    int ticks = idt_get_ticks();

    /* Wake up blocked processes */
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state == PROC_BLOCKED && procs[i].wake_tick <= (uint64_t)ticks) {
            procs[i].state = PROC_READY;
        }
    }

    /* Find next ready process (round-robin) */
    int start = (current_proc - procs) + 1;
    struct proc *next = 0;

    for (int i = 0; i < MAX_PROCS; i++) {
        int idx = (start + i) % MAX_PROCS;
        if (procs[idx].state == PROC_READY) {
            next = &procs[idx];
            break;
        }
    }

    /* Nothing to switch to, or only current is ready */
    if (!next || next == current_proc) {
        if (current_proc->state == PROC_RUNNING) return;
        /* Current is blocked/zombie, find any ready process */
        for (int i = 0; i < MAX_PROCS; i++) {
            if (procs[i].state == PROC_READY) {
                next = &procs[i];
                break;
            }
        }
        if (!next) return; /* All blocked, just return */
    }

    /* Mark current as ready (if still running) */
    if (current_proc->state == PROC_RUNNING)
        current_proc->state = PROC_READY;

    /* Switch to next */
    struct proc *old = current_proc;
    next->state = PROC_RUNNING;
    current_proc = next;

    /* Switch stacks */
    serial_print("[sched ");
    serial_print(old->name);
    serial_print("(rsp=");
    serial_print_hex(old->regs.rsp);
    serial_print(")->");
    serial_print(next->name);
    serial_print("(rsp=");
    serial_print_hex(next->regs.rsp);
    serial_print(",top=");
    serial_print_hex(*(uint64_t *)next->regs.rsp);
    serial_print(")] ");
    context_switch(&old->regs.rsp, next->regs.rsp);
    serial_print("[back] ");
}

/* ---- Init ---- */

void proc_init(void) {
    /* Set up idle process (pid 1) as the current process */
    current_proc = &procs[0];
    current_proc->pid = next_pid++;
    current_proc->state = PROC_RUNNING;
    for (int i = 0; i < 16; i++) current_proc->name[i] = 0;
    current_proc->name[0] = 'i'; current_proc->name[1] = 'd'; current_proc->name[2] = 'l'; current_proc->name[3] = 'e';
    current_proc->cr3 = 0;
    current_proc->priority = 0;

    /* Save current RSP as idle's stack pointer */
    __asm__ volatile ("movq %%rsp, %0" : "=m"(current_proc->regs.rsp));

    serial_print("[proc] init done, idle pid=1, rsp=");
    serial_print_hex(current_proc->regs.rsp);
    serial_print("\n");
}

/* ---- Debug dump ---- */

void proc_dump(void) {
    serial_print("PID  State     Name\n");
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].state == PROC_UNUSED) continue;
        serial_print_dec(procs[i].pid);
        serial_print("    ");
        switch (procs[i].state) {
            case PROC_READY:   serial_print("READY  "); break;
            case PROC_RUNNING: serial_print("RUNNING"); break;
            case PROC_BLOCKED: serial_print("BLOCKED"); break;
            case PROC_ZOMBIE:  serial_print("ZOMBIE "); break;
            default:           serial_print("???    "); break;
        }
        serial_print("  ");
        serial_print(procs[i].name);
        serial_print("\n");
    }
}
