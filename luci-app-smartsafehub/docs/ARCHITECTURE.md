# SmartSafeHub 아키텍처

이 문서는 SmartSafeHub LuCI 애플리케이션 **`0.2.16-r5`**의 구조, 런타임 흐름, 성능·안정성 설계와 확장 원칙을 설명합니다.

## 1. 설계 목표

SmartSafeHub는 일반 사용자가 OpenWrt의 복잡한 설정 전체를 직접 다루지 않고도 자주 사용하는 기능을 안전하게 관리할 수 있도록 설계되었습니다.

핵심 목표:

- 저사양 OpenWrt 장치에서도 동작하는 작은 Preact 프런트엔드
- LuCI 인증과 rpcd ACL을 그대로 사용하는 권한 모델
- 기능별로 분리된 ucode 백엔드
- Wi-Fi 변경 작업의 입력 검증과 실패 복구, SafeShield는 공식 API 계약 사용
- 일부 데이터 소스 실패를 전체 기능 실패로 확대하지 않는 best-effort 조회
- 데스크톱과 모바일에서 동일한 핵심 기능 제공
- 중복 RPC, 겹치는 폴링과 불필요한 hostapd 조회 최소화
- TypeScript/Vite와 OpenWrt 패키지 빌드로 소스·배포 산출물 오류를 조기에 확인

SmartSafeHub는 OpenWrt의 모든 고급 설정을 대체하지 않습니다. 게스트 Wi-Fi, VLAN, mesh, 방화벽, 패키지와 세부 시스템 설정은 기존 LuCI 화면으로 연결합니다.

## 2. 전체 구성

```text
브라우저
  │ /
  ▼
uHTTPd json_script
  │ exact root만 내부 rewrite → /cgi-bin/luci/
  ▼
LuCI public Preact shell (auth: {})
root/usr/share/ucode/luci/template/smartsafehub/login.ut
  │
  ├─ #smartsafehub-entry-root
  └─ 버전이 포함된 app.js 로드
       │
       ├─ GET /cgi-bin/luci/smartsafehub/session
       │      ├─ 403: LoginApp
       │      └─ 200 + session id: App
       │
       └─ POST /cgi-bin/luci/smartsafehub/session
              └─ LuCI password/session authentication
       │
       ▼
Preact 애플리케이션 · Shadow DOM
root/www/luci-static/smartsafehub/app.js + app.css
       │
       │ JSON-RPC /admin/ubus
       ├─────────────────────────────┐
       ▼                             ▼
rpcd ucode: smartsafehub       rpcd ucode: safeshield
       │                             │
       ├─ system / network           ├─ status / config
       ├─ wireless / hostapd         ├─ enable / refresh
       ├─ DHCP leases / ARP          ├─ local rules
       ├─ reboot / wifi reload       ├─ license storage / identity
       ├─ update status/settings     └─ DNS protection lifecycle
       └─ license lifecycle
              │
              ├─ smartsafehub-license (procd)
              │    └─ Hub activate / periodic status sync
              └─ smartsafehub-updater (procd)
                   └─ apk update / targeted package upgrade

SmartSafeHub backend는 SafeShield의 UCI, 규칙 파일, init script를 직접 다루지 않습니다.
SafeShield 관련 읽기·변경은 `safeshield` 패키지가 제공하는 공식 ubus API만 호출합니다.
```

## 3. LuCI 통합 계층

### 3.1 메뉴

메뉴 정의:

```text
root/usr/share/luci/menu.d/luci-app-smartsafehub.json
```

공식 사용자 URL은 공유기 루트 `/`입니다. `/etc/uhttpd/smartsafehub-root.json`은 uHTTPd `json_script`의 request rule로 `REQUEST_URI == "/"`인 경우에만 `/cgi-bin/luci/`로 내부 rewrite합니다. `uhttpd.main.index_page`나 `/www/index.html`은 변경하지 않으므로 다른 디렉터리 index, `/cgi-bin/cgi-upload`, `/ubus`, 정적 자산과 다른 패키지의 명시적 endpoint에는 적용되지 않습니다.

`/usr/libexec/smartsafehub-root-entry`는 기존 `uhttpd.main.json_script` 값을 덮어쓰지 않고 SmartSafeHub handler를 뒤에 추가합니다. 패키지 제거 시에는 자기 handler만 `del_list`하며 다른 패키지 handler의 순서와 값은 유지합니다. 패키지 설치/업그레이드에서는 postinst가 UCI 설정뿐 아니라 실행 중 uHTTPd의 command line도 확인합니다. UCI와 runtime의 SmartSafeHub `-H` 적용 여부가 서로 다를 때만 uHTTPd를 restart하므로, 설정에 handler가 이미 존재하지만 과거 reload 실패로 runtime에 반영되지 않은 상태도 스스로 복구합니다. 펌웨어 기본 포함 설치에서는 `uci-defaults`가 첫 부팅에 handler만 등록합니다.

LuCI의 `smartsafehub` 경로는 `auth: {}`인 공개 shell입니다. 따라서 비로그인 요청도 dispatcher 인증 단계에서 막히지 않고 항상 `smartsafehub/login` 템플릿과 Preact 번들을 로드합니다.

`smartsafehub/session`은 cookie authentication과 `login: true`를 사용하는 별도 보호 endpoint입니다. Preact는 이 endpoint를 GET하여 세션 유무를 확인하고, 로그인 폼 제출 시 같은 endpoint에 `luci_username` / `luci_password`를 POST합니다. 세션이 없으면 GET probe는 403으로 끝나지만 이는 background fetch이므로 stock 로그인 화면이 사용자 UI를 덮지 않습니다.

`/cgi-bin/luci/`, `smartsafehub`, `admin/smartsafehub`는 기존 first-child 동작과 북마크 호환을 위해 유지합니다. `admin/smartsafehub`는 child node에서 `auth: {}`를 명시하므로 LuCI의 `admin` parent가 인증 노드여도 public shell로 override되며, 호환 경로에서 shell이 로드되면 프런트엔드는 `history.replaceState()`로 브라우저 주소를 `/`로 정규화합니다.

### 3.2 ACL

ACL 정의:

```text
root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json
```

읽기 권한:

- `smartsafehub.status`
- `smartsafehub.connected_devices`
- `smartsafehub.wifi_summary`
- `smartsafehub.updates_status`
- `smartsafehub.health_status`
- `smartsafehub.license_status`
- `safeshield.status`
- `safeshield.config`
- `safeshield.rules_list`

쓰기 권한:

- `smartsafehub.wifi_update`
- `smartsafehub.system_reboot`
- `smartsafehub.updates_check`
- `smartsafehub.updates_install`
- `smartsafehub.updates_settings_update`
- `smartsafehub.health_run`
- `smartsafehub.health_reporter_update`
- `smartsafehub.license_activate`
- `safeshield.set_enabled`
- `safeshield.config_update` (통계 수집 설정에 한정)
- `safeshield.refresh`
- `safeshield.rule_add`
- `safeshield.rule_delete`
- `safeshield.license_get`
- `safeshield.license_update`

