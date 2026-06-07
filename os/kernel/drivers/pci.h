/*
 * ============================================================================
 * DNAOS - PCI Bus Driver
 * ============================================================================
 * 
 * Scans PCI bus to find devices (network cards, GPUs, etc.)
 * Used to locate E1000 NIC and other hardware.
 * 
 * PCI Configuration Space access via ports 0xCF8/0xCFC.
 * ============================================================================
 */

#ifndef PCI_H
#define PCI_H

#include <stdint.h>

#define PCI_CONFIG_ADDR  0xCF8
#define PCI_CONFIG_DATA  0xCFC

#define PCI_VENDOR_ID    0x00
#define PCI_DEVICE_ID    0x02
#define PCI_COMMAND      0x04
#define PCI_STATUS       0x06
#define PCI_CLASS_CODE   0x09    /* Revision ID + Class codes */
#define PCI_BAR0         0x10
#define PCI_BAR1         0x14
#define PCI_BAR2         0x18
#define PCI_BAR3         0x1C
#define PCI_BAR4         0x20
#define PCI_BAR5         0x24
#define PCI_INTERRUPT    0x3C

/* Known vendor/device IDs */
#define PCI_VENDOR_INTEL     0x8086
#define PCI_DEVICE_E1000     0x100E
#define PCI_DEVICE_E1000_82540EM 0x100E
#define PCI_DEVICE_E1000_82545EM 0x100F
#define PCI_DEVICE_E1000_82543GC 0x1004

#define PCI_VENDOR_REALTEK   0x10EC
#define PCI_DEVICE_RTL8139   0x8139

/* PCI device structure */
typedef struct {
    uint16_t vendor_id;
    uint16_t device_id;
    uint8_t  class_code;
    uint8_t  subclass;
    uint8_t  prog_if;
    uint8_t  bus;
    uint8_t  slot;
    uint8_t  func;
    uint64_t bar[6];          /* Base Address Registers */
    uint8_t  irq;
    int      has_mmio;
} pci_device_t;

#define MAX_PCI_DEVICES 32
static pci_device_t pci_devices[MAX_PCI_DEVICES];
static int pci_device_count = 0;

/* Port I/O */
static inline void outl(uint16_t port, uint32_t val) {
    __asm__ volatile ("outl %0, %1" :: "a"(val), "Nd"(port));
}

