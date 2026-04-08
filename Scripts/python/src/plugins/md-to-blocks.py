#!/usr/bin/env python3
"""
Markdown to JSON block parser for Noctalia's plugin README viewer.

Parses markdown into a JSON array of typed blocks that QML can render
with individual components, giving full control over styling.

Usage:
    python3 md-to-blocks.py <markdown_file>

Output: JSON array of blocks, one per line for SplitParser compatibility.

Block types:
  - heading: {type, level, text}
  - paragraph: {type, text}
  - code: {type, language, text}
  - list: {type, ordered, items[]}
  - image: {type, src, alt}
  - blockquote: {type, text}
  - table: {type, headers[], rows[][]}
  - hr: {type}

Falls back to [{type:"raw", text:"..."}] if markdown-it-py is not available.
"""

import sys
import json
import re


def strip_html_tags(text):
    """Remove HTML tags, keep content."""
    return re.sub(r'<[^>]+>', '', text)


def inline_to_plain(tokens):
    """Convert inline tokens to styled text with simple markup."""
    if not tokens:
        return ""
    parts = []
    pending_href = ''
    for t in tokens:
        if t.type == 'text':
            parts.append(t.content)
        elif t.type == 'code_inline':
            parts.append('`' + t.content + '`')
        elif t.type == 'softbreak' or t.type == 'hardbreak':
            parts.append('\n')
        elif t.type in ('em_open', 'em_close', 's_open', 's_close'):
            pass  # skip emphasis markers, keep text
        elif t.type in ('strong_open',):
            parts.append('**')
        elif t.type in ('strong_close',):
            parts.append('**')
        elif t.type == 'link_open':
            pending_href = ''
            for attr_name, attr_val in (t.attrs or {}).items():
                if attr_name == 'href':
                    pending_href = attr_val
            parts.append('[')
        elif t.type == 'link_close':
            parts.append('](' + pending_href + ')')
            pending_href = ''
        elif t.type == 'image':
            # handled separately at block level
            pass
        elif t.type == 'html_inline':
            # Strip HTML tags like <br>
            cleaned = re.sub(r'<br\s*/?>', '\n', t.content, flags=re.IGNORECASE)
            cleaned = strip_html_tags(cleaned)
            if cleaned.strip():
                parts.append(cleaned)
        else:
            if t.content:
                parts.append(t.content)
    return ''.join(parts)


def extract_list_items(tokens, start_idx):
    """Extract list items from token stream starting at list_open."""
    items = []
    i = start_idx
    depth = 0
    current_item_parts = []

    while i < len(tokens):
        t = tokens[i]

        if t.type == 'list_item_open':
            depth += 1
            if depth == 1:
                current_item_parts = []
        elif t.type == 'list_item_close':
            if depth == 1:
                items.append('\n'.join(current_item_parts))
                current_item_parts = []
            depth -= 1
        elif t.type == 'inline' and depth == 1:
            text = inline_to_plain(t.children) if t.children else t.content
            current_item_parts.append(text)
        elif t.type == 'paragraph_open' or t.type == 'paragraph_close':
            pass  # skip paragraph wrappers inside list items
        elif t.type in ('bullet_list_close', 'ordered_list_close'):
            break

        i += 1

    return items, i


