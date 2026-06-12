// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "ConstantFolding.h"

#include "BuiltinFolding.h"
#include "Utils.h"
#include "Luau/Bytecode.h"
#include "Luau/Lexer.h"

#include <vector>
#include <math.h>

LUAU_FASTFLAG(LuauIntegerType2)
LUAU_FASTFLAGVARIABLE(LuauCompilePropagateTableProps2)
LUAU_FASTFLAGVARIABLE(LuauCompileFoldOptimize)
LUAU_FASTFLAGVARIABLE(LuauCompileNewTableMutationTracker)

namespace Luau
{
namespace Compile
{

constexpr size_t kConstantFoldStringLimit = 4096;

static bool constantsEqual(const Constant& la, const Constant& ra)
{
    LUAU_ASSERT(la.type != Constant::Type_Unknown && ra.type != Constant::Type_Unknown);

    switch (la.type)
    {
    case Constant::Type_Nil:
        return ra.type == Constant::Type_Nil;

    case Constant::Type_Boolean:
        return ra.type == Constant::Type_Boolean && la.valueBoolean == ra.valueBoolean;

    case Constant::Type_Number:
        return ra.type == Constant::Type_Number && la.valueNumber == ra.valueNumber;

    case Constant::Type_Vector:
        return ra.type == Constant::Type_Vector && la.valueVector[0] == ra.valueVector[0] && la.valueVector[1] == ra.valueVector[1] &&
               la.valueVector[2] == ra.valueVector[2] && la.valueVector[3] == ra.valueVector[3];

    case Constant::Type_String:
        return ra.type == Constant::Type_String && la.stringLength == ra.stringLength && memcmp(la.valueString, ra.valueString, la.stringLength) == 0;

    case Constant::Type_Table:
        if (FFlag::LuauCompilePropagateTableProps2)
            return ra.type == Constant::Type_Table && la.valueTable == ra.valueTable;
        else
        {
            LUAU_ASSERT(!"Unexpected constant type in comparison");
            return false;
        }

    case Constant::Type_Integer:
        if (FFlag::LuauIntegerType2)
            return ra.type == Constant::Type_Integer && la.valueInteger64 == ra.valueInteger64;
        [[fallthrough]];

    default:
        LUAU_ASSERT(!"Unexpected constant type in comparison");
        return false;
    }
}

static void foldUnary(Constant& result, AstExprUnary::Op op, const Constant& arg)
{
    switch (op)
    {
    case AstExprUnary::Not:
        if (arg.type != Constant::Type_Unknown)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = !arg.isTruthful();
        }
        break;

    case AstExprUnary::Minus:
        if (arg.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = -arg.valueNumber;
        }
        else if (arg.type == Constant::Type_Vector)
        {
            result.type = Constant::Type_Vector;
            result.valueVector[0] = -arg.valueVector[0];
            result.valueVector[1] = -arg.valueVector[1];
            result.valueVector[2] = -arg.valueVector[2];
            result.valueVector[3] = -arg.valueVector[3];
        }
        break;

    case AstExprUnary::Len:
        if (arg.type == Constant::Type_String)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = double(arg.stringLength);
        }
        break;

    default:
        LUAU_ASSERT(!"Unexpected unary operation");
    }
}

