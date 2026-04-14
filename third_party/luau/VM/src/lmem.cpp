// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lmem.h"

#include "lstate.h"
#include "ldo.h"
#include "ldebug.h"

#include <string.h>

/*
 * Luau heap uses a size-segregated page structure, with individual pages and large allocations
 * allocated using system heap (via frealloc callback).
 *
 * frealloc callback serves as a general, if slow, allocation callback that can allocate, free or
 * resize allocations:
 *
 *    void* frealloc(void* ud, void* ptr, size_t oldsize, size_t newsize);
 *
 * frealloc(ud, NULL, 0, x) creates a new block of size x
 * frealloc(ud, p, x, 0) frees the block p (must return NULL)
 * frealloc(ud, NULL, 0, 0) does nothing, equivalent to free(NULL)
 *
 * frealloc returns NULL if it cannot create or reallocate the area
 * (any reallocation to an equal or smaller size cannot fail!)
 *
 * On top of this, Luau implements heap storage which is split into two types of allocations:
 *
 * - GCO, short for "garbage collected objects"
 * - other objects (for example, arrays stored inside table objects)
 *
 * The heap layout for these two allocation types is a bit different.
 *
 * All GCO are allocated in pages, which is a block of memory of ~16K in size that has a page header
 * (lua_Page). Each page contains 1..N blocks of the same size, where N is selected to fill the page
 * completely. This amortizes the allocation cost and increases locality. Each GCO block starts with
 * the GC header (GCheader) which contains the object type, mark bits and other GC metadata. If the
 * GCO block is free (not used), then it must have the type set to TNIL; in this case the block can
 * be part of the per-page free list, the link for that list is stored after the header (freegcolink).
 *
 * Importantly, the GCO block doesn't have any back references to the page it's allocated in, so it's
 * impossible to free it in isolation - GCO blocks are freed by sweeping the pages they belong to,
 * using luaM_freegco which must specify the page; this is called by page sweeper that traverses the
 * entire page's worth of objects. For this reason it's also important that freed GCO blocks keep the
 * GC header intact and accessible (with type = NIL) so that the sweeper can access it.
 *
 * Some GCOs are too large to fit in a 16K page without excessive fragmentation (the size threshold is
 * currently 512 bytes); in this case, we allocate a dedicated small page with just a single block's worth
 * storage space, but that requires allocating an extra page header. In effect large GCOs are a little bit
 * less memory efficient, but this allows us to uniformly sweep small and large GCOs using page lists.
 *
 * All GCO pages are linked in a large intrusive linked list (global_State::allgcopages). Additionally,
 * for each block size there's a page free list that contains pages that have at least one free block
 * (global_State::freegcopages). This free list is used to make sure object allocation is O(1).
 *
 * When LUAU_ASSERTENABLED is enabled, all non-GCO pages are also linked in a list (global_State::allpages).
 * Because this list is not strictly required for runtime operations, it is only tracked for the purposes of
 * debugging. While overhead of linking those pages together is very small, unnecessary operations are avoided.
 *
 * Compared to GCOs, regular allocations have two important differences: they can be freed in isolation,
 * and they don't start with a GC header. Because of this, each allocation is prefixed with block metadata,
 * which contains the pointer to the page for allocated blocks, and the pointer to the next free block
 * inside the page for freed blocks.
 * For regular allocations that are too large to fit in a page (using the same threshold of 512 bytes),
 * we don't allocate a separate page, instead simply using frealloc to allocate a vanilla block of memory.
 *
 * Just like GCO pages, we store a page free list (global_State::freepages) that allows O(1) allocation;
 * there is no global list for non-GCO pages since we never need to traverse them directly.
 *
 * In both cases, we pick the page by computing the size class from the block size which rounds the block
 * size up to reduce the chance that we'll allocate pages that have very few allocated blocks. The size
 * class strategy is determined by SizeClassConfig constructor.
 *
 * Note that when the last block in a page is freed, we immediately free the page with frealloc - the
 * memory manager doesn't currently attempt to keep unused memory around. This can result in excessive
 * allocation traffic and can be mitigated by adding a page cache in the future.
 *
 * For both GCO and non-GCO pages, the per-page block allocation combines bump pointer style allocation
 * (lua_Page::freeNext) and per-page free list (lua_Page::freeList). We use the bump allocator to allocate
 * the contents of the page, and the free list for further reuse; this allows shorter page setup times
 * which results in less variance between allocation cost, as well as tighter sweep bounds for newly
 * allocated pages.
 */

