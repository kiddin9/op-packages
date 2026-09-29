# SmartSafeHub 운영 가이드

패키지 설치, 설치 후 런타임 확인, 라이선스/Cloud 동기화, 진단과 일반적인 트러블슈팅 절차를 정리합니다. 개발·빌드 검증은 [DEVELOPMENT.md](DEVELOPMENT.md)를 참고하세요.

## 설치

SmartSafeHub 저장소를 사용하는 경우 최신 버전은 패키지 이름으로 설치하거나 업데이트합니다.

```bash
apk update
apk add --upgrade luci-app-smartsafehub
```

직접 빌드한 APK를 테스트 장치에 설치하는 경우에는 `/tmp`에 해당 APK만 복사한 뒤 실제 생성된 파일을 설치합니다.

```bash
apk add --allow-untrusted /tmp/luci-app-smartsafehub-*.apk
```

정확한 현재 버전은 `Makefile`의 `PKG_VERSION`과 `PKG_RELEASE`, 또는 설치된 장치의 `apk info luci-app-smartsafehub`로 확인합니다.

패키지의 postinst는 설치/업그레이드 후 events, updater, firmware, maintenance 등 항상 동작해야 하는 SmartSafeHub 서비스를 명시적으로 enable하고 LuCI 메뉴 캐시를 지운 뒤 `/usr/libexec/smartsafehub-rpcd-reconcile`을 실행합니다. helper는 먼저 `rpcd reload`로 기존 세션 영향을 최소화하고, reload가 끝난 뒤 핵심 `smartsafehub` ubus 객체가 실제로 다시 등록됐는지 최대 5회 확인하고 연속 2회 확인될 때만 정상으로 판정합니다. 실기기에서 확인된 것처럼 reload 명령 자체는 성공했는데 핵심 객체가 사라진 경우에만 `rpcd restart`로 자동 복구하며, restart 후에도 객체가 돌아오지 않으면 실패 상태를 남깁니다. 수동 설치 환경에서 같은 검증·복구를 실행하려면 아래 명령을 사용할 수 있습니다.

```bash
rm -f /tmp/luci-indexcache
/bin/sh /usr/libexec/smartsafehub-rpcd-reconcile
ubus list | grep smartsafehub
ubus call smartsafehub system_root_password_status '{}'
```

## 설치 후 확인

### 패키지와 정적 자산

```bash
apk info -e luci-app-smartsafehub
ls -lh /www/luci-static/smartsafehub/app.js
ls -lh /www/luci-static/smartsafehub/app.css
```

### rpcd 등록

```bash
ubus -v list smartsafehub
ubus call smartsafehub status '{}'
```

LAN/DHCP 구현은 기존 관리 RPC의 가용성을 보호하기 위해 별도 `smartsafehub_network` ubus 객체로 격리되어 있습니다. `네트워크` 화면의 내부 네트워크 영역은 같은 `rpcd` 프로세스 안에서 다른 객체를 동기 프록시하지 않고 이 객체를 직접 호출합니다. `smartsafehub_network`는 자체적으로 관리자 비밀번호 설정 상태를 확인하며 LuCI ACL도 LAN 읽기/쓰기 메서드에만 제한됩니다.

```bash
ubus -v list smartsafehub_network
ubus call smartsafehub_network lan_settings '{}'
```

`smartsafehub_network`가 로드되지 않더라도 `smartsafehub` 객체와 로그인/대시보드 RPC는 계속 동작해야 합니다. LAN 구현 파일은 기존 경로인 `smartsafehub/network-management.uc`를 그대로 사용해 패치/체크아웃 과정의 파일명 이동에 의존하지 않습니다.

주요 읽기 기능:

```bash
ubus call smartsafehub_network lan_settings '{}'
ubus call smartsafehub wifi_summary '{}'
ubus call smartsafehub connected_devices '{}'
ubus call smartsafehub system_time_settings '{}'
ubus call safeshield status '{}'
ubus call safeshield config '{}'
ubus call safeshield rules_list '{}'
```

SmartSafeHub의 핵심 `smartsafehub` RPC는 장치·Wi-Fi·시스템·로컬 Health 기능을 소유하고, LAN/DHCP는 장애 격리를 위해 `smartsafehub_network` 객체가 소유합니다. Health 관련 RPC는 다음과 같습니다.

```text
health_status
health_run
health_reporter_update
```

