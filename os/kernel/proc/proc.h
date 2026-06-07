/*
 * ============================================================================
 * DNAOS - Process Manager & Scheduler
 * ============================================================================
 * 
 * Round-robin preemptive scheduler with timer interrupt (PIT @ 100Hz).
 * Each process has its own page tables, kernel stack, and register state.
 * 
 * Process states:
 *   PROC_READY    - Runnable, waiting for CPU
 *   PROC_RUNNING  - Currently executing
 *   PROC_BLOCKED  - Waiting for I/O/event
 *   PROC_ZOMBIE   - Exited, waiting for parent to reap
 * 
 * Context switch saves/restores all GP registers + RIP + RFLAGS + CR3.
 * ============================================================================
 */

#ifndef PROC_H
#define PROC_H

#include <stdint.h>
#include "pmm.h"
#include "vmm.h"

#define MAX_PROCESSES   64
#define KERNEL_STACK_SIZE 8192   /* 8KB per process kernel stack */
#define USER_STACK_SIZE  65536   /* 64KB user stack */
#define PROC_NAME_LEN   32

/* Process states */
typedef enum {
    PROC_UNUSED = 0,
    PROC_READY,
    PROC_RUNNING,
    PROC_BLOCKED,
    PROC_ZOMBIE
} proc_state_t;

/* Saved register state for context switch */
typedef struct {
    /* Saved by switch_to */
    uint64_t r15, r14, r13, r12;
    uint64_t r11, r10, r9, r8;
    uint64_t rdi, rsi, rbp, rdx;
    uint64_t rcx, rbx, rax;
    uint64_t rip;
    uint64_t cs;
    uint64_t rflags;
    uint64_t rsp;
    uint64_t ss;
} registers_t;

/* Process Control Block */
typedef struct process {
    uint64_t        pid;
    char            name[PROC_NAME_LEN];
    proc_state_t    state;
    uint64_t        pml4_phys;       /* CR3 for this process */
    uint64_t       *page_tables;     /* Virtual address of PML4 */
    uint64_t        kernel_stack;    /* Kernel stack top */
    uint64_t        user_stack;      /* User stack top */
    uint64_t        entry_point;     /* Where RIP starts */
    registers_t     regs;            /* Saved context */
    uint64_t        atp_budget;      /* ATP allocated to this process */
    uint64_t        atp_used;        /* ATP consumed */
    uint64_t        quantum;         /* Time slices remaining */
    uint64_t        priority;        /* 0=highest */
    struct process *next;            /* Linked list */
    uint64_t        parent_pid;
    uint64_t        exit_code;
} process_t;

/* Global process table */
static process_t proc_table[MAX_PROCESSES];
static process_t *current_proc = 0;
static uint64_t next_pid = 1;
static uint64_t proc_count = 0;

/* Find a free process slot */
static process_t *proc_alloc_slot(void) {
    for (int i = 0; i < MAX_PROCESSES; i++) {
        if (proc_table[i].state == PROC_UNUSED) {
            return &proc_table[i];
        }
    }
    return 0;
}

/* Create a new kernel process */
static process_t *proc_create(const char *name, void (*entry)(void), 
                               uint64_t atp_budget) {
    process_t *proc = proc_alloc_slot();
    if (!proc) return 0;
    
    /* Initialize */
    for (int i = 0; i < PROC_NAME_LEN; i++) {
        proc->name[i] = name[i];
        if (name[i] == '\0') break;
    }
    
    proc->pid = next_pid++;
    proc->state = PROC_READY;
    proc->parent_pid = current_proc ? current_proc->pid : 0;
    proc->atp_budget = atp_budget;
    proc->atp_used = 0;
    proc->priority = 0;
    proc->quantum = 10; /* 10 ticks default */
    proc->exit_code = 0;
    proc->next = 0;
    
    /* Allocate kernel stack */
    uint64_t kstack_phys = pmm_alloc_pages(KERNEL_STACK_SIZE / PAGE_SIZE);
    if (!kstack_phys) { proc->state = PROC_UNUSED; return 0; }
    proc->kernel_stack = kstack_phys + KERNEL_STACK_SIZE;
    
    /* Use kernel page tables for now (no user space yet) */
    proc->pml4_phys = (uint64_t)current_pml4; /* Share kernel space */
    
    /* Set up initial register state */
    for (int i = 0; i < sizeof(registers_t) / sizeof(uint64_t); i++) {
        ((uint64_t *)&proc->regs)[i] = 0;
    }
    
    proc->regs.rip = (uint64_t)entry;
    proc->regs.cs = 0x08;           /* Kernel code segment */
    proc->regs.ss = 0x10;           /* Kernel data segment */
    proc->regs.rflags = 0x202;      /* IF flag set */
    proc->regs.rsp = proc->kernel_stack;
    
    proc_count++;
    return proc;
}

