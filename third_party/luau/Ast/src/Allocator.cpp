// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details

#include "Luau/Allocator.h"

namespace Luau
{

Allocator::Allocator()
    : root(static_cast<Page*>(operator new(sizeof(Page))))
    , offset(0)
{
    root->next = nullptr;
}

Allocator::Allocator(Allocator&& rhs)
    : root(rhs.root)
    , offset(rhs.offset)
{
    rhs.root = nullptr;
    rhs.offset = 0;
}

Allocator::~Allocator()
{
    Page* page = root;

    while (page)
    {
        Page* next = page->next;

        operator delete(page);

        page = next;
    }
}

void* Allocator::allocate(size_t size)
{
    constexpr size_t align = alignof(void*) > alignof(double) ? alignof(void*) : alignof(double);

    if (root)
    {
        uintptr_t data = reinterpret_cast<uintptr_t>(root->data);
        uintptr_t result = (data + offset + align - 1) & ~(align - 1);
        if (result + size <= data + sizeof(root->data))
        {
            offset = result - data + size;
            return reinterpret_cast<void*>(result);
        }
    }

    // allocate new page
    size_t pageSize = size > sizeof(root->data) ? size : sizeof(root->data);
    void* pageData = operator new(offsetof(Page, data) + pageSize);

    Page* page = static_cast<Page*>(pageData);

    page->next = root;

    root = page;
    offset = size;

    return page->data;
}

} // namespace Luau