`license_get`은 동작 자체는 읽기이지만 평문 라이선스 키를 반환하는 민감 API이므로 일반 상태 조회 권한과 분리해 write ACL 그룹에 포함합니다. 브라우저의 주기적 상태 polling, 로컬 Health 진단과 진단 다운로드에서는 호출하지 않습니다. opt-in된 Health Reporter daemon만 실제 HTTPS 보고 시 서버 인증을 위해 일시적으로 호출하며 키를 파일이나 payload에 저장하지 않습니다.

rpcd는 로그인 시점에 ACL 그룹을 세션 권한으로 확장하므로 패키지 업그레이드로 새 RPC 메서드가 추가되면 이미 로그인되어 있던 세션에는 새 메서드 권한이 아직 없을 수 있습니다. postinst는 `rpcd reload`로 새 ucode plugin/ACL을 즉시 로드하고, 프런트엔드는 `Access denied` 발생 시 오래전부터 존재한 `system_root_password_status`를 같은 session ID로 확인합니다. 이 control RPC도 거부될 때만 실제 세션 만료로 처리하고, control RPC가 성공하면 새 ACL만 부족한 유효 세션으로 간주해 전체 애플리케이션을 강제 로그아웃시키지 않습니다.

진단 다운로드용 별도 `system_diagnostics` RPC는 사용하지 않습니다. 진단 파일은 읽기 권한이 있는 기존 API 응답을 프런트엔드에서 결합해 생성합니다.

### 3.3 Public Preact shell과 보호된 session bootstrap

`root/usr/share/ucode/luci/template/smartsafehub/login.ut`는 인증 상태와 무관하게 같은 `#smartsafehub-entry-root`를 제공하는 공개 서버 shell입니다. 이 템플릿은 session ID를 HTML에 직접 넣지 않습니다.

`root/usr/share/ucode/luci/template/smartsafehub/session.ut`는 보호된 `smartsafehub/session` route에서만 실행되며 인증에 성공한 요청의 `ctx.authsession`만 반환합니다.

주요 흐름:

1. 브라우저가 `/`을 요청하면 uHTTPd가 exact-root rule로 `/cgi-bin/luci/`에 내부 rewrite하고 LuCI first-child가 `auth: {}`인 SmartSafeHub Preact shell을 렌더링
2. `main.tsx`가 `/cgi-bin/luci/smartsafehub/session`을 GET
3. 403이면 `LoginApp`, 유효한 32자리 session ID면 제품 `App` 렌더링
4. 로그인 폼은 같은 session endpoint에 credentials를 POST
5. LuCI dispatcher가 비밀번호 검증, cookie 발급 및 추가 인증 정책을 처리
6. fetch가 redirect를 따라 보호 template에서 session ID를 받으면 페이지 reload 없이 `App`으로 전환
7. 제품 API는 받은 session ID를 `/admin/ubus` JSON-RPC에 사용

이 분리로 public UI route에는 dispatcher authentication을 걸지 않으면서도 실제 관리 API와 session ID bootstrap은 LuCI 인증 경계 뒤에 유지합니다.

기존 `htdocs/luci-static/resources/view/smartsafehub/app.js` LuCI view loader는 사용하지 않습니다. 인증 상태 전환과 bootstrap은 `frontend/src/main.tsx`와 `frontend/src/auth/session.ts`가 담당합니다.

현재 자산 버전:

```text
0.2.16-r5
```

별도 `SMARTSAFEHUB_FRONTEND_BUILD_ID` 또는 `FRONTEND_BUILD_ID`는 사용하지 않습니다.

## 4. 프런트엔드 아키텍처

### 4.1 기술 구성

- Preact 10
- TypeScript
- Vite
- Tailwind CSS
- 브라우저 `fetch()` 기반 JSON-RPC
- hash route 기반 단일 페이지 애플리케이션

Vite production entry와 출력:

```text
frontend/src/main.tsx
  ↓
root/www/luci-static/smartsafehub/app.js
root/www/luci-static/smartsafehub/app.css
```

production build는 HTML을 entry로 사용하지 않습니다. `frontend/index.html`은 개발 서버용 shell에만 사용하며, 배포 디렉터리에는 `index.html`을 생성하지 않습니다. 실제 OpenWrt 진입 HTML은 LuCI의 `login.ut` / `session.ut` template이 담당합니다.

### 4.2 Shadow DOM

`frontend/src/main.tsx`는 public entry template이 만든 `#smartsafehub-entry-root`에 open Shadow DOM을 생성하고, session probe 결과에 따라 같은 mount point에서 `LoginApp`과 제품 `App`을 전환합니다.

사용 목적:

- LuCI 테마 CSS가 SmartSafeHub 컴포넌트에 미치는 영향 최소화
- SmartSafeHub 스타일이 다른 LuCI 화면으로 새는 현상 방지
- 제품 UI의 반응형 레이아웃 독립 유지

Shadow root에는 버전이 포함된 `app.css` 링크와 Preact mount point가 생성됩니다. 이미 Shadow DOM이 존재하더라도 CSS URL의 버전이 다르면 새 URL로 교체합니다. legacy LuCI view loader용 전역 mount/unmount hook과 DOM observer는 사용하지 않으며 public shell의 단일 Preact lifecycle만 유지합니다.

### 4.3 화면과 route

| route | hash | 화면 |
|---|---|---|
| `home` | `#home` | 장치 대시보드 |
| `lan` | `#lan` | LAN 및 DHCP |
| `wifi` | `#wifi` | Wi-Fi |
| `devices` | `#devices` | 연결된 기기 |
| `safeshield` | `#safeshield` | SafeShield |
| `rules` | `#rules` | 사용자 규칙 |
| `system` | `#system` | 업데이트 |
| `settings` | `#settings` | 시스템 상태와 설정 |

`App.tsx`는 route와 데이터 hook을 조합하는 composition root입니다.

```text
AppShell.tsx
├── ProductHeader.tsx
└── ProductNavigation.tsx
```

- `ProductHeader`: 제품명, 화면 제목, 설명, 새로고침 버튼
- `ProductNavigation`: 데스크톱·모바일 제품 메뉴와 로그아웃. LuCI 고급 설정 진입점은 `SettingsPage` 안에서만 제공
- `AppShell`: 공통 제품 chrome과 페이지 콘텐츠 조합

### 4.4 데이터 계층

```text
페이지 컴포넌트
  ↓
hooks/use*.ts
  ↓
api/smartsafehub.ts 또는 api/safeshield.ts
  ↓
api/rpc.ts
  ↓
/admin/ubus JSON-RPC
```

`api/rpc.ts`의 책임:

- LuCI bootstrap에서 session ID와 RPC URL 읽기
- JSON-RPC 요청 ID 관리
- HTTP 오류, JSON 파싱 오류, ubus 상태 코드와 애플리케이션 오류 통합
- JSON-RPC 버전, 요청 ID, error 객체, result 배열과 정수 상태 코드 검증
- 기본 20초 타임아웃과 호출별 제한 지원; Wi-Fi 변경은 35초 사용
- 사용자에게 표시할 한국어 오류 메시지 생성

SmartSafeHub 백엔드 공통 응답:

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

