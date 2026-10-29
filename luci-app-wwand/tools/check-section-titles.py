#!/usr/bin/env python3
"""A panel's title belongs INSIDE its .cbi-section, not beside it.

LuCI builds it that way itself: form.js appends the section title to the
`.cbi-section` element (modules/luci-base/.../form.js:2482-2490 for
TypedSection, :2792-2816 for TableSection, :4251+ for the grid), so a theme
that draws a section as a panel draws its heading inside the panel. A hand-built
panel that puts the <h3> beside the section gets a heading floating above the
box, unstyled.

That is not hypothetical: every panel on the status page had it right and every
one on the modem-tools tab had it wrong since 2026-07-23, and it took a user
comparing the two tabs to notice (ddimension/luci-app-wwand#14, 2026-09-24).
Nothing in the tree could have caught it, which is why this exists.

EVERY <h3> outside a .cbi-section fails. The first version of this tool tried to
be clever — it absolved an <h3> that had a section starting somewhere after it,
on the theory that such a one is a GROUP heading rather than a section title. The
counterproof killed that idea: putting the bug back turned the finding into an
absolution and the check stayed green, so the tool would not have caught the
thing it was written for. A heuristic that exonerates the defect is worse than no
tool. One rule, and the exceptions are named below where a reviewer can see them.

Usage: tools/check-section-titles.py
"""

# Named exceptions: a heading that genuinely titles a RUN of sibling sections and
# sub-headings rather than one panel, where conforming means restructuring the
# panel and not moving a line. Keyed by file and title text, so it survives the
# line moving; adding to this list is a decision, not a line-number refresh.
KNOWN = {
    # keyed by a marker from the heading call ITSELF, not by an absent title:
    # (file, None) would have exempted any dynamic-title heading in the file
    # (Codex review)
    ('htdocs/luci-static/resources/view/wwand/settings.js', "title + ' ('"):
        'plmnTable() returns a sub-block that is only ever appended INSIDE '
        "renderPlmnManager's .cbi-section; the nesting is a call, not a "
        'literal, so a static scan cannot see it',
}
import re, sys, pathlib

SECTION = re.compile(r"E\(\s*'div'\s*,\s*\{[^{}]*'class'\s*:\s*'cbi-section")
# <h3> AND <h4>: the first version checked only h3, and the SIM/eSIM panel's
# h4 sub-headings ("SIM PIN", "SIM overrides") sat outside their boxes on a
# release that passed it (ddimension/luci-app-wwand#14, reported on 1.6.8_p1).
H3 = re.compile(r"E\(\s*'h[34]'")

# A `/` starts a regex literal only where an OPERAND is expected. Without this
# a regex containing an apostrophe — `/'/` — opens a phantom string, blanks the
# code after it, and the tool stops seeing real headings. Codex review found
# that hole, 2026-09-24; the guard below then makes any remaining mis-lex fail
# loudly instead of passing quietly, which is the direction that matters for a
# tool whose whole job is not to miss things.
_BEFORE_REGEX = set('(,=:[!&|?{};+-*~^%<>') | {'\n'}

def strip_noise(s):
    """Blank strings, comments and regex literals so paren matching is not fooled
    by them, keeping offsets identical. Returns (clean, spans) where spans are
    (start, end, kind) so a caller can tell WHY a given offset was blanked."""
    out = list(s)
    spans = []
    i, n = 0, len(s)
    prev = ''          # last significant character before i
    while i < n:
        c = s[i]
        if c in "'\"`":
            q, j = c, i + 1
            while j < n:
                if s[j] == '\\':
                    j += 2
                    continue
                if s[j] == q:
                    break
                j += 1
            for k in range(i, min(j + 1, n)):
                out[k] = ' '
            spans.append((i, min(j + 1, n), 'string'))
            i = j + 1
            prev = 'x'
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '/':
            j = s.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            spans.append((i, j, 'comment'))
            i = j
            continue
        if c == '/' and i + 1 < n and s[i + 1] == '*':
            j = s.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                out[k] = ' '
            spans.append((i, j, 'comment'))
            i = j
            continue
        if c == '/' and prev in _BEFORE_REGEX:
            j, cls = i + 1, False
            while j < n and s[j] != '\n':
                if s[j] == '\\':
                    j += 2
                    continue
                if s[j] == '[':
                    cls = True
                elif s[j] == ']':
                    cls = False
                elif s[j] == '/' and not cls:
                    break
                j += 1
            if j < n and s[j] == '/':
                for k in range(i, j + 1):
                    out[k] = ' '
                spans.append((i, j + 1, 'regex'))
                i = j + 1
                prev = 'x'
                continue
        if not c.isspace():
            prev = c
        i += 1
    return ''.join(out), spans

