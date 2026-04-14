// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "ValueTracking.h"

#include "Luau/Lexer.h"

namespace Luau
{
namespace Compile
{

struct ValueVisitor : AstVisitor
{
    DenseHashMap<AstName, Global>& globals;
    DenseHashMap<AstLocal*, Variable>& variables;

    ValueVisitor(DenseHashMap<AstName, Global>& globals, DenseHashMap<AstLocal*, Variable>& variables)
        : globals(globals)
        , variables(variables)
    {
    }

    void assign(AstExpr* var)
    {
        if (AstExprLocal* lv = var->as<AstExprLocal>())
        {
            variables[lv->local].written = true;
        }
        else if (AstExprGlobal* gv = var->as<AstExprGlobal>())
        {
            globals[gv->name] = Global::Written;
        }
        else
        {
            // we need to be able to track assignments in all expressions, including crazy ones like t[function() t = nil end] = 5
            var->visit(this);
        }
    }

    bool visit(AstStatLocal* node) override
    {
        for (size_t i = 0; i < node->vars.size && i < node->values.size; ++i)
            variables[node->vars.data[i]].init = node->values.data[i];

        for (size_t i = node->values.size; i < node->vars.size; ++i)
            variables[node->vars.data[i]].init = nullptr;

        return true;
    }

    bool visit(AstStatAssign* node) override
    {
        for (size_t i = 0; i < node->vars.size; ++i)
            assign(node->vars.data[i]);

        for (size_t i = 0; i < node->values.size; ++i)
            node->values.data[i]->visit(this);

        return false;
    }

    bool visit(AstStatCompoundAssign* node) override
    {
        assign(node->var);
        node->value->visit(this);

        return false;
    }

    bool visit(AstStatLocalFunction* node) override
    {
        variables[node->name].init = node->func;

        return true;
    }

    bool visit(AstStatFunction* node) override
    {
        assign(node->name);
        node->func->visit(this);

        return false;
    }

    bool visit(AstExprFunction* node) override
    {
        for (AstLocal* arg : node->args)
            variables[arg].init = nullptr;

        return true;
    }
};

void assignMutable(DenseHashMap<AstName, Global>& globals, const AstNameTable& names, const char* const* mutableGlobals)
{
    if (AstName name = names.get("_G"); name.value)
        globals[name] = Global::Mutable;

    if (mutableGlobals)
        for (const char* const* ptr = mutableGlobals; *ptr; ++ptr)
            if (AstName name = names.get(*ptr); name.value)
                globals[name] = Global::Mutable;
}

void trackValues(DenseHashMap<AstName, Global>& globals, DenseHashMap<AstLocal*, Variable>& variables, AstNode* root)
{
    ValueVisitor visitor{globals, variables};
    root->visit(&visitor);
}

} // namespace Compile
} // namespace Luau
