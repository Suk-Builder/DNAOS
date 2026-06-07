/*
 * ============================================================================
 * DNAOS - E1000 Network Driver (Stub)
 * ============================================================================
 * 
 * Intel PRO/1000 - most common NIC in QEMU and many real machines.
 * Uses MMIO for register access.
 * 
 * Currently: initialization + packet receive
 * TODO: TX ring, DHCP, TCP/IP stack
 * ============================================================================
 */

#ifndef E1000_H
#define E1000_H

#include <stdint.h>

/* E1000 MMIO Register offsets */
#define E1000_CTRL      0x0000  /* Device Control */
#define E1000_STATUS    0x0008  /* Device Status */
#define E1000_EECD      0x0010  /* EEPROM/Flash Control */
#define E1000_EERD      0x0014  /* EEPROM Read */
#define E1000_MDIC      0x0020  /* MDI Control */
#define E1000_ICR       0x00C0  /* Interrupt Cause Read */
#define E1000_ITR       0x00C4  /* Interrupt Throttling */
#define E1000_ICS       0x00C8  /* Interrupt Cause Set */
#define E1000_IMS       0x00D0  /* Interrupt Mask Set */
#define E1000_IMC       0x00D8  /* Interrupt Mask Clear */
#define E1000_RCTL      0x0100  /* Receive Control */
#define E1000_TCTL      0x0400  /* Transmit Control */
#define E1000_RDBAL     0x2800  /* RX Descriptor Base Low */
#define E1000_RDBAH     0x2804  /* RX Descriptor Base High */
#define E1000_RDLEN     0x2808  /* RX Descriptor Length */
#define E1000_RDH       0x2810  /* RX Descriptor Head */
#define E1000_RDT       0x2818  /* RX Descriptor Tail */
#define E1000_TDBAL     0x3800  /* TX Descriptor Base Low */
#define E1000_TDBAH     0x3804  /* TX Descriptor Base High */
#define E1000_TDLEN     0x3808  /* TX Descriptor Length */
#define E1000_TDH       0x3810  /* TX Descriptor Head */
#define E1000_TDT       0x3818  /* TX Descriptor Tail */
#define E1000_RA        0x5400  /* Receive Address */
#define E1000_MTA       0x5200  /* Multicast Table Array */

/* RCTL flags */
#define E1000_RCTL_EN           (1 << 1)    /* Receive Enable */
#define E1000_RCTL_SBP          (1 << 2)    /* Store Bad Packets */
#define E1000_RCTL_UPE          (1 << 3)    /* Unicast Promiscuous */
#define E1000_RCTL_MPE          (1 << 4)    /* Multicast Promiscuous */
#define E1000_RCTL_LPE          (1 << 5)    /* Long Packet Enable */
#define E1000_RCTL_BAM          (1 << 15)   /* Broadcast Accept Mode */
#define E1000_RCTL_SZ_2048      (0 << 16)   /* Buffer size 2048 */
#define E1000_RCTL_SZ_1024      (1 << 16)   /* Buffer size 1024 */
#define E1000_RCTL_SZ_512       (2 << 16)   /* Buffer size 512 */
#define E1000_RCTL_SZ_256       (3 << 16)   /* Buffer size 256 */
#define E1000_RCTL_SECRC        (1 << 26)   /* Strip Ethernet CRC */

/* TCTL flags */
#define E1000_TCTL_EN           (1 << 1)    /* Transmit Enable */
#define E1000_TCTL_PSP          (1 << 3)    /* Pad Short Packets */
#define E1000_TCTL_CT_SHIFT     4           /* Collision Threshold */
#define E1000_TCTL_COLD_SHIFT   12          /* Collision Distance */

/* Descriptor flags */
#define E1000_TXD_CMD_EOP       (1 << 0)    /* End of Packet */
#define E1000_TXD_CMD_IFCS      (1 << 1)    /* Insert FCS */
#define E1000_TXD_CMD_RS        (1 << 3)    /* Report Status */
#define E1000_RXD_STAT_DD       (1 << 0)    /* Descriptor Done */

/* Number of descriptors */
#define E1000_NUM_RX_DESC   32
#define E1000_NUM_TX_DESC   32
#define E1000_RX_BUF_SIZE   2048

/* RX descriptor */
typedef struct {
    uint64_t addr;          /* Buffer address */
    uint16_t length;        /* Length of data */
    uint16_t checksum;      /* Packet checksum */
    uint8_t  status;        /* Descriptor status */
    uint8_t  errors;        /* Descriptor errors */
    uint16_t special;       /* Special field */
} __attribute__((packed)) e1000_rx_desc_t;

/* TX descriptor */
typedef struct {
    uint64_t addr;          /* Buffer address */
    uint16_t length;        /* Data length */
    uint8_t  cso;           /* Checksum offset */
    uint8_t  cmd;           /* Descriptor control */
    uint8_t  status;        /* Descriptor status */
    uint8_t  css;           /* Checksum start */
    uint16_t special;       /* Special field */
} __attribute__((packed)) e1000_tx_desc_t;

