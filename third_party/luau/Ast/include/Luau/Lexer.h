// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Allocator.h"
#include "Luau/Ast.h"
#include "Luau/Location.h"
#include "Luau/DenseHash.h"
#include "Luau/Common.h"

#include <vector>

namespace Luau
{

struct Lexeme
{
    enum Type
    {
        Eof = 0,

        // 1..255 means actual character values
        Char_END = 256,

        Equal,
        LessEqual,
        GreaterEqual,
        NotEqual,
        Dot2,
        Dot3,
        SkinnyArrow,
        DoubleColon,
        FloorDiv,

        InterpStringBegin,
        InterpStringMid,
        InterpStringEnd,
        // An interpolated string with no expressions (like `x`)
        InterpStringSimple,

        AddAssign,
        SubAssign,
        MulAssign,
        DivAssign,
        FloorDivAssign,
        ModAssign,
        PowAssign,
        ConcatAssign,

        RawString,
        QuotedString,
        Number,
        Name,

        Comment,
        BlockComment,

        Attribute,
        AttributeOpen,

        BrokenString,
        BrokenComment,
        BrokenUnicode,
        BrokenInterpDoubleBrace,
        Error,

        Reserved_BEGIN,
        ReservedAnd = Reserved_BEGIN,
        ReservedBreak,
        ReservedDo,
        ReservedElse,
        ReservedElseif,
        ReservedEnd,
        ReservedFalse,
        ReservedFor,
        ReservedFunction,
        ReservedIf,
        ReservedIn,
        ReservedLocal,
        ReservedNil,
        ReservedNot,
        ReservedOr,
        ReservedRepeat,
        ReservedReturn,
        ReservedThen,
        ReservedTrue,
        ReservedUntil,
        ReservedWhile,
        Reserved_END
    };

    enum struct QuoteStyle
    {
        Single,
        Double,
    };

    Type type;
    Location location;

    // Field declared here, before the union, to ensure that Lexeme size is 32 bytes.
private:
    // length is used to extract a slice from the input buffer.
    // This field is only valid for certain lexeme types which don't duplicate portions of input
    // but instead store a pointer to a location in the input buffer and the length of lexeme.
    unsigned int length;

public:
    union
    {
        const char* data;       // String, Number, Comment
        const char* name;       // Name
        unsigned int codepoint; // BrokenUnicode
    };

    Lexeme(const Location& location, Type type);
    Lexeme(const Location& location, char character);
    Lexeme(const Location& location, Type type, const char* data, size_t size);
    Lexeme(const Location& location, Type type, const char* name);

    unsigned int getLength() const;
    unsigned int getBlockDepth() const;
    QuoteStyle getQuoteStyle() const;

    std::string toString() const;
};

static_assert(sizeof(Lexeme) <= 32, "Size of `Lexeme` struct should be up to 32 bytes.");

class AstNameTable
{
public:
    AstNameTable(Allocator& allocator);

    AstName addStatic(const char* name, Lexeme::Type type = Lexeme::Name);

    std::pair<AstName, Lexeme::Type> getOrAddWithType(const char* name, size_t length);
    std::pair<AstName, Lexeme::Type> getWithType(const char* name, size_t length) const;

    AstName getOrAdd(const char* name, size_t len);
    AstName getOrAdd(const char* name);
    AstName get(const char* name) const;

private:
    struct Entry
    {
        AstName value;
        uint32_t length;
        Lexeme::Type type;

        bool operator==(const Entry& other) const;
    };

    struct EntryHash
    {
        size_t operator()(const Entry& e) const;
    };

    DenseHashSet<Entry, EntryHash> data;

    Allocator& allocator;
};

class Lexer
{
public:
    Lexer(const char* buffer, std::size_t bufferSize, AstNameTable& names, Position startPosition = {0, 0});

    void setSkipComments(bool skip);
    void setReadNames(bool read);

    const Location& previousLocation() const
    {
        return prevLocation;
    }

    const Lexeme& next();
    const Lexeme& next(bool skipComments, bool updatePrevLocation);
    void nextline();

    Lexeme lookahead();

    const Lexeme& current() const
    {
        return lexeme;
    }

    static bool isReserved(const std::string& word);

    static bool fixupQuotedString(std::string& data);
    static void fixupMultilineString(std::string& data);

    unsigned int getOffset() const
    {
        return offset;
    }

    enum class BraceType
    {
        InterpolatedString,
        Normal
    };

    std::optional<Lexer::BraceType> peekBraceStackTop();

private:
    char peekch() const;
    char peekch(unsigned int lookahead) const;

    Position position() const;

    // consume() assumes current character is not a newline for performance; when that is not known, consumeAny() should be used instead.
    void consume();
    void consumeAny();

    Lexeme readCommentBody();

    // Given a sequence [===[ or ]===], returns:
    // 1. number of equal signs (or 0 if none present) between the brackets
    // 2. -1 if this is not a long comment/string separator
    // 3. -N if this is a malformed separator
    // Does *not* consume the closing brace.
    int skipLongSeparator();

    Lexeme readLongString(const Position& start, int sep, Lexeme::Type ok, Lexeme::Type broken);
    Lexeme readQuotedString();

    Lexeme readInterpolatedStringBegin();
    Lexeme readInterpolatedStringSection(Position start, Lexeme::Type formatType, Lexeme::Type endType);

    void readBackslashInString();

    std::pair<AstName, Lexeme::Type> readName();

    Lexeme readNumber(const Position& start, unsigned int startOffset);

    Lexeme readUtf8Error();
    Lexeme readNext();

    const char* buffer;
    std::size_t bufferSize;

    unsigned int offset;

    unsigned int line;
    unsigned int lineOffset;

    Lexeme lexeme;

    Location prevLocation;

    AstNameTable& names;

    bool skipComments;
    bool readNames;

    std::vector<BraceType> braceStack;
};

inline bool isSpace(char ch)
{
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\v' || ch == '\f';
}

} // namespace Luau
