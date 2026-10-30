#!/usr/bin/env python3
"""Fail fast when a test is not connected to ShellSpec or GitHub Actions.

No third-party dependencies: the checker runs before CI installs ShellSpec/Node.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
REGISTRATION = re.compile(
    r'^\s*When\s+run\s+command\s+sh\s+["\']\$SHELLSPEC_PROJECT_ROOT/'
    r'(tests/[a-zA-Z0-9_./-]+\.sh)["\']\s*$'
)
JOB_HEADER = re.compile(r'^  ([a-zA-Z][a-zA-Z0-9_-]*):\s*$')


class CoverageError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CoverageError(message)


def relative_names(paths, root: Path) -> set[str]:
    return {path.relative_to(root).as_posix() for path in paths}


def check_shellspec(root: Path) -> int:
    tests_dir = root / 'tests'
    spec_dir = root / 'spec'
    scripts = relative_names(tests_dir.rglob('*.sh'), root)
    require(bool(scripts), 'tests/ 안에 셸 테스트가 없습니다.')
    specs = sorted(spec_dir.rglob('*_spec.sh'))
    unsupported_specs = sorted(spec_dir.rglob('*.sh'))
    unsupported_specs = [spec for spec in unsupported_specs if spec not in specs]
    require(not unsupported_specs, 'ShellSpec 자동 검색 대상이 아닌 spec 스크립트: ' +
            ', '.join(str(spec.relative_to(root)) for spec in unsupported_specs))
    require(bool(specs), 'ShellSpec spec/*_spec.sh 파일이 없습니다.')

    registrations: Counter[str] = Counter()
    for spec in specs:
        for line in spec.read_text(encoding='utf-8').splitlines():
            match = REGISTRATION.fullmatch(line)
            if match:
                registrations[match.group(1)] += 1

    missing = sorted(scripts - registrations.keys())
    stale = sorted(registrations.keys() - scripts)
    duplicates = sorted(name for name, count in registrations.items() if count > 1)
    require(not missing, 'ShellSpec 미등록 셸 테스트: ' + ', '.join(missing))
    require(not stale, 'ShellSpec 등록 경로에 파일 없음: ' + ', '.join(stale))
    require(not duplicates, 'ShellSpec 중복 등록: ' + ', '.join(duplicates))
    return len(scripts)


def check_runtime(root: Path) -> int:
    runtime_dir = root / 'tests/runtime'
    runtime = sorted(runtime_dir.glob('*.test.mjs'))
    require(bool(runtime), 'tests/runtime/*.test.mjs 테스트가 없습니다.')
    # The workflow deliberately uses a non-recursive *.test.mjs glob. Nested
    # tests or newly introduced .test.ts/.spec.mjs files must not be silent.
    for path in (root / 'tests').rglob('*'):
        if not path.is_file() or path.suffix == '.sh':
            continue
        name = path.name
        looks_like_test = (
            '.test.' in name or '.spec.' in name or
            name.startswith(('test-', 'test_')) or name.endswith('_test.py')
        )
        if looks_like_test and path not in runtime:
            raise CoverageError(
                f'CI 실행 대상이 아닌 테스트 파일: {path.relative_to(root)} '
                '(JavaScript 테스트는 tests/runtime/*.test.mjs에 배치하세요)'
            )
    return len(runtime)


def job_section(workflow: str, name: str) -> str:
    lines = workflow.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if JOB_HEADER.fullmatch(line) and JOB_HEADER.fullmatch(line).group(1) == name), None)
    require(start is not None, f'CI jobs.{name} 누락')
    end = next((i for i in range(start + 1, len(lines))
                if JOB_HEADER.fullmatch(lines[i])), len(lines))
    return '\n'.join(lines[start:end])


def command_is_unconditional(job: str, command: str) -> bool:
    if re.search(r'^    (?:if|continue-on-error)\s*:', job, re.MULTILINE):
        return False
    # Match exact YAML step commands rather than substrings, comments or
    # commands that can swallow failures (e.g. `... || true`).
    steps = re.split(r'(?=^      - )', job, flags=re.MULTILINE)
    for step in steps:
        if re.search(r'^        (?:if|continue-on-error)\s*:', step, re.MULTILINE):
            continue
        if re.search(r'^        run:[ \t]*' + re.escape(command) + r'[ \t]*$', step, re.MULTILINE):
            return True
    return False


def check_ci(root: Path) -> None:
    workflow = (root / '.github/workflows/ci.yml').read_text(encoding='utf-8')
    backend = job_section(workflow, 'backend')
    frontend = job_section(workflow, 'frontend')
    require(
        command_is_unconditional(backend, 'sh tests/test-suite-integrity.sh'),
        'Backend CI의 독립 테스트 누락 검사 단계가 없거나 조건부로 실행됩니다.',
    )
    require(
        command_is_unconditional(backend, 'shellspec'),
        'Backend CI에서 전체 ShellSpec 테스트를 실행하지 않습니다.',
    )
    require(
        command_is_unconditional(backend, 'sh tests/test-openwrt-commands.sh'),
        'Backend CI에서 OpenWrt 25.12 명령 호환성 검사가 누락되거나 조건부로 실행됩니다.',
    )
    require(
        command_is_unconditional(frontend, 'node --experimental-strip-types --test ../tests/runtime/*.test.mjs'),
        'Frontend CI에서 모든 *.test.mjs 파일을 자동 실행하지 않습니다.',
    )


def check(root: Path) -> tuple[int, int]:
    shell_count = check_shellspec(root)
    runtime_count = check_runtime(root)
    check_ci(root)
    return shell_count, runtime_count


def self_test() -> None:
    """Mutation tests: prove unregistered and skipped tests really fail."""
    with tempfile.TemporaryDirectory(prefix='smartsafehub-ci-gate-') as temp:
        root = Path(temp)
        for dirname in ('tests/runtime', 'spec', '.github/workflows'):
            (root / dirname).mkdir(parents=True)
        (root / 'tests/test-existing.sh').write_text('#!/bin/sh\n', encoding='utf-8')
        (root / 'tests/runtime/existing.test.mjs').write_text('', encoding='utf-8')
        spec_path = root / 'spec/contracts_spec.sh'
        spec_base = 'Describe "checks"\n  When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-existing.sh"\nEnd\n'
        spec_path.write_text(spec_base, encoding='utf-8')
        workflow_path = root / '.github/workflows/ci.yml'
        workflow_base = '''jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - name: Guard
        run: sh tests/test-suite-integrity.sh
      - name: Test
        run: shellspec
      - name: OpenWrt BusyBox
        run: sh tests/test-openwrt-commands.sh
  frontend:
    runs-on: ubuntu-latest
    steps:
      - name: Test
        run: node --experimental-strip-types --test ../tests/runtime/*.test.mjs
'''
        workflow_path.write_text(workflow_base, encoding='utf-8')
        require(check(root) == (1, 1), 'self-test fixture 불일치')

        def fails_with(fragment: str) -> None:
            try:
                check(root)
            except CoverageError as exc:
                require(fragment in str(exc), f'예상 외 오류: {exc}')
            else:
                raise CoverageError(f'누락 검출 실패: {fragment}')

        extra = root / 'tests/test-new.sh'
        extra.write_text('#!/bin/sh\n', encoding='utf-8')
        fails_with('ShellSpec 미등록')
        extra.unlink()

        spec_path.write_text(spec_base.replace('End\n',
            '  When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-existing.sh"\nEnd\n'), encoding='utf-8')
        fails_with('ShellSpec 중복')
        spec_path.write_text(spec_base.replace('End\n',
            '  When run command sh \"$SHELLSPEC_PROJECT_ROOT/tests/test-deleted.sh\"\nEnd\n'), encoding='utf-8')
        fails_with('등록 경로에 파일 없음')
        spec_path.write_text(spec_base, encoding='utf-8')
        extra_spec = root / 'spec/hidden.sh'
        extra_spec.write_text('Describe \"hidden\"\nEnd\n', encoding='utf-8')
        fails_with('자동 검색 대상이 아닌')
        extra_spec.unlink()

        # A correctly named new runtime test is covered by the CI glob.
        included = root / 'tests/runtime/new.test.mjs'
        included.write_text('', encoding='utf-8')
        require(check(root) == (1, 2), '새 JS 테스트 자동 검색 실패')
        included.unlink()

        unsupported = root / 'tests/runtime/new.test.js'
        unsupported.write_text('', encoding='utf-8')
        fails_with('CI 실행 대상이 아닌')
        unsupported.unlink()
        unsupported_python = root / 'tests/test_missing.py'
        unsupported_python.write_text('', encoding='utf-8')
        fails_with('CI 실행 대상이 아닌')
        unsupported_python.unlink()
        nested = root / 'tests/runtime/nested'
        nested.mkdir()
        (nested / 'new.test.mjs').write_text('', encoding='utf-8')
        fails_with('CI 실행 대상이 아닌')
        (nested / 'new.test.mjs').unlink()

        for old, replacement, error in (
            ('run: sh tests/test-openwrt-commands.sh', '# run: sh tests/test-openwrt-commands.sh', '명령 호환성'),
            ('run: sh tests/test-openwrt-commands.sh', 'run: sh tests/test-openwrt-commands.sh || true', '명령 호환성'),
            ('run: sh tests/test-suite-integrity.sh', '# run: sh tests/test-suite-integrity.sh', '독립 테스트'),
            ('run: shellspec', 'run: shellspec spec/selected_spec.sh', 'ShellSpec 테스트'),
            ('run: node --experimental-strip-types --test ../tests/runtime/*.test.mjs',
             'run: node --experimental-strip-types --test ../tests/runtime/existing.test.mjs', '*.test.mjs'),
            ('run: shellspec', 'if: false\n        run: shellspec', 'ShellSpec 테스트'),
            ('run: shellspec', 'run: shellspec || true', 'ShellSpec 테스트'),
            ('run: shellspec', 'continue-on-error: true\n        run: shellspec', 'ShellSpec 테스트'),
        ):
            workflow_path.write_text(workflow_base.replace(old, replacement), encoding='utf-8')
            fails_with(error)
        workflow_path.write_text(workflow_base, encoding='utf-8')
        require(check(root) == (1, 1), 'self-test fixture 복구 실패')


if __name__ == '__main__':
    try:
        shell, runtime = check(ROOT)
        if '--self-test' in sys.argv[1:]:
            self_test()
        print(f'PASS: ShellSpec {shell}개, Frontend CI {runtime}개 파일 등록 확인'
              + (' (누락/중복/CI 우회 회귀 테스트 통과)' if '--self-test' in sys.argv[1:] else ''))
    except (CoverageError, OSError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