#ifndef __has_feature
#define __has_feature(x) 0
#endif

#if __has_feature(address_sanitizer) || defined(LUAU_ENABLE_ASAN)
#include <sanitizer/asan_interface.h>
#define ASAN_POISON_MEMORY_REGION(addr, size) __asan_poison_memory_region((addr), (size))
#define ASAN_UNPOISON_MEMORY_REGION(addr, size) __asan_unpoison_memory_region((addr), (size))
#else
#define ASAN_POISON_MEMORY_REGION(addr, size) (void)0
#define ASAN_UNPOISON_MEMORY_REGION(addr, size) (void)0
#endif

/*
 * The sizes of most Luau objects aren't crucial for code correctness, but they are crucial for memory efficiency
 * To prevent some of them accidentally growing and us losing memory without realizing it, we're going to lock
 * the sizes of all critical structures down.
 */
#if defined(__APPLE__)
#define ABISWITCH(x64, ms32, gcc32) (sizeof(void*) == 8 ? x64 : gcc32)
#elif defined(__i386__) && defined(__MINGW32__) && !defined(__MINGW64__)
#define ABISWITCH(x64, ms32, gcc32) (ms32)
#elif defined(__i386__) && !defined(_MSC_VER)
#define ABISWITCH(x64, ms32, gcc32) (gcc32)
#else
// Android somehow uses a similar ABI to MSVC, *not* to iOS...
#define ABISWITCH(x64, ms32, gcc32) (sizeof(void*) == 8 ? x64 : ms32)
#endif

#if LUA_VECTOR_SIZE == 4
static_assert(sizeof(TValue) == ABISWITCH(24, 24, 24), "size mismatch for value");
static_assert(sizeof(LuaNode) == ABISWITCH(48, 48, 48), "size mismatch for table entry");
#else
static_assert(sizeof(TValue) == ABISWITCH(16, 16, 16), "size mismatch for value");
static_assert(sizeof(LuaNode) == ABISWITCH(32, 32, 32), "size mismatch for table entry");
#endif

static_assert(offsetof(TString, data) == ABISWITCH(24, 20, 20), "size mismatch for string header");
static_assert(sizeof(LuaTable) == ABISWITCH(48, 32, 32), "size mismatch for table header");
static_assert(offsetof(Buffer, data) == ABISWITCH(8, 8, 8), "size mismatch for buffer header");

// The userdata is designed to provide 16 byte alignment for 16 byte and larger userdata sizes
static_assert(offsetof(Udata, data) == 16, "data must be at precise offset provide proper alignment");

const size_t kSizeClasses = LUA_SIZECLASSES;

// Controls the number of entries in SizeClassConfig and define the maximum possible paged allocation size
// Modifications require updates the SizeClassConfig initialization
const size_t kMaxSmallSize = 1024;

// Effective limit on object size to use paged allocation
// Can be modified without additional changes to code, provided it is smaller or equal to kMaxSmallSize
const size_t kMaxSmallSizeUsed = 1024;

const size_t kLargePageThreshold = 512; // larger pages are used for objects larger than this size to fit more of them into a page

// constant factor to reduce our page sizes by, to increase the chances that pages we allocate will
// allow external allocators to allocate them without wasting space due to rounding introduced by their heap meta data
const size_t kExternalAllocatorMetaDataReduction = 24;

const size_t kSmallPageSize = 16 * 1024 - kExternalAllocatorMetaDataReduction;
const size_t kLargePageSize = 32 * 1024 - kExternalAllocatorMetaDataReduction;

const size_t kBlockHeader = sizeof(double) > sizeof(void*) ? sizeof(double) : sizeof(void*); // suitable for aligning double & void* on all platforms
const size_t kGCOLinkOffset = (sizeof(GCheader) + sizeof(void*) - 1) & ~(sizeof(void*) - 1); // GCO pages contain freelist links after the GC header

struct SizeClassConfig
{
    int sizeOfClass[kSizeClasses];
    int8_t classForSize[kMaxSmallSize + 1];
    int classCount = 0;

