# SPDX-License-Identifier: GPL-3.0-or-later

Describe 'SmartSafeHub 셸 계약 테스트'
  It '셸 문법과 JSON 유효성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-static-validation.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '공유기 각 메뉴의 카드 밖 섹션 제목과 기능 버튼 보존을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-section-layout.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Preact 11 의존성과 JSX 타입 호환성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-preact11-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'OpenWrt 25.12 BusyBox 기본 명령과 의존성 호환성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-openwrt-commands.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '셸 파이프라인의 Broken pipe 회귀를 방지한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-shell-pipeline-safety.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '계정 상태와 캐시·업데이트 폴링 안정화 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-stability-r16.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End
  It '공유기 데모의 실제 기기 접근 차단과 Git 배포 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-router-demo-contract.sh"
    The status should be success
    The output should start with 'PASS: router demo contract'
    The error should be blank
  End

  It '게스트 Wi-Fi 분리망과 관리 UI 보안 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-guest-wifi-contract.sh"
    The status should be success
    The output should start with 'guest Wi-Fi security and UI contract: PASS'
    The error should be blank
  End

  It '패키지 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-package-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '정규화 이벤트 큐와 상태 전이 기록 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-events.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '공유기 최근 활동 RPC와 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-activity-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '사용자 규칙 렌더링 최적화와 RPC 진단 개인정보 보호 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rules-performance.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '추천 사용자 규칙의 적용과 해제 및 수동 규칙 보존을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-recommended-rules.sh"
    The status should be success
    The output should start with '추천 사용자 규칙 동기화 및 UI 계약: PASS'
    The error should be blank
  End

  It '추천 사용자 규칙의 빠른 적용 확인 보고와 재전송 방지를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-recommended-ack.sh"
    The status should be success
    The output should start with 'PASS: lightweight recommended confirmation'
    The error should be blank
  End

  It '계정 기반 Cloud 활동 동기화와 직접/관찰 이벤트 분리를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-activity-cloud-sync.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '공통 JSON shell helper 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-common-shell.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '루트 URL 내부 rewrite 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-root-url-rewrite.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '패키지 업그레이드 후 rpcd 핵심 객체 자동 복구 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rpcd-reconcile.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Apps 설치 성공 이벤트 전송과 재시도·복원 제외 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-metrics.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '펌웨어 업데이트 후 검증된 Apps 자동 복원 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-restore.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '내비게이션 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-navigation-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Tailwind Shadow DOM fallback 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-tailwind-shadow-dom.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '문서 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-document-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'CHANGELOG 릴리즈 사이 빈 줄 두 개를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-changelog-spacing.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'README와 상세 문서 분리 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-documentation-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '로그인 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-login-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '초기 관리자 비밀번호 설정 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-initial-password-setup.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '대시보드 계정 미연결 안내 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-dashboard-account-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '대시보드 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-dashboard-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '네트워크 입력 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-network-input-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '공통 커스텀 드롭다운 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-custom-select-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'LAN/DHCP 설정과 subnet 충돌 방지 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-lan-settings.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'OpenWrt 25.12 LAN UCI list/CIDR 런타임 호환성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-lan-uci-runtime.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'WAN DHCP/PPPoE/고정 IPv4 설정 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-wan-settings.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'PPPoE WAN UCI 런타임과 비밀번호 비노출을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-wan-uci-runtime.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'SKB/LG U+ IPTV Beta 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-iptv.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '업데이트 및 SafeShield 상대 시간 표시 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-relative-time-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '업데이트 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-update-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '새로고침과 세션 안전 회귀 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-reload-safety.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '설정 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-settings-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '시스템 시간대 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-system-time-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '예약 재부팅 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-scheduled-reboot.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '로컬 진단과 원격 상태 보고 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-health.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '설정 백업과 복원 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-backup-restore.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'RPC 외부 작업 분리와 캐시/작업 중복 방지를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rpc-jobs.sh"
    The status should be success
    The output should start with 'PASS: detached RPC worker'
    The error should be blank
  End

  It 'SmartSafeHub Apps 설치와 제거 안전성 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-manager.sh"
    The status should be success
    The output should start with 'PASS: Apps install/remove'
    The error should be blank
  End

  It 'Apps 설치/제거 색상과 제거 확인 팝업 및 진행 상태를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-ui.sh"
    The status should be success
    The output should start with 'PASS: Apps removal confirmation'
    The error should be blank
  End

  It 'SmartSafeHub Apps 공식 UI 새 탭 실행과 알림 닫기 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-launch.sh"
    The status should be success
    The output should start with 'PASS: Apps secure new-tab launch'
    The error should be blank
  End

  It 'SmartSafeHub Apps 메뉴와 승인된 앱 카탈로그를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '모든 rpcd ucode 진입점과 모듈의 실제 컴파일을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-ucode-syntax.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'ucode import 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-ucode-imports.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'RPC 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rpc-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '규칙 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rules-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'SmartSafeHub 계정 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-account-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'SafeShield 페이지 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-safeshield-page-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '보호 통계 UI 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-statistics-ui-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '관리 소프트웨어 업데이트 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-updater.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '펌웨어 업데이트 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-firmware-updater.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  # 지속적으로 보호해야 하는 기능 계약(과거 CI에서 누락된 테스트 포함)
  It '최근 활동 동기화 데몬의 유휴 폴링 제한을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-activity-idle-polling.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '최근 활동의 Cloud 설정과 기록 표시 및 접근성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-activity-layout.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '관리자 비밀번호 변경 권한과 입력 검증을 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-admin-password-change.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '물리 버튼 비밀번호 복구의 안전성 및 초기화를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-admin-password-recovery.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '데몬 실행 및 상태 관리의 런타임 계약을 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-daemon-runtime.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '대시보드의 데이터 중복 호출과 병렬 RPC를 방지한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-dashboard-performance-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '기기 등록 코드와 자격증명 처리의 안전성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-device-registration.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '펌웨어 내장 소프트웨어 버전 비교를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-firmware-bundling.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '펌웨어 식별 정보와 업데이트 연결을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-firmware-identity.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'WAN/LAN 통합 메뉴 및 과거 링크 호환성을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-network-settings.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '설정 탭 이동 및 입력값 유지와 키보드 접근을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-page-tabs.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '임시 상태 파일과 런타임 경로를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-runtime-path-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '테스트 파일이 CI 실행 목록에서 누락되지 않는지 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-suite-integrity.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '기본 UCI 설정값과 초기화를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-system-defaults.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Wi-Fi QR 인증과 비밀번호 보호를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-wifi-qr-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

End