static void foldBinary(Constant& result, AstExprBinary::Op op, const Constant& la, const Constant& ra, AstNameTable& stringTable)
{
    switch (op)
    {
    case AstExprBinary::Add:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = la.valueNumber + ra.valueNumber;
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Vector)
        {
            result.type = Constant::Type_Vector;
            result.valueVector[0] = la.valueVector[0] + ra.valueVector[0];
            result.valueVector[1] = la.valueVector[1] + ra.valueVector[1];
            result.valueVector[2] = la.valueVector[2] + ra.valueVector[2];
            result.valueVector[3] = la.valueVector[3] + ra.valueVector[3];
        }
        break;

    case AstExprBinary::Sub:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = la.valueNumber - ra.valueNumber;
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Vector)
        {
            result.type = Constant::Type_Vector;
            result.valueVector[0] = la.valueVector[0] - ra.valueVector[0];
            result.valueVector[1] = la.valueVector[1] - ra.valueVector[1];
            result.valueVector[2] = la.valueVector[2] - ra.valueVector[2];
            result.valueVector[3] = la.valueVector[3] - ra.valueVector[3];
        }
        break;

    case AstExprBinary::Mul:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = la.valueNumber * ra.valueNumber;
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Vector)
        {
            bool hadW = la.valueVector[3] != 0.0f || ra.valueVector[3] != 0.0f;
            float resultW = la.valueVector[3] * ra.valueVector[3];

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = la.valueVector[0] * ra.valueVector[0];
                result.valueVector[1] = la.valueVector[1] * ra.valueVector[1];
                result.valueVector[2] = la.valueVector[2] * ra.valueVector[2];
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Number && ra.type == Constant::Type_Vector)
        {
            bool hadW = ra.valueVector[3] != 0.0f;
            float resultW = float(la.valueNumber) * ra.valueVector[3];

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = float(la.valueNumber) * ra.valueVector[0];
                result.valueVector[1] = float(la.valueNumber) * ra.valueVector[1];
                result.valueVector[2] = float(la.valueNumber) * ra.valueVector[2];
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Number)
        {
            bool hadW = la.valueVector[3] != 0.0f;
            float resultW = la.valueVector[3] * float(ra.valueNumber);

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = la.valueVector[0] * float(ra.valueNumber);
                result.valueVector[1] = la.valueVector[1] * float(ra.valueNumber);
                result.valueVector[2] = la.valueVector[2] * float(ra.valueNumber);
                result.valueVector[3] = resultW;
            }
        }
        break;

    case AstExprBinary::Div:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = la.valueNumber / ra.valueNumber;
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Vector)
        {
            bool hadW = la.valueVector[3] != 0.0f || ra.valueVector[3] != 0.0f;
            float resultW = la.valueVector[3] / ra.valueVector[3];

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = la.valueVector[0] / ra.valueVector[0];
                result.valueVector[1] = la.valueVector[1] / ra.valueVector[1];
                result.valueVector[2] = la.valueVector[2] / ra.valueVector[2];
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Number && ra.type == Constant::Type_Vector)
        {
            bool hadW = ra.valueVector[3] != 0.0f;
            float resultW = float(la.valueNumber) / ra.valueVector[3];

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = float(la.valueNumber) / ra.valueVector[0];
                result.valueVector[1] = float(la.valueNumber) / ra.valueVector[1];
                result.valueVector[2] = float(la.valueNumber) / ra.valueVector[2];
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Number)
        {
            bool hadW = la.valueVector[3] != 0.0f;
            float resultW = la.valueVector[3] / float(ra.valueNumber);

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = la.valueVector[0] / float(ra.valueNumber);
                result.valueVector[1] = la.valueVector[1] / float(ra.valueNumber);
                result.valueVector[2] = la.valueVector[2] / float(ra.valueNumber);
                result.valueVector[3] = resultW;
            }
        }
        break;

    case AstExprBinary::FloorDiv:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = floor(la.valueNumber / ra.valueNumber);
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Vector)
        {
            bool hadW = la.valueVector[3] != 0.0f || ra.valueVector[3] != 0.0f;
            float resultW = floor(la.valueVector[3] / ra.valueVector[3]);

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = floor(la.valueVector[0] / ra.valueVector[0]);
                result.valueVector[1] = floor(la.valueVector[1] / ra.valueVector[1]);
                result.valueVector[2] = floor(la.valueVector[2] / ra.valueVector[2]);
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Number && ra.type == Constant::Type_Vector)
        {
            bool hadW = ra.valueVector[3] != 0.0f;
            float resultW = floor(float(la.valueNumber) / ra.valueVector[3]);

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = floor(float(la.valueNumber) / ra.valueVector[0]);
                result.valueVector[1] = floor(float(la.valueNumber) / ra.valueVector[1]);
                result.valueVector[2] = floor(float(la.valueNumber) / ra.valueVector[2]);
                result.valueVector[3] = resultW;
            }
        }
        else if (la.type == Constant::Type_Vector && ra.type == Constant::Type_Number)
        {
            bool hadW = la.valueVector[3] != 0.0f;
            float resultW = floor(la.valueVector[3] / float(ra.valueNumber));

            if (resultW == 0.0f || hadW)
            {
                result.type = Constant::Type_Vector;
                result.valueVector[0] = floor(la.valueVector[0] / float(ra.valueNumber));
                result.valueVector[1] = floor(la.valueVector[1] / float(ra.valueNumber));
                result.valueVector[2] = floor(la.valueVector[2] / float(ra.valueNumber));
                result.valueVector[3] = floor(la.valueVector[3] / float(ra.valueNumber));
            }
        }
        break;

    case AstExprBinary::Mod:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = la.valueNumber - floor(la.valueNumber / ra.valueNumber) * ra.valueNumber;
        }
        break;

    case AstExprBinary::Pow:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Number;
            result.valueNumber = pow(la.valueNumber, ra.valueNumber);
        }
        break;

    case AstExprBinary::Concat:
        if (la.type == Constant::Type_String && ra.type == Constant::Type_String && la.stringLength + ra.stringLength <= kConstantFoldStringLimit)
        {
            result.type = Constant::Type_String;
            result.stringLength = la.stringLength + ra.stringLength;
            if (la.stringLength == 0)
                result.valueString = ra.valueString;
            else if (ra.stringLength == 0)
                result.valueString = la.valueString;
            else
            {
                std::string tmp;
                tmp.reserve(result.stringLength + 1);
                tmp.append(la.valueString, la.stringLength);
                tmp.append(ra.valueString, ra.stringLength);
                AstName name = stringTable.getOrAdd(tmp.c_str(), result.stringLength);
                result.valueString = name.value;
            }
        }
        break;

    case AstExprBinary::CompareNe:
        if (la.type != Constant::Type_Unknown && ra.type != Constant::Type_Unknown)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = !constantsEqual(la, ra);
        }
        break;

    case AstExprBinary::CompareEq:
        if (la.type != Constant::Type_Unknown && ra.type != Constant::Type_Unknown)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = constantsEqual(la, ra);
        }
        break;

    case AstExprBinary::CompareLt:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = la.valueNumber < ra.valueNumber;
        }
        break;

    case AstExprBinary::CompareLe:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = la.valueNumber <= ra.valueNumber;
        }
        break;

    case AstExprBinary::CompareGt:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = la.valueNumber > ra.valueNumber;
        }
        break;

    case AstExprBinary::CompareGe:
        if (la.type == Constant::Type_Number && ra.type == Constant::Type_Number)
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = la.valueNumber >= ra.valueNumber;
        }
        break;

    case AstExprBinary::And:
        if (la.type != Constant::Type_Unknown)
        {
            result = la.isTruthful() ? ra : la;
        }
        break;

    case AstExprBinary::Or:
        if (la.type != Constant::Type_Unknown)
        {
            result = la.isTruthful() ? la : ra;
        }
        break;

    default:
        LUAU_ASSERT(!"Unexpected binary operation");
    }
}

static void foldInterpString(Constant& result, AstExprInterpString* expr, DenseHashMap<AstExpr*, Constant>& constants, AstNameTable& stringTable)
{
    LUAU_ASSERT(expr->strings.size == expr->expressions.size + 1);
    size_t resultLength = 0;
    for (size_t index = 0; index < expr->strings.size; ++index)
    {
        resultLength += expr->strings.data[index].size;
        if (index < expr->expressions.size)
        {
            const Constant* c = constants.find(expr->expressions.data[index]);
            LUAU_ASSERT(c != nullptr && c->type == Constant::Type::Type_String);
            resultLength += c->stringLength;
        }
    }

    if (resultLength > kConstantFoldStringLimit)
        return;

    result.type = Constant::Type_String;
    result.stringLength = unsigned(resultLength);

    if (resultLength == 0)
    {
        result.valueString = "";
        return;
    }

    std::string tmp;
    tmp.reserve(resultLength);

    for (size_t index = 0; index < expr->strings.size; ++index)
    {
        AstArray<char> string = expr->strings.data[index];
        tmp.append(string.data, string.size);
        if (index < expr->expressions.size)
        {
            const Constant* c = constants.find(expr->expressions.data[index]);
            tmp.append(c->valueString, c->stringLength);
        }
    }
    result.type = Constant::Type_String;
    result.stringLength = unsigned(resultLength);
    AstName name = stringTable.getOrAdd(tmp.c_str(), resultLength);
    result.valueString = name.value;
}