    SizeClassConfig()
    {
        memset(sizeOfClass, 0, sizeof(sizeOfClass));
        memset(classForSize, -1, sizeof(classForSize));

        // we use a progressive size class scheme:
        // - all size classes are aligned by 8b to satisfy pointer alignment requirements
        // - we first allocate sizes classes in multiples of 8
        // - after the first cutoff we allocate size classes in multiples of 16
        // - after the second cutoff we allocate size classes in multiples of 32
        // - after the third cutoff we allocate size classes in multiples of 64
        // this balances internal fragmentation vs external fragmentation
        for (int size = 8; size < 64; size += 8)
            sizeOfClass[classCount++] = size;

        for (int size = 64; size < 256; size += 16)
            sizeOfClass[classCount++] = size;

        for (int size = 256; size < 512; size += 32)
            sizeOfClass[classCount++] = size;

        for (int size = 512; size <= 1024; size += 64)
            sizeOfClass[classCount++] = size;

        LUAU_ASSERT(size_t(classCount) <= kSizeClasses);

        // fill the lookup table for all classes
        for (int klass = 0; klass < classCount; ++klass)
            classForSize[sizeOfClass[klass]] = int8_t(klass);

        // fill the gaps in lookup table
        for (int size = kMaxSmallSize - 1; size >= 0; --size)
            if (classForSize[size] < 0)
                classForSize[size] = classForSize[size + 1];
    }
};

const SizeClassConfig kSizeClassConfig;

// size class for a block of size sz; returns -1 for size=0 because empty allocations take no space
#define sizeclass(sz) (size_t((sz) - 1) < kMaxSmallSizeUsed ? kSizeClassConfig.classForSize[sz] : -1)

// metadata for a block is stored in the first pointer of the block
#define metadata(block) (*(void**)(block))
#define freegcolink(block) (*(void**)((char*)block + kGCOLinkOffset))

#if defined(LUAU_ASSERTENABLED)
#define debugpageset(x) (x)
#else
#define debugpageset(x) NULL
#endif

struct lua_Page
{
    // list of pages with free blocks
    lua_Page* prev;
    lua_Page* next;

    // list of all pages
    lua_Page* listprev;
    lua_Page* listnext;

    int pageSize;  // page size in bytes, including page header
    int blockSize; // block size in bytes, including block header (for non-GCO)

    void* freeList; // next free block in this page; linked with metadata()/freegcolink()
    int freeNext;   // next free block offset in this page, in bytes; when negative, freeList is used instead
    int busyBlocks; // number of blocks allocated out of this page

    // provide additional padding based on current object size to provide 16 byte alignment of data
    // later static_assert checks that this requirement is held
    char padding[sizeof(void*) == 8 ? 8 : 12];

    char data[1];
};

static_assert(offsetof(lua_Page, data) % 16 == 0, "data must be 16 byte aligned to provide properly aligned allocation of userdata objects");

l_noret luaM_toobig(lua_State* L)
{
    luaG_runerror(L, "memory allocation error: block too big");
}

static lua_Page* newpage(lua_State* L, lua_Page** pageset, int pageSize, int blockSize, int blockCount)
{
    global_State* g = L->global;

    LUAU_ASSERT(pageSize - int(offsetof(lua_Page, data)) >= blockSize * blockCount);

    lua_Page* page = (lua_Page*)(*g->frealloc)(g->ud, NULL, 0, pageSize);
    if (!page)
        luaD_throw(L, LUA_ERRMEM);

    ASAN_POISON_MEMORY_REGION(page->data, blockSize * blockCount);

    // setup page header
    page->prev = NULL;
    page->next = NULL;

    page->listprev = NULL;
    page->listnext = NULL;

    page->pageSize = pageSize;
    page->blockSize = blockSize;

    // note: we start with the last block in the page and move downward
    // either order would work, but that way we don't need to store the block count in the page
    // additionally, GC stores objects in singly linked lists, and this way the GC lists end up in increasing pointer order
    page->freeList = NULL;
    page->freeNext = (blockCount - 1) * blockSize;
    page->busyBlocks = 0;

    if (pageset)
    {
        page->listnext = *pageset;
        if (page->listnext)
            page->listnext->listprev = page;
        *pageset = page;
    }

    return page;
}

// this is part of a cold path in newblock and newgcoblock
// it is marked as noinline to prevent it from being inlined into those functions
// if it is inlined, then the compiler may determine those functions are "too big" to be profitably inlined, which results in reduced performance
LUAU_NOINLINE static lua_Page* newclasspage(lua_State* L, lua_Page** freepageset, lua_Page** pageset, uint8_t sizeClass, bool storeMetadata)
{
    int sizeOfClass = kSizeClassConfig.sizeOfClass[sizeClass];
    int pageSize = sizeOfClass > int(kLargePageThreshold) ? kLargePageSize : kSmallPageSize;
    int blockSize = sizeOfClass + (storeMetadata ? kBlockHeader : 0);
    int blockCount = (pageSize - offsetof(lua_Page, data)) / blockSize;

    lua_Page* page = newpage(L, pageset, pageSize, blockSize, blockCount);

    // prepend a page to page freelist (which is empty because we only ever allocate a new page when it is!)
    LUAU_ASSERT(!freepageset[sizeClass]);
    freepageset[sizeClass] = page;

    return page;
}

