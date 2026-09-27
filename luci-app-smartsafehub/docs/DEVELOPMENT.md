# SmartSafeHub 개발 가이드

로컬 프런트엔드 개발, 저장소 구조, 빌드와 검증 절차를 정리합니다. 런타임 구조와 RPC 데이터 흐름은 [ARCHITECTURE.md](ARCHITECTURE.md), 실제 장치 설치와 운영 점검은 [OPERATIONS.md](OPERATIONS.md)를 참고하세요.

## 로컬 프런트엔드 개발

실제 공유기에 패키지를 반복 설치하지 않고 UI와 API 연동을 빠르게 확인하려면 Vite 개발 서버가 `/cgi-bin/*` 요청만 테스트 공유기로 프록시하도록 실행할 수 있습니다. 공유기 주소는 소스에 고정하지 않고 `SMARTSAFEHUB_DEV_ROUTER` 환경 변수로 지정합니다.

```bash
cd frontend
SMARTSAFEHUB_DEV_ROUTER=http://192.168.1.1 npm run dev
```

매번 환경 변수를 입력하고 싶지 않다면 `frontend/.env.example`을 참고해 Git에서 제외되는 `frontend/.env.local`을 만들 수 있습니다.

```dotenv
SMARTSAFEHUB_DEV_ROUTER=http://192.168.1.1
```

이 경우에는 `frontend` 디렉터리에서 `npm run dev`만 실행하면 됩니다. 브라우저에서는 Vite가 출력한 `http://localhost:5173/` 주소로 접속합니다. 프론트엔드 소스와 Shadow DOM용 Tailwind CSS는 로컬 Vite 서버에서 제공하고, `/cgi-bin/luci/...` RPC·세션 요청과 `/cgi-bin/cgi-upload` 업로드 요청은 실제 공유기로 전달합니다. `https://` 장치를 지정했을 때 개발용 자체 서명 인증서도 사용할 수 있도록 proxy의 TLS 검증은 개발 환경에서만 비활성화합니다.

로컬 SmartSafeHub 화면은 LuCI 세션 API가 필요하므로 `SMARTSAFEHUB_DEV_ROUTER`가 없으면 Vite 개발 서버가 즉시 오류를 내고 시작하지 않습니다. 이렇게 해서 proxy가 비활성화된 채 `/cgi-bin/luci/smartsafehub/session` 요청이 localhost의 Vite 서버로 들어가 404가 되는 상태를 방지합니다. 환경 변수에는 `http://` 또는 `https://`를 포함한 절대 URL을 사용해야 합니다. 이 값은 `npm run dev`처럼 Vite가 `serve` 모드일 때만 읽고 검증하며, production `vite build`에서는 환경 변수가 존재하거나 잘못된 값이어도 읽지 않습니다. 개발 proxy와 Vite `server` 설정도 production build 설정에는 포함되지 않으므로 기존 `/luci-static/smartsafehub/` asset base와 OpenWrt 런타임 동작은 유지됩니다. 펌웨어 설치, Wi-Fi reload, 재부팅, uHTTPd root rewrite처럼 장치 런타임 자체가 관여하는 기능은 최종적으로 실제 패키지를 설치한 공유기에서 확인합니다.

Tailwind CSS v4는 border, ring/shadow, transform 등의 내부 기본값을 `@property`로 등록하지만 현재 브라우저의 ShadowRoot 안에서는 해당 등록이 안정적으로 적용되지 않습니다. SmartSafeHub는 UI 전체를 Shadow DOM에 격리하므로 `frontend/src/styles/app.css`의 가장 낮은 `properties` layer에서 Tailwind 자체 fallback과 같은 custom property 기본값을 명시합니다. 이 fallback을 제거하면 로컬 Vite에서는 정상이어도 실제 공유기 production asset에서 `border-r`가 `border-style: none`으로 계산되는 등 환경별 차이가 다시 발생할 수 있습니다. 관련 Tailwind 이슈는 `tailwindlabs/tailwindcss#15005`와 그 duplicate인 `#16025`입니다.

