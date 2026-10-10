import os, re, json, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PO = os.path.join(HERE, 'zerotier.po')
OUT = os.path.join(HERE, '..', '..', 'htdocs', 'luci-static', 'zerotier', 'tr-zh-cn.js')

def sfh(s):
    def u16(b, o): return ((b[o+1] << 8) + b[o]) & 0xFFFFFFFF
    def s8(b, o):  return b[o] if b[o] < 128 else b[o] - 256
    b = s.encode(); M = 0xFFFFFFFF
    h, ln, off = len(b) & M, len(b) // 4, 0
    while ln:
        ln -= 1
        h = (h + u16(b, off)) & M
        t = ((u16(b, off+2) << 11) ^ h) & M
        h = ((h << 16) ^ t) & M
        h = (h + (h >> 11)) & M
        off += 4
    r = len(b) & 3
    if r == 3:
        h = (h + u16(b, off)) & M; h = (h ^ ((h << 16) & M)) & M
        h = (h ^ ((s8(b, off+2) << 18) & M)) & M; h = (h + (h >> 11)) & M
    elif r == 2:
        h = (h + u16(b, off)) & M; h = (h ^ ((h << 11) & M)) & M; h = (h + (h >> 17)) & M
    elif r == 1:
        h = (h + s8(b, off)) & M; h = (h ^ ((h << 10) & M)) & M; h = (h + (h >> 1)) & M
    for s_, a in ((3, 5), (4, 17), (25, 6)):
        h = (h ^ ((h << s_) & M)) & M; h = (h + (h >> a)) & M
    return format(h, '08x')

def unesc(s): return s.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t')
def trimws(s): return re.sub(r'[ \t\n]+', ' ', s.strip())

pairs = re.findall(r'msgid "((?:[^"\\]|\\.)*)"\nmsgstr "((?:[^"\\]|\\.)*)"', open(PO, encoding='utf-8').read())
msgs = [(unesc(a), unesc(b)) for a, b in pairs if a]
assert len(msgs) == 227, len(msgs)

tr = {}
for mid, t in msgs:
    tr[sfh(trimws(mid))] = t
assert len(tr) >= 220, len(tr)
assert sfh('Remote Controller') in tr
assert tr[sfh('Remote Controller')] == '远程控制器'

body = ('/* Generated from po/zh_Hans/zerotier.po - do not edit by hand.\n'
        ' * Keys are sfh(trimws(msgid)) in hex, exactly what cbi.js _() looks up.\n'
        ' * This firmware ships no window.TR bridge of its own. */\n'
        'window.TR = window.TR || {};\n'
        'Object.assign(window.TR, ' + json.dumps(tr, ensure_ascii=False, separators=(',', ':')) + ');\n')
open(OUT, 'w', encoding='utf-8').write(body)
print('OK', len(tr), '键，字节数', len(body.encode()))