static void freepage(lua_State* L, lua_Page** pageset, lua_Page* page)
{
    global_State* g = L->global;

    if (pageset)
    {
        // remove page from alllist
        if (page->listnext)
            page->listnext->listprev = page->listprev;

        if (page->listprev)
            page->listprev->listnext = page->listnext;
        else if (*pageset == page)
            *pageset = page->listnext;
    }

    // so long
    (*g->frealloc)(g->ud, page, page->pageSize, 0);
}

static void freeclasspage(lua_State* L, lua_Page** freepageset, lua_Page** pageset, lua_Page* page, uint8_t sizeClass)
{
    // remove page from freelist
    if (page->next)
        page->next->prev = page->prev;

    if (page->prev)
        page->prev->next = page->next;
    else if (freepageset[sizeClass] == page)
        freepageset[sizeClass] = page->next;

    freepage(L, pageset, page);
}

static void* newblock(lua_State* L, int sizeClass)
{
    global_State* g = L->global;
    lua_Page* page = g->freepages[sizeClass];

    // slow path: no page in the freelist, allocate a new one
    if (!page)
        page = newclasspage(L, g->freepages, debugpageset(&g->allpages), sizeClass, true);

    LUAU_ASSERT(!page->prev);
    LUAU_ASSERT(page->freeList || page->freeNext >= 0);
    LUAU_ASSERT(size_t(page->blockSize) == kSizeClassConfig.sizeOfClass[sizeClass] + kBlockHeader);

    void* block;

    if (page->freeNext >= 0)
    {
        block = &page->data + page->freeNext;
        ASAN_UNPOISON_MEMORY_REGION(block, page->blockSize);

        page->freeNext -= page->blockSize;
        page->busyBlocks++;
    }
    else
    {
        block = page->freeList;
        ASAN_UNPOISON_MEMORY_REGION(block, page->blockSize);

        page->freeList = metadata(block);
        page->busyBlocks++;
    }

    // the first word in a block point back to the page
    metadata(block) = page;

    // if we allocate the last block out of a page, we need to remove it from free list
    if (!page->freeList && page->freeNext < 0)
    {
        g->freepages[sizeClass] = page->next;
        if (page->next)
            page->next->prev = NULL;
        page->next = NULL;
    }

    // the user data is right after the metadata
    return (char*)block + kBlockHeader;
}

static void* newgcoblock(lua_State* L, int sizeClass)
{
    global_State* g = L->global;
    lua_Page* page = g->freegcopages[sizeClass];

    // slow path: no page in the freelist, allocate a new one
    if (!page)
        page = newclasspage(L, g->freegcopages, &g->allgcopages, sizeClass, false);

    LUAU_ASSERT(!page->prev);
    LUAU_ASSERT(page->freeList || page->freeNext >= 0);
    LUAU_ASSERT(page->blockSize == kSizeClassConfig.sizeOfClass[sizeClass]);

    void* block;

    if (page->freeNext >= 0)
    {
        block = &page->data + page->freeNext;
        ASAN_UNPOISON_MEMORY_REGION(block, page->blockSize);

        page->freeNext -= page->blockSize;
        page->busyBlocks++;
    }
    else
    {
        block = page->freeList;
        ASAN_UNPOISON_MEMORY_REGION((char*)block + sizeof(GCheader), page->blockSize - sizeof(GCheader));

        // when separate block metadata is not used, free list link is stored inside the block data itself
        page->freeList = freegcolink(block);
        page->busyBlocks++;
    }

    // if we allocate the last block out of a page, we need to remove it from free list
    if (!page->freeList && page->freeNext < 0)
    {
        g->freegcopages[sizeClass] = page->next;
        if (page->next)
            page->next->prev = NULL;
        page->next = NULL;
    }

    return block;
}