/* Create a user process (with own address space) */
static process_t *proc_create_user(const char *name, uint64_t entry_phys,
                                    uint64_t atp_budget) {
    process_t *proc = proc_alloc_slot();
    if (!proc) return 0;
    
    for (int i = 0; i < PROC_NAME_LEN; i++) {
        proc->name[i] = name[i];
        if (name[i] == '\0') break;
    }
    
    proc->pid = next_pid++;
    proc->state = PROC_READY;
    proc->parent_pid = current_proc ? current_proc->pid : 0;
    proc->atp_budget = atp_budget;
    proc->atp_used = 0;
    proc->priority = 1;
    proc->quantum = 10;
    proc->exit_code = 0;
    proc->next = 0;
    
    /* Allocate user page tables */
    uint64_t pml4_phys = pmm_alloc_page();
    if (!pml4_phys) { proc->state = PROC_UNUSED; return 0; }
    proc->pml4_phys = pml4_phys;
    proc->page_tables = (uint64_t *)pml4_phys;
    
    /* Copy kernel mappings (higher half) from current PML4 */
    uint64_t *src = (uint64_t *)current_pml4;
    uint64_t *dst = (uint64_t *)pml4_phys;
    for (int i = 256; i < 512; i++) { /* Upper half = kernel */
        dst[i] = src[i];
    }
    
    /* Map user code at 0x400000 (4MB) */
    vmm_map_page(0x400000, entry_phys, PTE_PRESENT | PTE_WRITABLE | PTE_USER);
    
    /* Allocate user stack at 0x7FFFF000 (grows down from 2GB) */
    uint64_t ustack = pmm_alloc_pages(USER_STACK_SIZE / PAGE_SIZE);
    if (!ustack) { proc->state = PROC_UNUSED; return 0; }
    for (uint64_t i = 0; i < USER_STACK_SIZE / PAGE_SIZE; i++) {
        vmm_map_page(0x7FFFE000 - i * PAGE_SIZE, ustack + i * PAGE_SIZE,
                     PTE_PRESENT | PTE_WRITABLE | PTE_USER);
    }
    proc->user_stack = 0x7FFFF000;
    
    /* Kernel stack */
    uint64_t kstack = pmm_alloc_pages(KERNEL_STACK_SIZE / PAGE_SIZE);
    if (!kstack) { proc->state = PROC_UNUSED; return 0; }
    proc->kernel_stack = kstack + KERNEL_STACK_SIZE;
    
    /* Set up registers for user mode */
    for (int i = 0; i < sizeof(registers_t) / sizeof(uint64_t); i++) {
        ((uint64_t *)&proc->regs)[i] = 0;
    }
    proc->regs.rip = 0x400000;
    proc->regs.cs = 0x18 | 3;       /* User code segment + RPL 3 */
    proc->regs.ss = 0x20 | 3;       /* User data segment + RPL 3 */
    proc->regs.rflags = 0x202;
    proc->regs.rsp = proc->user_stack;
    
    proc_count++;
    return proc;
}