## 지원 환경과 의존성

OpenWrt 패키지 의존성은 Makefile에 다음과 같이 선언합니다.

```text
luci-base
rpcd-mod-ucode
ucode
ucode-mod-ubus
ucode-mod-fs
ucode-mod-uci
procd
uclient-fetch
jsonfilter
igmpproxy
safeshield (>= 0.3.24)
```

`LUCI_DEPENDS`의 `+igmpproxy`는 IPTV Beta의 멀티캐스트 proxy runtime을 함께 설치하고, `+safeshield`는 빌드 시 SafeShield 패키지 선택 관계를 유지합니다. `LUCI_EXTRA_DEPENDS:=safeshield (>=0.3.24)`는 설치·업데이트 시 필요한 최소 SafeShield 버전을 강제합니다.

프런트엔드 빌드에는 **Node.js 24 이상**이 필요합니다.

```bash
node --version
npm --version
```

## 저장소 구조

```text
luci-app-smartsafehub/
├── Makefile
├── README.md
├── CHANGELOG.md
├── docs/
│   └── ARCHITECTURE.md
├── frontend/
│   ├── index.html          # Vite 개발 서버용 shell (배포 입력 아님)
│   ├── src/
│   │   ├── api/
│   │   ├── app/
│   │   ├── auth/
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── login/
│   │   ├── pages/            # IPTV Beta 포함
│   │   ├── styles/
│   │   ├── types/
│   │   └── utils/
│   ├── package.json
│   └── vite.config.ts
├── root/
│   ├── etc/config/smartsafehub
│   ├── etc/init.d/smartsafehub-events
│   ├── etc/init.d/smartsafehub-updater
│   ├── etc/init.d/smartsafehub-firmware
│   ├── etc/init.d/smartsafehub-health
│   ├── etc/init.d/smartsafehub-license
│   ├── etc/init.d/smartsafehub-maintenance
│   ├── usr/libexec/smartsafehub-events
│   ├── usr/libexec/smartsafehub-updater
│   ├── usr/libexec/smartsafehub-firmware
│   ├── usr/libexec/smartsafehub-health
│   ├── usr/libexec/smartsafehub-license
│   ├── usr/libexec/smartsafehub-maintenance
│   ├── usr/libexec/smartsafehub-backup
│   ├── usr/share/luci/menu.d/
│   ├── usr/share/rpcd/acl.d/
│   ├── usr/share/rpcd/ucode/
│   │   ├── smartsafehub.uc
│   │   └── smartsafehub/
│   │       ├── core.uc
│   │       ├── security.uc
│   │       ├── backup.uc
│   │       ├── devices.uc
│   │       ├── system.uc
│   │       ├── firmware.uc
│   │       ├── updates.uc
│   │       ├── license.uc
│   │       ├── network-management.uc
│   │       ├── wifi-management.uc
│   │       └── wifi.uc
│   └── www/luci-static/smartsafehub/
│       ├── app.js
│       └── app.css
```

`root/www/luci-static/smartsafehub/app.js`와 `app.css`는 Vite가 만드는 배포 산출물입니다. production build는 `frontend/src/main.tsx`를 직접 entry로 사용하므로 배포 디렉터리에 `index.html`을 생성하지 않습니다. `frontend/index.html`은 Vite 개발 서버에서만 사용하는 shell입니다. 프런트엔드 소스를 수정한 뒤 반드시 다시 빌드해야 합니다.

## 프런트엔드 개발

### 의존성 설치

```bash
cd frontend
npm ci
```

### LAN/DHCP 주소 입력 안전장치

LAN 설정 화면은 공유기 IPv4 주소를 4개의 octet 입력으로 분리해 받습니다. DHCP 시작/종료 주소는 공유기 주소의 앞 3개 octet을 고정해서 표시하고 마지막 octet만 수정할 수 있습니다. 공유기 주소의 앞 3개 octet을 변경하면 DHCP 범위도 같은 prefix로 즉시 동기화되어 서로 다른 대역을 실수로 저장하는 가능성을 줄입니다. 실제 저장 시에는 backend의 subnet/DHCP 범위 검증도 그대로 적용됩니다.