// Figures out which locals are initialized with constant tables, and never potentially mutated
// The bulk of the work is done on two analyses on AstExpr nodes:
// isConstantTableLiteral determines if an expression consists mainly of a table literal with constant keys and values, which we can fold into a
// constant table. We don't yet support folding nested tables, so we require keys and values to be non table constants. If we see a local initialized
// with a constant table literal, we start tracking it as a potentially foldable ConstantTable.
// observeMutations is used to check for whether a local we have mapped to a ConstantTable is ever potentially mutated in order to ensure that any
// folding we perform later on is sound.
struct TableMutationTracker_DEPRECATED : AstVisitor
{
    DenseHashMap<AstLocal*, TableConstantKind>& constantTables;
    const DenseHashMap<AstLocal*, Variable>& variables;

    TableMutationTracker_DEPRECATED(DenseHashMap<AstLocal*, TableConstantKind>& constantTables, const DenseHashMap<AstLocal*, Variable>& variables)
        : constantTables(constantTables)
        , variables(variables)
    {
        LUAU_ASSERT(FFlag::LuauCompilePropagateTableProps2);
    }

    bool isNonTableConstant(const AstExpr* node)
    {
        if (const AstExprGroup* expr = node->as<AstExprGroup>())
            return isNonTableConstant(expr->expr);
        else if (node->is<AstExprConstantNil>())
            return true;
        else if (node->is<AstExprConstantBool>())
            return true;
        else if (node->is<AstExprConstantNumber>())
            return true;
        else if (node->is<AstExprConstantInteger>())
            return true;
        else if (node->is<AstExprConstantString>())
            return true;
        else if (const AstExprLocal* expr = node->as<AstExprLocal>())
            if (const TableConstantKind* kind = constantTables.find(expr->local))
                return *kind == ConstantOther; // We don't support folding nested tables yet
            else
                return false;
        else if (node->is<AstExprGlobal>())
            return false;
        else if (node->is<AstExprVarargs>())
            return false;
        else if (const AstExprCall* expr = node->as<AstExprCall>())
            return false;
        else if (const AstExprIndexName* expr = node->as<AstExprIndexName>())
        {
            const AstExprLocal* local = expr->expr->as<AstExprLocal>();
            if (!local)
                return false;

            // We don't currently constant fold nested tables, so property access on a constant table never returns a table
            if (const TableConstantKind* kind = constantTables.find(local->local))
                return *kind == ConstantTable;
            else
                return false;
        }
        else if (const AstExprIndexExpr* expr = node->as<AstExprIndexExpr>())
        {
            const AstExprLocal* local = expr->expr->as<AstExprLocal>();
            if (!local)
                return false;

            // We don't currently constant fold nested tables, so property access on a constant table never returns a table
            if (const TableConstantKind* kind = constantTables.find(local->local))
                return *kind == ConstantTable && isNonTableConstant(expr->index);
            else
                return false;
        }
        else if (const AstExprFunction* expr = node->as<AstExprFunction>())
            return false;
        else if (const AstExprTable* expr = node->as<AstExprTable>())
        {
            // we only fold table literals directly assigned to locals, which we hit in isTableLiteral
            // if we see a table literal here, we're not folding it, so we treat it as not constant
            return false;
        }
        else if (const AstExprUnary* expr = node->as<AstExprUnary>())
            return isNonTableConstant(expr->expr);
        else if (const AstExprBinary* expr = node->as<AstExprBinary>())
        {
            return isNonTableConstant(expr->left) && isNonTableConstant(expr->right);
        }
        else if (const AstExprTypeAssertion* expr = node->as<AstExprTypeAssertion>())
            return isNonTableConstant(expr->expr);
        else if (const AstExprIfElse* expr = node->as<AstExprIfElse>())
        {
            return isNonTableConstant(expr->condition) && isNonTableConstant(expr->trueExpr) && isNonTableConstant(expr->falseExpr);
        }
        else if (const AstExprInterpString* expr = node->as<AstExprInterpString>())
        {
            for (AstExpr* expression : expr->expressions)
            {
                if (!isNonTableConstant(expression))
                    return false;
            }
            return true;
        }
        else if (const AstExprInstantiate* expr = node->as<AstExprInstantiate>())
            return isNonTableConstant(expr->expr);
        else
            LUAU_ASSERT(!"Unknown expression type");

        return false;
    }

    bool isConstantTableLiteral(const AstExpr* node)
    {
        if (const AstExprTable* table = node->as<AstExprTable>())
        {
            for (const AstExprTable::Item& item : table->items)
            {
                if (item.key && !isNonTableConstant(item.key))
                    return false;
                if (!isNonTableConstant(item.value))
                    return false;
            }
            return true;
        }
        else if (const AstExprGroup* group = node->as<AstExprGroup>())
            return isConstantTableLiteral(group->expr);
        else if (const AstExprTypeAssertion* assert = node->as<AstExprTypeAssertion>())
            return isConstantTableLiteral(assert->expr);
        else if (const AstExprInstantiate* instantiate = node->as<AstExprInstantiate>())
            return isConstantTableLiteral(instantiate->expr);
        else
            return false;
    }