`health_status`는 `/tmp/smartsafehub/health.json`과 Reporter 상태를 읽습니다. 최초 결과가 아직 없으면 rpcd를 막지 않도록 진단 helper를 분리된 프로세스로 시작하고 `확인 중` 상태를 즉시 반환합니다. `health_run`도 같은 방식으로 사용자의 `지금 진단`을 비동기로 시작하며 프런트엔드가 새 `generatedAt`이 기록될 때까지 짧게 재조회합니다. `health_reporter_update`는 최근 로컬 eligibility 상태를 확인한 뒤 opt-in 설정을 저장하며, 실제 Hub API는 라이선스/Trial 여부를 다시 검증해야 합니다.

Health helper의 awk 코드는 OpenWrt의 기본 awk뿐 아니라 GitHub Actions에서 사용하는 GNU awk에서도 실행 가능해야 합니다. GNU awk 내장 이름과 충돌할 수 있는 식별자를 `awk -v` 변수명으로 사용하지 않으며, `test-health.sh`가 이 호환성 계약을 회귀 검사합니다.

SafeShield 기능은 `luci-app-smartsafehub`가 별도 프록시를 만들지 않고 SafeShield 패키지가 제공하는 공식 ubus API를 직접 사용합니다.

```text
safeshield.status
safeshield.config
safeshield.set_enabled
safeshield.refresh
safeshield.rules_list
safeshield.rule_add
safeshield.rule_delete
safeshield.license_get
safeshield.license_update
```

`license_get`은 평문 라이선스 키를 반환하므로 브라우저의 일반 상태 조회에는 사용하지 않습니다. 사용자가 현재 키를 명시적으로 불러올 때 호출하며 LuCI ACL에서도 일반 read 권한과 분리합니다. 로컬 Health 진단, 진단 다운로드와 주기적 UI polling은 `safeshield.status`의 마스킹된 라이선스 정보만 사용합니다. 예외적으로 opt-in된 유료/Trial Health Reporter daemon은 실제 HTTPS 보고 직전에 서버 인증 헤더를 만들기 위해 평문 키를 일시적으로 조회하며, 키를 런타임 상태 파일이나 보고 payload에 기록하지 않습니다.

SafeShield `license_get`의 현재 응답 계약은 `{ "license": { "configured": true, "key": "..." } }` 형태이며 Health Reporter와 라이선스 상태 동기화 daemon은 필요한 순간에만 `license.key`를 메모리에서 읽습니다. 이전 개발 빌드의 최상위 `key` 응답은 Health Reporter 호환 fallback으로만 허용합니다.

### SmartSafeHub 라이선스 lifecycle

Hub 계정과 장치의 라이선스 연결 lifecycle은 SafeShield 엔진이 아니라 SmartSafeHub 관리 계층이 소유합니다. SafeShield는 계속해서 실제 키 저장소와 장치 identity의 authoritative source 역할만 담당합니다.

```text
사용자가 라이선스 등록/변경
  → smartsafehub.license_activate
  → mode 0600 private request에 키만 기록
  → detached /usr/libexec/smartsafehub-license activate 시작 후 RPC 즉시 반환
  → helper가 safeshield.status에서 authoritative device identity 조회
  → POST /api/v1/licenses/activate
  → 성공한 경우에만 safeshield.license_update

smartsafehub-license daemon
  → 기본 300초 주기
  → safeshield.license_get으로 현재 키를 일시 조회
  → safeshield.status에서 physical_fingerprint 조회
  → POST /api/v1/licenses/status
      ├─ device_action=none: 로컬 상태 유지
      │    └─ Cloud 활동 ON일 때만 activity_history credential을 /tmp runtime cache에 저장
      ├─ device_action=clear_license: safeshield.license_update { license_key: "" } + activity credential 제거
      └─ 네트워크/API 실패: 오류만 기록하고 로컬 키/유효한 기존 credential 유지

smartsafehub-activity-sync
  ├─ Cloud 활동 OFF: outbox/wake/credential 정리 후 네트워크 작업 없이 disabled 유지
  └─ Cloud 활동 ON
       → 유효한 cached activity credential 사용
       → credential 없음/만료 임박: smartsafehub-license status-sync 요청
       → POST /api/v1/activity/events
       → 성공한 snapshot event_id만 ack
```

`smartsafehub-license`는 `daemon`, `activate`, `status-sync`, `status` 명령을 독립 subcommand로 제공합니다. `license_activate` RPC 자체는 SafeShield를 동기 호출하지 않으며, 장치 identity와 profile 구성은 detached `activate` subcommand 안에서 수행합니다. 이는 현재는 작은 독립 procd 서비스로 장애 범위와 디버깅 경계를 유지하면서, 향후 주기적인 Hub 동기화 작업이 늘어나면 명령 경계를 그대로 `smartsafehub-agent license ...` 모듈로 옮길 수 있도록 하기 위한 구조입니다. updater처럼 장시간 설치·재부팅 상태 머신을 가지는 기능은 별도 서비스로 유지하는 것을 전제로 합니다.

