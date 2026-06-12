// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include <cstddef>
#include <cstring>
#include <stdint.h>

namespace Luau
{

template<typename T>
T read(const char* data, size_t& offset)
{
    T result;
    memcpy(&result, data + offset, sizeof(T));
    offset += sizeof(T);

    return result;
}

unsigned int readVarInt(const char* data, size_t& offset);
uint64_t readVarInt64(const char* data, size_t& offset);

} // namespace Luau