오류 응답:

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "ERROR_CODE",
    "message": "사용자 메시지"
  }
}
```

SafeShield 상세 상태는 기존 `safeshield.status`의 원시 응답을 프런트엔드에서 화면용 모델로 정규화합니다. 객체 없음과 일부 ubus 오류는 `available: false` 상태로 변환합니다.

### 4.5 비동기 리소스와 폴링

공통 훅 `useAsyncResource()`는 읽기 화면의 로딩, 새로고침, 오류와 폴링을 관리합니다.

핵심 계약:

- `inFlight` Promise가 있으면 같은 loader를 다시 실행하지 않고 기존 Promise 반환
- active 상태에 진입할 때 초기 로드 실행; 비활성화 뒤 재진입하면 다시 조회
- `setInterval()`을 사용하지 않음
- 이전 요청이 완료된 뒤 다음 `setTimeout()` 예약
- `document.visibilityState === 'hidden'`이면 타이머 중단
- 탭이 다시 표시되면 즉시 한 번 갱신한 뒤 폴링 재개
- unmount 후 상태 변경 방지
- 홈·설정의 시스템 상태는 활성 상태에서 60초 간격으로 갱신

이 구조는 CPU와 네트워크가 느린 공유기에서 요청이 누적되는 문제를 방지합니다.

### 4.6 진단 정보 생성

진단은 프런트엔드 `useSystemActions()`에서 생성합니다.

```text
SettingsPage에 이미 로드된 smartsafehub.status
        │
        ├─ Promise.allSettled(smartsafehub.wifi_summary)
        ├─ Promise.allSettled(safeshield.status)
        └─ Promise.allSettled(smartsafehub.health_status)
                    │
                    ▼
        브라우저에서 SystemDiagnostics 조합
                    │
                    ▼
             JSON Blob 다운로드
```

설계 이유:

- 시스템 상태를 중복 조회하지 않음
- 독립적인 Wi-Fi, SafeShield, Health 상세 요청을 병렬 실행
- 선택적 서비스 한쪽이 실패해도 전체 다운로드 유지
- rpcd 안에서 다시 ubus를 중첩 호출하는 복합 진단 RPC 제거
- Wi-Fi 비밀번호와 라이선스 키를 수집하지 않음
- 호스트명, WAN IPv4와 Wi-Fi SSID는 진단 목적의 식별 정보로 포함될 수 있음을 화면에 안내

### 4.7 로컬 Health와 원격 Health Reporter

로컬 진단과 서버 보고는 의도적으로 분리합니다.

```text
smartsafehub-health daemon
  ├─ 5분마다 로컬 Health 진단
  │   ├─ 부팅 초기 SafeShield 준비 중이면 60초 tick에서 재확인
  │   └─ /tmp/smartsafehub/health.json
  │
  └─ Health Reporter
      ├─ reporter_enabled=1
      ├─ 유료 멤버십 또는 Trial
      ├─ 30분 heartbeat 또는 issue fingerprint 변경
      └─ POST /api/v1/health/reports
```

로컬 진단은 멤버십과 관계없이 항상 사용할 수 있습니다. Health Reporter는 `reporter_enabled=0`을 기본값으로 하며 유료/Trial 사용자가 설정 화면에서 직접 활성화해야 합니다. OFF 상태에서는 heartbeat, 이상 발생/복구 보고를 포함해 Reporter의 서버 요청을 수행하지 않습니다.

Reporter 토글 UI는 사용자의 입력 직후 로컬 화면 상태를 optimistic하게 전환하고 RPC 저장이 실패하면 직전 상태로 rollback합니다. 활성화 직후 detached `run-cycle`이 첫 보고를 처리하는 동안 상태 파일에 이전 `disabled`/`never` 값이 잠시 남더라도 UI는 이를 `첫 보고 준비 중/진행 중`으로 해석합니다. 저장 성공 뒤에는 0.4~4초 범위의 짧은 확인 조회를 수행해 첫 보고 성공/실패를 정규 60초 polling보다 빠르게 반영하며, mutation sequence로 이전 토글의 늦은 응답이 최신 상태를 덮어쓰지 않게 합니다.

진단 대상은 가용 메모리, CPU 코어 대비 1분 load, `/overlay` 여유 공간, WAN, dnsmasq, SafeShield 런타임, 관리 소프트웨어/펌웨어 업데이트 오류와 시스템 시간입니다. 주기 결과는 flash에 쓰지 않고 `/tmp/smartsafehub/health.json`에 atomic write합니다. 부팅 후 기본 120초의 `startup_grace_s` 동안 SafeShield가 첫 갱신 stage에 있거나 DNS 런타임/차단 목록/상태 API가 아직 준비되지 않은 경우에는 `initializing`으로 기록하고 issue fingerprint를 만들지 않습니다. grace가 끝난 뒤에도 준비되지 않으면 실제 warning/critical 상태로 승격합니다.

대시보드는 설정 페이지와 같은 `health_status` 결과를 읽어 `시스템 상태 > 리소스 사용량` 카드 아래에 로컬 진단 요약을 표시합니다. 정상 상태는 한 줄 요약과 마지막 진단 시각/검사 항목 수만 간결하게 보여주고, 부팅 초기 SafeShield `initializing`은 `준비 중`으로 표시하며, 주의·이상 상태는 최대 2개의 비정상 항목을 함께 노출합니다. 원격 Health Reporter의 opt-in 상태나 서버 보고 내용은 대시보드의 핵심 상태 요약과 분리하고 설정 페이지에서 관리합니다.

Health helper는 OpenWrt awk와 CI의 GNU awk에서 동일하게 실행되는 POSIX 호환 표현만 사용합니다. 특히 GNU awk 내장 이름과 충돌하는 이름을 `-v` 변수로 전달하지 않으며 contract test가 이를 고정합니다.

서버 보고 payload는 로컬 진단 JSON을 그대로 재사용하지 않고 whitelist 방식으로 새로 생성합니다. 허용 필드는 schema, 보고 시각, 전체 상태, 메모리/부하/저장 공간 수치와 `{code, severity}` 이상 목록뿐입니다. 호스트명, WAN IP, SSID/MAC, DNS 요청 내용, 로그 원문과 라이선스 키는 payload에 넣지 않습니다. SafeShield가 부팅 초기화 중이면 Reporter는 전송을 보류해 transient issue가 서버 장애 이력으로 남지 않게 하고, 준비 완료 뒤 기존 heartbeat/fingerprint 규칙으로 복귀합니다. 전송 실패 시 5분 backoff를 적용해 서버 장애 중 요청이 매 분 반복되지 않도록 합니다.

### 4.8 반응형 UI

- `md` 이상에서는 가로 제품 메뉴
- 768px 미만에서는 sticky 모바일 메뉴
- route 변경과 `Escape` 입력 시 메뉴 닫힘
- 주요 버튼과 링크에 최소 44px 터치 영역
- LuCI 경고 배너도 모바일에서 전체 폭 버튼 사용
- 긴 문자열은 화면 폭 안에서 줄바꿈

## 5. rpcd 백엔드 아키텍처

### 5.1 composition root

```text
root/usr/share/rpcd/ucode/smartsafehub.uc
```

진입점은 기능 구현을 포함하지 않고 하위 모듈의 public function을 RPC 메서드에 연결합니다.

```ucode
return { smartsafehub: methods };
```

rpcd는 이 반환값으로 `smartsafehub` ubus 객체를 등록합니다.

### 5.2 모듈 구성

```text
root/usr/share/rpcd/ucode/
├── smartsafehub.uc
├── smartsafehub-network.uc
└── smartsafehub/
    ├── core.uc
    ├── devices.uc
    ├── health.uc
    ├── network-management.uc
    ├── system.uc
    ├── wifi.uc
    └── wifi-management.uc
