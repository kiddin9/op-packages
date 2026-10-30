# SmartSafeHub Apps — 공유기 웹사이트

## 메뉴 및 아키텍처

- `System` 영역: `SmartSafeHub 계정 → Apps → 업데이트 → 설정` / 해시 URL `#apps`.
- 앱 목록: `smartsafehub.apps_catalog` RPC → `/usr/libexec/smartsafehub-apps` → Hub 승인 카탈로그.
- 설치 상태: `smartsafehub.apps_status` RPC → 독립된 `smartsafehub-apps-manager`의 로컬 APK 상태와 설치 기록.
- 앱 설치 저장 공간과 설치된 APK의 용량은 별도 `smartsafehub.apps_metrics` 읽기 RPC로 조회합니다. LuCI ACL의 `read.ubus.smartsafehub`에도 `apps_metrics`가 있어야 합니다. 실패하더라도 설치·제거 상태에는 영향을 주지 않습니다.
- 설치된 버전은 `apk list -I`에서 조회한 대표 승인 APK의 실제 설치 버전입니다. Wake-on-LAN은 백엔드 `etherwake`가 아닌 `luci-app-wol` 버전을 표시합니다. 카탈로그의 `version`은 현재 **제공/승인된 앱 버전**이므로 둘을 구분해 표시합니다. 복수 APK 앱은 대표 패키지 버전이 앱 릴리스 버전과 다를 수 있습니다.
- 설치·업데이트·제거: `smartsafehub.apps_install`, `smartsafehub.apps_update`, `smartsafehub.apps_remove` RPC. 앱 ID만 받으며, 실제 작업은 root 전용 백그라운드 매니저에서 진행합니다. 다른 앱 작업이 진행 중이면 거절합니다.
- Phase 2의 IoT/로컬 AI 설치기는 추후 `runtime`에 따라 별도 어댑터로 추가합니다. 현재는 `router + apk`만 가능하며 Hub의 패키지명·URL·명령을 브라우저가 보낼 수 없습니다.

## 앱 카테고리 아이콘

- **네트워크**: 연결된 노드 아이콘 / **도구**(`utilities`): 렌치 아이콘 / **기타**(`other`): 원 안의 점 3개 아이콘.
- 분류되지 않은 앱은 기타로 묶고, 같은 아이콘을 실제 공유기와 읽기 전용 체험 화면에서 사용합니다. 앱 설치·승인 정보와 정렬 순서는 변경하지 않습니다.

## 설치를 활성화하기 위한 **필수 운영 조건**

현재 버전은 APK 엔진까지 구현했지만 **아무 OpenWrt 미러에서나 바로 설치하지 않습니다.**

1. Hub에 `store.patch`의 앱 카탈로그가 배포되고 펌웨어가 `device_code`와 `build_id`로 등록되어 있어야 합니다.
2. 관리자 승인이 특정 펌웨어 빌드, 채널, 패키지 아키텍처 및 **정확한 APK 버전과 SHA-256**에 대해 완료되어야 합니다.
3. 공유기에는 OpenWrt 공식 패키지 관리자(`apk`)와 필요한 시스템 의존성이 설치되어 있어야 합니다. SmartSafeHub가 사용하는 APK 서명 공개 키도 신뢰 저장소에 등록되어 있어야 합니다.
4. 설치기는 고정된 릴리스 ID, 승인된 채널(`beta`/`stable`)과 공유기 아키텍처로 `https://repo.smartsafehub.com/<채널>/packages/<아키텍처>/smartsafehub/<릴리스 ID>/packages.adb`를 조회합니다. 이 인덱스를 새로 다운로드한 뒤 Hub 승인 SHA-256과 비교합니다. 펌웨어에 별도 인덱스 파일을 복사할 필요가 없습니다.
5. 실제 APK는 위 고정 도메인/경로에서 이름과 버전으로만 내려받아 SHA-256을 검증합니다. 임의 URL 입력이나 `--allow-untrusted`는 허용되지 않습니다.
6. `apk`, `sha256sum`, `start-stop-daemon`, `jsonfilter`, `uclient-fetch`가 공유기에 있어야 하며 RAM/overlay 용량이 충분해야 합니다.

