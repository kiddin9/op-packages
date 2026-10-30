#!/usr/bin/env python3
"""Conservative shell command audit for stock OpenWrt 25.12 router images.

Checks all shipped shell entry points, with a pinned BusyBox applet allowlist
and a narrowly documented set of OpenWrt commands from required packages.
No third-party parser, network, or host PATH is required by CI.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import shlex
import sys

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'tools/openwrt-25.12-commands.txt'
SHELL = re.compile(r'^#!\s*(?:/bin/sh|/bin/ash|/usr/bin/env\s+sh)(?:\s|$)')
FUNCTION = re.compile(r'^\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*\(\s*\)\s*\{')
HEREDOC = re.compile(r'<<-?\s*([\'\"]?)([a-zA-Z_][a-zA-Z_0-9]*)\1')
# Command sites: first word, pipeline/statement/conditional, and substitutions.
SITE = re.compile(
    r'(?:^|[;|`]|\$\(|\(\s*|\bthen\s+|\bdo\s+|\belse\s+|\bif\s+|'
    r'\belif\s+|\bwhile\s+|\buntil\s+|\b!\s+)'
    r'\s*(?:!\s*)?(?P<name>[a-zA-Z_][a-zA-Z_0-9.-]*)\b'
)
# Also inspect arguments to command lookup / exec (these are executable
# names, but not the first word of a compound shell statement).
PROBE = re.compile(r'\b(?:command\s+-[vV]|which|exec|env)\s+(?P<name>[a-zA-Z_][a-zA-Z_0-9.-]*)\b')
POST_KEYWORD = re.compile(r'\b(?:then|do|else|if|elif|while|until)\s+(?:!\s*)?(?P<name>[a-zA-Z_][a-zA-Z_0-9.-]*)\b')
# Dynamic command variables are commonplace in this project. Audit the
# fallback name as well, so `OD_BIN="${OD_BIN:-od}"; "$OD_BIN" ...`
# cannot bypass the command gate.
COMMAND_DEFAULT = re.compile(
    r'\b(?P<var>[a-zA-Z_][a-zA-Z_0-9]*)\s*=\s*["\']?'
    r'\$\{[a-zA-Z_][a-zA-Z_0-9]*:-(?P<name>[a-zA-Z_][a-zA-Z_0-9.+-]*)\}'
)
# Shell syntax, builtins, environment assignments, and case patterns.
# Provided by /etc/rc.common and /etc/diag.sh, which are sourced at runtime.
SOURCED_FUNCTIONS = {
    'procd_add_reload_trigger', 'procd_close_instance', 'procd_open_instance',
    'procd_set_param', 'set_state',
}
# OpenWrt's standard rootfs does not ship curl. Device registration has a
# legacy *conditional* curl fallback; it uses the required uclient-fetch when
# curl is absent. Allow that existing branch only, never a new curl caller.
OPTIONAL_CURL_SOURCE = 'root/usr/libexec/smartsafehub-device'


def legacy_curl_is_guarded(source: str) -> bool:
    """Verify every curl invocation is in the existing guarded branch."""
    match = re.search(r'^post_json\(\)\s*\{(?P<body>.*?)^\}', source,
                      flags=re.MULTILINE | re.DOTALL)
    if not match:
        return False
    body = match.group('body')
    guard = re.search(r'^ if command -v curl >/dev/null 2>&1; then$',
                      body, flags=re.MULTILINE)
    end_guard = re.search(r'^ fi$', body, flags=re.MULTILINE)
    invocations = list(re.finditer(r'^\s*curl\s', source, flags=re.MULTILINE))
    if not guard or not end_guard or not invocations:
        return False
    # The fallback requires both authenticated and unauthenticated requests.
    for invocation in invocations:
        if not (match.start('body') + guard.end() <= invocation.start() <
                match.start('body') + end_guard.start()):
            return False
    return True
INTERNAL = set('''
if then elif else fi for in do done while until case esac function return exit
local export readonly set shift trap read eval exec command builtin type hash alias
unalias unset wait break continue cd pwd printf echo test true false time
umask ulimit getopts kill jobs fg bg select coproc
'''.split())


def policy_names(path: Path) -> set[str]:
    names = set()
    for line in path.read_text(encoding='utf-8').splitlines():
        value = line.partition('#')[0].strip()
        if not value:
            continue
        if not re.fullmatch(r'[a-z][a-z0-9._+-]*', value):
            raise ValueError(f'invalid allowlisted command: {value}')
        names.add(value)
    if not names:
        raise ValueError('empty command policy')
    return names


def router_scripts(root: Path) -> list[Path]:
    scripts = []
    for path in sorted((root / 'root').rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if not rel.startswith(('root/usr/libexec/', 'root/usr/lib/', 'root/etc/',
                               'root/www/cgi-bin/')):
            continue
        with path.open('rb') as stream:
            shebang = stream.readline(128).decode('utf-8', errors='replace').strip()
        if SHELL.match(shebang):
            scripts.append(path)
    return scripts


def unquoted_shell(line: str, state: list[dict]) -> str:
    """Mask shell literals, retain executable command substitutions.

    Each nested $(...) is a separate shell context. Single-quoted awk/sed
    source is *not* parsed as shell code, including across source lines.
    """
    out = []
    i = 0
    while i < len(line):
        ctx = state[-1]
        quote = ctx['quote']
        char = line[i]
        if char == "\\" and quote != "'":
            out.append(' ')
            if i + 1 < len(line):
                out.append(' ')
                i += 2
            else:
                i += 1
            continue
        if quote != "'" and line.startswith('$((', i):
            # Arithmetic expansion is not a command substitution.
            end = line.find('))', i + 3)
            if end != -1:
                out.extend(' ' * (end + 2 - i))
                i = end + 2
                continue
        if quote != "'" and line.startswith('$(', i):
            out.extend('$(')
            state.append({'quote': None, 'depth': 1})
            i += 2
            continue
        if quote == "'":
            if char == "'":
                ctx['quote'] = None
            out.append(' ')
        elif quote == '"':
            if char == '"':
                ctx['quote'] = None
            out.append(' ')
        elif char in ("'", '"'):
            ctx['quote'] = char
            out.append(' ')
        elif char == '#' and (not out or out[-1].isspace()):
            break
        else:
            out.append(char)
            if len(state) > 1:
                if char == '(':
                    ctx['depth'] += 1
                if char == ')':
                    ctx['depth'] -= 1
                    if ctx['depth'] == 0:
                        state.pop()
        i += 1
    return ''.join(out)


def commands(source: str) -> set[str]:
    functions = {match.group(1) for line in source.splitlines()
                 if (match := FUNCTION.match(line))}
    found: set[str] = set()
    heredoc_end: str | None = None
    state = [{'quote': None, 'depth': 0}]
    for raw in source.splitlines():
        if heredoc_end:
            if raw.strip() == heredoc_end:
                heredoc_end = None
            continue
        # Check heredoc delimiters on raw shell syntax before quote masking.
        heredoc = HEREDOC.search(raw)
        if heredoc and state[0]['quote'] is None and len(state) == 1:
            heredoc_end = heredoc.group(2)
        # A quoted executable path/variable is one command token. Keep a
        # placeholder to prevent its first argument being mistaken for a call.
        raw = re.sub(r'"\$(?:\{[a-zA-Z0-9_]+\}|[a-zA-Z0-9_]+)"', 'DYNAMIC_EXEC', raw)
        line = unquoted_shell(raw, state)
        # Case labels are not commands, including multi-pattern arms and
        # single-line `case value in one|two) ...` forms.
        if re.match(r'^\s*case\b.*\bin\b.*\)', line):
            line = line.split(')', 1)[1]
        elif re.match(r'^\s*[^#$;={}()]+\)', line):
            line = line.split(')', 1)[1]
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        # Ignore shell function definitions, pattern arms, and plain assignments.
        for probe in (*PROBE.finditer(line), *POST_KEYWORD.finditer(line)):
            name = probe.group('name')
            if name in INTERNAL or name in functions or name == 'DYNAMIC_EXEC':
                continue
            if line[probe.end('name'):].lstrip().startswith('='):
                continue
            found.add(name)
        for match in SITE.finditer(line):
            name = match.group('name')
            # Shell case arms / function declarations are not executable calls.
            suffix = line[match.end('name'):].lstrip()
            if suffix.startswith('()') or suffix.startswith(')'):
                continue
            if name in INTERNAL or name in functions or name == 'DYNAMIC_EXEC':
                continue
            # An assignment cannot be an executable command name.
            if suffix.startswith('='):
                continue
            # Expressions like $(foo) are real commands but `${foo}` is not.
            if line[:match.start('name')].endswith('${'):
                continue
            found.add(name)
    return found



# Performance guardrails for constrained router hardware. These are deliberately
# high-confidence anti-patterns, not a blanket ban on grep/find/sort: bounded
# scans and file processing are legitimate and often faster than alternatives.
# Using the same shipped-script discovery as the compatibility audit ensures
# that every added router entry point receives both checks automatically.
# Detect executable sites, not command names embedded in quotes or comments.
# Assignment prefixes such as LC_ALL=C grep -R must not bypass the audit.
PERFORMANCE_SITE = re.compile(
    r'(?:^|[;|`]|\$\(|\bthen\s+|\bdo\s+|\belse\s+|'
    r'\bif\s+|\belif\s+|\bwhile\s+|\buntil\s+|\b!\s+)'
    r'\s*(?:[a-zA-Z_][a-zA-Z_0-9]*=[^\s;|]+\s+)*'
    r'(?P<name>find|du|grep|ls|dd|xargs|sleep)\b'
)
INFINITE_LOOP = re.compile(
    r'(?:^|[;|]|\$\()\s*(?:while\s+(?:true|:)|until\s+false)\s*;\s*do\b'
)
NESTED_LOOP = re.compile(r'\b(?:for|while|until)\b[^;]*;\s*do\b')
LOOP_DONE = re.compile(r'(?:^|;)\s*done\b')
BLOCKING_ACTION = re.compile(r'\b(?:sleep|wait)\b|\bubus\s+listen\b')
LOOP_EXIT = re.compile(r'\b(?:break|return|exit)\b')
ZERO_SLEEP = re.compile(r'0+(?:\.0+)?[smhd]?$', re.IGNORECASE)


def shell_lines(source: str) -> list[tuple[int, str, str]]:
    """Return source and quote-masked shell lines, excluding heredoc data.

    The mask retains offsets, so we can lex *real arguments* only after we have
    established that a command name is executable shell, not a quoted string.
    """
    lines = []
    heredoc_end: str | None = None
    state = [{'quote': None, 'depth': 0}]
    for number, raw in enumerate(source.splitlines(), 1):
        if heredoc_end:
            if raw.strip() == heredoc_end:
                heredoc_end = None
            continue
        heredoc = HEREDOC.search(raw)
        if heredoc and state[0]['quote'] is None and len(state) == 1:
            heredoc_end = heredoc.group(2)
        masked = unquoted_shell(raw, state)
        lines.append((number, raw, masked))
    return lines


def call_arguments(raw: str, masked: str, end: int) -> list[str]:
    """Parse arguments up to the next unquoted shell operator."""
    boundary = re.search(r'[;|`]|\$\(', masked[end:])
    stop = end + boundary.start() if boundary else len(masked)
    try:
        return shlex.split(raw[end:stop], comments=True, posix=True)
    except ValueError:
        # The command may use a line continuation or multiline quotes. Avoid
        # a false positive based on incomplete arguments; build/runtime tests
        # remain necessary for cases this static checker cannot resolve.
        return []


def command_risk(name: str, args: list[str]) -> str | None:
    """Only report expensive or unbounded operations with clear evidence."""
    options = [a for a in args if a.startswith('-')]
    shorts = ''.join(a[1:] for a in options if a.startswith('-') and not a.startswith('--'))
    recursive = 'R' in shorts or '--recursive' in options
    if name == 'find' and args and args[0] == '/':
        return 'full filesystem traversal (find /); use a bounded subtree'
    if name == 'du' and ('a' in shorts or '--all' in options or '/' in args):
        return 'unbounded disk scan (du -a or du /); target a bounded path'
    if name == 'grep' and (recursive or 'r' in shorts):
        return 'recursive grep; limit the files/directory and scan budget'
    if name == 'ls' and recursive:
        return 'recursive ls; use a targeted directory listing'
    if name == 'dd' and any(a in ('if=/dev/zero', 'if=/dev/urandom') for a in args):
        if not any(a.startswith(('count=', 'count_bytes=')) for a in args):
            return 'unbounded dd from a generator; specify count='
    if name == 'xargs' and ('-P0' in args or '--max-procs=0' in args or
                            any(args[i:i + 2] == ['-P', '0']
                                for i in range(len(args) - 1))):
        return 'unbounded xargs concurrency (-P 0); specify a small limit'
    if name == 'sleep' and args and ZERO_SLEEP.fullmatch(args[0]):
        return 'zero-delay sleep; set a positive delay to prevent busy polling'
    return None


def performance_risks(source: str, rel: str) -> list[str]:
    errors: list[str] = []
    lines = shell_lines(source)
    # Some shell code has case labels (`grep)`) and function declarations;
    # they are not command invocations. Raw strings in heredocs are excluded.
    for number, raw, masked in lines:
        for match in PERFORMANCE_SITE.finditer(masked):
            name = match.group('name')
            suffix = masked[match.end('name'):].lstrip()
            if suffix.startswith((')', '()')):
                continue
            args = call_arguments(raw, masked, match.end('name'))
            reason = command_risk(name, args)
            if reason:
                errors.append(f'{rel}:{number}: performance risk: {reason}')

    # An unconditional infinite loop needs explicit throttling, blocking
    # wait, or an exit path. A zero-delay sleep is separately rejected. A
    # bounded `while :` loop with `break` must remain valid (apps-manager).
    for i, (number, _, masked) in enumerate(lines):
        loop = INFINITE_LOOP.search(masked)
        if not loop:
            continue
        depth = 1
        body: list[str] = []
        closed = False
        # Handle both multiline loops and `while true; do :; done`.
        for next_line in [masked[loop.end():], *(line[2] for line in lines[i + 1:])]:
            closing = LOOP_DONE.search(next_line)
            if depth == 1 and closing:
                body.append(next_line[:closing.start()])
                closed = True
                break
            depth += len(NESTED_LOOP.findall(next_line))
            depth -= len(LOOP_DONE.findall(next_line))
            if depth <= 0:
                closed = True
                break
            body.append(next_line)
        if closed and not any(BLOCKING_ACTION.search(line) or LOOP_EXIT.search(line)
                              for line in body):
            errors.append(f'{rel}:{number}: performance risk: '
                          'unthrottled infinite loop (no sleep, wait, or exit)')
    return errors


def audit(root: Path, allowed: set[str]) -> list[str]:
    errors = []
    files = router_scripts(root)
    if not files:
        return ['no router shell scripts found']
    # A newly added script requiring bash/python must not escape the audit just
    # because its shebang is not /bin/sh. Ucode files have no shell shebang.
    runtime_roots = ('root/usr/libexec/', 'root/usr/lib/', 'root/etc/',
                     'root/www/cgi-bin/')
    for path in sorted((root / 'root').rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if not rel.startswith(runtime_roots):
            continue
        with path.open('rb') as stream:
            shebang = stream.readline(128).decode('utf-8', errors='replace').strip()
        if re.match(r'^#!\s*(?:/bin/bash|/usr/bin/env\s+(?:bash|python3?))\b', shebang):
            errors.append(f'{rel}: unsupported interpreter: {shebang}')
    # Shared shell helpers can define functions used by sourced scripts.
    shared = set()
    for path in files:
        shared.update(match.group(1) for line in path.read_text(encoding='utf-8').splitlines()
                      if (match := FUNCTION.match(line)))
    for path in files:
        rel = path.relative_to(root).as_posix()
        source = path.read_text(encoding='utf-8')
        for match in COMMAND_DEFAULT.finditer(source):
            variable = match.group('var')
            command = match.group('name')
            if variable.upper().endswith(('_BIN', '_COMMAND', '_CMD', '_EXEC')):
                if command not in allowed and command not in INTERNAL:
                    errors.append(f'{rel}: unsupported command default: '
                                  f'{variable}={command}')
        for command in sorted(commands(source) - allowed - shared - SOURCED_FUNCTIONS):
            if (rel == OPTIONAL_CURL_SOURCE and command == 'curl' and
                    legacy_curl_is_guarded(source)):
                continue
            errors.append(f'{rel}: unsupported command: {command}')
        errors.extend(performance_risks(source, rel))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        errors = audit(args.root, policy_names(POLICY))
    except (OSError, ValueError) as exc:
        print(f'FAIL: OpenWrt command policy: {exc}', file=sys.stderr)
        return 1
    if errors:
        print('FAIL: OpenWrt 25.12 unsupported or high-cost router shell operation(s):', file=sys.stderr)
        for error in errors:
            print(f'  {error}', file=sys.stderr)
        return 1
    print('PASS: OpenWrt 25.12 command and performance policy')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
