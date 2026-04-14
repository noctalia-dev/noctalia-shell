// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "ValueTracking.h"

namespace Luau
{
struct CompileOptions;
}

namespace Luau
{
namespace Compile
{

struct Builtin
{
    AstName object;
    AstName method;

    bool empty() const
    {
        return object == AstName() && method == AstName();
    }

    bool isGlobal(const char* name) const
    {
        return object == AstName() && method == name;
    }

    bool isMethod(const char* table, const char* name) const
    {
        return object == table && method == name;
    }
};

Builtin getBuiltin(AstExpr* node, const DenseHashMap<AstName, Global>& globals, const DenseHashMap<AstLocal*, Variable>& variables);

void analyzeBuiltins(
    DenseHashMap<AstExprCall*, int>& result,
    const DenseHashMap<AstName, Global>& globals,
    const DenseHashMap<AstLocal*, Variable>& variables,
    const CompileOptions& options,
    AstNode* root,
    const AstNameTable& names
);

struct BuiltinInfo
{
    enum Flags
    {
        // none-safe builtins are builtins that have the same behavior for arguments that are nil or none
        // this allows the compiler to compile calls to builtins more efficiently in certain cases
        // for example, math.abs(x()) may compile x() as if it returns one value; if it returns no values, abs() will get nil instead of none
        Flag_NoneSafe = 1 << 0,
    };

    int params;
    int results;
    unsigned int flags;
};

BuiltinInfo getBuiltinInfo(int bfid);

} // namespace Compile
} // namespace Luau