```

#### `core.uc`

공통 런타임 기능:

- 공유 ubus 연결
- 동기 안전 호출과 deferred 호출
- 공통 성공·실패 응답
- 문자열·숫자·메모리 값 정규화
- UCI cursor 생성
- 제한 시간이 있는 시스템 명령 실행

ucode module loader가 모듈을 캐시하므로 기능 모듈은 하나의 ubus 연결을 공유합니다.

#### `smartsafehub-network.uc` / `network-management.uc`

`smartsafehub-network.uc`는 LAN 구현을 별도 `smartsafehub_network` ubus 객체로 등록해 핵심 `smartsafehub` RPC와 장애 범위를 분리합니다. LAN 화면은 이 객체를 직접 호출하며 핵심 RPC가 같은 `rpcd` 프로세스의 다른 ucode 객체를 동기 `ubus.call()`로 다시 호출하지 않습니다. LAN 객체는 자체적으로 관리자 비밀번호 설정 상태를 확인하고 LuCI ACL에는 LAN 메서드만 최소 권한으로 노출합니다. 따라서 LAN 구현이 로드되지 않아도 `system_root_password_status`와 대시보드용 기존 RPC 객체는 유지됩니다.

기존 `network-management.uc` 파일명은 그대로 유지합니다. LAN backend 격리와 무관한 파일명 rename을 피하여 패치/checkout 과정에서 구현 모듈이 누락되는 회귀를 방지합니다.

기본 `network.lan`/`dhcp.lan`의 LAN 및 DHCP 관리:

- LAN IPv4 주소와 CIDR(`/8~30`) 읽기·검증
- OpenWrt 25.12의 `list ipaddr 'address/prefix'`가 ucode에서 배열로 반환되는 형식과 이전 scalar `ipaddr + netmask` 형식을 함께 해석하고, 25.12 list 구성에서는 CIDR/list 형태를 보존해 저장
- DHCP 시작/종료 주소를 OpenWrt `start`/`limit` 형식으로 변환
- DHCP 서버 사용 여부(`ignore`)와 임대 시간 관리
- `network.interface.wan.status`를 이용한 WAN/LAN IPv4 subnet 충돌 감지
- `network.interface dump`의 다른 활성 IPv4 subnet까지 피하는 안전한 `/24` 추천
- RFC1918 사설 주소/대역, network/broadcast 주소와 DHCP pool 유효성 검증
- `/tmp/smartsafehub/lan-update.lock`으로 동시 변경 직렬화
- UCI snapshot 복구와 2초 지연 `/sbin/reload_config` 적용

#### `wifi.uc`

읽기 전용 Wi-Fi 도메인 로직:

- 주파수 대역 판별
- 보안 방식 정규화
- 비밀번호 필요 여부 판별
- 무선 장치별 기본 AP 선택
- `network.wireless`와 hostapd 상태 결합
- 클라이언트 수, 채널과 런타임 상태 계산
- 변경 대상 section이 SmartSafeHub 관리 대상인지 UCI 기준 검증

각 radio에서는 LAN 네트워크에 연결된 AP를 우선하고 활성 상태와 격리 여부를 점수화해 하나의 기본 AP를 선택합니다.

#### `wifi-management.uc`

Wi-Fi 조회 RPC와 변경 작업:

- SSID UTF-8 1~32바이트 검증
- 지원 보안 방식 검증
- 비밀번호 8~63자 또는 64자리 16진수 검증
- 관리 대상 기본 AP만 변경 허용
- 변경 전 UCI snapshot 저장
- UCI commit
- `/sbin/wifi reload`
- 적용 실패 시 snapshot 복원과 reload 재시도
- `/tmp/smartsafehub/wifi-update.lock`으로 동시 변경 직렬화
- 잠금은 120초 뒤 stale 상태로 판단해 복구 가능
- 기존 키 재사용 시 WPA2/WPA3 비밀번호 형식 재검증

지원 보안 값:

- `keep`
- `none`
- `psk2`
- `sae-mixed`
- `sae`

변경 대상 검증에서는 무선 런타임 전체를 다시 조회하지 않고 UCI 설정을 사용합니다. 고급 또는 알 수 없는 보안 방식은 조회할 수 있지만, 해당 방식을 변경하려면 기존 LuCI를 사용합니다.

#### `devices.uc`

연결 기기 정보를 다음 소스에서 결합합니다.

1. dnsmasq DHCP lease 파일
2. `/proc/net/arp`
3. `network.wireless.status`
4. station 정보가 없는 인터페이스에 한해 `hostapd.<ifname>.get_clients`

MAC 주소를 기본 키로 병합해 다음 값을 생성합니다.

- hostname
- IPv4 address
- connection: `wifi`, `ethernet`, `unknown`
- online / leaseActive
- lease 만료 시각
- interface
- SSID, radio, band
- signal dBm, inactive time, connected time

개별 데이터 소스 실패는 빈 결과로 처리하고 다른 소스의 정보는 계속 반환합니다.

#### SafeShield 공식 API 소비

`smartsafehub/safeshield.uc` 같은 프록시·컨트롤러 모듈은 두지 않습니다. 프런트엔드의 `src/api/safeshield.ts`가 LuCI 세션으로 공식 `safeshield` ubus 객체를 직접 호출합니다.

SafeShield가 소유하는 기능:

- 상태와 health
- 공개 설정 조회
- enable/disable lifecycle
- 수동 refresh
- local allow/block 규칙
- 라이선스 키 저장·조회·제거와 장치 identity 제공
- 규칙 파일, dnsmasq, procd와 refresh scheduling

SmartSafeHub는 API 응답을 화면 모델로 정규화할 뿐 SafeShield의 UCI, `/etc/safeshield/*`, `/tmp/dnsmasq.d/*` 또는 `/etc/init.d/safeshield`를 직접 수정하지 않습니다. 통계 수집 ON/OFF는 SafeShield 공식 `safeshield.config_update`에 `statistics_enabled`만 전달해 변경하며, 그 외 일반 설정 편집에는 사용하지 않습니다. `set_enabled`는 비동기 요청이므로 mutation 응답으로 최종 상태를 추정하지 않고 `safeshield.status`를 다시 조회해 runtime 수렴을 확인합니다.

라이선스 상태의 기본 화면 조회는 `safeshield.status`의 `configured`, `key_masked`, plan/status 정보만 사용합니다. 브라우저가 평문 키를 가져오는 것은 사용자가 **현재 키 불러오기**를 명시적으로 실행한 경우뿐입니다. 새 키 등록과 변경은 SmartSafeHub의 `license_activate` RPC가 SafeShield `status.device` identity를 사용해 Hub `/api/v1/licenses/activate`를 먼저 통과시킨 뒤 성공한 경우에만 `safeshield.license_update`로 저장합니다. 사용자의 로컬 제거는 기존처럼 `license_update`에 빈 키를 전달합니다.

서버에서 해제한 라이선스의 로컬 수렴은 `/usr/libexec/smartsafehub-license` daemon이 담당합니다. 기본 300초마다 `license_get`으로 현재 키를 메모리에 일시 조회하고 `/api/v1/licenses/status`를 호출하며, 성공 응답이 명시적으로 `device_action=clear_license`를 지시한 경우에만 `safeshield.license_update`로 제거합니다. 서버/API 장애는 로컬 권한을 즉시 파괴하지 않는 fail-open 상태로 기록합니다. 명시적 activate와 status-sync는 activation lock으로 직렬화해 상태 파일과 키 갱신이 서로 덮어쓰지 않게 합니다. 로컬 Health 진단·진단 다운로드·일반 UI polling에는 평문 키가 포함되지 않습니다. opt-in된 유료/Trial Health Reporter daemon 역시 실제 서버 보고 직전에만 `safeshield.license_get`으로 키를 메모리에 조회해 HTTPS 인증 헤더에 사용하고 즉시 폐기합니다.

#### `system.uc`

시스템 상태와 재부팅을 담당합니다.

상태 수집 객체:

- `system.board`
- `system.info`
- `network.interface.wan.status`

rpcd handler에서 중첩 동기 ubus 호출을 수행하면 이벤트 루프가 막힐 수 있으므로 `ubus.defer()`로 순차 호출하고 마지막 콜백에서 `request.reply()`를 실행합니다. 최초 `system.board` 요청을 시작하지 못하면 `SYSTEM_BOARD_REQUEST_FAILED` 오류를 즉시 반환하며, WAN 조회 실패는 장치·런타임 정보 전체 실패로 처리하지 않습니다.

`smartsafehub-health` helper도 내부에서 `network.interface.wan`과 `safeshield` ubus 객체를 사용하므로 rpcd handler에서 동기 실행하지 않습니다. `health_status`에 캐시가 없거나 `health_run`을 요청한 경우 `/bin/sh -c '... &'`로 helper를 분리된 프로세스에서 시작하고 즉시 반환합니다. 프런트엔드는 새 `generatedAt`이 확인될 때까지 제한된 횟수만 재조회합니다.

재부팅은 요청 인자 `confirm: "reboot"`를 확인한 뒤 2초 후 실행합니다.

## 6. 공개 RPC 계약

핵심 `smartsafehub` RPC에는 장치·Wi-Fi·시스템 기능과 로컬 Health 기능이 포함됩니다. LAN/DHCP는 별도 `smartsafehub_network` 객체가 제공합니다.

| 객체 / 메서드 | 유형 | 인자 | 설명 |
|---|---|---|---|
| `smartsafehub.status` | 읽기 | 없음 | 장치, 소프트웨어, 런타임과 WAN 상태 |
| `smartsafehub.connected_devices` | 읽기 | 없음 | 연결 기기 목록과 집계 |
| `smartsafehub_network.lan_settings` | 읽기 | 없음 | LAN/DHCP 설정, WAN 충돌 상태와 추천 대역 |
| `smartsafehub_network.lan_update` | 쓰기 | `ip_address`, `prefix_length`, `dhcp_enabled`, `dhcp_start`, `dhcp_end`, `lease_time`, `confirm` | LAN/DHCP 수동 변경 |
| `smartsafehub_network.lan_auto_subnet` | 쓰기 | `confirm` | WAN 충돌 시 안전한 추천 `/24` 대역 자동 적용 |
| `smartsafehub.wifi_summary` | 읽기 | 없음 | 관리 대상 기본 Wi-Fi 요약 |
| `smartsafehub.wifi_update` | 쓰기 | `section`, `ssid`, `security`, `password`, `enabled` | Wi-Fi 설정 변경과 reload |
| `smartsafehub.system_reboot` | 쓰기 | `confirm` | 확인 후 재부팅 예약 |
| `smartsafehub.health_status` | 읽기 | 없음 | 최신 로컬 Health와 Reporter 상태 조회 |
| `smartsafehub.health_run` | 쓰기 | 없음 | 로컬 Health 진단 helper를 비동기로 시작 |
| `smartsafehub.health_reporter_update` | 쓰기 | `enabled` | 유료/Trial eligibility 확인 후 원격 보고 opt-in 변경 |

SafeShield 기능은 아래 공식 API를 직접 소비합니다.

| SafeShield API | 유형 | 설명 |
|---|---|---|
| `safeshield.status` | 읽기 | 상태, runtime, artifact, health |
| `safeshield.config` | 읽기 | 공개 설정과 마스킹된 라이선스 상태 |
| `safeshield.set_enabled` | 쓰기 | 비동기 enable/disable lifecycle 요청 |
| `safeshield.config_update` | 쓰기 | `statistics_enabled` 통계 수집 설정 변경 |
| `safeshield.refresh` | 쓰기 | 비동기 refresh 요청 |
| `safeshield.rules_list` | 읽기 | 사용자 허용·차단 규칙 조회 |
| `safeshield.rule_add` | 쓰기 | 사용자 규칙 추가 |
| `safeshield.rule_delete` | 쓰기 | 사용자 규칙 삭제 |
| `safeshield.license_get` | 민감 읽기 | 사용자가 요청한 경우 현재 평문 라이선스 키 조회 |
| `safeshield.license_update` | 쓰기 | 라이선스 키 등록·변경, 빈 키로 제거 |

## 7. 주요 데이터 흐름

### 7.1 장치 상태

```text
HomePage 또는 SettingsPage
  → useStatus
  → fetchStatus
  → smartsafehub.status
  → system.uc read_status
  → system.board
  → system.info
  → network.interface.wan.status
  → request.reply(ApiResponse)
```

### 7.2 LAN/DHCP 변경

```text
LanPage form
  → useLan.save 또는 useLan.applyRecommendation
  → smartsafehub_network.lan_update / lan_auto_subnet
  → smartsafehub_network 자체 관리자 비밀번호 gate
  → 사설 IPv4·CIDR·DHCP pool 검증
  → WAN/LAN subnet overlap 거부
  → network.lan + dhcp.lan UCI snapshot
  → UCI commit
  → 2초 지연 /sbin/reload_config 예약
      ├─ 주소 유지: 같은 페이지에서 런타임 재조회
      └─ 주소 변경: 새 공유기 IP 안내 후 클라이언트 재연결
  → 예약 실패 시 snapshot 복원
```

자동 추천은 현재 활성 인터페이스들의 IPv4 subnet을 읽고 미리 정한 RFC1918 `/24` 후보 중 겹치지 않는 첫 대역을 선택합니다. 사용자의 명시적 확인 없이 자동으로 LAN 주소를 바꾸지는 않습니다.

### 7.3 Wi-Fi 변경

```text
WifiPage form
  → useWifi.update
  → smartsafehub.wifi_update
  → 입력 검증
  → UCI 기반 관리 대상 검증
  → 현재 UCI snapshot 저장
  → UCI 변경 및 commit
  → Wi-Fi 변경 lock 획득
  → /sbin/wifi reload
      ├─ 성공: 새 summary 반환 및 2초·5초 지연 재조회
      └─ 실패: snapshot 복원 후 reload 재시도
  → lock 해제
```

### 7.4 대시보드 Internet 상태

대시보드는 핵심 `smartsafehub.status`의 WAN 링크/IP/프로토콜과 `smartsafehub_network.lan_settings`의 WAN/LAN subnet 및 충돌 판정을 함께 사용합니다. `INTERNET` 개요 카드는 WAN이 올라와 있고 subnet 충돌이 없을 때 정상 상태와 다른 개요 카드와 동일한 `자세히 보기` 링크를 표시하며, WAN/LAN 대역이 겹치면 연결 자체가 up이어도 `네트워크 충돌` 경고와 `#lan` `해결하기` 링크를 우선 표시합니다. LAN 상태 조회가 실패해도 핵심 대시보드 상태 조회와 렌더링은 유지하고, 대역 관련 메타데이터만 확인 필요 상태로 처리합니다.

`네트워크 보호 활동 > 연결 상태` 카드는 연결 기기 수를 중복 표시하지 않고 WAN IP/프로토콜, 상위 네트워크, LAN 네트워크, 충돌 여부를 보여주는 네트워크 구성 요약 역할을 담당합니다. WAN IPv4가 RFC1918 사설 주소이면 `사설 네트워크`로 표시하되 이를 장애로 취급하지 않습니다. 대시보드 수동 새로고침은 기존 상태 소스와 함께 LAN 상태도 갱신합니다.

### 7.5 연결 기기

대시보드의 연결 기기 카드에서 `generatedAt`은 마지막 목록 확인 시각을 보여주는 정보성 값으로만 사용합니다. 사용자가 대시보드에 머무르는 동안 연결 기기 조회는 주기 polling을 하지 않으므로 시간이 오래되었다는 사실 자체를 장애나 주의 상태로 판단하지 않습니다. 실제 연결 기기 조회가 실패한 경우에만 확인 필요 상태로 표시합니다.


```text
ConnectedDevicesPage
  → smartsafehub.connected_devices
  → DHCP leases + ARP + network.wireless
  → station 누락 인터페이스만 hostapd fallback
  → MAC 기준 병합·분류·집계
```

### 7.6 SafeShield 사용자 규칙

```text
SafeShieldRulesPage
  → safeshield.rule_add / safeshield.rule_delete
  → SafeShield 엔진이 규칙 검증·저장·직렬화 수행
  → cached-artifact local apply 요청
  → safeshield.status polling
  → last_local_apply / last_local_apply_failure 확인
```

SmartSafeHub는 규칙 입력 형식을 프런트엔드에서 1차 검증하지만, 규칙 파일과 적용 lifecycle의 authoritative source는 SafeShield입니다.

### 7.7 SmartSafeHub / SafeShield 라이선스 lifecycle

```text
기본 화면 상태 조회
  → safeshield.status
  → configured + key_masked만 사용

현재 키 불러오기
  → 사용자 명시 동작
  → safeshield.license_get
  → 평문 키를 입력란에 채워 수정 가능

등록 / 변경
  → smartsafehub.license_activate
  → safeshield.status.device에서 authoritative identity 수집
  → private /tmp request file 생성
  → smartsafehub-license activate --request-file ...
  → POST /api/v1/licenses/activate
  → Hub 성공 시에만 safeshield.license_update { license_key: "..." }

주기적 서버 상태 수렴
  → smartsafehub-license daemon (기본 300초)
  → safeshield.license_get + safeshield.status.device.physical_fingerprint
  → POST /api/v1/licenses/status
      ├─ none + licensed: 유지
      ├─ clear_license: safeshield.license_update { license_key: "" }
      └─ 통신 실패/비정상 응답: 로컬 키 유지 + 진단 오류 기록

사용자 로컬 제거
  → 사용자 확인
  → safeshield.license_update { license_key: "" }
```

SafeShield는 키 저장과 device identity의 authoritative source이며 Hub 계정/장치 activation lifecycle은 SmartSafeHub가 소유합니다. SmartSafeHub는 SafeShield UCI를 직접 수정하지 않고 항상 공식 ubus API를 사용합니다. activate 요청의 평문 키는 command line이나 `/tmp/smartsafehub/license.json`에 기록하지 않고 mode 0600의 일시 request file로 helper에 넘긴 뒤 완료 시 제거합니다.

`smartsafehub-license`는 `daemon`, `activate`, `status-sync`, `status` subcommand로 구성합니다. 이 명령 경계와 상태 모델은 향후 `smartsafehub-agent license ...`로 통합할 때 기능 코드를 큰 단일 loop로 합치지 않고 license 모듈 단위로 그대로 옮길 수 있게 의도한 것입니다. 현재는 독립 procd 서비스라 장애 격리와 `logread -e smartsafehub-license`, 수동 `status-sync` 같은 디버깅 경로를 유지합니다.

daemon의 startup/check interval은 interrupt 가능한 child `sleep` + `wait` 경계로 구현합니다. SIGTERM/SIGINT 시 wait 중인 child를 종료하고 scheduler loop를 빠져나오므로 300초 대기 중 procd stop/restart가 SIGKILL까지 지연되지 않습니다. HTTP 요청은 최대 10초이므로 init script의 `term_timeout`은 15초로 두어 요청 중 종료에도 정상 정리 여유를 둡니다.

`/tmp/smartsafehub/license.json`은 현재 동작 상태와 별도로 마지막 Hub/activation 진단을 유지합니다. `lastHttpStatus`는 성공한 Hub JSON API 요청에서 200을 기록하고 실제 HTTP 상태를 신뢰할 수 없는 fetch 실패에서는 `null`을 기록합니다. `lastActivationResult`와 `lastActivationErrorCode`는 마지막 명시적 activate의 성공/실패 결과이며, 이후 `status-sync`, 서버 revoke에 따른 clear, 로컬 unconfigured 전환이 발생해도 덮어쓰지 않습니다. 따라서 현재 상태(`phase`, `lastResult`)와 마지막 사용자 activation 결과를 독립적으로 진단할 수 있습니다.

라이선스 입력란은 비밀번호 필드로 취급하지 않고 일반 텍스트 입력으로 사용합니다. 브라우저 비밀번호 관리자 대상이 되지 않도록 autocomplete 및 주요 password-manager ignore 속성을 적용합니다.

### 7.8 진단 파일

```text
SettingsPage의 기존 system snapshot
  → wifi_summary와 safeshield.status 병렬 호출
  → fulfilled 결과만 사용
  → 실패 섹션은 unavailable 기본값
  → 비밀 정보가 없는 JSON 다운로드
```

### 7.9 Health Reporter

```text
5분 로컬 진단
  → health.json atomic write
  → 유료/Trial + reporter_enabled=1 여부 확인
      ├─ OFF / 미대상: 서버 요청 없음
      └─ ON / 대상
          ├─ 30분 heartbeat
          ├─ 이상 fingerprint 변경 즉시 보고
          └─ 실패 시 5분 backoff
              → license_get (일시 인증)
              → privacy whitelist payload
              → POST /api/v1/health/reports
```

Health Reporter가 서버 인증 헤더를 만들 때 사용하는 `safeshield.license_get` 응답은 `license.key`에 평문 키를 담는 중첩 구조를 사용합니다. Reporter는 이 실제 계약을 우선 읽고, 과거 개발 빌드의 최상위 `key`는 호환 fallback으로만 처리합니다. 키는 상태 파일이나 보고 payload에 저장하지 않습니다.

Hub 수신 API는 라이선스/Trial eligibility를 서버에서도 독립적으로 검증해야 합니다. 공유기의 클라이언트 측 gating은 서버 권한 검사를 대신하지 않습니다.

### 7.10 다크 테마 상태 패널

대시보드 장치 진단은 Tailwind의 반투명 상태 배경(`bg-emerald-50/70`, `bg-amber-50/70`, `bg-rose-50/70`)과 세부 카드(`bg-white/70`, `border-white/80`)를 사용합니다. Shadow DOM 안의 `.ssh-app[data-theme='dark']` 테마 레이어가 이 유틸리티를 어두운 상태색과 slate 계열로 명시적으로 재매핑해 라이트 테마용 밝은 반투명 배경이 다크 모드에 그대로 남지 않도록 합니다.

### 7.11 프런트엔드 자산 갱신

```text
PKG_VERSION + PKG_RELEASE
  → data-asset-version = 0.2.16-r5
  → app.js?v=0.2.16-r5
  → app.css?v=0.2.16-r5
```

통합 진입 템플릿은 패키지 릴리스를 정적 자산 query version으로 사용합니다. 로그인과 제품 화면은 동일한 `app.js` / `app.css`를 재사용하며, Shadow DOM의 stylesheet URL도 host의 `data-asset-version`을 따릅니다.

## 8. 보안과 안정성

### 8.1 권한 경계

- 브라우저는 LuCI session ID를 사용합니다.
- 모든 원격 호출은 `/admin/ubus`를 통과합니다.
- ACL에 등록하지 않은 메서드는 호출할 수 없습니다.
- 읽기와 쓰기 메서드를 분리합니다.
- 평문 라이선스 키를 반환하는 `license_get`은 일반 read ACL과 분리합니다. 브라우저에서는 사용자 명시 동작에서만 호출하고, opt-in된 Health Reporter daemon에서는 실제 서버 보고의 인증 순간에만 일시 사용합니다.
- 진단 파일은 비밀번호와 라이선스 키를 요청하거나 저장하지 않습니다.
- 진단 파일에 포함될 수 있는 호스트명, WAN IPv4와 Wi-Fi SSID를 사용자에게 사전 안내합니다.
- Health Reporter payload는 별도 whitelist builder를 사용하며 네트워크 식별 정보, DNS 요청 내용, 로그 원문과 라이선스 키를 포함하지 않습니다.
- Health Reporter는 기본 OFF이고 유료/Trial 사용자도 직접 opt-in해야 하며 OFF 이후 자동 보고 요청을 보내지 않습니다.

### 8.2 입력 검증

- Wi-Fi section과 device가 실제 AP인지 확인
- 새 비밀번호뿐 아니라 재사용할 기존 키도 대상 WPA 보안 방식에 맞는지 확인
- SmartSafeHub 관리 대상 AP만 변경
- SSID, 보안 방식, 비밀번호와 bool 타입 검증
- 재부팅 확인 문자열 검증
- SafeShield 도메인은 프런트엔드에서 1차 형식 검증하고 최종 규칙 검증과 제한은 SafeShield API가 담당
- 규칙 파일 크기와 개수 제한은 SafeShield 엔진이 담당

### 8.3 실패 격리

- 연결 기기 데이터 소스 하나가 실패해도 전체 목록 조회 유지
- WAN 인터페이스를 읽지 못해도 장치와 런타임 상태 반환
- SafeShield API가 없으면 사용 불가 상태로 정규화
- 진단 상세 조회 하나가 실패해도 JSON 다운로드 유지
- Health Reporter 전송 실패는 로컬 진단을 실패시키지 않고 5분 backoff 후 재시도
- Wi-Fi 적용 실패 시 원래 UCI 설정 복원 시도
- SafeShield 갱신과 규칙 변경에 별도 lock 사용
- Wi-Fi 변경에도 별도 lock을 사용해 여러 탭의 동시 commit과 reload 방지
- deferred ubus 요청 시작 실패를 명시적인 애플리케이션 오류로 변환

### 8.4 요청량 제어

- 동일 loader 중복 실행 방지
- 완료 기반 폴링으로 요청 중첩 방지
- 숨겨진 탭에서 폴링 중단
- station 정보가 있을 때 hostapd 중복 조회 생략
- 시스템 진단에서 이미 로드된 상태 재사용
- Health Reporter heartbeat는 30분 간격, 상태 변경은 fingerprint 변화 시 한 번만 즉시 보고
- 비활성 화면은 폴링하지 않고 재진입 시 최신 상태 조회
- 모든 RPC에 제한 시간을 둬 영구 대기와 single-flight 고착 방지

## 9. 빌드와 검증

### 9.1 프런트엔드 검사

프런트엔드는 문자열 기반 계약 검사 대신 TypeScript와 Vite 자체 검증에 의존합니다.

```bash
cd frontend
npm ci
npm run typecheck
npm run build
```

`npm run build`는 TypeScript 검사를 통과한 뒤 `frontend/src/main.tsx`를 직접 production entry로 사용해 `root/www/luci-static/smartsafehub/`에 `app.js`와 `app.css`를 생성합니다. Vite HTML entry를 사용하지 않으므로 배포용 `index.html`은 생성하지 않습니다. 프런트엔드 변경 시 생성된 `app.js`와 `app.css`도 함께 갱신합니다.

### 9.2 OpenWrt 패키지 빌드

Makefile에는 별도의 `Build/Prepare` 검증 hook을 두지 않습니다. 패키지는 `luci.mk`의 기본 흐름으로 구성합니다.

```bash
make package/luci-app-smartsafehub/clean
make package/luci-app-smartsafehub/compile V=s
```

### 9.3 실제 장치 검사

정적 검사는 ucode parser와 실제 rpcd 런타임 전체를 대신하지 않습니다.

```bash
ucode -c \
  -o /tmp/smartsafehub/smartsafehub.ucb \
  /usr/share/rpcd/ucode/smartsafehub.uc

/etc/init.d/rpcd restart
ubus -v list smartsafehub
ubus call smartsafehub status '{}'
ubus call smartsafehub wifi_summary '{}'
ubus call smartsafehub connected_devices '{}'
```

브라우저에서는 진단 JSON 다운로드를 포함한 각 화면의 동작을 별도로 확인합니다.

## 10. 확장 원칙

1. `smartsafehub.uc`에는 기능 구현을 넣지 않고 RPC 등록만 추가합니다.
2. 여러 기능에서 실제로 공유하는 처리만 `core.uc`에 배치합니다.
3. 읽기 전용 도메인 로직과 변경 작업을 가능한 한 분리합니다.
4. ucode named import 마지막 항목에는 쉼표를 넣지 않습니다.
5. exported function은 반드시 `};`로 종료합니다.
6. 새 RPC를 추가하면 ACL, 프런트엔드 API와 타입을 함께 수정합니다.
7. 프런트엔드 페이지는 직접 JSON-RPC를 호출하지 않고 hook과 API 계층을 사용합니다.
8. 독립된 선택적 조회는 병렬 실행하되 부분 실패를 명시적으로 처리합니다.
9. 폴링 기능은 중복 요청과 숨겨진 탭을 고려해야 합니다.
10. 프런트엔드 소스를 변경하면 `npm run build`로 배포 산출물을 갱신합니다.
11. 패키지 릴리스를 변경하면 통합 진입 템플릿의 `data-asset-version`과 `app.js?v=`도 함께 변경합니다.
12. 배포 전 TypeScript 검사, 프런트엔드 빌드, OpenWrt 패키지 빌드와 실제 ubus 호출을 확인합니다.

## 11. 현재 제약

- Wi-Fi 화면은 각 radio에서 선택한 기본 LAN AP 하나만 관리합니다.
- WAN 상태는 `network.interface.wan` 객체를 기준으로 합니다.
- SafeShield 기능은 별도 `safeshield` 패키지와 공식 ubus API 계약에 의존하며 내부 파일·init script에는 직접 의존하지 않습니다.
- 진단 다운로드 파일은 현재 시점의 상세 snapshot이며 장기간의 로그 수집 기능은 아닙니다. Health Reporter는 별도의 최소 상태 payload만 주기적으로 전송합니다.
- 현재 저장소에는 Hub의 `/api/v1/health/reports` 수신 구현이 포함되어 있지 않으므로 실제 원격 저장/이력 조회 기능은 Hub backend의 대응 API가 함께 배포되어야 합니다.
- 프런트엔드 개발 서버만으로는 LuCI ACL과 실제 ubus 동작을 완전히 재현할 수 없습니다.
- ucode module 문법은 JavaScript·TypeScript와 차이가 있으므로 실제 `ucode -c` 검사가 필요합니다.

## 12. SmartSafeHub 패키지 업데이트

SmartSafeHub의 휘발성 런타임 파일은 `/tmp/smartsafehub/` 한 단계 아래에 통합합니다. 업데이트, 펌웨어, Health 진단/Reporter, 예약 재부팅, LAN/Wi-Fi 변경 lock, 설정 백업 업로드가 같은 제품 전용 디렉터리를 사용하며 기능별 추가 하위 디렉터리는 두지 않습니다. init script와 helper가 `/tmp` 초기화 이후 디렉터리 존재를 보장합니다.

업데이트 기능은 rpcd와 실제 APK 작업을 분리합니다. `updates_check`와 `updates_install`은 요청을 검증한 뒤 `/usr/libexec/smartsafehub-updater`를 백그라운드에서 시작하고 즉시 반환합니다. updater는 `apk update`와 패키지 조회·설치를 수행하고 `/tmp/smartsafehub/updates.state`에 결과를 atomic write합니다. `updates_status`는 이 로컬 상태 파일과 UCI 설정만 읽으므로 저장소 응답 속도가 제품 UI API에 영향을 주지 않습니다.

업데이트 감지 대상은 `luci-app-smartsafehub` 하나입니다. 새 버전이 확인되면 `apk add --upgrade luci-app-smartsafehub`만 실행합니다. Makefile은 `LUCI_DEPENDS:=... +safeshield`와 `LUCI_EXTRA_DEPENDS:=safeshield (>=0.3.23)`를 함께 선언합니다. 따라서 빌드 시 SafeShield 선택 관계를 유지하면서, 설치·업데이트 시 APK dependency resolver가 최소 `0.3.23` 조건을 만족하도록 필요한 경우 SafeShield를 함께 갱신합니다.

새 버전이 있으면 updater는 SmartSafeHub 전용 `/etc/apk/repositories.d/smartsafehub.list`의 APK repository URL에서 `https://repo.smartsafehub.com/<channel>` base를 유도하고 먼저 `releases/luci-app-smartsafehub/index.json`을 조회합니다. 다른 repository 파일은 release channel 결정에 사용하지 않습니다. index의 newest-first 순서를 이용해 현재 설치 버전 이후부터 APK가 제시한 최신 버전까지의 `<version>.json`만 내려받고 `/tmp/smartsafehub/release-notes.json` 하나의 bundle로 atomic cache합니다. rpcd는 bundle의 설치/최신 버전 범위, 각 릴리즈의 schema·package·version과 크기 제한을 검증한 뒤 `updates_status.releaseNotes`와 `releaseNotesComplete`로 노출합니다. index 또는 일부 릴리즈 노트를 가져오지 못한 경우에도 가능한 노트만 표시하며, 이 메타데이터는 signed APK metadata를 대체하지 않는 표시용 보조 정보이므로 다운로드·파싱 실패는 update check/install 결과에 영향을 주지 않습니다.

자동화 설정은 `/etc/config/smartsafehub`의 `updates` section에 보존됩니다. `smartsafehub-updater` procd 서비스는 기본 6시간 주기로 확인하며, 자동 설치는 기본 비활성화 상태입니다. 자동 설치를 활성화하면 지정 시각의 다음 실행 기회에 하루 한 번만 설치를 시도합니다. 공유기가 예약 시각 이후에 부팅된 경우 그날의 지난 예약을 즉시 소급 실행하지 않고 다음 예약 시각까지 기다립니다.

### LAN 입력 UX 안전장치

LAN 화면은 공유기 IPv4 주소를 4개 octet으로 분리해 입력받고, DHCP 시작/종료 주소는 공유기 주소의 앞 3개 octet을 읽기 전용 prefix로 사용한다. 공유기 prefix가 바뀌면 DHCP host octet은 유지하면서 같은 prefix로 동기화한다. 이 프런트엔드 제약은 사용자 입력 오류를 줄이기 위한 것이며, 최종 subnet·DHCP 범위 검증은 계속 `network-management.uc` backend가 담당한다.


### Hash route 새로고침 보존

SmartSafeHub는 현재 route를 별도 storage에 복제하지 않고 브라우저의 URL fragment를 직접 사용한다. uHTTPd exact-root handler가 `/`을 내부 rewrite하면 브라우저 navigation이 발생하지 않으므로 `/#settings`, `/#system` 같은 fragment는 일반 새로고침에서도 그대로 유지된다.

### License activation RPC 경계

`smartsafehub.license_activate`는 rpcd 실행 컨텍스트에서 `safeshield.status`를 다시 동기 호출하지 않습니다. RPC는 mode 0600 request 파일에 라이선스 키만 기록하고 detached `smartsafehub-license activate` helper를 시작한 뒤 즉시 반환합니다. helper가 별도 프로세스에서 SafeShield authoritative device identity/profile을 읽고 Hub `/api/v1/licenses/activate`를 호출하며, 성공한 경우에만 SafeShield `license_update`로 로컬 키를 저장합니다. 이 경계는 rpcd nested ubus 대기를 피하고 향후 `smartsafehub-agent license activate`로 이동할 때도 그대로 유지합니다.

프런트엔드는 activation 상태를 1초 간격으로 확인하되 `license_status` RPC timeout을 5초로 제한하고 일시적인 timeout/네트워크 오류를 최대 2회 재시도합니다. 라이선스 관련 진행/성공/오류 피드백은 작업 위치인 라이선스 카드 안에서 표시합니다.
