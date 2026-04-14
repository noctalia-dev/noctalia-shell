// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Ast.h"
#include "Luau/DenseHash.h"

#include "ConstantFolding.h"

namespace Luau
{
namespace Compile
{

inline bool isConstantTrue(const DenseHashMap<AstExpr*, Constant>& constants, AstExpr* node)
{
    const Constant* cv = constants.find(node);

    return cv && cv->type != Constant::Type_Unknown && cv->isTruthful();
}

inline bool isConstantFalse(const DenseHashMap<AstExpr*, Constant>& constants, AstExpr* node)
{
    const Constant* cv = constants.find(node);

    return cv && cv->type != Constant::Type_Unknown && !cv->isTruthful();
}

// true iff all execution paths through node subtree result in return/break/continue
// note: because this function doesn't visit loop nodes, it (correctly) only detects break/continue that refer to the outer control flow
inline bool alwaysTerminates(const DenseHashMap<AstExpr*, Constant>& constants, AstStat* node)
{
    if (AstStatBlock* stat = node->as<AstStatBlock>())
    {
        for (size_t i = 0; i < stat->body.size; ++i)
        {
            if (alwaysTerminates(constants, stat->body.data[i]))
                return true;
        }

        return false;
    }

    if (node->is<AstStatReturn>())
        return true;

    if (node->is<AstStatBreak>() || node->is<AstStatContinue>())
        return true;

    if (AstStatIf* stat = node->as<AstStatIf>())
    {
        if (isConstantTrue(constants, stat->condition))
            return alwaysTerminates(constants, stat->thenbody);

        if (isConstantFalse(constants, stat->condition) && stat->elsebody)
            return alwaysTerminates(constants, stat->elsebody);

        return stat->elsebody && alwaysTerminates(constants, stat->thenbody) && alwaysTerminates(constants, stat->elsebody);
    }

    return false;
}

} // namespace Compile
} // namespace Luau