daemon의 startup/check 대기는 foreground `sleep`이 아니라 interrupt 가능한 child wait로 처리합니다. SIGTERM/SIGINT를 받으면 대기 중인 sleep child를 깨우고 loop를 종료하므로 5분 상태 확인 주기 중에도 procd stop/restart가 오래 기다리지 않습니다. Hub 요청 자체는 10초 timeout을 사용하고 procd `term_timeout`은 15초로 두어, 요청 중 종료가 들어와도 정상 정리 시간을 확보한 뒤 강제 종료하도록 합니다.

런타임 상태는 `/tmp/smartsafehub/license.json`에 atomic write하며 평문 라이선스 키를 저장하지 않습니다. 명시적 활성화와 주기 `status-sync`가 겹치면 activation single-flight lock이 우선하며, status-sync는 활성화 결과를 덮어쓰지 않고 다음 주기까지 건너뜁니다. SafeShield의 `license_get` 자체가 실패한 경우는 미설정 상태로 오인하지 않고 `LICENSE_LOCAL_READ_FAILED`로 기록합니다.

운영 진단을 위해 상태 파일에는 `lastHttpStatus`, `lastActivationResult`, `lastActivationErrorCode`도 기록합니다. 정상 Hub JSON 응답은 현재 API 계약에 따라 HTTP 200으로 기록하며, `uclient-fetch`가 transport/HTTP 실패로 종료되어 실제 상태 코드를 신뢰할 수 없는 경우 `lastHttpStatus`는 `null`로 기록합니다. `lastActivationResult`와 `lastActivationErrorCode`는 이후의 주기 `status-sync`나 `unconfigured` 전환에서도 유지되어 마지막 명시적 activation 결과를 별도로 추적할 수 있습니다.

### 라이선스 셸 계약 테스트

`tests/test-license.sh`는 activate/status 동기화, stale activation lock 복구, activation 진단 필드 보존과 장기 sleep 중 SIGTERM 정상 종료를 검증합니다. 각 시나리오는 mock 환경을 명시적으로 초기화해 Linux `dash`와 macOS `/bin/sh`처럼 함수 앞 임시 환경 변수의 처리 차이가 있는 환경에서도 이전 실패 주기의 값이 다음 테스트에 누적되지 않도록 합니다.


## SmartSafeHub Reset Policy v1

SmartSafeHub 펌웨어는 OpenWrt 기본 `/etc/rc.button/reset`과 제품 전용 Reset 정책이 동시에 존재하지 않도록 빌드해야 합니다. OpenWrt 소스 빌드 config에서 `CONFIG_TARGET_BUTTON_CUSTOMIZATION=y`와 `CONFIG_TARGET_BUTTON_CUSTOMIZATION_RESET_DISABLED=y`를 활성화하고, firmware image에 포함되는 `luci-app-smartsafehub`가 `/etc/rc.button/reset`을 제공합니다.

- 1초 미만: 재부팅
- 1~4초: 동작 없음
- 5~9초: 관리자 비밀번호 복구
- 10초 이상: `factoryreset -y` 후 재부팅

`0.2.22-r12` 이상 패키지는 실행 중인 장치에 OpenWrt 기본 reset handler가 남아 있으면 live package upgrade를 중단합니다. 이 경우 관리 소프트웨어만 먼저 올리지 말고 Reset Policy v1 config로 빌드한 펌웨어를 먼저 설치해야 합니다. 펌웨어 이미지에 패키지가 함께 포함되는 정상 빌드에서는 rootfs 생성 시 기본 handler가 제거된 상태이므로 충돌하지 않습니다.

### 펌웨어 공통 system 기본값

펌웨어 build overlay에서 `/etc/config/system` 전체를 제공하면 OpenWrt가 장치별로 생성하는 `compat_version` 같은 메타데이터를 덮어쓸 수 있습니다. 특히 A3004T처럼 Sysupgrade metadata가 `compat_version=1.1`인 장치에서는 실행 중인 `/etc/config/system`에 값이 없을 경우 현재 버전을 1.0으로 판단해 정상 이미지도 호환성 불일치로 거부할 수 있습니다.

