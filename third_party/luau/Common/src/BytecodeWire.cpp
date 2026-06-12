// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "Luau/BytecodeWire.h"

#include "Luau/Common.h"

namespace Luau
{

uint64_t readVarInt64(const char* data, size_t& offset)
{
    uint64_t result = 0;
    unsigned int shift = 0;

    uint8_t byte;

    do
    {
        byte = read<uint8_t>(data, offset);
        result |= static_cast<uint64_t>(byte & 127) << shift;
        shift += 7;
    } while (byte & 128);

    return result;
}

unsigned int readVarInt(const char* data, size_t& offset)
{
    return static_cast<unsigned int>(readVarInt64(data, offset));
}

} // namespace Luau