/* Driver state */
typedef struct {
    uint64_t        mmio_base;      /* MMIO base address */
    uint8_t         mac[6];         /* MAC address */
    e1000_rx_desc_t *rx_descs;      /* RX descriptor ring */
    uint8_t         *rx_buffers;    /* RX buffer pool */
    uint32_t        rx_tail;        /* Current RX tail */
    e1000_tx_desc_t *tx_descs;      /* TX descriptor ring */
    uint8_t         *tx_buffers;    /* TX buffer pool */
    uint32_t        tx_tail;        /* Current TX tail */
    int             link_up;        /* Link status */
    uint64_t        rx_packets;     /* Stats */
    uint64_t        tx_packets;
    uint64_t        rx_bytes;
    uint64_t        tx_bytes;
} e1000_t;

static e1000_t e1000;

/* MMIO read/write */
static inline uint32_t e1000_read(uint64_t base, uint32_t reg) {
    return *(volatile uint32_t *)(base + reg);
}

static inline void e1000_write(uint64_t base, uint32_t reg, uint32_t val) {
    *(volatile uint32_t *)(base + reg) = val;
}

/* Read MAC address from EEPROM */
static void e1000_read_mac(uint64_t base, uint8_t *mac) {
    for (int i = 0; i < 3; i++) {
        e1000_write(base, E1000_EERD, (uint32_t)(i << 8) | 1);
        
        /* Wait for done */
        int timeout = 10000;
        uint32_t data;
        while (timeout--) {
            data = e1000_read(base, E1000_EERD);
            if (data & 0x10) break; /* Done bit */
        }
        
        uint16_t word = (uint16_t)(data >> 16);
        mac[i * 2]     = word & 0xFF;
        mac[i * 2 + 1] = (word >> 8) & 0xFF;
    }
}

/* Initialize E1000 */
static int e1000_init(uint64_t mmio_base) {
    e1000.mmio_base = mmio_base;
    
    /* Read MAC address */
    e1000_read_mac(mmio_base, e1000.mac);
    
    /* Disable interrupts */
    e1000_write(mmio_base, E1000_IMC, 0xFFFFFFFF);
    
    /* Reset the device */
    e1000_write(mmio_base, E1000_CTRL, 
                e1000_read(mmio_base, E1000_CTRL) | 0x04000000); /* RST */
    
    /* Wait for reset */
    int timeout = 10000;
    while (timeout--) {
        if (!(e1000_read(mmio_base, E1000_CTRL) & 0x04000000)) break;
    }
    
    /* Disable interrupts again after reset */
    e1000_write(mmio_base, E1000_IMC, 0xFFFFFFFF);
    
    /* Set link up */
    e1000_write(mmio_base, E1000_CTRL, 
                e1000_read(mmio_base, E1000_CTRL) | 0x40); /* SLU */
    
    /* Allocate RX descriptor ring (page-aligned) */
    uint64_t rx_desc_phys = pmm_alloc_pages(
        (E1000_NUM_RX_DESC * sizeof(e1000_rx_desc_t) + PAGE_SIZE - 1) / PAGE_SIZE);
    if (!rx_desc_phys) return -1;
    e1000.rx_descs = (e1000_rx_desc_t *)rx_desc_phys;
    
    /* Allocate RX buffers */
    uint64_t rx_buf_phys = pmm_alloc_pages(
        (E1000_NUM_RX_DESC * E1000_RX_BUF_SIZE + PAGE_SIZE - 1) / PAGE_SIZE);
    if (!rx_buf_phys) return -1;
    e1000.rx_buffers = (uint8_t *)rx_buf_phys;
    
    /* Initialize RX descriptors */
    for (int i = 0; i < E1000_NUM_RX_DESC; i++) {
        e1000.rx_descs[i].addr = rx_buf_phys + i * E1000_RX_BUF_SIZE;
        e1000.rx_descs[i].status = 0;
    }
    
    /* Program RX registers */
    e1000_write(mmio_base, E1000_RDBAL, (uint32_t)rx_desc_phys);
    e1000_write(mmio_base, E1000_RDBAH, (uint32_t)(rx_desc_phys >> 32));
    e1000_write(mmio_base, E1000_RDLEN, E1000_NUM_RX_DESC * sizeof(e1000_rx_desc_t));
    e1000_write(mmio_base, E1000_RDH, 0);
    e1000_write(mmio_base, E1000_RDT, E1000_NUM_RX_DESC - 1);
    
    /* Enable RX */
    e1000_write(mmio_base, E1000_RCTL,
                E1000_RCTL_EN | E1000_RCTL_SBP | E1000_RCTL_UPE |
                E1000_RCTL_MPE | E1000_RCTL_BAM | E1000_RCTL_SZ_2048 |
                E1000_RCTL_SECRC);
    
    /* Allocate TX descriptor ring */
    uint64_t tx_desc_phys = pmm_alloc_pages(
        (E1000_NUM_TX_DESC * sizeof(e1000_tx_desc_t) + PAGE_SIZE - 1) / PAGE_SIZE);
    if (!tx_desc_phys) return -1;
    e1000.tx_descs = (e1000_tx_desc_t *)tx_desc_phys;
    
    /* Allocate TX buffers */
    uint64_t tx_buf_phys = pmm_alloc_pages(
        (E1000_NUM_TX_DESC * E1000_RX_BUF_SIZE + PAGE_SIZE - 1) / PAGE_SIZE);
    if (!tx_buf_phys) return -1;
    e1000.tx_buffers = (uint8_t *)tx_buf_phys;
    
    /* Program TX registers */
    e1000_write(mmio_base, E1000_TDBAL, (uint32_t)tx_desc_phys);
    e1000_write(mmio_base, E1000_TDBAH, (uint32_t)(tx_desc_phys >> 32));
    e1000_write(mmio_base, E1000_TDLEN, E1000_NUM_TX_DESC * sizeof(e1000_tx_desc_t));
    e1000_write(mmio_base, E1000_TDH, 0);
    e1000_write(mmio_base, E1000_TDT, 0);
    
    /* Enable TX */
    e1000_write(mmio_base, E1000_TCTL,
                E1000_TCTL_EN | E1000_TCTL_PSP |
                (0x10 << E1000_TCTL_CT_SHIFT) |
                (0x40 << E1000_TCTL_COLD_SHIFT));
    
    /* Enable interrupts */
    e1000_write(mmio_base, E1000_IMS, 
                (1 << 0) |   /* TXDW - Transmit Descriptor Written Back */
                (1 << 1) |   /* TXQE - Transmit Queue Empty */
                (1 << 2) |   /* LSC - Link Status Change */
                (1 << 7));   /* RXO - Receiver Overrun */
    
    /* Check link */
    uint32_t status = e1000_read(mmio_base, E1000_STATUS);
    e1000.link_up = (status & 0x02) ? 1 : 0;
    
    e1000.rx_tail = E1000_NUM_RX_DESC - 1;
    e1000.tx_tail = 0;
    e1000.rx_packets = 0;
    e1000.tx_packets = 0;
    
    return 0;
}