## 개발 서버

```bash
npm run dev
```

Vite 개발 서버는 컴포넌트 작업에 사용할 수 있지만 실제 LuCI 세션, ACL과 ubus 호출은 OpenWrt 장치에서 확인해야 합니다.

### 정적 검사

```bash
npm run typecheck
```

### 배포 빌드

```bash
npm run build
```

빌드 결과는 다음 위치에 생성됩니다.

```text
root/www/luci-static/smartsafehub/app.js
root/www/luci-static/smartsafehub/app.css
```

`npm run build`는 TypeScript 검사를 통과한 뒤 `frontend/src/main.tsx`를 production entry로 사용해 Vite 배포 자산을 생성합니다. HTML entry를 사용하지 않으므로 `root/www/luci-static/smartsafehub/index.html`은 생성되지 않습니다. 프런트엔드 소스를 변경한 경우 갱신된 `app.js`와 `app.css`도 함께 커밋합니다.

## OpenWrt 패키지 빌드

패키지를 OpenWrt 소스 트리의 `package/luci-app-smartsafehub` 또는 사용하는 feed에 배치한 뒤 실행합니다.

```bash
make package/luci-app-smartsafehub/clean
make package/luci-app-smartsafehub/compile V=s
```

별도의 `Build/Prepare` 검증 hook은 사용하지 않습니다. OpenWrt 패키지 빌드는 `luci.mk`의 기본 패키징 흐름을 사용하며, 프런트엔드 자산은 패키지 빌드 전에 `npm run build`로 갱신합니다.

별도의 프런트엔드 build ID는 사용하지 않습니다. JavaScript와 CSS 캐시 무효화 키는 현재 `Makefile`의 `PKG_VERSION`과 `PKG_RELEASE`를 기준으로 관리합니다. README에는 특정 릴리스 버전을 고정해서 기록하지 않습니다.

## ucode 컴파일 검사

`smartsafehub` ubus 객체가 등록되지 않으면 진입점을 직접 컴파일합니다.

```bash
mkdir -p /tmp/smartsafehub
rm -f /tmp/smartsafehub/smartsafehub.ucb
ucode -c \
  -o /tmp/smartsafehub/smartsafehub.ucb \
  /usr/share/rpcd/ucode/smartsafehub.uc

echo "main compile exit=$?"

ucode -c \
  -o /tmp/smartsafehub/smartsafehub-network.ucb \
  /usr/share/rpcd/ucode/smartsafehub-network.uc

echo "lan compile exit=$?"
```

공개 `smartsafehub.uc`는 LAN 구현 모듈을 직접 import하지 않습니다. 따라서 LAN 전용 진입점의 컴파일/로드 오류가 기존 관리자 보안 상태 확인과 대시보드 진입까지 중단시키지 않아야 합니다.

정상 결과는 `main compile exit=0`, `lan compile exit=0`입니다. 실패하면 출력되는 모듈 파일과 줄 번호를 먼저 수정합니다. SmartSafeHub의 ucode 모듈에서 `export function` 선언은 일반 내부 함수와 달리 기존 모듈들과 동일하게 함수 본문 뒤를 `};`로 종료해야 합니다. `}`만 사용하면 다음 `export` 또는 파일 끝에서 `Expecting ';'` 컴파일 오류가 발생해 해당 ubus 객체가 등록되지 않습니다.

같은 종류의 문법 오류를 장치 설치 이후에 발견하지 않도록 Backend CI에서는 실제 ucode 컴파일을 필수 계약으로 실행합니다. CI는 OpenWrt 25.12에서 사용하는 ucode `2026.01.16~85922056` 계열의 source revision `8592205`를 host용으로 빌드한 뒤 `tests/test-ucode-syntax.sh`를 실행합니다. 이 테스트는 `smartsafehub.uc`, `smartsafehub-network.uc` 같은 모든 rpcd 최상위 진입점을 실제 `ucode -c`로 컴파일하므로 상대 import를 따라가는 과정에서 feature module의 문법 오류도 함께 잡습니다.