/* Kill a process */
static void proc_kill(process_t *proc, uint64_t exit_code) {
    proc->state = PROC_ZOMBIE;
    proc->exit_code = exit_code;
    proc_count--;
    
    /* Free resources (but keep PCB for parent to reap) */
    /* Stack and page tables freed when reaped */
}

/* Clean up zombie process */
static void proc_reap(process_t *proc) {
    if (proc->state != PROC_ZOMBIE) return;
    
    /* Free kernel stack */
    /* Free page tables */
    /* Free user stack */
    
    proc->state = PROC_UNUSED;
    proc->pid = 0;
}

/* ============================================================================
 * Scheduler
 * ============================================================================
 */

/* Timer tick counter */
static volatile uint64_t scheduler_ticks = 0;

/* Round-robin schedule: find next READY process */
static process_t *schedule_next(void) {
    if (proc_count == 0) return 0;
    
    /* Start searching from after current */
    int start = current_proc ? (current_proc - proc_table + 1) : 0;
    
    for (int i = 0; i < MAX_PROCESSES; i++) {
        int idx = (start + i) % MAX_PROCESSES;
        if (proc_table[idx].state == PROC_READY) {
            return &proc_table[idx];
        }
    }
    
    return 0; /* No runnable processes */
}

/* Context switch (assembly in boot.S) */
extern void context_switch(registers_t *old_ctx, registers_t *new_ctx, 
                           uint64_t new_cr3);

/* Timer interrupt handler - called from IRQ0 */
static void scheduler_tick(void) {
    scheduler_ticks++;
    
    if (!current_proc) return;
    
    /* Consume ATP */
    current_proc->atp_used++;
    if (current_proc->atp_used >= current_proc->atp_budget) {
        /* ATP exhausted - kill process */
        proc_kill(current_proc, 1); /* exit code 1 = ATP death */
    }
    
    /* Decrement quantum */
    current_proc->quantum--;
    if (current_proc->quantum <= 0) {
        /* Time's up - reschedule */
        if (current_proc->state == PROC_RUNNING) {
            current_proc->state = PROC_READY;
        }
        current_proc->quantum = 10; /* Reset quantum */
        
        process_t *next = schedule_next();
        if (next && next != current_proc) {
            next->state = PROC_RUNNING;
            
            registers_t *old = &current_proc->regs;
            registers_t *new_r = &next->regs;
            
            current_proc = next;
            context_switch(old, new_r, next->pml4_phys);
        }
    }
}

/* Initialize process manager */
static void proc_init(void) {
    for (int i = 0; i < MAX_PROCESSES; i++) {
        proc_table[i].state = PROC_UNUSED;
        proc_table[i].pid = 0;
    }
    current_proc = 0;
    next_pid = 1;
    proc_count = 0;
}

/* Get process info for display */
static int proc_list_info(char *buf, int bufsize) {
    int pos = 0;
    const char *header = "PID  State     ATP      Name\n";
    while (*header && pos < bufsize - 1) buf[pos++] = *header++;
    
    for (int i = 0; i < MAX_PROCESSES && pos < bufsize - 50; i++) {
        if (proc_table[i].state == PROC_UNUSED) continue;
        
        process_t *p = &proc_table[i];
        pos += snprintf(buf + pos, bufsize - pos, "%-4d %-9s %lld/%lld  %s\n",
                       (int)p->pid,
                       p->state == PROC_RUNNING ? "RUNNING" :
                       p->state == PROC_READY ? "READY" :
                       p->state == PROC_BLOCKED ? "BLOCKED" : "ZOMBIE",
                       p->atp_used, p->atp_budget, p->name);
    }
    return pos;
}

/* Simple snprintf for kernel use */
static int snprintf(char *buf, int size, const char *fmt, ...) {
    __builtin_va_list args;
    __builtin_va_start(args, fmt);
    int ret = __builtin_vsnprintf(buf, size, fmt, args);
    __builtin_va_end(args);
    return ret;
}

#endif /* PROC_H */