    // Could node evaluate to a reference to a constant table?
    bool couldBeTableReference(const AstExpr* node)
    {
        if (const AstExprGroup* expr = node->as<AstExprGroup>())
            return couldBeTableReference(expr->expr);
        else if (const AstExprTypeAssertion* expr = node->as<AstExprTypeAssertion>())
            return couldBeTableReference(expr->expr);
        else if (const AstExprInstantiate* expr = node->as<AstExprInstantiate>())
            return couldBeTableReference(expr->expr);
        else if (const AstExprIfElse* expr = node->as<AstExprIfElse>())
            return couldBeTableReference(expr->trueExpr) || couldBeTableReference(expr->falseExpr);
        else if (const AstExprBinary* binExpr = node->as<AstExprBinary>();
                 binExpr && (binExpr->op == AstExprBinary::And || binExpr->op == AstExprBinary::Or))
            return couldBeTableReference(binExpr->left) || couldBeTableReference(binExpr->right);
        else if (node->is<AstExprLocal>())
            return true;
        else
        { // We ignore AstExprIndexName and AstExprIndexExpr here since tables referencing other tables should be caught in the AstExprTable case
            // of observeMutations or the AstStatAssign visitor
            return false;
        }
    }

    // Updates constantTables if mutations are observed
    void observeMutations(const AstExpr* node, bool couldMutateTable)
    {
        if (const AstExprGroup* expr = node->as<AstExprGroup>())
            observeMutations(expr->expr, couldMutateTable);
        else if (node->is<AstExprConstantNil>())
            return;
        else if (node->is<AstExprConstantBool>())
            return;
        else if (node->is<AstExprConstantNumber>())
            return;
        else if (node->is<AstExprConstantInteger>())
            return;
        else if (node->is<AstExprConstantString>())
            return;
        else if (const AstExprLocal* expr = node->as<AstExprLocal>())
        {
            AstLocal* local = expr->local;
            if (couldMutateTable && constantTables.contains(local))
                constantTables[local] = NotConstant;
        }
        else if (node->is<AstExprGlobal>())
            return;
        else if (node->is<AstExprVarargs>())
            return;
        else if (const AstExprCall* expr = node->as<AstExprCall>())
        {
            observeMutations(expr->func, /* couldMutateTable */ true); // t:method() could mutate t

            for (size_t i = 0; i < expr->args.size; ++i)
            {
                AstExpr* arg = expr->args.data[i];
                // func(t) could mutate t, but func(t.prop) can't
                observeMutations(arg, /* couldMutateTable */ couldBeTableReference(arg));
            }
        }
        else if (const AstExprIndexName* expr = node->as<AstExprIndexName>())
            observeMutations(expr->expr, couldMutateTable);
        else if (const AstExprIndexExpr* expr = node->as<AstExprIndexExpr>())
        {
            observeMutations(expr->index, /* couldMutateTable */ false);
            observeMutations(expr->expr, couldMutateTable);
        }
        else if (const AstExprFunction* expr = node->as<AstExprFunction>())
        {
            // this is necessary to observe mutations in the function's body
            expr->body->visit(this);
        }
        else if (const AstExprTable* expr = node->as<AstExprTable>())
        {
            for (const AstExprTable::Item& item : expr->items)
            {
                if (item.key)
                    observeMutations(item.key, /* couldMutateTable */ false);
                observeMutations(item.value, /* couldMutateTable */ couldBeTableReference(item.value));
            }
        }
        else if (const AstExprUnary* expr = node->as<AstExprUnary>())
        {
            // We don't worry about metamethods because we observe mutations from setmetatable calls elsewhere
            observeMutations(expr->expr, /* couldMutateTable */ false);
        }
        else if (const AstExprBinary* expr = node->as<AstExprBinary>())
        {
            // We don't worry about metamethods because we observe mutations from setmetatable calls elsewhere
            bool shortCircuiting = expr->op == AstExprBinary::And || expr->op == AstExprBinary::Or;
            observeMutations(expr->left, /* couldMutateTable */ shortCircuiting);
            observeMutations(expr->right, /* couldMutateTable */ shortCircuiting);
        }
        else if (const AstExprTypeAssertion* expr = node->as<AstExprTypeAssertion>())
            observeMutations(expr->expr, couldMutateTable);
        else if (const AstExprIfElse* expr = node->as<AstExprIfElse>())
        {
            observeMutations(expr->condition, /* couldMutateTable */ false);
            observeMutations(expr->trueExpr, couldMutateTable);
            observeMutations(expr->falseExpr, couldMutateTable);
        }
        else if (const AstExprInterpString* expr = node->as<AstExprInterpString>())
        {
            for (AstExpr* expression : expr->expressions)
                observeMutations(expression, /* couldMutateTable */ false);
        }
        else if (const AstExprInstantiate* expr = node->as<AstExprInstantiate>())
            observeMutations(expr->expr, couldMutateTable);
        else
        {
            LUAU_ASSERT(!"Unknown expression type");
        }
    }

    bool visit(AstExpr* node) override
    {
        observeMutations(node, /* couldMutateTable */ false);
        return false;
    }

    bool visit(AstStatLocal* node) override
    {
        // all values that align wrt indexing are simple - we just match them 1-1
        for (size_t i = 0; i < node->vars.size && i < node->values.size; ++i)
        {
            AstLocal* local = node->vars.data[i];
            const AstExpr* rhs = node->values.data[i];

            // note: we rely on trackValues to have been run before us
            // if the local isn't written to, see if we can mark it as a constant
            const Variable* v = variables.find(local);
            LUAU_ASSERT(v);

            if (!v->written)
            {
                if (isConstantTableLiteral(rhs))
                    constantTables[local] = ConstantTable;
                else if (isNonTableConstant(rhs))
                    constantTables[local] = ConstantOther;
            }

            // aliasing a table reference could lead to downstream mutations, so we conservatively treat a referenced table as mutated
            if (!constantTables.contains(local))
                observeMutations(rhs, /* couldMutateTable */ couldBeTableReference(rhs));
        }

        // check remaining values to observe mutations
        if (node->vars.size < node->values.size)
        {
            for (size_t i = node->vars.size; i < node->values.size; ++i)
                observeMutations(node->values.data[i], /* couldMutateTable */ false);
        }

        return false;
    }

