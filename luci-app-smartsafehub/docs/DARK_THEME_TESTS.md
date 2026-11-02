# 다크 모드 스타일 검사

`tests/runtime/dark-theme-coverage.test.mjs`는 `frontend/src`의 모든 TSX에서
**완전한 정적 Tailwind 색상 클래스**를 수집하고, `frontend/src/styles/app.css`의
실제 다크 모드 선택자와 선언을 비교합니다. 기존 `dark-theme-css.test.mjs`의
회귀 계약을 보완하며 새 클래스가 추가될 때 누락을 발견하는 목적입니다.

검사 대상:
- `bg-*` 밝은 배경, `border-*` 밝은 테두리, `divide-*` 구분선, `ring-*`
  포커스 링, 어두운 `text-*` 글자 색상
- 기본 상태와 `hover:`, `focus:`, `focus-visible:`, `disabled:` 변형
- 템플릿 문자열과 조건부 문자열 안에 있는 완전한 클래스명

검사는 CSS에서 다크 테마 선택자와 실제 색상 선언이 함께 존재하는지 확인합니다.
구분선은 Tailwind v4에 맞게 **부모가 아닌 자식**의 `border-color`를 검사합니다.
배경·테두리가 지나치게 밝거나 글자가 지나치게 어두우면 실패합니다.
이는 간단한 명도 검사이며 WCAG 접근성 검증이나 실브라우저 렌더링을 대체하지 않습니다.

새 클래스를 추가할 때 `app.css`에서 동일한 클래스의 다크 모드 스타일을
추가하거나, **정당한 예외**라면 `tests/support/dark-theme-exceptions.json`에
정확한 파일 경로·클래스명·20자 이상의 사유를 명시하세요.

```json
[
  {
    "file": "frontend/src/pages/ExamplePage.tsx",
    "utility": "bg-violet-50",
    "reason": "사용자가 색상을 비교하는 미리보기 영역에서는 원래 색상이 필요합니다."
  }
]
```

위 코드는 예시입니다. 실제 프로젝트의 예외 목록은 현재 비어 있습니다.
예외는 해당 파일에서만 적용됩니다. 중복·미사용·근거 없는 예외는 실패합니다.

실행:

```sh
node --test tests/runtime/dark-theme-coverage.test.mjs
node --test tests/runtime/*.test.mjs
```

CI는 `tests/runtime/*.test.mjs`를 자동 실행하므로 별도의 등록이 필요하지 않습니다.
유틸리티 이름을 실행 시점에 동적으로 조합하거나 Tailwind 임의값(`bg-[#...]`),
서드파티 내부 CSS, 실제 브라우저의 최종 캐스케이드는 정적 검사 범위 밖입니다.
해당 경우에는 브라우저에서 라이트·다크 모드를 함께 확인하세요.