static void freeblock(lua_State* L, int sizeClass, void* block)
{
    global_State* g = L->global;

    // the user data is right after the metadata
    LUAU_ASSERT(block);
    block = (char*)block - kBlockHeader;

    lua_Page* page = (lua_Page*)metadata(block);
    LUAU_ASSERT(page && page->busyBlocks > 0);
    LUAU_ASSERT(size_t(page->blockSize) == kSizeClassConfig.sizeOfClass[sizeClass] + kBlockHeader);
    LUAU_ASSERT(block >= page->data && block < (char*)page + page->pageSize);

    // if the page wasn't in the page free list, it should be now since it got a block!
    if (!page->freeList && page->freeNext < 0)
    {
        LUAU_ASSERT(!page->prev);
        LUAU_ASSERT(!page->next);

        page->next = g->freepages[sizeClass];
        if (page->next)
            page->next->prev = page;
        g->freepages[sizeClass] = page;
    }

    // add the block to the free list inside the page
    metadata(block) = page->freeList;
    page->freeList = block;

    ASAN_POISON_MEMORY_REGION(block, page->blockSize);

    page->busyBlocks--;

    // if it's the last block in the page, we don't need the page
    if (page->busyBlocks == 0)
        freeclasspage(L, g->freepages, debugpageset(&g->allpages), page, sizeClass);
}

static void freegcoblock(lua_State* L, int sizeClass, void* block, lua_Page* page)
{
    LUAU_ASSERT(page && page->busyBlocks > 0);
    LUAU_ASSERT(page->blockSize == kSizeClassConfig.sizeOfClass[sizeClass]);
    LUAU_ASSERT(block >= page->data && block < (char*)page + page->pageSize);

    global_State* g = L->global;

    // if the page wasn't in the page free list, it should be now since it got a block!
    if (!page->freeList && page->freeNext < 0)
    {
        LUAU_ASSERT(!page->prev);
        LUAU_ASSERT(!page->next);

        page->next = g->freegcopages[sizeClass];
        if (page->next)
            page->next->prev = page;
        g->freegcopages[sizeClass] = page;
    }

    // when separate block metadata is not used, free list link is stored inside the block data itself
    freegcolink(block) = page->freeList;
    page->freeList = block;

    ASAN_POISON_MEMORY_REGION((char*)block + sizeof(GCheader), page->blockSize - sizeof(GCheader));

    page->busyBlocks--;

    // if it's the last block in the page, we don't need the page
    if (page->busyBlocks == 0)
        freeclasspage(L, g->freegcopages, &g->allgcopages, page, sizeClass);
}

void* luaM_new_(lua_State* L, size_t nsize, uint8_t memcat)
{
    global_State* g = L->global;

    int nclass = sizeclass(nsize);

    void* block = nclass >= 0 ? newblock(L, nclass) : (*g->frealloc)(g->ud, NULL, 0, nsize);
    if (block == NULL && nsize > 0)
        luaD_throw(L, LUA_ERRMEM);

    g->totalbytes += nsize;
    g->memcatbytes[memcat] += nsize;

    if (LUAU_UNLIKELY(!!g->cb.onallocate))
    {
        g->cb.onallocate(L, 0, nsize);
    }

    return block;
}

GCObject* luaM_newgco_(lua_State* L, size_t nsize, uint8_t memcat)
{
    // we need to accommodate space for link for free blocks (freegcolink)
    LUAU_ASSERT(nsize >= kGCOLinkOffset + sizeof(void*));

    global_State* g = L->global;

    int nclass = sizeclass(nsize);

    void* block = NULL;

    if (nclass >= 0)
    {
        block = newgcoblock(L, nclass);
    }
    else
    {
        lua_Page* page = newpage(L, &g->allgcopages, offsetof(lua_Page, data) + int(nsize), int(nsize), 1);

        block = &page->data;
        ASAN_UNPOISON_MEMORY_REGION(block, page->blockSize);

        page->freeNext -= page->blockSize;
        page->busyBlocks++;
    }

    if (block == NULL && nsize > 0)
        luaD_throw(L, LUA_ERRMEM);

    g->totalbytes += nsize;
    g->memcatbytes[memcat] += nsize;

    if (LUAU_UNLIKELY(!!g->cb.onallocate))
    {
        g->cb.onallocate(L, 0, nsize);
    }

    return (GCObject*)block;
}

void luaM_free_(lua_State* L, void* block, size_t osize, uint8_t memcat)
{
    global_State* g = L->global;
    LUAU_ASSERT((osize == 0) == (block == NULL));

    int oclass = sizeclass(osize);

    if (oclass >= 0)
        freeblock(L, oclass, block);
    else
        (*g->frealloc)(g->ud, block, osize, 0);

    g->totalbytes -= osize;
    g->memcatbytes[memcat] -= osize;
}