    bool visit(AstStatAssign* node) override
    {
        for (size_t i = 0; i < node->vars.size && i < node->values.size; ++i)
        {
            AstExpr* rhs = node->values.data[i];

            // aliasing a table reference could lead to downstream mutations, so we conservatively treat a referenced table as mutated
            observeMutations(rhs, /* couldMutateTable */ couldBeTableReference(rhs));
        }

        // Any remaining values don't inherently mutate tables, but we still observe for things like function calls that could mutate tables
        if (node->values.size > node->vars.size)
        {
            for (size_t i = node->vars.size; i < node->values.size; ++i)
                observeMutations(node->values.data[i], /* couldMutateTable */ false);
        }

        // Tables referred to in lhs expressions could be mutated by the assignment
        for (AstExpr* lhs : node->vars)
            observeMutations(lhs, /* couldMutateTable */ true);

        return false;
    }

    bool visit(AstStatCompoundAssign* node) override
    {
        AstExpr* rhs = node->value;
        observeMutations(rhs, /* couldMutateTable */ couldBeTableReference(rhs));
        // Tables referred to in the lhs could be mutated by the assignment
        observeMutations(node->var, /* couldMutateTable */ true);

        return false;
    }

    bool visit(AstStatFunction* node) override
    {
        // Mutations in the body of the function will get caught by other visitor cases
        observeMutations(node->func, /* couldMutateTable */ false);
        // If this stat adds a table method, the table is no longer constant
        observeMutations(node->name, /* couldMutateTable */ true);

        return false;
    }

    bool visit(AstStatReturn* node) override
    {
        for (AstExpr* expr : node->list)
            observeMutations(expr, /* couldMutateTable */ couldBeTableReference(expr));

        return false;
    }

    bool visit(AstStatForIn* node) override
    {
        // Table iterators could mutate their tables
        for (AstExpr* expr : node->values)
            observeMutations(expr, /* couldMutateTable */ true);

        node->body->visit(this);

        return false;
    }
};

// Pass to detect which tables are mutated or 'escape'
struct TableMutationTracker : AstVisitor
{
    const DenseHashMap<AstLocal*, Variable>& variables;

    DenseHashSet<AstLocal*> escaped{nullptr};

    TableMutationTracker(const DenseHashMap<AstLocal*, Variable>& variables)
        : variables(variables)
    {
    }

    void markEscaped(AstExpr* expr)
    {
        for (;;)
        {
            if (AstExprLocal* local = expr->as<AstExprLocal>())
            {
                escaped.insert(local->local);
                return;
            }
            else if (AstExprGroup* group = expr->as<AstExprGroup>())
            {
                expr = group->expr;
            }
            else if (AstExprTypeAssertion* assertion = expr->as<AstExprTypeAssertion>())
            {
                expr = assertion->expr;
            }
            else if (AstExprInstantiate* inst = expr->as<AstExprInstantiate>())
            {
                expr = inst->expr;
            }
            else if (AstExprIfElse* ifElse = expr->as<AstExprIfElse>())
            {
                markEscaped(ifElse->trueExpr); // recurse through true branch
                expr = ifElse->falseExpr;      // continue loop with false branch
            }
            else if (AstExprBinary* bin = expr->as<AstExprBinary>())
            {
                if (bin->op == AstExprBinary::And || bin->op == AstExprBinary::Or)
                {
                    markEscaped(bin->left); // recurse through lhs
                    expr = bin->right;      // continue loop with rhs
                }
                else
                {
                    return;
                }
            }
            else
            {
                return;
            }
        }
    }

    void markEscapedTableIndex(AstExpr* expr, bool isLvalue)
    {
        if (AstExprIndexName* idx = expr->as<AstExprIndexName>())
        {
            markEscaped(idx->expr);
        }
        else if (AstExprIndexExpr* idx = expr->as<AstExprIndexExpr>())
        {
            markEscaped(idx->expr);

            if (isLvalue)
                markEscaped(idx->index);
        }
    }

    bool visit(AstExprCall* node) override
    {
        // Values passed in as arguments can escape
        for (AstExpr* arg : node->args)
            markEscaped(arg);

        // Table indexed in a self call escapes through 'self'
        if (node->self)
            markEscapedTableIndex(node->func, false);

        return true;
    }

    bool visit(AstExprTable* node) override
    {
        // Values stored inside a table constructor can escape
        for (const AstExprTable::Item& item : node->items)
        {
            if (item.key)
                markEscaped(item.key);

            markEscaped(item.value);
        }

        return true;
    }

    bool visit(AstStatLocal* node) override
    {
        // Aliasing a table reference marks the source as escaped
        for (size_t i = 0; i < node->values.size && i < node->vars.size; ++i)
            markEscaped(node->values.data[i]);

        return true;
    }

    bool visit(AstStatAssign* node) override
    {
        // RHS values that are table locals are being aliased
        for (AstExpr* rhs : node->values)
            markEscaped(rhs);

        // LHS index expressions mutate the table being indexed
        for (AstExpr* lhs : node->vars)
            markEscapedTableIndex(lhs, true);

        return true;
    }

    bool visit(AstStatCompoundAssign* node) override
    {
        // LHS index expressions mutate the table
        markEscapedTableIndex(node->var, true);
        return true;
    }

    bool visit(AstStatFunction* node) override
    {
        // Adding a method on a table mutates it
        markEscapedTableIndex(node->name, true);
        return true;
    }

    bool visit(AstStatForIn* node) override
    {
        // Iterator state values escape
        for (AstExpr* expr : node->values)
            markEscaped(expr);

        return true;
    }

    bool visit(AstStatReturn* node) override
    {
        // Returning a table is sometimes safe, but when it's combined with upvalues and local functions, it's very brittle
        for (AstExpr* expr : node->list)
            markEscaped(expr);

        return true;
    }
};

struct ConstantVisitor : AstVisitor
{
    DenseHashMap<AstExpr*, Constant>& constants;
    DenseHashMap<AstLocal*, Variable>& variables;
    DenseHashMap<AstLocal*, Constant>& locals;

    const DenseHashMap<AstExprCall*, int>* builtins;
    bool foldLibraryK = false;
    LibraryMemberConstantCallback libraryMemberConstantCb;
    AstNameTable& stringTable;
    std::vector<DenseHashMap<AstName, Constant>> constantTables;

    bool wasEmpty = false;

    std::vector<Constant> builtinArgs;