또한 `smartsafehub/` 아래의 모든 `.uc` 파일을 합성 모듈에서 직접 import해 현재 어느 진입점에서도 사용하지 않는 모듈까지 컴파일합니다. host compiler에는 OpenWrt 전용 `ubus`/`uci` 모듈이 없기 때문에 테스트 중 최소 stub을 module search path에 넣지만, 이 stub은 외부 모듈 이름 해석만 담당하며 SmartSafeHub 소스 자체와 상대 import는 실제 ucode parser/compiler가 검사합니다. 과거에 발생한 `export function ... }` 형태도 별도 negative regression으로 컴파일이 거부되는지 확인합니다.

로컬에 `ucode`가 설치되어 있으면 다음 명령으로 CI와 같은 소스 검사를 강제할 수 있습니다. `SMARTSAFEHUB_REQUIRE_UCODE=1`에서는 compiler가 없으면 skip하지 않고 실패합니다.

```bash
SMARTSAFEHUB_REQUIRE_UCODE=1 sh tests/test-ucode-syntax.sh
```

일반 로컬 ShellSpec 실행에서는 ucode가 설치되지 않은 환경의 개발 흐름을 막지 않기 위해 해당 검사만 skip할 수 있지만, GitHub Actions Backend job은 `SMARTSAFEHUB_REQUIRE_UCODE=1`을 고정하므로 실제 컴파일 없이 성공할 수 없습니다.

실제 ucode 컴파일은 `tests/test-ucode-syntax.sh`에서만 수행합니다. GitHub Actions에서 빌드한 host ucode에는 OpenWrt 런타임 전용 `ubus`, `uci`, `fs` 모듈이 포함되지 않으므로 `test-lan-settings.sh` 같은 기능별 계약 테스트에서 raw `ucode -c`를 직접 실행하면 정상 소스도 외부 모듈 import 해석 단계에서 실패할 수 있습니다. 전용 문법 테스트가 최소 stub과 module search path를 구성하고, 기능별 테스트는 소스 구조와 동작 계약만 검증하도록 역할을 분리합니다. 정적 검증은 이 원칙을 위반하는 raw compile 호출이 다른 테스트에 다시 추가되는 것도 차단합니다.

LAN 설정은 문법 검사만으로 실제 OpenWrt UCI 값의 타입 차이를 검출할 수 없으므로 `tests/test-lan-uci-runtime.sh`에서 별도 런타임 회귀 검사를 수행합니다. 이 테스트는 실제 장치에서 확인된 OpenWrt 25.12 형식인 `network.lan.ipaddr = [ "192.168.1.1/24" ]` fixture와 DHCP `start=100`, `limit=150`을 stub UCI cursor로 제공하고 실제 `network-management.uc`의 `read_lan_settings()`와 동일값 update를 실행합니다. CI에서는 주소가 `192.168.1.1/24`, DHCP 범위가 `192.168.1.100~249`로 해석되고 동일 설정이 `changed=false`로 판정되는지까지 확인합니다.

LAN 컴파일이 성공한 뒤에는 다음 명령으로 실제 객체와 메서드 등록을 확인합니다.

```bash
/etc/init.d/rpcd restart
sleep 2
ubus -v list smartsafehub_network
ubus call smartsafehub_network lan_settings '{}'
```

기존 핵심 RPC도 함께 확인하려면 다음을 실행합니다.

```bash
/etc/init.d/rpcd restart
sleep 2

logread | grep -Ei 'rpcd|ucode|smartsafehub' | tail -200
ubus -v list smartsafehub
```

## 배포 전 체크리스트

셸 계약 테스트는 stdout의 `PASS:`뿐 아니라 stderr가 비어 있는지도 확인합니다. ACL을 `jq`로 검증할 때 여러 배열을 `or`로 비교하는 식은 각 파이프 표현식을 괄호로 분리해, 파이프의 중간 배열이 다음 ACL 경로의 입력으로 전달되지 않도록 유지합니다.