**주의:** 모든 승인은 고정된 SmartSafeHub 릴리스에서 설치합니다. 릴리스 파일 또는 인덱스의 SHA-256이 승인값과 다르면 설치를 차단합니다.

**의존성 주의:** `nlbwmon`, `luci-app-nlbwmon`, `luci-lib-chartjs`는 동일한 SmartSafeHub 서명 저장소에서만 설치합니다. 이외의 의존성을 자동으로 가져오지 않으며, 새로운 커널 모듈·라이브러리는 별도 검증이 필요합니다.

OpenWrt 25.12의 패키지 인덱스는 `packages.adb` 형식일 수 있으며, 이전의 `APKINDEX.tar.gz` 형식이라고 가정하면 안 됩니다.

## Wake-on-LAN 앱 (0.2.30-r37)

- Hub에서 `wake-on-lan` 앱을 현재 펌웨어와 아키텍처에 승인하면 Apps에 표시됩니다. `utilities` 카테고리는 **도구** 탭에 표시합니다.
- 서명된 고정 릴리스에서 `etherwake`, `luci-app-wol` **두 APK만** 함께 설치합니다. 다른 경로로 설치된 패키지는 Apps가 자동으로 소유하지 않습니다.
- `luci-app-wol`까지 설치된 경우에만 **열기**를 표시하고, 새 탭에서 공유기의 `/cgi-bin/luci/admin/services/wol`로 이동합니다. LuCI 로그인을 추가로 요구할 수 있습니다.
- 지원되는 유선 컴퓨터의 BIOS/UEFI 및 운영체제에서 Wake-on-LAN 기능을 켜야 합니다. 원격 인터넷에서 임의로 전원을 켜는 기능이나 별도 포트 개방을 제공하지 않습니다.
- 패키지를 설치·제거하면 LuCI 메뉴 캐시를 갱신합니다. 공유기 체험 화면의 카드는 예시이며 실제 설치·신호 전송을 하지 않습니다.

## 설치된 앱 열기 (0.2.30-r9)

- 웹 화면을 제공하는 앱은 설치 후 `열기`로 **새 탭**에서 공식 LuCI UI를 표시합니다. SmartSafeHub 탭은 그대로 유지합니다.
- 웹 UI는 `web_ui: {"type":"luci","path":"/cgi-bin/luci/admin/…","package":"…"}`로 승인된 카탈로그에서 선언할 수 있습니다. 경로는 **같은 공유기의 LuCI 관리자 화면**으로 제한됩니다. 외부 사이트, 임의 포트, 실행 명령은 허용되지 않습니다.
- `network-usage-monitor`는 기존 카탈로그에도 `admin/services/nlbw/display` 경로를 사용할 수 있지만, **`luci-app-nlbwmon`이 설치되어 있어야만** 열기 버튼이 표시됩니다. `nlbwmon`만 설치된 공유기에는 `웹 UI 미설치`가 표시됩니다.
- 세 APK와 인덱스의 해시를 모두 확인하며, 설치 관리자는 승인된 릴리스 ID를 필수로 요구합니다.
- `luci-app-nlbwmon`은 OpenWrt LuCI 인증을 다시 요구할 수 있습니다.

## 동작과 제한

