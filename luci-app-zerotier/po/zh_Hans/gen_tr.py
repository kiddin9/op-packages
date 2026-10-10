import os, re, json, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PO = os.path.join(HERE, 'zerotier.po')
OUT = os.path.join(HERE, '..', '..', 'htdocs', 'luci-static', 'zerotier', 'tr-zh-cn.js')
OUT_LMO = os.path.join(HERE, 'zerotier.lmo')

def sfh_int(s):
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
    return h

def sfh(s):
    return format(sfh_int(s), '08x')   # cbi.js _() 查找键：十六进制字符串

def unesc(s): return s.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t')
def trimws(s): return re.sub(r'[ \t\n]+', ' ', s.strip())

pairs = re.findall(r'msgid "((?:[^"\\]|\\.)*)"\nmsgstr "((?:[^"\\]|\\.)*)"', open(PO, encoding='utf-8').read())
msgs = [(unesc(a), unesc(b)) for a, b in pairs if a]
assert len(msgs) > 200, len(msgs)   # sanity only; count grows as strings are added

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
print('tr.js:', len(tr), '键')

# ---- lmo（OpenWrt po2lmo 格式，与其编译器逐字节一致：值按 4 字节对齐，
#        msgid==msgstr 的条目跳过，索引条目 (hash,1,off,len) 大端升序，
#        尾部 u32 = 索引偏移） ----
blob = bytearray(); entries = []
def _add(h, vid, val):
    vb = val.encode()
    entries.append((h, vid, len(blob), len(vb)))
    blob.extend(vb)
    blob.extend(b'\x00' * ((4 - (len(vb) % 4)) % 4))
_add(0, 0, 'nplurals=1; plural=0;')
for mid, t in msgs:
    if mid == t: continue
    _add(sfh_int(mid), 1, t)
entries.sort(key=lambda e: e[0])  # 按整数 hash 升序
lmo = bytes(blob) + b''.join(struct.pack('>IIII', *e) for e in entries) + struct.pack('>I', len(blob))
open(OUT_LMO, 'wb').write(lmo)
print('lmo :', len(entries), '条目（构建期再经官方 po2lmo 交叉验证）')
