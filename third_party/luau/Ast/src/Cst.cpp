// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "Luau/Ast.h"
#include "Luau/Cst.h"
#include "Luau/Common.h"

namespace Luau
{

int gCstRttiIndex = 0;

CstExprConstantNumber::CstExprConstantNumber(const AstArray<char>& value)
    : CstNode(CstClassIndex())
    , value(value)
{
}

CstExprConstantString::CstExprConstantString(AstArray<char> sourceString, QuoteStyle quoteStyle, unsigned int blockDepth)
    : CstNode(CstClassIndex())
    , sourceString(sourceString)
    , quoteStyle(quoteStyle)
    , blockDepth(blockDepth)
{
    LUAU_ASSERT(blockDepth == 0 || quoteStyle == QuoteStyle::QuotedRaw);
}

CstExprConstantInteger::CstExprConstantInteger(const AstArray<char>& value)
    : CstNode(CstClassIndex())
    , value(value)
{
}

CstExprCall::CstExprCall(std::optional<Position> openParens, std::optional<Position> closeParens, AstArray<Position> commaPositions)
    : CstNode(CstClassIndex())
    , openParens(openParens)
    , closeParens(closeParens)
    , commaPositions(commaPositions)
{
}

CstExprIndexExpr::CstExprIndexExpr(Position openBracketPosition, Position closeBracketPosition)
    : CstNode(CstClassIndex())
    , openBracketPosition(openBracketPosition)
    , closeBracketPosition(closeBracketPosition)
{
}

CstExprFunction::CstExprFunction()
    : CstNode(CstClassIndex())
{
}

CstExprTable::CstExprTable(const AstArray<Item>& items)
    : CstNode(CstClassIndex())
    , items(items)
{
}

CstExprOp::CstExprOp(Position opPosition)
    : CstNode(CstClassIndex())
    , opPosition(opPosition)
{
}

CstExprTypeAssertion::CstExprTypeAssertion(Position opPosition)
    : CstNode(CstClassIndex())
    , opPosition(opPosition)
{
}

CstExprIfElse::CstExprIfElse(Position thenPosition, Position elsePosition, bool isElseIf)
    : CstNode(CstClassIndex())
    , thenPosition(thenPosition)
    , elsePosition(elsePosition)
    , isElseIf(isElseIf)
{
}

CstExprInterpString::CstExprInterpString(AstArray<AstArray<char>> sourceStrings, AstArray<Position> stringPositions)
    : CstNode(CstClassIndex())
    , sourceStrings(sourceStrings)
    , stringPositions(stringPositions)
{
}

CstExprExplicitTypeInstantiation::CstExprExplicitTypeInstantiation(CstTypeInstantiation instantiation)
    : CstNode(CstClassIndex())
    , instantiation(instantiation)
{
}

CstStatDo::CstStatDo(Position statsStartPosition, Position endPosition)
    : CstNode(CstClassIndex())
    , statsStartPosition(statsStartPosition)
    , endPosition(endPosition)
{
}

CstStatRepeat::CstStatRepeat(Position untilPosition)
    : CstNode(CstClassIndex())
    , untilPosition(untilPosition)
{
}

CstStatReturn::CstStatReturn(AstArray<Position> commaPositions)
    : CstNode(CstClassIndex())
    , commaPositions(commaPositions)
{
}

CstStatLocal::CstStatLocal(
    AstArray<Position> varsAnnotationColonPositions,
    AstArray<Position> varsCommaPositions,
    AstArray<Position> valuesCommaPositions
)
    : CstNode(CstClassIndex())
    , varsAnnotationColonPositions(varsAnnotationColonPositions)
    , varsCommaPositions(varsCommaPositions)
    , valuesCommaPositions(valuesCommaPositions)
{
}

CstStatFor::CstStatFor(
    Position annotationColonPosition,
    Position equalsPosition,
    Position endCommaPosition,
    std::optional<Position> stepCommaPosition
)
    : CstNode(CstClassIndex())
    , annotationColonPosition(annotationColonPosition)
    , equalsPosition(equalsPosition)
    , endCommaPosition(endCommaPosition)
    , stepCommaPosition(stepCommaPosition)
{
}

CstStatForIn::CstStatForIn(
    AstArray<Position> varsAnnotationColonPositions,
    AstArray<Position> varsCommaPositions,
    AstArray<Position> valuesCommaPositions
)
    : CstNode(CstClassIndex())
    , varsAnnotationColonPositions(varsAnnotationColonPositions)
    , varsCommaPositions(varsCommaPositions)
    , valuesCommaPositions(valuesCommaPositions)
{
}

CstStatAssign::CstStatAssign(AstArray<Position> varsCommaPositions, Position equalsPosition, AstArray<Position> valuesCommaPositions)
    : CstNode(CstClassIndex())
    , varsCommaPositions(varsCommaPositions)
    , equalsPosition(equalsPosition)
    , valuesCommaPositions(valuesCommaPositions)
{
}

CstStatCompoundAssign::CstStatCompoundAssign(Position opPosition)
    : CstNode(CstClassIndex())
    , opPosition(opPosition)
{
}

CstStatFunction::CstStatFunction(Position functionKeywordPosition)
    : CstNode(CstClassIndex())
    , functionKeywordPosition(functionKeywordPosition)
{
}

CstStatLocalFunction::CstStatLocalFunction(Position localKeywordPosition, Position functionKeywordPosition)
    : CstNode(CstClassIndex())
    , localKeywordPosition(localKeywordPosition)
    , functionKeywordPosition(functionKeywordPosition)
{
}

CstGenericType::CstGenericType(std::optional<Position> defaultEqualsPosition)
    : CstNode(CstClassIndex())
    , defaultEqualsPosition(defaultEqualsPosition)
{
}

CstGenericTypePack::CstGenericTypePack(Position ellipsisPosition, std::optional<Position> defaultEqualsPosition)
    : CstNode(CstClassIndex())
    , ellipsisPosition(ellipsisPosition)
    , defaultEqualsPosition(defaultEqualsPosition)
{
}

CstStatTypeAlias::CstStatTypeAlias(
    Position typeKeywordPosition,
    Position genericsOpenPosition,
    AstArray<Position> genericsCommaPositions,
    Position genericsClosePosition,
    Position equalsPosition
)
    : CstNode(CstClassIndex())
    , typeKeywordPosition(typeKeywordPosition)
    , genericsOpenPosition(genericsOpenPosition)
    , genericsCommaPositions(genericsCommaPositions)
    , genericsClosePosition(genericsClosePosition)
    , equalsPosition(equalsPosition)
{
}

CstStatTypeFunction::CstStatTypeFunction(Position typeKeywordPosition, Position functionKeywordPosition)
    : CstNode(CstClassIndex())
    , typeKeywordPosition(typeKeywordPosition)
    , functionKeywordPosition(functionKeywordPosition)
{
}

CstTypeReference::CstTypeReference(
    std::optional<Position> prefixPointPosition,
    Position openParametersPosition,
    AstArray<Position> parametersCommaPositions,
    Position closeParametersPosition
)
    : CstNode(CstClassIndex())
    , prefixPointPosition(prefixPointPosition)
    , openParametersPosition(openParametersPosition)
    , parametersCommaPositions(parametersCommaPositions)
    , closeParametersPosition(closeParametersPosition)
{
}

CstTypeTable::CstTypeTable(AstArray<Item> items, bool isArray)
    : CstNode(CstClassIndex())
    , items(items)
    , isArray(isArray)
{
}

CstTypeFunction::CstTypeFunction(
    Position openGenericsPosition,
    AstArray<Position> genericsCommaPositions,
    Position closeGenericsPosition,
    Position openArgsPosition,
    AstArray<std::optional<Position>> argumentNameColonPositions,
    AstArray<Position> argumentsCommaPositions,
    Position closeArgsPosition,
    Position returnArrowPosition
)
    : CstNode(CstClassIndex())
    , openGenericsPosition(openGenericsPosition)
    , genericsCommaPositions(genericsCommaPositions)
    , closeGenericsPosition(closeGenericsPosition)
    , openArgsPosition(openArgsPosition)
    , argumentNameColonPositions(argumentNameColonPositions)
    , argumentsCommaPositions(argumentsCommaPositions)
    , closeArgsPosition(closeArgsPosition)
    , returnArrowPosition(returnArrowPosition)
{
}

CstTypeTypeof::CstTypeTypeof(Position openPosition, Position closePosition)
    : CstNode(CstClassIndex())
    , openPosition(openPosition)
    , closePosition(closePosition)
{
}

CstTypeUnion::CstTypeUnion(std::optional<Position> leadingPosition, AstArray<Position> separatorPositions)
    : CstNode(CstClassIndex())
    , leadingPosition(leadingPosition)
    , separatorPositions(separatorPositions)
{
}

CstTypeIntersection::CstTypeIntersection(std::optional<Position> leadingPosition, AstArray<Position> separatorPositions)
    : CstNode(CstClassIndex())
    , leadingPosition(leadingPosition)
    , separatorPositions(separatorPositions)
{
}

CstTypeSingletonString::CstTypeSingletonString(AstArray<char> sourceString, CstExprConstantString::QuoteStyle quoteStyle, unsigned int blockDepth)
    : CstNode(CstClassIndex())
    , sourceString(sourceString)
    , quoteStyle(quoteStyle)
    , blockDepth(blockDepth)
{
    LUAU_ASSERT(quoteStyle != CstExprConstantString::QuotedInterp);
}

CstTypePackExplicit::CstTypePackExplicit()
    : CstNode(CstClassIndex())
    , hasParentheses(false)
    , openParenthesesPosition(Position{0, 0})
    , closeParenthesesPosition(Position{0, 0})
    , commaPositions({})
{
}

CstTypePackExplicit::CstTypePackExplicit(Position openParenthesesPosition, Position closeParenthesesPosition, AstArray<Position> commaPositions)
    : CstNode(CstClassIndex())
    , hasParentheses(true)
    , openParenthesesPosition(openParenthesesPosition)
    , closeParenthesesPosition(closeParenthesesPosition)
    , commaPositions(commaPositions)
{
}

CstTypePackGeneric::CstTypePackGeneric(Position ellipsisPosition)
    : CstNode(CstClassIndex())
    , ellipsisPosition(ellipsisPosition)
{
}

} // namespace Luau
