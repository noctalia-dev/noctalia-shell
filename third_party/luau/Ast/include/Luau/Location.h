// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

namespace Luau
{

struct Position
{
    unsigned int line, column;

    Position(unsigned int line, unsigned int column)
        : line(line)
        , column(column)
    {
    }

    bool operator==(const Position& rhs) const
    {
        return this->column == rhs.column && this->line == rhs.line;
    }

    bool operator!=(const Position& rhs) const
    {
        return !(*this == rhs);
    }
    bool operator<(const Position& rhs) const
    {
        if (line == rhs.line)
            return column < rhs.column;
        else
            return line < rhs.line;
    }
    bool operator>(const Position& rhs) const
    {
        if (line == rhs.line)
            return column > rhs.column;
        else
            return line > rhs.line;
    }
    bool operator<=(const Position& rhs) const
    {
        return *this == rhs || *this < rhs;
    }
    bool operator>=(const Position& rhs) const
    {
        return *this == rhs || *this > rhs;
    }

    void shift(const Position& start, const Position& oldEnd, const Position& newEnd);
};

struct Location
{
    Position begin, end;

    Location()
        : begin(0, 0)
        , end(0, 0)
    {
    }

    Location(const Position& begin, const Position& end)
        : begin(begin)
        , end(end)
    {
    }

    Location(const Position& begin, unsigned int length)
        : begin(begin)
        , end(begin.line, begin.column + length)
    {
    }

    Location(const Location& begin, const Location& end)
        : begin(begin.begin)
        , end(end.end)
    {
    }

    bool operator==(const Location& rhs) const
    {
        return this->begin == rhs.begin && this->end == rhs.end;
    }
    bool operator!=(const Location& rhs) const
    {
        return !(*this == rhs);
    }

    bool encloses(const Location& l) const;
    bool overlaps(const Location& l) const;
    bool contains(const Position& p) const;
    bool containsClosed(const Position& p) const;
    void extend(const Location& other);
    void shift(const Position& start, const Position& oldEnd, const Position& newEnd);
};

} // namespace Luau