- 설치 시작 시 **Hub에서 승인 목록을 다시 조회**합니다. 인터넷이 끊겼거나 승인이 취소된 앱은 신규 설치가 불가능합니다.
- SmartSafeHub 저장소에서 승인된 인덱스와 APK를 내려받아 SHA-256을 확인합니다. 확인된 파일만 임시 로컬 저장소로 구성하며, APK의 서명 검증은 그대로 적용합니다.
- 모든 앱 APK는 SmartSafeHub가 빌드하고 서명한 하나의 불변 릴리스에서 설치합니다. `apk --simulate`는 저장소 인덱스를 자동 갱신하지 않으므로, 검증된 임시 로컬 저장소에 대해 `apk update`를 수행한 후 설치 계획을 검사하고 설치합니다. 승인되지 않은 패키지는 자동 설치하지 않습니다.
- `--allow-untrusted`, 전체 `apk upgrade`, 사용자 입력 셸 명령 및 공유기의 영구 저장소 설정 변경은 사용하지 않습니다. 임시 저장소는 검증된 파일로만 구성하며 작업 종료 시 삭제합니다.
- 핵심 시스템 패키지 및 SafeShield 관련 패키지는 앱 패키지 대상에서 제외합니다. 의존성 해석과 설치 스크립트 실행은 APK가 담당하므로, 앱마다 실제 환경 테스트가 필요합니다.
- `/etc/smartsafehub/apps-installed/<앱 ID>`에 **Apps가 직접 설치한 패키지 소유권**을 기록합니다. 기존 Software/SSH로 설치된 동일 패키지는 Apps에서 제거하지 않습니다.
- 테스트 기기의 이전 설치·승인 정보는 승계하지 않습니다. 새 승인으로 설치한 앱만 이 버전에서 관리합니다.
- 펌웨어 변경으로 앱 바이너리가 사라진 경우 소유권 기록과 새 펌웨어 승인에 따라 자동 복원하며, 조건이 일치하지 않으면 안전하게 중단합니다.
- 설치 작업 중 공유기를 재부팅하거나 전원을 끊지 말아야 합니다. APK 실패 후 트랜잭션의 수동 복구가 필요할 수 있으며 **완전한 자동 롤백은 제공하지 않습니다**.
- Apps에서 직접 설치한 앱은 새 펌웨어·기기 모델·아키텍처에 맞게 승인된 **더 높은 버전**이 나타날 때 `업데이트` 버튼을 표시합니다. 외부에서 설치한 앱은 업데이트하거나 자동 인수하지 않습니다.
- 사용자가 명시적으로 업데이트를 선택해야 하며, 업데이트 전 카탈로그와 서명된 불변 저장소·파일 해시를 다시 검증합니다.
- 앱별 APK의 **같은 패키지 집합**에서 버전만 올릴 수 있습니다. 패키지 추가·제거, 다운그레이드, 같은 버전의 해시 변경, 기존 설치 버전 불일치, 다른 패키지 변경을 요구하는 계획은 거부합니다.
- OpenWrt 전체 `apk upgrade`를 실행하지 않습니다. 기존 패키지를 대상으로 `apk add --upgrade`를 정확한 버전으로 한정하고 사전 계획을 검증합니다. OpenWrt는 펌웨어의 시스템 패키지를 무분별하게 업그레이드하는 것을 권장하지 않습니다.
- 업데이트가 성공해야 소유권 파일의 버전·해시를 교체합니다. 실패 시 원본 소유권 기록은 유지되며, 부분적으로 변경된 APK를 자동으로 롤백하지 않습니다. 이 경우 관리자 확인이 필요할 수 있습니다.
- 업데이트는 새로운 설치 성공 다운로드 통계에 포함하지 않습니다. 펌웨어 갱신 후 자동 복원은 기존대로 소유권 기록을 활용하며 업데이트를 자동 수행하지 않습니다.

## 장애 확인

- `E21`: 서버에서 새 카탈로그를 조회하지 못함 / `E22`: 승인 앱 없음 / `E23`, `E24`: 런타임 또는 기기 아키텍처 불일치.
- `E25`: SmartSafeHub 배포 인덱스 다운로드 실패 또는 SHA 불일치 / `E26`: 리소스 부족 / `E27`: 승인 패키지 정보 검증 실패.
- `E51`~`E55`: 소유권 없는 앱 업데이트, 승인 버전 불일치, 변경 범위 초과, APK 업데이트 또는 기록 저장 실패.
- `E29`: 기존 외부 설치 패키지 충돌 / `E31`~`E34`: 다운로드·해시·설치 시뮬레이션 실패 / `E35`: 설치 실패.
- `E41`: Apps가 설치한 앱이 아니라서 제거 불가 / `E44`, `E45`: 제거 시뮬레이션·실행 실패.
- `/tmp/smartsafehub/apps-operation.state`: 최근 작업 상태 및 코드 (재부팅 시 초기화).
- `/etc/smartsafehub/apps-installed/`: Apps가 설치한 패키지 소유권 기록 (설치 바이너리는 포함하지 않음).
- `apk` 작업 로그는 작업 후 임시 디렉터리에서 정리되며, 실패한 경우 최신 패키지 관리자 오류만 최대 4KB까지 `/tmp/smartsafehub/apps-last-error.log`에 보존합니다 (재부팅 시 초기화).