    const DenseHashMap<AstLocal*, TableConstantKind>& constantTableLocals;
    DenseHashMap<AstLocal*, Constant> tableLocals{nullptr};

    ExprConstantChangeLog* exprChangeLog = nullptr;
    LocalConstantChangeLog* localChangeLog = nullptr;

    ConstantVisitor(
        DenseHashMap<AstExpr*, Constant>& constants,
        DenseHashMap<AstLocal*, Variable>& variables,
        DenseHashMap<AstLocal*, Constant>& locals,
        const DenseHashMap<AstExprCall*, int>* builtins,
        bool foldLibraryK,
        LibraryMemberConstantCallback libraryMemberConstantCb,
        AstNameTable& stringTable,
        const DenseHashMap<AstLocal*, TableConstantKind>& constantTableLocals,
        ExprConstantChangeLog* exprChangeLog = nullptr,
        LocalConstantChangeLog* localChangeLog = nullptr
    )
        : constants(constants)
        , variables(variables)
        , locals(locals)
        , builtins(builtins)
        , foldLibraryK(foldLibraryK)
        , libraryMemberConstantCb(libraryMemberConstantCb)
        , stringTable(stringTable)
        , constantTableLocals(constantTableLocals)
        , exprChangeLog(exprChangeLog)
        , localChangeLog(localChangeLog)
    {
        // since we do a single pass over the tree, if the initial state was empty we don't need to clear out old entries
        wasEmpty = constants.empty() && locals.empty();
    }

    Constant analyze(AstExpr* node)
    {
        Constant result;
        result.type = Constant::Type_Unknown;

        if (AstExprGroup* expr = node->as<AstExprGroup>())
        {
            result = analyze(expr->expr);
        }
        else if (node->is<AstExprConstantNil>())
        {
            result.type = Constant::Type_Nil;
        }
        else if (AstExprConstantBool* expr = node->as<AstExprConstantBool>())
        {
            result.type = Constant::Type_Boolean;
            result.valueBoolean = expr->value;
        }
        else if (AstExprConstantNumber* expr = node->as<AstExprConstantNumber>())
        {
            result.type = Constant::Type_Number;
            result.valueNumber = expr->value;
        }
        else if (AstExprConstantInteger* expr = node->as<AstExprConstantInteger>())
        {
            result.type = Constant::Type_Integer;
            result.valueInteger64 = expr->value;
        }
        else if (AstExprConstantString* expr = node->as<AstExprConstantString>())
        {
            result.type = Constant::Type_String;
            result.valueString = expr->value.data;
            result.stringLength = unsigned(expr->value.size);
        }
        else if (AstExprLocal* expr = node->as<AstExprLocal>())
        {
            if (const Constant* l = locals.find(expr->local))
                result = *l;
            else if (FFlag::LuauCompileFoldOptimize)
            {
                if (const Constant* l = tableLocals.find(expr->local))
                    result = *l;
            }
        }
        else if (node->is<AstExprGlobal>())
        {
            // nope
        }
        else if (node->is<AstExprVarargs>())
        {
            // nope
        }
        else if (AstExprCall* expr = node->as<AstExprCall>())
        {
            analyze(expr->func);

            const int* bfid = builtins ? builtins->find(expr) : nullptr;

            if (bfid && *bfid != LBF_NONE)
            {
                // since recursive calls to analyze() may reuse the vector we need to be careful and preserve existing contents
                size_t offset = builtinArgs.size();
                bool canFold = true;

                builtinArgs.reserve(offset + expr->args.size);

                for (size_t i = 0; i < expr->args.size; ++i)
                {
                    Constant ac = analyze(expr->args.data[i]);

                    if (FFlag::LuauCompilePropagateTableProps2 ? ac.type == Constant::Type_Unknown || ac.type == Constant::Type_Table
                                                               : ac.type == Constant::Type_Unknown)
                        canFold = false;
                    else
                        builtinArgs.push_back(ac);
                }

                if (canFold)
                {
                    LUAU_ASSERT(builtinArgs.size() == offset + expr->args.size);
                    result = foldBuiltin(stringTable, *bfid, builtinArgs.data() + offset, expr->args.size);
                }

                builtinArgs.resize(offset);
            }
            else
            {
                for (size_t i = 0; i < expr->args.size; ++i)
                    analyze(expr->args.data[i]);
            }
        }
        else if (AstExprIndexName* expr = node->as<AstExprIndexName>())
        {
            Constant value = analyze(expr->expr);
            if (FFlag::LuauCompilePropagateTableProps2 && value.type == Constant::Type_Table)
            {
                LUAU_ASSERT(value.valueTable < constantTables.size());
                if (value.valueTable < constantTables.size())
                {
                    const DenseHashMap<AstName, Constant>& props = constantTables[value.valueTable];
                    if (const Constant* prop = props.find(expr->index))
                        result = *prop;
                }
            }
            else if (value.type == Constant::Type_Vector)
            {
                if (expr->index == "x" || expr->index == "X")
                {
                    result.type = Constant::Type_Number;
                    result.valueNumber = value.valueVector[0];
                }
                else if (expr->index == "y" || expr->index == "Y")
                {
                    result.type = Constant::Type_Number;
                    result.valueNumber = value.valueVector[1];
                }
                else if (expr->index == "z" || expr->index == "Z")
                {
                    result.type = Constant::Type_Number;
                    result.valueNumber = value.valueVector[2];
                }

                // Do not handle 'w' component because it isn't known if the runtime will be configured in 3-wide or 4-wide mode
                // In 3-wide, access to 'w' will call unspecified metamethod or fail
            }
            else if (foldLibraryK)
            {
                if (AstExprGlobal* eg = expr->expr->as<AstExprGlobal>())
                {
                    if (eg->name == "math")
                        result = foldBuiltinMath(expr->index);

                    // if we have a custom handler and the constant hasn't been resolved
                    if (libraryMemberConstantCb && result.type == Constant::Type_Unknown)
                        libraryMemberConstantCb(eg->name.value, expr->index.value, reinterpret_cast<Luau::CompileConstant*>(&result));
                }
            }
        }
        else if (AstExprIndexExpr* expr = node->as<AstExprIndexExpr>())
        {
            Constant indexVal = analyze(expr->index);
            Constant tableVal = analyze(expr->expr);

            if (FFlag::LuauCompilePropagateTableProps2 && tableVal.type == Constant::Type_Table && indexVal.type == Constant::Type_String)
            {
                LUAU_ASSERT(tableVal.valueTable < constantTables.size());
                if (tableVal.valueTable < constantTables.size() && indexVal.stringLength != 0)
                {
                    const DenseHashMap<AstName, Constant>& props = constantTables[tableVal.valueTable];
                    AstName indexName = stringTable.getOrAdd(indexVal.valueString, indexVal.stringLength);
                    if (const Constant* prop = props.find(std::move(indexName)))
                        result = *prop;
                }
            }
        }
        else if (AstExprFunction* expr = node->as<AstExprFunction>())
        {
            // this is necessary to propagate constant information in all child functions
            expr->body->visit(this);
        }
        else if (AstExprTable* expr = node->as<AstExprTable>())
        {
            if (FFlag::LuauCompilePropagateTableProps2)
            {
                // If expr is a constant table, update result to be a table constant, and insert it into constantTables
                DenseHashMap<AstName, Constant> props{AstName()};
                for (size_t i = 0; i < expr->items.size; ++i)
                {
                    const AstExprTable::Item& item = expr->items.data[i];

                    Constant valueVal = analyze(item.value);

                    if (item.key)
                    {
                        Constant keyVal = analyze(item.key);

                        if (keyVal.type == Constant::Type_String && valueVal.type != Constant::Type_Unknown &&
                            valueVal.type != Constant::Type_Table && keyVal.stringLength != 0)
                        {
                            AstName constKey = stringTable.getOrAdd(keyVal.valueString, keyVal.stringLength);

                            props[std::move(constKey)] = std::move(valueVal);
                        }
                        // TODO: Support other types of keys
                    }
                }

                if (props.size() == expr->items.size)
                {
                    result.type = Constant::Type_Table;
                    result.valueTable = constantTables.size();
                    constantTables.push_back(std::move(props));
                }
            }
            else
            {
                for (size_t i = 0; i < expr->items.size; ++i)
                {
                    const AstExprTable::Item& item = expr->items.data[i];

                    if (item.key)
                        analyze(item.key);

                    analyze(item.value);
                }
            }
        }
        else if (AstExprUnary* expr = node->as<AstExprUnary>())
        {
            Constant arg = analyze(expr->expr);

            if (arg.type != Constant::Type_Unknown)
                foldUnary(result, expr->op, arg);
        }
        else if (AstExprBinary* expr = node->as<AstExprBinary>())
        {
            Constant la = analyze(expr->left);
            Constant ra = analyze(expr->right);

            // note: ra doesn't need to be constant to fold and/or
            if (la.type != Constant::Type_Unknown)
                foldBinary(result, expr->op, la, ra, stringTable);
        }
        else if (AstExprTypeAssertion* expr = node->as<AstExprTypeAssertion>())
        {
            Constant arg = analyze(expr->expr);

            result = arg;
        }
        else if (AstExprIfElse* expr = node->as<AstExprIfElse>())
        {
            Constant cond = analyze(expr->condition);
            Constant trueExpr = analyze(expr->trueExpr);
            Constant falseExpr = analyze(expr->falseExpr);

            if (cond.type != Constant::Type_Unknown)
                result = cond.isTruthful() ? trueExpr : falseExpr;
        }
        else if (AstExprInterpString* expr = node->as<AstExprInterpString>())
        {
            bool onlyConstantSubExpr = true;
            for (AstExpr* expression : expr->expressions)
                if (analyze(expression).type != Constant::Type_String)
                    onlyConstantSubExpr = false;

            if (onlyConstantSubExpr)
                foldInterpString(result, expr, constants, stringTable);
        }
        else if (AstExprInstantiate* expr = node->as<AstExprInstantiate>())
        {
            result = analyze(expr->expr);
        }
        else
        {
            LUAU_ASSERT(!"Unknown expression type");
        }

        recordConstant(constants, node, result);

        return result;
    }