static inline uint32_t inl(uint16_t port) {
    uint32_t ret;
    __asm__ volatile ("inl %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* Read PCI config register */
static uint32_t pci_read_config(uint8_t bus, uint8_t slot, uint8_t func, uint8_t offset) {
    uint32_t addr = ((uint32_t)bus << 16) | ((uint32_t)slot << 11) |
                    ((uint32_t)func << 8) | (offset & 0xFC) | 0x80000000;
    outl(PCI_CONFIG_ADDR, addr);
    return inl(PCI_CONFIG_DATA);
}

/* Write PCI config register */
static void pci_write_config(uint8_t bus, uint8_t slot, uint8_t func, 
                              uint8_t offset, uint32_t value) {
    uint32_t addr = ((uint32_t)bus << 16) | ((uint32_t)slot << 11) |
                    ((uint32_t)func << 8) | (offset & 0xFC) | 0x80000000;
    outl(PCI_CONFIG_ADDR, addr);
    outl(PCI_CONFIG_DATA, value);
}

/* Read BAR and determine if MMIO or I/O */
static uint64_t pci_read_bar(uint8_t bus, uint8_t slot, uint8_t func, int bar_idx) {
    uint8_t offset = PCI_BAR0 + bar_idx * 4;
    uint32_t bar = pci_read_config(bus, slot, func, offset);
    
    if (bar & 0x01) {
        /* I/O space */
        return bar & ~0x03;
    } else {
        /* Memory space - might be 64-bit */
        if ((bar & 0x06) == 0x04) {
            /* 64-bit BAR */
            uint32_t bar_hi = pci_read_config(bus, slot, func, offset + 4);
            return ((uint64_t)bar_hi << 32) | (bar & ~0x0F);
        }
        return bar & ~0x0F;
    }
}

/* Enable PCI device (bus mastering, MMIO, I/O) */
static void pci_enable_device(pci_device_t *dev) {
    uint32_t cmd = pci_read_config(dev->bus, dev->slot, dev->func, PCI_COMMAND);
    cmd |= 0x07; /* I/O space + Memory space + Bus master */
    pci_write_config(dev->bus, dev->slot, dev->func, PCI_COMMAND, cmd);
}

/* Scan a single PCI function */
static void pci_scan_func(uint8_t bus, uint8_t slot, uint8_t func) {
    uint32_t id = pci_read_config(bus, slot, func, 0);
    uint16_t vendor = id & 0xFFFF;
    uint16_t device = (id >> 16) & 0xFFFF;
    
    if (vendor == 0xFFFF) return; /* No device */
    
    if (pci_device_count >= MAX_PCI_DEVICES) return;
    
    pci_device_t *dev = &pci_devices[pci_device_count];
    dev->vendor_id = vendor;
    dev->device_id = device;
    dev->bus = bus;
    dev->slot = slot;
    dev->func = func;
    
    /* Class codes */
    uint32_t class_info = pci_read_config(bus, slot, func, 0x08);
    dev->class_code = (class_info >> 24) & 0xFF;
    dev->subclass = (class_info >> 16) & 0xFF;
    dev->prog_if = (class_info >> 8) & 0xFF;
    
    /* BARs */
    for (int i = 0; i < 6; i++) {
        dev->bar[i] = pci_read_bar(bus, slot, func, i);
    }
    
    /* IRQ */
    uint32_t irq_info = pci_read_config(bus, slot, func, PCI_INTERRUPT);
    dev->irq = irq_info & 0xFF;
    
    /* Check if has MMIO */
    dev->has_mmio = 0;
    for (int i = 0; i < 6; i++) {
        if (dev->bar[i] && !(dev->bar[i] & 0x01)) {
            dev->has_mmio = 1;
            break;
        }
    }
    
    pci_device_count++;
}

/* Scan entire PCI bus */
static void pci_scan(void) {
    pci_device_count = 0;
    
    for (int bus = 0; bus < 256; bus++) {
        for (int slot = 0; slot < 32; slot++) {
            /* Check function 0 */
            uint32_t id = pci_read_config(bus, slot, 0, 0);
            if ((id & 0xFFFF) == 0xFFFF) continue;
            
            pci_scan_func(bus, slot, 0);
            
            /* Check if multi-function device */
            uint32_t hdr = pci_read_config(bus, slot, 0, 0x0C);
            if (hdr & 0x00800000) {
                for (int func = 1; func < 8; func++) {
                    pci_scan_func(bus, slot, func);
                }
            }
        }
    }
}

/* Find E1000 NIC */
static pci_device_t *pci_find_e1000(void) {
    for (int i = 0; i < pci_device_count; i++) {
        if (pci_devices[i].vendor_id == PCI_VENDOR_INTEL &&
            (pci_devices[i].device_id == PCI_DEVICE_E1000 ||
             pci_devices[i].device_id == PCI_DEVICE_E1000_82540EM ||
             pci_devices[i].device_id == PCI_DEVICE_E1000_82545EM)) {
            return &pci_devices[i];
        }
    }
    return 0;
}

/* Find device by class */
static pci_device_t *pci_find_by_class(uint8_t class_code, uint8_t subclass) {
    for (int i = 0; i < pci_device_count; i++) {
        if (pci_devices[i].class_code == class_code &&
            pci_devices[i].subclass == subclass) {
            return &pci_devices[i];
        }
    }
    return 0;
}

/* Get device info string */
static void pci_device_info(pci_device_t *dev, char *buf, int bufsize) {
    int pos = 0;
    const char *hex = "0123456789ABCDEF";
    
    pos += snprintf(buf + pos, bufsize - pos, "%02x:%02x.%d ", 
                    dev->bus, dev->slot, dev->func);
    pos += snprintf(buf + pos, bufsize - pos, "ven=%04x dev=%04x ",
                    dev->vendor_id, dev->device_id);
    pos += snprintf(buf + pos, bufsize - pos, "class=%02x%02x irq=%d",
                    dev->class_code, dev->subclass, dev->irq);
}

#endif /* PCI_H */