## 테스트

```sh
sh tests/test-apps-contract.sh
sh tests/test-apps-manager.sh
sh tests/test-apps-restore.sh
sh tests/test-apps-ui.sh
sh tests/test-ucode-imports.sh
# 개발 환경에서 (프론트엔드 빌드 결과는 패치 미포함)
cd frontend && npm ci && npm run typecheck && npm run build
```


## 펌웨어 업데이트 후 Apps 복원

- `sysupgrade`는 `/etc/smartsafehub/apps-installed/`의 **소유권 기록**을 보관합니다. APK 바이너리 자체는 새 펌웨어에 포함되지 않으면 사라질 수 있습니다.
- 기존 `smartsafehub-firmware` daemon이 부팅 시 **일회성 복원 스크립트**를 실행하여 누락된, SmartSafeHub가 관리한 앱만 복원합니다. 별도의 procd/init 서비스나 상시 실행 daemon은 추가하지 않습니다. 기록이 없거나 이미 설치되어 있으면 아무것도 설치하지 않습니다.
- 복원은 현재 펌웨어의 `device_code`·`build_id`에 일치하는 Hub 카탈로그를 새로 받아 기존 Apps manager의 **서명, SHA-256, 의존성 및 소유권 검사**를 통과해야 합니다. 지난 펌웨어의 승인이나 캐시된 카탈로그로 설치하지 않습니다.
- 네트워크 오류는 제한적으로 다시 시도합니다. 앱 승인이 철회되거나, APK 해시·SmartSafeHub 서명 인덱스·아키텍처·소유권 기록이 맞지 않으면 중단합니다. 다른 방법으로 설치된 패키지를 인수하지 않습니다.
- 공유기에서 `/tmp/smartsafehub/apps-restore.state`와 `logread -e smartsafehub-apps-restore`로 결과를 확인할 수 있습니다. 실패 시 Apps 화면의 **설치 마무리**로 다시 검증할 수 있습니다. 수동 재시도는 `/usr/libexec/smartsafehub-apps-restore run`을 사용합니다.
- 인터넷이 오래 끊겨 재시도 횟수를 넘기면 해당 실행은 종료됩니다. 이후 WAN이 다시 연결되면 hotplug이 네트워크 오류에 한하여 일회성 복원을 재시도하며, 수동 실행이나 다음 부팅으로도 다시 시도할 수 있습니다.
- 주의: 새로운 펌웨어에서 승인된 패키지 pin이 변경되었으면 이전 manifest를 무단으로 덮어쓰지 않고 중단합니다. 이 경우 호환성 확인과 승인 후 별도 마이그레이션이 필요합니다.

## 설치 성공 건수 수집 (2026-10-28)

Apps에서 사용자가 새로 설치에 성공하면, 앱 ID·릴리스 버전·작업 ID만 로컬 outbox에 보관했다가 기존 Device 자격증명으로 Hub에 전송합니다. 실패한 설치, 제거, 펌웨어 업데이트에 따른 자동 복원은 집계하지 않습니다. 최대 500건을 보관하고 네트워크 장애 시 5분 간격으로 최대 3건씩 재시도하며, 해당 전송은 앱 설치의 성공 여부에 영향을 주지 않습니다. 수치는 공개 Apps 화면에 표시하지 않습니다.
