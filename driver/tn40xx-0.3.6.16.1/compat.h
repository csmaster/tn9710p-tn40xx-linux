/* compat.h — Linux kernel API shims for pre-5.18 out-of-tree driver */
#ifndef _TN40_COMPAT_H
#define _TN40_COMPAT_H

#include <linux/dma-mapping.h>

/*
 * PCI DMA -> generic DMA API (removed in kernel 5.18).
 * Macro params use _p to avoid colliding with the ->dev struct field name —
 * the preprocessor would substitute 'dev' inside '->dev' otherwise.
 */
#define pci_alloc_consistent(_p, size, dma) \
	dma_alloc_coherent(&(_p)->dev, size, dma, GFP_KERNEL)
#define pci_free_consistent(_p, size, cpu, dma) \
	dma_free_coherent(&(_p)->dev, size, cpu, dma)
#define pci_map_single(_p, cpu, size, dir) \
	dma_map_single(&(_p)->dev, cpu, size, dir)
#define pci_unmap_single(_p, dma, size, dir) \
	dma_unmap_single(&(_p)->dev, dma, size, dir)
#define pci_map_page(_p, page, off, size, dir) \
	dma_map_page(&(_p)->dev, page, off, size, dir)
#define pci_unmap_page(_p, dma, size, dir) \
	dma_unmap_page(&(_p)->dev, dma, size, dir)
#define pci_dma_mapping_error(_p, dma) \
	dma_mapping_error(&(_p)->dev, dma)

/* pci_set_dma_mask/pci_set_consistent_dma_mask: fixed by direct edits in tn40.c */

#define PCI_DMA_FROMDEVICE    DMA_FROM_DEVICE
#define PCI_DMA_TODEVICE      DMA_TO_DEVICE
#define PCI_DMA_BIDIRECTIONAL DMA_BIDIRECTIONAL

/* strlcpy removed in kernel 6.8 */
#define strlcpy(dst, src, size) strscpy(dst, src, size)

/* skb_frag_struct renamed to skb_frag (kernel 5.4+) */
#define skb_frag_struct skb_frag

#endif /* _TN40_COMPAT_H */
