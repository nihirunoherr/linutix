/* SPDX-License-Identifier: GPL-2.0-only */
/*
 *  linux/arch/arm/mm/cache-v4wt.S
 *
 *  Copyright (C) 1997-2002 Russell king
 *
 *  ARMv4 write through cache operations support.
 *
 *  We assume that the write buffer is not enabled.
 */
#include <linux/linkage.h>
#include <linux/init.h>
#include <linux/cfi_types.h>
#include <asm/assembler.h>
#include <asm/page.h>
#include "proc-macros.S"

/*
 * The size of one data cache line.
 */
#define CACHE_DLINESIZE	32

/*
 * The number of data cache segments.
 */
#define CACHE_DSEGMENTS	8

/*
 * The number of lines in a cache segment.
 */
#define CACHE_DENTRIES	64

/*
 * This is the size at which it becomes more efficient to
 * clean the whole cache, rather than using the individual
 * cache line maintenance instructions.
 *
 * *** This needs benchmarking
 */
#define CACHE_DLIMIT	16384

/*
 *	flush_icache_all()
 *
 *	Unconditionally clean and invalidate the entire icache.
 */
SYM_TYPED_FUNC_START(v4wt_flush_icache_all)
	mov	r0, #0
	mcr	p15, 0, r0, c7, c5, 0		@ invalidate I cache
	ret	lr
SYM_FUNC_END(v4wt_flush_icache_all)

/*
 *	flush_user_cache_all()
 *
 *	Invalidate all cache entries in a particular address
 *	space.
 */
SYM_FUNC_ALIAS(v4wt_flush_user_cache_all, v4wt_flush_kern_cache_all)

/*
 *	flush_kern_cache_all()
 *
 *	Clean and invalidate the entire cache.
 */
SYM_TYPED_FUNC_START(v4wt_flush_kern_cache_all)
	mov	r2, #VM_EXEC
	mov	ip, #0
__flush_whole_cache:
	tst	r2, #VM_EXEC
	mcrne	p15, 0, ip, c7, c5, 0		@ invalidate I cache
	mcr	p15, 0, ip, c7, c6, 0		@ invalidate D cache
	ret	lr
SYM_FUNC_END(v4wt_flush_kern_cache_all)

/*
 *	flush_user_cache_range(start, end, flags)
 *
 *	Clean and invalidate a range of cache entries in the specified
 *	address space.
 *
 *	- start - start address (inclusive, page aligned)
 *	- end	- end address (exclusive, page aligned)
 *	- flags	- vma_area_struct flags describing address space
 */
SYM_TYPED_FUNC_START(v4wt_flush_user_cache_range)
	sub	r3, r1, r0			@ calculate total size
	cmp	r3, #CACHE_DLIMIT
	bhs	__flush_whole_cache

1:	mcr	p15, 0, r0, c7, c6, 1		@ invalidate D entry
	tst	r2, #VM_EXEC
	mcrne	p15, 0, r0, c7, c5, 1		@ invalidate I entry
	add	r0, r0, #CACHE_DLINESIZE
	cmp	r0, r1
	blo	1b
	ret	lr
SYM_FUNC_END(v4wt_flush_user_cache_range)

/*
 *	coherent_kern_range(start, end)
 *
 *	Ensure coherency between the Icache and the Dcache in the
 *	region described by start.  If you have non-snooping
 *	Harvard caches, you need to implement this function.
 *
 *	- start  - virtual start address
 *	- end	 - virtual end address
 */
SYM_TYPED_FUNC_START(v4wt_coherent_kern_range)
#ifdef CONFIG_CFI_CLANG /* Fallthrough if !CFI */
	b	v4wt_coherent_user_range
#endif
SYM_FUNC_END(v4wt_coherent_kern_range)

/*
 *	coherent_user_range(start, end)
 *
 *	Ensure coherency between the Icache and the Dcache in the
 *	region described by start.  If you have non-snooping
 *	Harvard caches, you need to implement this function.
 *
 *	- start  - virtual start address
 *	- end	 - virtual end address
 */
SYM_TYPED_FUNC_START(v4wt_coherent_user_range)
	bic	r0, r0, #CACHE_DLINESIZE - 1
1:	mcr	p15, 0, r0, c7, c5, 1		@ invalidate I entry
	add	r0, r0, #CACHE_DLINESIZE
	cmp	r0, r1
	blo	1b
	mov	r0, #0
	ret	lr
SYM_FUNC_END(v4wt_coherent_user_range)

/*
 *	flush_kern_dcache_area(void *addr, size_t size)
 *
 *	Ensure no D cache aliasing occurs, either with itself or
 *	the I cache
 *
 *	- addr	- kernel address
 *	- size	- region size
 */
SYM_TYPED_FUNC_START(v4wt_flush_kern_dcache_area)
	mov	r2, #0
	mcr	p15, 0, r2, c7, c5, 0		@ invalidate I cache
	add	r1, r0, r1
	b	v4wt_dma_inv_range
SYM_FUNC_END(v4wt_flush_kern_dcache_area)

/*
 *	dma_inv_range(start, end)
 *
 *	Invalidate (discard) the specified virtual address range.
 *	May not write back any entries.  If 'start' or 'end'
 *	are not cache line aligned, those lines must be written
 *	back.
 *
 *	- start  - virtual start address
 *	- end	 - virtual end address
 */
v4wt_dma_inv_range:
	bic	r0, r0, #CACHE_DLINESIZE - 1
1:	mcr	p15, 0, r0, c7, c6, 1		@ invalidate D entry
	add	r0, r0, #CACHE_DLINESIZE
	cmp	r0, r1
	blo	1b
	ret	lr

/*
 *	dma_flush_range(start, end)
 *
 *	Clean and invalidate the specified virtual address range.
 *
 *	- start  - virtual start address
 *	- end	 - virtual end address
*/
SYM_TYPED_FUNC_START(v4wt_dma_flush_range)
	b	v4wt_dma_inv_range
SYM_FUNC_END(v4wt_dma_flush_range)

/*
 *	dma_unmap_area(start, size, dir)
 *	- start	- kernel virtual start address
 *	- size	- size of region
 *	- dir	- DMA direction
 */
SYM_TYPED_FUNC_START(v4wt_dma_unmap_area)
	add	r1, r1, r0
	teq	r2, #DMA_TO_DEVICE
	bne	v4wt_dma_inv_range
	ret	lr
SYM_FUNC_END(v4wt_dma_unmap_area)

/*
 *	dma_map_area(start, size, dir)
 *	- start	- kernel virtual start address
 *	- size	- size of region
 *	- dir	- DMA direction
 */
SYM_TYPED_FUNC_START(v4wt_dma_map_area)
	ret	lr
SYM_FUNC_END(v4wt_dma_map_area)