    template<typename T>
    void recordConstant(DenseHashMap<T, Constant>& map, T key, const Constant& value)
    {
        if (FFlag::LuauCompileFoldOptimize && FFlag::LuauCompilePropagateTableProps2)
        {
            if (value.type == Constant::Type_Table)
            {
                // Table constants are recorded in a separate map
            }
            else if (value.type != Constant::Type_Unknown)
            {
                logChange(map, key);
                map[key] = value;
            }
            else if (wasEmpty)
            {
                // No need to clear out entries if we started with empty maps
            }
            else if (Constant* old = map.find(key))
            {
                logChange(map, key, old);
                old->type = Constant::Type_Unknown;
            }
        }
        else
        {
            if (value.type != Constant::Type_Unknown)
                map[key] = value;
            else if (wasEmpty && !FFlag::LuauCompilePropagateTableProps2)
                ;
            else if (Constant* old = map.find(key))
                old->type = Constant::Type_Unknown;
        }
    }

    void logChange(DenseHashMap<AstExpr*, Constant>& map, AstExpr* key, const Constant* existing = nullptr)
    {
        if (!exprChangeLog)
            return;

        const Constant* old = existing ? existing : map.find(key);
        exprChangeLog->push_back({key, old ? *old : Constant{}, old == nullptr});
    }

    void logChange(DenseHashMap<AstLocal*, Constant>& map, AstLocal* key, const Constant* existing = nullptr)
    {
        if (!localChangeLog)
            return;

        const Constant* old = existing ? existing : map.find(key);
        localChangeLog->push_back({key, old ? *old : Constant{}, old == nullptr});
    }

