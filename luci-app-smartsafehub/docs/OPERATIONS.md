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
```

### SmartSafeHub entitlement lifecycle

Hub 계정 연결과 플랜 권한은 SafeShield 라이선스 키가 아니라 SmartSafeHub Device credential을 기준으로 동기화합니다. Device credential은 `/etc/smartsafehub/device-credential.json`에 저장하고, 계정/플랜의 마지막 확인 상태는 `/tmp/smartsafehub/device.json`에서 확인합니다.

```text
공유기 부팅 또는 주기 동기화
  → smartsafehub-device status-sync
  → Authorization: Device <credential>
  → POST /api/v1/devices/sync
      ├─ account.connected=true
      │    ├─ 현재 entitlement plan/status 저장
      │    └─ Activity 등 Cloud runtime credential 갱신
      └─ account.connected=false
           ├─ 로컬 계정 연결 상태 해제
           ├─ Cloud runtime credential 정리
           └─ SafeShield 보호 정보 재동기화

SafeShield refresh
  → 같은 Device credential로 /api/v1/devices/sync
  → entitlement.plan/status와 artifact 정보 수신
  → safeshield.status.entitlement에 현재 권한 표시
```

Hub 연결 실패는 기존 로컬 DNS 보호나 마지막으로 적용된 차단 목록을 제거하지 않습니다. 웹사이트에서 등록 해제가 명시적으로 확인된 경우에만 계정 종속 Cloud 상태를 정리하며, Device credential 자체는 유지해 같은 기기를 다시 연결할 수 있습니다.

Health Reporter는 `smartsafehub-device`가 동기화한 현재 플랜을 기준으로 Pro/Ultimate에서만 활성화됩니다. 서버 보고 인증도 라이선스 키가 아니라 Device credential을 사용합니다.


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

SmartSafeHub는 `/usr/share/smartsafehub/firmware.json`을 OpenWrt 설정 백업에 포함하지 않습니다. 이 파일은 현재 설치된 펌웨어 이미지의 고유 정보이므로 sysupgrade에서 이전 값을 보존하면 안 됩니다. 대신 부팅 및 패키지 업데이트 시 현재 펌웨어의 `device_code`를 `/etc/config/smartsafehub`의 `firmware.device_code`에 동기화하고, 복원 시 백업의 해당 값과 현재 장치를 비교합니다. 다른 모델의 백업이나 장치 식별 정보가 없는 기존 백업은 fail-closed로 거부합니다. 복원 후에는 현재 펌웨어의 `device_code`와 `build_id`를 UCI 캐시에 다시 동기화합니다.

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

Cloud 활동 기록 전송이 ON이고 Activity API 또는 device sync/Cloud upload가 일시적으로 통신할 수 없는 경우 로컬 최근 활동과 Cloud outbox는 유지됩니다. credential 갱신 또는 upload 실패는 15분, 30분, 60분 순으로 backoff하며 이후 60분 상한을 유지합니다. backoff 중 새 이벤트가 발생해도 즉시 네트워크 재시도를 강제하지 않습니다. `smartsafehub-activity-sync sync-once`는 운영자가 배포 직후 즉시 동기화를 확인할 때 사용할 수 있습니다. Cloud 전송이 OFF이면 이 네트워크 재시도 경로 자체를 실행하지 않고 outbox도 만들지 않습니다. 공유기 웹사이트의 로컬 최근 활동은 Cloud 통신/전송 설정과 무관하게 최대 128건을 표시합니다.

## 프런트엔드 캐시 문제

패키지를 업그레이드했는데 이전 화면이 남으면 다음 순서로 확인합니다.

```bash
rm -f /tmp/luci-indexcache
/etc/init.d/uhttpd restart
```

브라우저에서는 강력 새로고침을 수행하거나 기존 SmartSafeHub 탭을 닫고 다시 접속합니다. 통합 진입 템플릿의 `app.js?v=...`와 Shadow DOM용 `app.css?v=...`에는 현재 패키지의 `PKG_VERSION-rPKG_RELEASE` 값이 사용되므로 패키지 릴리스 변경 시 브라우저 캐시가 함께 무효화됩니다.
