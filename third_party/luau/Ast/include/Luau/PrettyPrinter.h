// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Location.h"
#include "Luau/ParseOptions.h"
#include "Luau/ParseResult.h"

#include <string>

namespace Luau
{
class AstNode;
class AstStatBlock;

struct PrettyPrintResult
{
    std::string code;
    Location errorLocation;
    std::string parseError; // Nonempty if the transpile failed
};

std::string toString(AstNode* node);
void dump(AstNode* node);

// Never fails on a well-formed AST
std::string prettyPrint(AstStatBlock& ast);
std::string prettyPrintWithTypes(AstStatBlock& block);
std::string prettyPrintWithTypes(AstStatBlock& block, const CstNodeMap& cstNodeMap);

// Only fails when parsing fails
PrettyPrintResult prettyPrint(std::string_view source, ParseOptions options = ParseOptions{}, bool withTypes = false);

} // namespace Luau
