#ifndef DNAOS_PROC_H
#define DNAOS_PROC_H

#include <stdint.h>

/* Process states */
#define PROC_UNUSED   0
#define PROC_READY    1
#define PROC_RUNNING  2
#define PROC_BLOCKED  3
#define PROC_ZOMBIE   4

/* Max processes */
#define MAX_PROCS 64

/* Process ID */
typedef int pid_t;

/* Saved register context for context switch */
struct proc_regs {
    uint64_t r15, r14, r13, r12, r11, r10, r9, r8;
    uint64_t rdi, rsi, rbp, rdx, rcx, rbx, rax;
    uint64_t rip;
    uint64_t cs;
    uint64_t rflags;
    uint64_t rsp;
    uint64_t ss;
};

/* Process control block */
struct proc {
    pid_t pid;
    int state;
    char name[16];

    /* Saved context */
    struct proc_regs regs;

    /* Kernel stack (separate per process) */
    uint64_t kernel_stack;
    uint64_t kernel_stack_top;

    /* Page table (CR3) */
    uint64_t cr3;

    /* Scheduling */
    int priority;
    uint64_t wake_tick;     /* wake time for blocked processes */

    /* Exit code (for zombies) */
    int exit_code;
};

/* Initialize process subsystem */
void proc_init(void);

/* Create a kernel process (runs in ring 0) */
pid_t proc_create(const char *name, void (*entry)(void *), void *arg);

/* Create a process with its own address space */
pid_t proc_create_user(const char *name, void (*entry)(void *), void *arg);

/* Exit current process */
void proc_exit(int code) __attribute__((noreturn));

/* Yield CPU */
void proc_yield(void);

/* Block current process until tick */
void proc_sleep(uint64_t ticks);

/* Get current process */
struct proc *proc_current(void);

/* Scheduler — called from timer IRQ */
void proc_schedule(void);

/* Dump process list (debug) */
void proc_dump(void);

#endif