따라서 build 서버의 `overlays/common/etc/config/system`은 사용하지 않고, SmartSafeHub 패키지의 `/etc/uci-defaults/90-smartsafehub-system-defaults`가 기존 system 섹션을 유지합니다. 새 설치의 OpenWrt 기본 hostname/UTC 값이나 누락된 옵션에만 SmartSafeHub 기본값을 채우고, 이미 사용자가 바꾼 hostname, 시간대, 로그와 NTP 설정 및 `compat_version`은 그대로 보존합니다. 새 펌웨어를 만들기 전에 외부 build overlay의 기존 `/etc/config/system` 파일을 반드시 제거해야 합니다.

### 설정 백업 장치 검증

SmartSafeHub는 별도의 `backup-device.json`을 만들지 않습니다. `/lib/upgrade/keep.d/smartsafehub`가 펌웨어에 이미 존재하는 `/usr/share/smartsafehub/firmware.json`을 OpenWrt 표준 설정 백업에 포함하고, 복원 시 해당 파일의 `device_code`와 현재 설치된 펌웨어의 `device_code`를 비교합니다. 다른 모델의 백업이나 장치 식별 metadata가 없는 기존 백업은 fail-closed로 거부합니다. `firmware.json`은 검증용 metadata일 뿐이므로 `sysupgrade --restore-backup` 후에는 복원 전에 보관해 둔 현재 펌웨어의 파일을 다시 기록하여 `build_id`가 과거 값으로 되돌아가지 않도록 합니다.

비밀번호 복구는 `/etc/smartsafehub/password-recovery` marker로 추적합니다. helper는 root 비밀번호만 비우고 Dropbear의 기존 enable 상태를 marker에 기록한 뒤 SSH를 중지/비활성화합니다. 재부팅 후 공개 recovery bridge는 marker가 존재하고 root 비밀번호가 비어 있을 때만 `system_root_password_status`와 `system_root_password_set` 두 RPC로 제한된 15분 ubus 세션을 발급하므로 일반 로그인 화면 없이 복구 UI로 바로 진입할 수 있습니다. 새 관리자 비밀번호 설정이 완료되면 marker를 삭제하고 이전 SSH enable 상태를 복원합니다.

## 진단 다운로드 확인

시스템 화면의 **진단 정보 다운로드**를 눌렀을 때 JSON 파일이 생성되어야 합니다. 현재 구현에는 `smartsafehub.system_diagnostics` RPC가 없습니다.

진단 생성 흐름은 다음과 같습니다.

```text
현재 시스템/Health 상태 재사용
  + smartsafehub.wifi_summary
  + safeshield.status
  → 브라우저에서 JSON 결합 및 다운로드
```

Wi-Fi 또는 SafeShield가 설치되지 않았거나 일시적으로 응답하지 않아도 진단 파일은 생성되며 해당 섹션은 사용 불가 기본값으로 기록됩니다. 로컬 Health 결과도 함께 포함됩니다. 진단 파일에는 비밀번호와 라이선스 키는 없지만 호스트명, WAN IPv4와 Wi-Fi SSID 같은 네트워크 식별 정보가 포함될 수 있으므로 외부 전달 전에 내용을 확인하세요.

오류가 발생하면 브라우저 개발자 도구의 Network 항목과 다음 로그를 함께 확인합니다.

```bash
logread | grep -Ei 'rpcd|ucode|smartsafehub|safeshield' | tail -200
```

### Cloud 활동 기록 재시도 정책

Cloud 활동 기록 전송이 ON이고 Activity API 또는 license status/Cloud upload가 일시적으로 통신할 수 없는 경우 로컬 최근 활동과 Cloud outbox는 유지됩니다. credential 갱신 또는 upload 실패는 15분, 30분, 60분 순으로 backoff하며 이후 60분 상한을 유지합니다. backoff 중 새 이벤트가 발생해도 즉시 네트워크 재시도를 강제하지 않습니다. `smartsafehub-activity-sync sync-once`는 운영자가 배포 직후 즉시 동기화를 확인할 때 사용할 수 있습니다. Cloud 전송이 OFF이면 이 네트워크 재시도 경로 자체를 실행하지 않고 outbox도 만들지 않습니다. 공유기 웹사이트의 로컬 최근 활동은 Cloud 통신/전송 설정과 무관하게 최대 128건을 표시합니다.

## 프런트엔드 캐시 문제

패키지를 업그레이드했는데 이전 화면이 남으면 다음 순서로 확인합니다.

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/uhttpd restart
```

브라우저에서는 강력 새로고침을 수행하거나 기존 SmartSafeHub 탭을 닫고 다시 접속합니다. 통합 진입 템플릿의 `app.js?v=...`와 Shadow DOM용 `app.css?v=...`에는 현재 패키지의 `PKG_VERSION-rPKG_RELEASE` 값이 사용되므로 패키지 릴리스 변경 시 브라우저 캐시가 함께 무효화됩니다.