    void recordValue(AstLocal* local, const Constant& value)
    {
        // note: we rely on trackValues to have been run before us
        Variable* v = variables.find(local);
        LUAU_ASSERT(v);

        if (!v->written)
        {
            if (FFlag::LuauCompileFoldOptimize && FFlag::LuauCompilePropagateTableProps2)
            {
                if (value.type == Constant::Type_Table)
                {
                    v->constant = false;
                    tableLocals[local] = value;
                }
                else
                {
                    v->constant = (value.type != Constant::Type_Unknown);
                    recordConstant(locals, local, value);
                }
            }
            else
            {
                v->constant = FFlag::LuauCompilePropagateTableProps2 ? value.type != Constant::Type_Unknown && value.type != Constant::Type_Table
                                                                     : value.type != Constant::Type_Unknown;
                recordConstant(locals, local, value);
            }
        }
    }

    bool visit(AstExpr* node) override
    {
        // note: we short-circuit the visitor traversal through any expression trees by returning false
        // recursive traversal is happening inside analyze() which makes it easier to get the resulting value of the subexpression
        analyze(node);

        return false;
    }

    bool visit(AstStatLocal* node) override
    {
        // all values that align wrt indexing are simple - we just match them 1-1
        for (size_t i = 0; i < node->vars.size && i < node->values.size; ++i)
        {
            AstExpr* rhs = node->values.data[i];
            Constant arg = analyze(rhs);

            if (FFlag::LuauCompilePropagateTableProps2 && arg.type == Constant::Type_Table)
            {
                AstLocal* local = node->vars.data[i];

                // If this table could be mutated later, record Constant_Unknown instead of Constant_Table
                const TableConstantKind* kind = constantTableLocals.find(local);
                if (kind && *kind == ConstantTable)
                    recordValue(local, arg);
                else
                    recordValue(local, {});
            }
            else
                recordValue(node->vars.data[i], arg);
        }

        if (node->vars.size > node->values.size)
        {
            // if we have trailing variables, then depending on whether the last value is capable of returning multiple values
            // (aka call or varargs), we either don't know anything about these vars, or we know they're nil
            AstExpr* last = node->values.size ? node->values.data[node->values.size - 1] : nullptr;
            bool multRet = last && (last->is<AstExprCall>() || last->is<AstExprVarargs>());

            if (!multRet)
            {
                for (size_t i = node->values.size; i < node->vars.size; ++i)
                {
                    Constant nil = {Constant::Type_Nil};
                    recordValue(node->vars.data[i], nil);
                }
            }
        }
        else
        {
            // we can have more values than variables; in this case we still need to analyze them to make sure we do constant propagation inside
            // them
            for (size_t i = node->vars.size; i < node->values.size; ++i)
                analyze(node->values.data[i]);
        }

        return false;
    }
};

void buildTableConstantMap(DenseHashMap<AstLocal*, TableConstantKind>& result, const DenseHashMap<AstLocal*, Variable>& variables, AstNode* root)
{
    LUAU_ASSERT(FFlag::LuauCompileFoldOptimize && FFlag::LuauCompilePropagateTableProps2);

    if (FFlag::LuauCompileNewTableMutationTracker)
    {
        TableMutationTracker tracker{variables};
        root->visit(&tracker);

        for (auto& [local, var] : variables)
        {
            if (var.written)
                continue;

            if (!var.init || !unwrapExprOfType<AstExprTable>(var.init))
                continue;

            if (!tracker.escaped.contains(local))
                result[local] = ConstantTable;
        }
    }
    else
    {
        TableMutationTracker_DEPRECATED mutationTracker{result, variables};
        root->visit(&mutationTracker);
    }
}

void undoChanges(DenseHashMap<AstExpr*, Constant>& constants, const ExprConstantChangeLog& changes)
{
    for (auto it = changes.rbegin(); it != changes.rend(); ++it)
    {
        if (it->wasAbsent)
        {
            if (Constant* old = constants.find(it->key))
                old->type = Constant::Type_Unknown;
        }
        else
        {
            constants[it->key] = it->oldValue;
        }
    }
}

void undoChanges(DenseHashMap<AstLocal*, Constant>& locals, const LocalConstantChangeLog& changes)
{
    for (auto it = changes.rbegin(); it != changes.rend(); ++it)
    {
        if (it->wasAbsent)
        {
            if (Constant* old = locals.find(it->key))
                old->type = Constant::Type_Unknown;
        }
        else
        {
            locals[it->key] = it->oldValue;
        }
    }
}

void foldConstants(
    DenseHashMap<AstExpr*, Constant>& constants,
    DenseHashMap<AstLocal*, Variable>& variables,
    DenseHashMap<AstLocal*, Constant>& locals,
    const DenseHashMap<AstExprCall*, int>* builtins,
    bool foldLibraryK,
    LibraryMemberConstantCallback libraryMemberConstantCb,
    AstNode* root,
    AstNameTable& stringTable,
    const DenseHashMap<AstLocal*, TableConstantKind>& tableConstants,
    ExprConstantChangeLog* exprChangeLog,
    LocalConstantChangeLog* localChangeLog
)
{
    DenseHashMap<AstLocal*, TableConstantKind> constantTables_DEPRECATED{nullptr};

    if (FFlag::LuauCompilePropagateTableProps2 && !FFlag::LuauCompileFoldOptimize)
    {
        TableMutationTracker_DEPRECATED mutationTracker{constantTables_DEPRECATED, variables};
        root->visit(&mutationTracker);
    }

    ConstantVisitor visitor{
        constants,
        variables,
        locals,
        builtins,
        foldLibraryK,
        libraryMemberConstantCb,
        stringTable,
        FFlag::LuauCompileFoldOptimize ? tableConstants : constantTables_DEPRECATED,
        exprChangeLog,
        localChangeLog
    };
    root->visit(&visitor);

    if (FFlag::LuauCompilePropagateTableProps2 && !FFlag::LuauCompileFoldOptimize)
    {
        // Set any table constants to have constant type unknown, since we don't support emitting them as constants
        for (auto& [_, constant] : constants)
        {
            if (constant.type == Constant::Type_Table)
                constant.type = Constant::Type_Unknown;
        }

        for (auto& [_, constant] : locals)
        {
            if (constant.type == Constant::Type_Table)
                constant.type = Constant::Type_Unknown;
        }
    }
}

} // namespace Compile
} // namespace Luau