/* Receive a packet (non-blocking) */
static int e1000_recv(void *buf, int bufsize) {
    /* Check if next descriptor is done */
    int next = (e1000.rx_tail + 1) % E1000_NUM_RX_DESC;
    
    if (!(e1000.rx_descs[next].status & E1000_RXD_STAT_DD)) {
        return 0; /* No packet */
    }
    
    int len = e1000.rx_descs[next].length;
    if (len > bufsize) len = bufsize;
    
    /* Copy data */
    uint8_t *src = (uint8_t *)e1000.rx_descs[next].addr;
    uint8_t *dst = (uint8_t *)buf;
    for (int i = 0; i < len; i++) {
        dst[i] = src[i];
    }
    
    /* Reset descriptor */
    e1000.rx_descs[next].status = 0;
    e1000.rx_tail = next;
    
    /* Update tail register */
    e1000_write(e1000.mmio_base, E1000_RDT, e1000.rx_tail);
    
    e1000.rx_packets++;
    e1000.rx_bytes += len;
    
    return len;
}

/* Send a packet */
static int e1000_send(const void *buf, int len) {
    if (len > E1000_RX_BUF_SIZE) return -1;
    
    /* Copy data to TX buffer */
    uint8_t *dst = e1000.tx_buffers + e1000.tx_tail * E1000_RX_BUF_SIZE;
    const uint8_t *src = (const uint8_t *)buf;
    for (int i = 0; i < len; i++) {
        dst[i] = src[i];
    }
    
    /* Set up descriptor */
    e1000.tx_descs[e1000.tx_tail].addr = 
        (uint64_t)(e1000.tx_buffers + e1000.tx_tail * E1000_RX_BUF_SIZE);
    e1000.tx_descs[e1000.tx_tail].length = len;
    e1000.tx_descs[e1000.tx_tail].cmd = E1000_TXD_CMD_EOP | E1000_TXD_CMD_IFCS |
                                          E1000_TXD_CMD_RS;
    e1000.tx_descs[e1000.tx_tail].status = 0;
    
    /* Advance tail */
    e1000.tx_tail = (e1000.tx_tail + 1) % E1000_NUM_TX_DESC;
    e1000_write(e1000.mmio_base, E1000_TDT, e1000.tx_tail);
    
    e1000.tx_packets++;
    e1000.tx_bytes += len;
    
    return len;
}

/* Get MAC address string */
static void e1000_mac_str(char *buf) {
    const char *hex = "0123456789ABCDEF";
    for (int i = 0; i < 6; i++) {
        buf[i * 3] = hex[e1000.mac[i] >> 4];
        buf[i * 3 + 1] = hex[e1000.mac[i] & 0x0F];
        buf[i * 3 + 2] = ':';
    }
    buf[17] = '\0';
}

#endif /* E1000_H */