def extent(clean, start):
    """offset range of the E( ... ) call beginning at `start`."""
    i = clean.find('(', start)
    if i < 0:
        return None
    depth = 0
    while i < len(clean):
        if clean[i] == '(':
            depth += 1
        elif clean[i] == ')':
            depth -= 1
            if depth == 0:
                return (start, i)
        i += 1
    return None

def line_of(s, off):
    return s.count('\n', 0, off) + 1

root = pathlib.Path(__file__).resolve().parent.parent
files = sorted((root / 'htdocs/luci-static/resources').rglob('*.js'))
bad, structural, unparsed, ok = [], [], [], 0
claimed = set()

for f in files:
    raw = f.read_text()
    clean, spans_noise = strip_noise(raw)
    # the PATTERNS are matched on the raw text (they contain string literals
    # that strip_noise blanks out), the paren matching on the cleaned one. A
    # match whose own `E` was blanked lived inside a string or a comment and is
    # not code — clean[off] tells us that, since strip_noise preserves offsets.
    spans = [e for e in (extent(clean, m.start()) for m in SECTION.finditer(raw)
                         if clean[m.start()] == 'E') if e]
    for m in H3.finditer(raw):
        off = m.start()
        if clean[off] != 'E':
            # A COMMENTED-OUT CALL IS NOT CODE and is skipped. Anything else that
            # swallowed it means the lexer above got the file wrong, and a tool
            # that cannot read the file must say so rather than report success.
            kind = next((k for a, b, k in spans_noise if a <= off < b), '?')
            if kind != 'comment':
                unparsed.append((str(f.relative_to(root)), line_of(raw, off), kind))
            continue
        inside = [sp for sp in spans if sp[0] < off < sp[1]]
        rel = str(f.relative_to(root))
        if inside:
            ok += 1
            continue
        t = re.match(r"E\(\s*'h[34]'\s*,[^,]*,\s*\[?\s*_\(\s*'([^']*)'", raw[off:off + 200])
        title = t.group(1) if t else None
        tag = raw[off:off + 12].split("'")[1]
        key = (rel, title)
        call = raw[off:off + 120]
        for (kf, kmark) in KNOWN:
            if kf == rel and kmark and kmark not in (title or '') and kmark in call:
                key = (kf, kmark)
        # EXACTLY ONE. Keyed by file and title alone, a second accidental
        # <h3>SIM</h3> in the same file would inherit the exemption — the
        # false negative an allowlist is always one step away from. Codex
        # review, 2026-09-24.
        if key in KNOWN and key not in claimed:
            claimed.add(key)
            structural.append((rel, line_of(raw, off), title, tag, key))
        else:
            bad.append((rel, line_of(raw, off), title, tag))

for rel, ln, title, tag in bad:
    print('  OUTSIDE a .cbi-section: %s:%d  <%s>%s</%s>' % (rel, ln, tag, title or '?', tag))
    print('           LuCI puts a section title inside the section (form.js:2482-2490).')
for rel, ln, title, tag, key in structural:
    print('  known exception  %s:%d  <%s>%s</%s>' % (rel, ln, tag, title or '?', tag))
    print('           %s' % KNOWN[key])

for rel, ln, kind in unparsed:
    print('  UNPARSED  %s:%d  an E(\'h3\' the lexer lost inside a %s — fix strip_noise()' % (rel, ln, kind))

print('checked %d headings in %d files: %d inside a .cbi-section, %d outside, %d known, %d unparsed'
      % (ok + len(bad) + len(structural) + len(unparsed), len(files), ok, len(bad),
         len(structural), len(unparsed)))

sys.exit(1 if (bad or unparsed) else 0)
