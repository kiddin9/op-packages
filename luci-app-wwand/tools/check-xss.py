#!/usr/bin/env python3
"""Refuse to let outside text reach innerHTML.

LuCI's E() takes either E(tag, children) or E(tag, attrs, children). A child
passed as a bare STRING is assigned through innerHTML and its markup is parsed;
a child passed inside an ARRAY becomes a text node and is not. Every string
wwand renders can come from the modem, the SIM, the operator or lpac -- an SMS
body most of all, which anyone who knows the number can write -- so the rule is:

    E('td', {}, [ msg.text ])       and never       E('td', {}, msg.text)

A literal is fine (we wrote it). A translated literal is fine. A translated
literal with .format() is NOT: the substituted value is the outside part.

This is the checkable half of that rule. It is deliberately syntactic and errs
toward reporting: a false positive costs a pair of brackets, a false negative
costs a cross-site scripting hole in an authenticated admin session.

Usage: check-xss.py <dir>...      (exit 1 if anything is flagged)
"""
import re, sys, os

def split_args(s, i):
    """Split the argument list of a call whose '(' is at s[i]. Returns
    (args, end) with args as raw source slices, or (None, None) if unbalanced."""
    depth, args, start, j = 0, [], i + 1, i
    quote = None
    while j < len(s):
        c = s[j]
        if quote:
            if c == '\\':
                j += 2
                continue
            if c == quote:
                quote = None
        elif c in '\'"`':
            quote = c
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append(s[start:j])
                return args, j
        elif c == ',' and depth == 1:
            args.append(s[start:j])
            start = j + 1
        j += 1
    return None, None

# Deciding this in general needs types: E('div', {}, cards) with an array of
# nodes is safe, E('td', {}, msg.text) is not, and they are the same syntax. So
# this checks only what can be PROVEN to be a string -- a .format() result or a
# concatenation with a string literal. Those are always text, always reach
# innerHTML, and are the shape nearly every real finding here had. Bare
# identifiers are left alone deliberately: flagging them drowned the real hits
# ~3:1 in node arrays, and a check nobody can keep green stops being run.
STRINGS = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")

def mask_nested(e):
    """Blank out nested E(...) calls. Their contents are checked as their own
    children; counted here they make every enclosing .map() look like a string."""
    out, i = e, 0
    while True:
        m = re.search(r'\bE\s*\(', out[i:])
        if not m:
            return out
        j = i + m.end() - 1
        args, end = split_args(out, j)
        if end is None:
            return out
        out = out[:j] + '\x01' * (end - j + 1) + out[end + 1:]
        i = end + 1

def safe_child(expr):
    e = expr.strip()
    if not e or e.startswith('[') or e.startswith('{') or e.startswith('E('):
        return True
    # blank out string literals, then look for the two provable-string shapes
    masked = STRINGS.sub(lambda m: '\x00' * len(m.group(0)), mask_nested(e))
    if '.format(' in masked:
        return False
    if '+' in masked and '\x00' in masked:
        return False        # concatenation involving a literal -> a string
    # `a() || b || 'fallback'` is a string in EVERY branch, but it carries no
    # .format() and no +, so both tests above pass it. That shape shipped a real
    # hole: a PLMN row rendered `describe(...) || e.name || '—'` as a bare child,
    # and e.name is the operator name the MODEM supplied (openwrt/luci#8917).
    # A literal anywhere in an || chain settles the type of the whole expression.
    if '||' in masked and '\x00' in masked:
        return False
    return True

def check(path):
    src = open(path, encoding='utf-8').read()
    bad = []
    for m in re.finditer(r'\bE\s*\(', src):
        i = m.end() - 1
        args, end = split_args(src, i)
        if not args or len(args) < 2:
            continue
        # E(tag, attrs, child...) vs E(tag, child)
        children = args[2:] if args[1].strip().startswith('{') else args[1:]
        for c in children:
            if not safe_child(c):
                line = src.count('\n', 0, i) + 1
                bad.append((line, ' '.join(c.split())[:96]))
                break
    return bad

# NO ARGUMENTS USED TO MEAN NO WORK, and it still printed "clean" and exited 0.
# That is the worst possible answer: it was quoted as evidence that a diff was
# safe when nothing had been read at all. Default to the package's own trees, and
# refuse rather than reassure if even those are missing.
roots = sys.argv[1:]

if not roots:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    roots = [ d for d in (os.path.join(here, 'htdocs'), os.path.join(here, 'root'))
              if os.path.isdir(d) ]

if not roots:
    sys.exit('check-xss: nothing to scan — pass a directory')

rc = 0
scanned = 0
for root in roots:
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if not f.endswith('.js'):
                continue
            p = os.path.join(dirpath, f)
            scanned += 1
            for line, expr in check(p):
                print(f'{p}:{line}: bare string child -> innerHTML: {expr}')
                rc = 1
print('check-xss: %s (%d files)' % ('FLAGGED' if rc else 'clean', scanned))
sys.exit(rc)