Health 계약 테스트의 mock 환경은 각 시나리오를 subshell에서 실행하고 기본값을 매번 다시 설정합니다. macOS `/bin/sh`와 Linux `dash`처럼 함수 호출 앞 `VAR=value` 임시 대입의 복원 동작 차이가 다음 시나리오의 SafeShield/license mock 상태로 전파되지 않도록 하기 위한 테스트 격리 규칙입니다.

```bash
sh tests/test-lan-settings.sh
SMARTSAFEHUB_REQUIRE_UCODE=1 sh tests/test-ucode-syntax.sh
shellspec spec/contracts_spec.sh
```

```bash
cd frontend
npm ci
npm run typecheck
npm run build
cd ..
```

OpenWrt buildroot에서:

```bash
make package/luci-app-smartsafehub/clean
make package/luci-app-smartsafehub/compile V=s
```

실제 장치에서:

```bash
mkdir -p /tmp/smartsafehub
ucode -c -o /tmp/smartsafehub/smartsafehub.ucb /usr/share/rpcd/ucode/smartsafehub.uc
/etc/init.d/rpcd restart
ubus -v list smartsafehub
ubus call smartsafehub status '{}'
ubus call smartsafehub wifi_summary '{}'
ubus call smartsafehub connected_devices '{}'
ubus call smartsafehub system_time_settings '{}'
```

브라우저에서는 root 비밀번호가 없는 초기 상태의 강제 비밀번호 설정·재로그인, 홈, Wi-Fi 조회·변경, Wi-Fi reload 뒤 상태 재조회, 연결 기기, SafeShield 상태·갱신, 사용자 규칙, 진단 다운로드, 시간대 조회·변경과 현재 시간 표시, 메뉴 재진입 데이터 갱신, 다른 LuCI 화면 이동 뒤 폴링 종료, 자산 로드 실패 화면, 설정 메뉴의 LuCI 보조 진입점과 모바일 메뉴를 확인합니다. 재부팅과 실제 시간대 변경은 테스트 장치에서만 실행합니다.

생성된 `app.js` 계약 테스트는 minify 과정에서 변경될 수 있는 TypeScript 식별자 이름에 의존하지 않고, 사용자 동작에 필요한 값과 결과물이 실제 번들에 포함되었는지를 검증합니다.

## 버전 관리 원칙

- 사용자 기능 버전은 `PKG_VERSION`으로 관리합니다.
- 같은 기능 버전의 정식 배포 후 패키지 수정은 `PKG_RELEASE`를 올립니다.
- 정식 배포 전 개발 과정에서 사용한 임시 package revision은 배포 기준점에서 `r1`로 squash할 수 있으며, `CHANGELOG.md`에는 중간 revision을 별도 릴리스로 남기지 않습니다.
- `frontend/package.json`과 `frontend/package-lock.json`의 버전은 `PKG_VERSION`과 맞춥니다.
- 통합 진입 템플릿의 `data-asset-version`과 `app.js?v=` 버전은 `PKG_VERSION-rPKG_RELEASE`와 맞춥니다.
- 프런트엔드 build ID 상수는 별도로 두지 않습니다.
- 정식 배포 이력은 `CHANGELOG.md`에 기록합니다.
- README에는 현재 SmartSafeHub 릴리스 버전을 직접 기록하지 않습니다. 최신 버전은 `Makefile`과 배포 저장소를 기준으로 확인합니다.

현재 소스 트리의 패키지 버전은 다음 명령으로 확인할 수 있습니다.

```bash
awk -F':=' '
  /^PKG_VERSION:=/ { version=$2 }
  /^PKG_RELEASE:=/ { release=$2 }
  END { printf "%s-r%s\\n", version, release }
' Makefile
```

설치된 장치에서는 다음 명령으로 실제 설치 버전을 확인합니다.

```bash
apk info luci-app-smartsafehub
```