def parse_markdown(text):
    """Parse markdown text into a list of block dicts."""
    try:
        from markdown_it import MarkdownIt
    except ImportError:
        print("Warning: markdown-it-py not installed, falling back to raw mode", file=sys.stderr)
        return [{"type": "raw", "text": text}]

    md = MarkdownIt("commonmark", {"html": True})
    md.enable("table")
    tokens = md.parse(text)
    blocks = []
    i = 0

    while i < len(tokens):
        t = tokens[i]

        # Headings
        if t.type == 'heading_open':
            level = int(t.tag[1])  # h1 -> 1, h2 -> 2, etc.
            # Next token is inline with heading text
            if i + 1 < len(tokens) and tokens[i + 1].type == 'inline':
                text = inline_to_plain(tokens[i + 1].children) if tokens[i + 1].children else tokens[i + 1].content
                blocks.append({"type": "heading", "level": level, "text": text})
                i += 3  # skip heading_open, inline, heading_close
                continue

        # Paragraphs
        elif t.type == 'paragraph_open':
            if i + 1 < len(tokens) and tokens[i + 1].type == 'inline':
                inline_token = tokens[i + 1]
                # Check if this paragraph contains only an image
                if inline_token.children and len(inline_token.children) == 1 and inline_token.children[0].type == 'image':
                    img = inline_token.children[0]
                    src = ''
                    for attr_name, attr_val in (img.attrs or {}).items():
                        if attr_name == 'src':
                            src = attr_val
                    alt = img.content or ''
                    blocks.append({"type": "image", "src": src, "alt": alt})
                    i += 3
                    continue

                # Check for images mixed with text
                has_image = False
                if inline_token.children:
                    for child in inline_token.children:
                        if child.type == 'image':
                            has_image = True
                            src = ''
                            for attr_name, attr_val in (child.attrs or {}).items():
                                if attr_name == 'src':
                                    src = attr_val
                            blocks.append({"type": "image", "src": src, "alt": child.content or ''})

                text = inline_to_plain(inline_token.children) if inline_token.children else inline_token.content
                text = text.strip()
                if text:
                    blocks.append({"type": "paragraph", "text": text})
                i += 3
                continue

        # Code blocks (fenced)
        elif t.type == 'fence':
            lang = t.info.strip() if t.info else ""
            blocks.append({"type": "code", "language": lang, "text": t.content.rstrip('\n')})
            i += 1
            continue

        # Code blocks (indented)
        elif t.type == 'code_block':
            blocks.append({"type": "code", "language": "", "text": t.content.rstrip('\n')})
            i += 1
            continue

        # Bullet lists
        elif t.type == 'bullet_list_open':
            items, end_i = extract_list_items(tokens, i + 1)
            blocks.append({"type": "list", "ordered": False, "items": items})
            i = end_i + 1
            continue

        # Ordered lists
        elif t.type == 'ordered_list_open':
            items, end_i = extract_list_items(tokens, i + 1)
            blocks.append({"type": "list", "ordered": True, "items": items})
            i = end_i + 1
            continue

        # Blockquotes
        elif t.type == 'blockquote_open':
            # Collect all content until blockquote_close
            parts = []
            i += 1
            while i < len(tokens) and tokens[i].type != 'blockquote_close':
                if tokens[i].type == 'inline':
                    text = inline_to_plain(tokens[i].children) if tokens[i].children else tokens[i].content
                    parts.append(text)
                i += 1
            blocks.append({"type": "blockquote", "text": '\n'.join(parts)})
            i += 1
            continue

        # Tables
        elif t.type == 'table_open':
            headers = []
            rows = []
            i += 1
            in_thead = False
            in_tbody = False
            current_row = []

            while i < len(tokens) and tokens[i].type != 'table_close':
                tt = tokens[i]
                if tt.type == 'thead_open':
                    in_thead = True
                elif tt.type == 'thead_close':
                    in_thead = False
                elif tt.type == 'tbody_open':
                    in_tbody = True
                elif tt.type == 'tbody_close':
                    in_tbody = False
                elif tt.type == 'tr_open':
                    current_row = []
                elif tt.type == 'tr_close':
                    if in_thead:
                        headers = current_row
                    else:
                        rows.append(current_row)
                    current_row = []
                elif tt.type == 'inline':
                    cell_text = inline_to_plain(tt.children) if tt.children else tt.content
                    current_row.append(cell_text)
                i += 1

            blocks.append({"type": "table", "headers": headers, "rows": rows})
            i += 1  # skip table_close
            continue

        # Horizontal rule
        elif t.type == 'hr':
            blocks.append({"type": "hr"})
            i += 1
            continue

        # HTML blocks (render as paragraph, strip tags)
        elif t.type == 'html_block':
            cleaned = re.sub(r'<br\s*/?>', '\n', t.content, flags=re.IGNORECASE)
            cleaned = strip_html_tags(cleaned).strip()
            if cleaned:
                blocks.append({"type": "paragraph", "text": cleaned})
            i += 1
            continue

        i += 1

    return blocks


def main():
    if len(sys.argv) < 2:
        print("Usage: md-to-blocks.py <file>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]

    if filepath == "-":
        raw = sys.stdin.read()
    else:
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                raw = f.read()
        except FileNotFoundError:
            sys.exit(1)

    blocks = parse_markdown(raw)

    # Output as single-line JSON (SplitParser reads line by line)
    print(json.dumps(blocks))


if __name__ == "__main__":
    main()