void luaM_freegco_(lua_State* L, GCObject* block, size_t osize, uint8_t memcat, lua_Page* page)
{
    global_State* g = L->global;
    LUAU_ASSERT((osize == 0) == (block == NULL));

    int oclass = sizeclass(osize);

    if (oclass >= 0)
    {
        block->gch.tt = LUA_TNIL;

        freegcoblock(L, oclass, block, page);
    }
    else
    {
        LUAU_ASSERT(page->busyBlocks == 1);
        LUAU_ASSERT(size_t(page->blockSize) == osize);
        LUAU_ASSERT((void*)block == page->data);

        freepage(L, &g->allgcopages, page);
    }

    g->totalbytes -= osize;
    g->memcatbytes[memcat] -= osize;
}

void* luaM_realloc_(lua_State* L, void* block, size_t osize, size_t nsize, uint8_t memcat)
{
    global_State* g = L->global;
    LUAU_ASSERT((osize == 0) == (block == NULL));

    int nclass = sizeclass(nsize);
    int oclass = sizeclass(osize);
    void* result;

    // if either block needs to be allocated using a block allocator, we can't use realloc directly
    if (nclass >= 0 || oclass >= 0)
    {
        result = nclass >= 0 ? newblock(L, nclass) : (*g->frealloc)(g->ud, NULL, 0, nsize);
        if (result == NULL && nsize > 0)
            luaD_throw(L, LUA_ERRMEM);

        if (osize > 0 && nsize > 0)
            memcpy(result, block, osize < nsize ? osize : nsize);

        if (oclass >= 0)
            freeblock(L, oclass, block);
        else
            (*g->frealloc)(g->ud, block, osize, 0);
    }
    else
    {
        result = (*g->frealloc)(g->ud, block, osize, nsize);
        if (result == NULL && nsize > 0)
            luaD_throw(L, LUA_ERRMEM);
    }

    LUAU_ASSERT((nsize == 0) == (result == NULL));
    g->totalbytes = (g->totalbytes - osize) + nsize;
    g->memcatbytes[memcat] += nsize - osize;

    if (LUAU_UNLIKELY(!!g->cb.onallocate))
    {
        g->cb.onallocate(L, osize, nsize);
    }

    return result;
}

void luaM_getpagewalkinfo(lua_Page* page, char** start, char** end, int* busyBlocks, int* blockSize)
{
    int blockCount = (page->pageSize - offsetof(lua_Page, data)) / page->blockSize;

    LUAU_ASSERT(page->freeNext >= -page->blockSize && page->freeNext <= (blockCount - 1) * page->blockSize);

    char* data = page->data; // silences ubsan when indexing page->data

    *start = data + page->freeNext + page->blockSize;
    *end = data + blockCount * page->blockSize;
    *busyBlocks = page->busyBlocks;
    *blockSize = page->blockSize;
}

void luaM_getpageinfo(lua_Page* page, int* pageBlocks, int* busyBlocks, int* blockSize, int* pageSize)
{
    *pageBlocks = (page->pageSize - offsetof(lua_Page, data)) / page->blockSize;
    *busyBlocks = page->busyBlocks;
    *blockSize = page->blockSize;
    *pageSize = page->pageSize;
}

lua_Page* luaM_getnextpage(lua_Page* page)
{
    return page->listnext;
}

void luaM_visitpage(lua_Page* page, void* context, bool (*visitor)(void* context, lua_Page* page, GCObject* gco))
{
    char* start;
    char* end;
    int busyBlocks;
    int blockSize;
    luaM_getpagewalkinfo(page, &start, &end, &busyBlocks, &blockSize);

    for (char* pos = start; pos != end; pos += blockSize)
    {
        GCObject* gco = (GCObject*)pos;

        // skip memory blocks that are already freed
        if (gco->gch.tt == LUA_TNIL)
            continue;

        // when true is returned it means that the element was deleted
        if (visitor(context, page, gco))
        {
            LUAU_ASSERT(busyBlocks > 0);

            // if the last block was removed, page would be removed as well
            if (--busyBlocks == 0)
                break;
        }
    }
}

void luaM_visitgco(lua_State* L, void* context, bool (*visitor)(void* context, lua_Page* page, GCObject* gco))
{
    global_State* g = L->global;

    for (lua_Page* curr = g->allgcopages; curr;)
    {
        lua_Page* next = curr->listnext; // block visit might destroy the page

        luaM_visitpage(curr, context, visitor);

        curr = next;
    }
}
