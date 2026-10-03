# 변경 기록

## [0.2.27-r1] - 2026-10-03

### 개선

- 일부 UI를 개선하여 더 명확하게 정보를 표현하도록 하였습니다.
- 첫 설치 시 브라우저의 시간대를 기본 시간대로 사용할 수 있도록 개선하였습니다.

## [0.2.26-r4] - 2026-10-01

### 개선

- SafeShield의 보호 데이터 영역을 내부 용어 중심의 `Tier`, `Version`, `Rules`, `Unique domains` 목록 대신 사용자가 바로 이해할 수 있는 보호 상태 중심 화면으로 변경했습니다.
- 현재 적용된 보호 도메인 수를 가장 눈에 띄게 표시하고, `light` 같은 내부 tier 값은 `기본 보호`처럼 사용자 친화적인 보호 수준으로 표현합니다.
- 보호 데이터 버전에 포함된 UTC 시각을 사용자 브라우저의 로컬 시간으로 변환해 마지막 업데이트 시각으로 표시합니다.
- 원본 데이터 버전과 적용 규칙 수는 `세부 정보`에 남겨 문제 해결이 필요할 때만 확인할 수 있도록 정리했습니다.
- SafeShield 설정 설명에서도 `아티팩트` 같은 내부 용어 대신 `보호 데이터`를 사용하도록 문구를 정리했습니다.

### 테스트

- 보호 데이터 카드가 보호 도메인, 보호 수준, 마지막 업데이트, 상태 안내와 접힌 세부 정보를 제공하고 기존 영어 내부 필드를 기본 화면에 직접 노출하지 않는지 UI 계약 테스트를 추가했습니다.
- 패키지 revision과 로그인/프론트엔드 asset version이 `0.2.26-r4`로 일치하는지 기존 패키지 계약 테스트로 함께 검증합니다.

## [0.2.26-r3] - 2026-10-01

### 개선

- 원격 상태 보고에서 어떤 정보가 서버로 전송되고 어떤 정보가 전송되지 않는지 더 쉽게 구분할 수 있도록 개인정보 보호 안내를 개선했습니다.
- 전송되는 기기 상태와 진단 정보는 항목별로 나누고, 호스트명·WAN IP·Wi-Fi 정보·DNS 요청 내용·시스템 로그 원문처럼 전송하지 않는 정보는 별도의 보호 영역으로 강조했습니다.
- 라이트 모드와 다크 모드에서 개인정보 안내 카드의 배경, 테두리와 텍스트 대비가 자연스럽게 유지되도록 기존 테마 색상 체계를 사용했습니다.

### 테스트

- 원격 상태 보고 화면에 개인정보 보호 설명과 전송/비전송 정보 분류가 유지되는지 UI 계약 테스트를 보강했습니다.
- DNS 요청 내용과 시스템 로그 원문이 서버에 전송되지 않는다는 안내가 계속 표시되는지 Health 계약 테스트를 추가했습니다.

## [0.2.26-r2] - 2026-09-30

### 추가

- 새로 설치한 SmartSafeHub가 처음 접속한 브라우저의 시간대를 확인해 공유기 시간대를 자동으로 설정하도록 추가했습니다.

### 개선

- 공유기 hostname은 항상 `SmartRouter` 기본 이름을 사용하도록 초기 설정 동작을 정리했습니다.
- 이미 시간대를 설정한 기존 장치와 기존 OpenWrt 설정은 자동 시간대 설정 대상에서 제외해 사용자 설정을 그대로 유지합니다.

### 테스트

- 신규 설치의 1회 시간대 자동 설정, 기존 장치 시간대 보존, 지원하지 않는 브라우저 시간대 처리와 `SmartRouter` hostname 강제 적용을 검증하는 회귀 테스트를 보강했습니다.

## [0.2.26-r1] - 2026-09-30

### 수정

- 펌웨어를 업데이트한 뒤에도 이전 펌웨어 버전으로 인식되어 같은 업데이트가 다시 표시되던 문제를 수정했습니다.

## [0.2.25-r2] - 2026-09-29

### 수정

- 펌웨어를 업데이트한 뒤에도 이전 펌웨어 버전으로 인식되어 같은 업데이트가 다시 표시되던 문제를 수정했습니다.
- 펌웨어 고유 정보가 설정 유지 업그레이드에 함께 보존되지 않도록 변경해, 새 펌웨어의 버전과 빌드 정보를 그대로 사용합니다.

### 개선

- 설정 백업의 기기 호환성 확인은 펌웨어 파일 대신 SmartSafeHub 설정에 저장된 기기 코드를 사용하도록 분리했습니다.
- 현재 펌웨어의 기기 코드와 빌드 정보를 부팅 및 패키지 업데이트 시 SmartSafeHub 설정에 자동으로 동기화합니다.

### 테스트

- 이전 `firmware.json`이 남아 있어도 현재 ROM의 펌웨어 정보를 우선하는지, 설정 백업에 펌웨어 파일을 포함하지 않는지, 다른 모델의 백업을 계속 차단하는지 검증하는 회귀 테스트를 보강했습니다.

### 호환성

- 이 버전부터 생성한 설정 백업에는 SmartSafeHub 기기 코드가 `/etc/config/smartsafehub`에 포함됩니다. 기기 코드가 없는 이전 백업은 다른 모델 백업의 오적용을 막기 위해 복원이 거부될 수 있습니다.

## [0.2.25-r1] - 2026-09-29

### 개선

- 관리자 비밀번호 변경 UI를 개선하였습니다.
- 내부 모듈을 정리하였습니다.

## [0.2.24-r5] - 2026-09-29

### 개선

- 관리자 비밀번호 변경 화면에서 비밀번호 요구 사항 안내와 `새 비밀번호 확인` 입력 영역 사이의 간격을 넓혀 각 입력 단계가 더 명확하게 구분되도록 개선했습니다.

### 테스트

- 비밀번호 요구 사항 안내 다음의 확인 입력 영역에 추가 여백이 유지되는지 UI 계약 테스트를 보강했습니다.

## [0.2.24-r4] - 2026-09-29

### 수정

- Cloud 활동 기록 전송 설정이 없거나 잘못된 값인 경우 전송을 켜지 않고 OFF로 처리하도록 변경했습니다.
- 과거 버전에서 Cloud 활동 기록을 암묵적으로 켜던 업그레이드 호환 코드를 제거해, 패키지 업데이트만으로 Cloud 전송이 자동 활성화되지 않도록 했습니다.

### 테스트

- 패키지 설치 과정에서 Cloud 전송을 강제로 켜는 레거시 migration이 남아 있지 않은지 검증하고, RPC·이벤트 기록·동기화·라이선스 경로 모두 명시적으로 ON인 경우에만 Cloud 기능을 사용하도록 계약 테스트를 보강했습니다.

## [0.2.24-r3] - 2026-09-29

### 수정

- `90-smartsafehub-system-defaults`가 펌웨어 업그레이드 때 기존 hostname, 시간대, 로그 및 NTP 사용자 설정을 다시 SmartSafeHub 기본값으로 덮어쓰지 않도록 하고, 새 설치의 OpenWrt 기본값 또는 누락된 옵션에만 기본값을 적용하도록 변경했습니다.
- OpenWrt 표준 설정 백업에 기존 `/usr/share/smartsafehub/firmware.json`을 포함하고 `device_code`가 현재 공유기와 일치하는 경우에만 복원을 허용해 다른 모델의 설정 백업 적용을 차단했습니다. 별도의 장치 identity 파일은 추가하지 않습니다.
- 백업에 포함된 과거 `firmware.json`은 호환성 검증에만 사용하고, 복원 직후 현재 설치된 펌웨어 metadata를 다시 복구해 `build_id`와 firmware identity가 과거 값으로 되돌아가지 않도록 했습니다.

### 테스트

- 기존 사용자 system/NTP 설정 보존, 새 설치 기본값 적용, `compat_version` 비변경을 검증하는 system-defaults 회귀 테스트를 보강했습니다.
- 같은 `device_code` 백업 허용, 다른 장치 및 식별 metadata 없는 백업 거부, 성공/실패 복원 후 현재 `firmware.json` 보존을 검증하는 백업 회귀 테스트를 추가했습니다.

## [0.2.24-r2] - 2026-09-29

### 개선

- `새 펌웨어가 있습니다.` 안내에서 내부 OpenWrt 기반 버전 표기를 제거하고 SmartSafeHub 펌웨어 버전, 이미지 크기와 배포 채널만 표시하도록 단순화했습니다.
- OpenWrt 기반 버전이 확인되지 않을 때 사용자에게 `OpenWrt 미확인`이 노출되지 않도록 했습니다.

### 테스트

- 사용 가능한 펌웨어 요약에 OpenWrt 기반 버전이 다시 노출되지 않고 SmartSafeHub 펌웨어 버전과 이미지 크기가 유지되는지 UI contract 테스트를 추가했습니다.

## [0.2.24-r1] - 2026-09-28

### 수정

- 내부 설정 충돌을 해결하였습니다.

## [0.2.23-r2] - 2026-09-28

### 수정

- 펌웨어에서 공통 `/etc/config/system` 파일을 통째로 덮어쓰지 않고 `90-smartsafehub-system-defaults` uci-defaults 스크립트가 SmartSafeHub 기본 hostname, 시간대, 로그와 NTP 옵션만 적용하도록 변경했습니다.
- OpenWrt가 기기별로 생성하는 `system.@system[0].compat_version`을 그대로 보존해 A3004T처럼 `compat_version=1.1`을 사용하는 장치에서 정상 Sysupgrade 이미지가 `FIRMWARE_IMAGE_INVALID`로 거부되지 않도록 했습니다.

### 테스트

- system/NTP 섹션이 이미 존재할 때 섹션을 재생성하지 않는지, `compat_version`을 수정하거나 삭제하지 않는지, 누락된 섹션만 방어적으로 생성하는지 검증하는 회귀 테스트를 추가했습니다.

## [0.2.23-r1] - 2026-09-28

### 개선

- 관리자 비밀번호 기능을 추가하고, 초기화 기능도 함께 제공합니다.
- 인터넷 설정을 새롭게 추가하고 기존의 LAN 메뉴와 합쳤습니다.

### 수정

- 다크 모드에서 일부 UI의 가독성이 떨어진 부분을 수정하였습니다.

## [0.2.22-r14] - 2026-09-28

### 개선

- 사이드바 `업데이트` 메뉴 badge를 개별 패키지 수가 아니라 업데이트 유형 단위로 표시하도록 변경했습니다. 관리 소프트웨어 업데이트가 여러 개여도 1개로 계산하고, 펌웨어 업데이트가 있으면 별도로 1개를 더해 badge가 최대 2까지만 표시됩니다.
- 접힌 사이드바의 접근성 라벨도 실제 의미에 맞게 업데이트 유형 개수를 안내하도록 정리했습니다.

### 테스트

- 관리 소프트웨어 업데이트 수가 여러 개여도 사이드바 badge에서는 1개 유형으로만 계산하고 펌웨어와 합산해 최대 2가 되는 계약을 검증하도록 업데이트 UI 회귀 테스트를 보강했습니다.

## [0.2.22-r13] - 2026-09-28

### 개선

- 물리 Reset 버튼으로 관리자 비밀번호 복구가 활성화된 경우 일반 로그인 화면을 거치지 않고 곧바로 관리자 비밀번호 복구 화면으로 진입하도록 흐름을 개선했습니다.
- 복구 중에는 전체 root 세션을 자동 생성하지 않고 `system_root_password_status`와 `system_root_password_set` 두 RPC만 허용하는 15분 제한 세션을 발급해 복구 화면의 권한 범위를 최소화했습니다.
- 복구 marker가 없거나 root 비밀번호가 이미 설정된 경우 공개 recovery bridge가 세션을 발급하지 않도록 방어 조건을 추가했습니다.

### 테스트

- recovery bridge의 marker/빈 root 비밀번호 조건, 제한 RPC grant, 일반 로그인보다 우선하는 복구 진입 순서와 production asset version 계약을 검증하는 회귀 테스트를 추가했습니다.

## [0.2.22-r12] - 2026-09-28

### 추가

- SmartSafeHub Reset Policy v1을 추가해 Reset 버튼을 5~9초 누르면 관리자 비밀번호만 복구하고, 10초 이상 누르면 OpenWrt factory reset으로 모든 사용자 설정을 초기화하도록 동작을 분리했습니다.
- 물리 비밀번호 복구 시 WAN/LAN, Wi-Fi, SafeShield와 라이선스 설정은 유지하고 root 관리자 비밀번호만 비운 뒤 복구 상태로 재부팅합니다.
- 비밀번호가 비어 있는 복구 구간에는 Dropbear를 중지/비활성화하고, 새 비밀번호 설정이 끝나면 복구 전 SSH 활성 상태를 복원합니다.
- 복구 상태에서는 최초 설정과 구분되는 관리자 비밀번호 복구 화면을 표시하고 완료 후 새 비밀번호로 다시 로그인하도록 했습니다.

### 호환성

- SmartSafeHub 전용 Reset handler가 `/etc/rc.button/reset`을 소유하도록 변경했습니다. 펌웨어는 OpenWrt의 기본 reset handler를 포함하지 않도록 `CONFIG_TARGET_BUTTON_CUSTOMIZATION=y`와 `CONFIG_TARGET_BUTTON_CUSTOMIZATION_RESET_DISABLED=y`를 사용해야 합니다.
- 기존 OpenWrt reset handler가 남아 있는 구형 펌웨어에서는 5초 이상 누름이 즉시 factory reset으로 해석될 수 있으므로, 관리 소프트웨어 단독 업그레이드를 차단하고 먼저 호환 펌웨어 업데이트를 요구합니다.

### 테스트

- Reset 5~9초/10초 경계, 구형 펌웨어 업그레이드 차단 계약, 비밀번호 복구 marker, Dropbear 보호/복원, 실패 rollback과 복구 전용 UI를 검증하는 회귀 테스트를 추가했습니다.

## [0.2.22-r11] - 2026-09-28

### 추가

- 설정의 `시스템 관리` 영역에서 현재 관리자 비밀번호를 확인한 뒤 새 비밀번호로 변경할 수 있는 전용 카드를 추가했습니다.
- 비밀번호 변경 전에 rpcd `session.login`으로 현재 비밀번호를 검증하고, 임시 검증 세션은 즉시 폐기하도록 했습니다.
- 새 비밀번호는 최초 설정과 동일하게 8자 이상, 영문자와 숫자 각각 1자 이상 정책을 적용하며 현재 비밀번호와 동일한 값은 허용하지 않습니다.
- 변경 성공 시 현재 ubus/LuCI 로그인 세션을 종료하고 로그인 화면으로 이동해 새 비밀번호로 다시 인증하도록 했습니다.
- 최초 설정 화면과 설정 화면이 동일한 프런트엔드 비밀번호 정책 유틸리티를 공유하도록 정리했습니다.

### 개선

- 시스템 관리 카드를 `관리자 비밀번호`와 `설정 백업 및 복원`의 2열 구성으로 정리하고 `시스템 도구`는 그 아래 전체 폭으로 배치했습니다.

### 테스트

- 관리자 비밀번호 변경 RPC, ACL, 현재 비밀번호 검증, 세션 폐기, 공통 비밀번호 정책과 설정 UI 재로그인 흐름을 검증하는 회귀 테스트를 추가했습니다.

## [0.2.22-r10] - 2026-09-28

### 수정

- 관리 소프트웨어 업데이트 설치 중 진행 패널에서 `text-sky-800` 및 `text-sky-950`이 다크 모드 색상으로 변환되지 않아 제목과 안내 문구가 배경에 묻히던 문제를 수정했습니다.
- 설치 진행 패널의 제목, 설명과 아이콘이 다크 모드에서도 동일한 sky 계열의 읽기 쉬운 대비를 유지하도록 색상 매핑을 보완했습니다.

### 테스트

- 업데이트 UI 계약 테스트에 설치 진행 패널의 `text-sky-800` 및 `text-sky-950` 다크 모드 매핑 회귀 검증을 추가했습니다.

## [0.2.22-r9] - 2026-09-28

### 개선

- 관리 소프트웨어뿐 아니라 새 펌웨어가 있는 경우에도 사이드바 `업데이트` 메뉴에 알림 badge를 표시합니다.
- 관리 소프트웨어와 펌웨어 업데이트가 동시에 있으면 하나의 badge에서 설치 가능한 업데이트 수를 합산해 표시합니다.
- 펌웨어 상태를 현재 페이지와 관계없이 백그라운드에서 조회해 네트워크, Wi-Fi, SafeShield 등 다른 화면에서도 펌웨어 업데이트 알림이 유지되도록 했습니다.

### 테스트

- 사이드바 업데이트 badge가 관리 소프트웨어 업데이트 수와 펌웨어 `updateAvailable` 상태를 합산하는지, 펌웨어 상태 조회가 전역에서 활성화되는지 검증하는 회귀 조건을 추가했습니다.

## [0.2.22-r8] - 2026-09-28

### 개선

- 고정 IPv4의 IP 주소, 기본 게이트웨이, 기본/보조 DNS를 LAN 공유기 주소와 동일한 4개 octet 입력 UI로 통일해 모바일과 데스크톱에서 주소 입력 방식을 일관되게 했습니다.
- LAN과 WAN이 같은 공용 IPv4 octet 컴포넌트를 사용하도록 정리해 입력 제약과 모바일 레이아웃이 기능별로 달라지지 않도록 했습니다.
- 사이드바와 페이지 제목의 `네트워크 설정`을 더 간결한 `네트워크`로 변경하고 대시보드 이동 문구도 `네트워크 보기`로 맞췄습니다.
- 보조 DNS의 4개 octet을 모두 비우면 선택 필드가 빈 값으로 정상 복원되도록 공용 입력 컴포넌트에서 처리합니다.

### 테스트

- WAN 고정 IPv4의 주소/게이트웨이/DNS가 공용 octet 입력을 사용하는지, LAN도 같은 컴포넌트를 재사용하는지와 `네트워크` 메뉴명을 검증하는 회귀 조건을 추가했습니다.

## [0.2.22-r7] - 2026-09-28

### 개선

- 사이드바의 `인터넷`과 `LAN` 메뉴를 `네트워크 설정` 하나로 통합해 WAN 연결과 내부 LAN/DHCP 구성을 한 화면에서 관리할 수 있도록 했습니다.
- 통합 화면에서도 WAN과 LAN의 저장되지 않은 변경 상태, 입력 검증, 저장/적용 및 재연결 동작은 서로 독립적으로 유지합니다.
- 기존 `#wan`, `#lan` hash는 `#network` 화면으로 계속 연결되도록 호환 경로를 유지하고, 대시보드의 네트워크 상세/충돌 해결 링크도 새 화면으로 통일했습니다.
- WAN 영역과 내부 네트워크 영역 사이에 명확한 구분선을 두어 하나의 화면에서도 각 설정 범위를 쉽게 구분할 수 있도록 했습니다.

### 테스트

- 네트워크 설정 단일 route, 기존 WAN/LAN hash 호환, 메뉴 통합, 대시보드 링크 및 WAN/LAN 동시 새로고침을 검증하는 회귀 테스트를 추가했습니다.
- 기존 WAN, LAN, IPTV와 내비게이션 계약 테스트를 새 통합 메뉴 구조에 맞게 갱신했습니다.

## [0.2.22-r6] - 2026-09-28

### 추가

- `네트워크 > 인터넷` WAN 관리 화면을 추가해 현재 연결 상태, IPv4 주소, 기본 게이트웨이, DNS와 연결 시간을 확인할 수 있도록 했습니다.
- WAN 연결 방식을 자동 IP(DHCP), PPPoE, 고정 IPv4로 변경할 수 있고 별도의 수동 WAN 재연결 기능을 제공합니다.
- PPPoE 비밀번호는 읽기 API에서 원문을 반환하지 않고 설정 여부만 노출하며, 사용자가 새 비밀번호를 입력하지 않으면 기존 값을 유지합니다.
- 고정 IPv4 설정에서 주소, CIDR 서브넷 마스크, 기본 게이트웨이와 기본/보조 DNS를 설정할 수 있습니다.
- WAN 설정 변경은 LAN 관리 연결을 재시작하지 않고 WAN 인터페이스만 지연 재연결하며, 재연결 예약 실패 시 UCI 설정을 이전 값으로 복구합니다.
- WAN 설정 변경을 최근 활동의 `인터넷 설정 변경` 이벤트로 표시합니다.

### 문서

- README의 네트워크 관리 범위에 WAN DHCP/PPPoE/고정 IPv4 설정과 재연결 기능을 추가했습니다.

### 테스트

- WAN RPC/ACL, UCI 저장, 입력 검증, PPPoE 비밀번호 비노출/보존, WAN-only 재연결, 메뉴/화면/최근 활동 연결을 검증하는 계약 테스트를 추가했습니다.
- OpenWrt ucode 런타임 fixture에서 PPPoE `/32` 주소, gateway/DNS 상태 해석과 기존 비밀번호를 노출하지 않는 무변경 저장을 검증합니다.

## [0.2.22-r5] - 2026-09-28

### 정리

- 개발 중 잠시 사용했던 독립 `smartsafehub-safeshield-events` 서비스의 업그레이드 호환 처리와 관련 계약 테스트를 제거했습니다. 실제 SafeShield 비동기 갱신 관찰은 기존과 동일하게 통합 `smartsafehub-events` daemon이 담당합니다.
- 통합 이벤트 daemon의 SafeShield observer 상태/lock 파일명을 `safeshield-observer.*`로 정리해 더 이상 존재하지 않는 독립 서비스와 혼동되지 않도록 했습니다.

### 테스트

- 이벤트 테스트가 새 SafeShield observer 상태 파일명을 사용하도록 갱신하고, 패키지/Cloud activity 계약에서 존재하지 않는 legacy 서비스의 stop/disable migration 요구사항을 제거했습니다.

## [0.2.22-r4] - 2026-09-28

### 개선

- iPhone 15 Pro처럼 폭이 좁은 화면에서도 대시보드 `최근 활동`의 `전체 보기`와 `최근 24시간 보호 활동`의 `상세 통계` 링크가 제목 오른쪽에 유지되도록 섹션 헤더 배치를 정리했습니다.
- SafeShield 최근 24시간 보호 활동의 집계 시각을 절대 날짜 대신 `방금 전`, `N분 전`, `N시간 전` 같은 상대 시간으로 표시하고, 정확한 시각은 title 정보로 유지합니다.

### 테스트

- 대시보드 계약 테스트에 최근 활동 액션의 제목 행 배치, 모바일 줄바꿈 방지, SafeShield 집계 상대 시간과 1분 주기 갱신 연동을 검증하는 회귀 조건을 추가했습니다.

## [0.2.22-r3] - 2026-09-28

### 수정

- 일부 OpenWrt 환경의 `tr`이 POSIX 대소문자 클래스를 기대한 방식으로 처리하지 않아 SafeShield의 `pro` 플랜이 Health Reporter 상태에서 `prp`로 변형되던 문제를 수정했습니다. 라이선스/상태 토큰의 대소문자 정규화는 명시적인 ASCII 문자 매핑을 사용하도록 변경했습니다.
- 같은 대소문자 변환을 사용하던 Cloud 최근 활동 동기화의 라이선스 phase/plan/action 처리도 공통 ASCII 정규화 helper를 사용하도록 통일해 기기별 `tr` 구현 차이로 권한 판정이 달라지지 않도록 했습니다.

### 테스트

- 공통 shell helper가 `pro`/`ULTIMATE` 같은 라이선스 토큰을 OpenWrt 호환 방식으로 정확히 대소문자 변환하는지 검증하는 회귀 테스트를 추가했습니다.
- Health Reporter에서 `pro` + `ACTIVE`가 `PRO` + `active`로 정규화되고 유료 권한으로 판정되는지 검증합니다.
- Cloud 최근 활동 동기화가 POSIX 문자 클래스 기반 `tr` 대소문자 변환을 다시 사용하지 않는지 검증합니다.

## [0.2.22-r2] - 2026-09-28

### 수정

- iPhone 15 Pro처럼 폭이 좁은 모바일 화면에서 LAN 공유기 IP와 DHCP 시작/종료 주소의 4개 옥텟 입력이 카드 오른쪽을 벗어나 잘리던 문제를 수정했습니다. IPv4 입력을 WebKit의 input intrinsic width에 의존하는 flex 배치 대신 4개의 `minmax(0, 1fr)` 그리드로 고정해 모든 옥텟이 항상 카드 안에 표시됩니다.
- IPTV 사용 스위치가 모바일의 44px 터치 타깃 규칙에 의해 세로로 늘어나 thumb 위치가 어긋나던 문제를 수정했습니다. 다른 SmartSafeHub 설정 화면과 동일한 공통 스위치 크기를 사용하고 제목 행 안에 배치해 모바일에서도 안정적으로 표시됩니다.

### 테스트

- LAN 계약 테스트에 모바일 IPv4 4열 그리드와 입력 폭 제한 회귀 검증을 추가했습니다.
- IPTV 계약 테스트에 공통 스위치 geometry 사용과 모바일 제목 행 배치 회귀 검증을 추가했습니다.

## [0.2.22-r1] - 2026-09-27

### 개선

- 신규 기기 지원을 위해서 내부 모듈을 업데이트 하였습니다.
- 가독성을 위해서 최근 활동의 UI를 개선하였습니다.

## [0.2.21-r3] - 2026-09-27

### 개선

- 펌웨어 장치 식별 목록에 `iptime-a3004t`와 `iptime-ax3000se`를 추가했습니다.
- 펌웨어 메타데이터나 UCI 장치 코드가 없는 경우에도 OpenWrt board name `iptime,a3004t`, `iptime,ax3000se`를 각각 SmartSafeHub 장치 코드로 변환해 OTA 펌웨어 확인이 동작하도록 했습니다.
- 셸 펌웨어 helper와 rpcd ucode가 동일한 지원 장치 판정을 사용하도록 중복 조건을 공통 helper로 정리했습니다.

### 테스트

- A3004T와 AX3000SE가 펌웨어 메타데이터와 board-name fallback 양쪽에서 올바른 장치 코드로 식별되는지 검증하는 회귀 테스트를 추가했습니다.
- rpcd 펌웨어 모듈이 두 신규 장치 코드와 OpenWrt board name 매핑을 포함하는지 계약 테스트를 추가했습니다.

## [0.2.21-r2] - 2026-09-25

### 개선

- 대시보드의 `최근 활동` 3개 항목 사이에 작은 세로 간격을 추가해 제목과 설명이 연속해서 붙어 보이지 않도록 가독성을 개선했습니다. 전체 `최근 활동` 화면의 밀도는 변경하지 않습니다.

### 테스트

- 최근 활동 UI 계약 테스트에 대시보드 compact 타임라인의 항목 간격을 검증하는 회귀 테스트를 추가했습니다.

## [0.2.21-r1] - 2026-09-25

### 수정

- 모바일 기기에서 자동 업데이트 시간 설정의 UI가 깨지는 문제를 수정하였습니다.

## [0.2.20-r5] - 2026-09-25

### 수정

- iPadOS의 모든 브라우저가 WebKit을 사용하면서 native `input[type="time"]`의 지역화된 내부 컨트롤 폭을 강제하는 문제를 근본적으로 회피했습니다. 관리 소프트웨어 자동 설치 시각을 시간/분 두 개의 SmartSafeHub 커스텀 선택기로 교체해 부모 카드 폭과 무관하게 레이아웃이 넘치지 않도록 했습니다.
- 같은 native time input을 사용하던 설정 > 예약 재부팅 시간도 동일한 커스텀 시간 선택기로 통일했습니다. iPad에서 같은 문제가 다른 화면으로 재발하지 않도록 공통 `TimeSelect` 컴포넌트로 분리했습니다.
- 태블릿 가로 화면에서 자동 업데이트 설정 카드가 실제 사용 가능한 폭을 기준으로 줄바꿈하는 기존 보정은 유지하고, 시간/분 선택기 자체에도 `minmax(0, 1fr)` 폭 제약을 적용했습니다.

### 테스트

- 업데이트 UI와 설정 UI 계약 테스트에서 native `type="time"` 재도입을 금지하고 공통 `TimeSelect` 사용 및 실제 배포 `app.js`/`app.css` 반영 여부를 검증하도록 보강했습니다.

## [0.2.20-r4] - 2026-09-25

### 수정

- iPad Pro에서 관리 소프트웨어의 `설치 시각` 입력창이 자동 업데이트 카드 오른쪽 경계를 벗어나는 현상을 다시 보강했습니다. 설정 카드와 내부 flex item에 명시적인 `min-width: 0` 제약을 적용하고, native time input에는 inline style과 WebKit 내부 date/time edit 영역까지 폭 제한을 적용했습니다.
- r3에서 소스(`frontend/src`)에는 iPad 레이아웃 보정이 들어갔지만 패키지가 실제로 제공하는 사전 빌드 자산(`root/www/luci-static/smartsafehub/app.js`, `app.css`)이 갱신되지 않아 실제 기기에서는 수정 내용이 반영되지 않는 문제를 수정했습니다. r4에서는 실제 패키지에 포함되는 런타임 배포 자산까지 함께 갱신해 소스와 배포 결과를 동기화했습니다.

### 테스트

- 업데이트 UI 계약 테스트가 소스 코드뿐 아니라 실제 패키지에 포함되는 `app.js`/`app.css`에도 iPad 레이아웃 보정이 들어갔는지 확인하도록 확장했습니다.

## [0.2.20-r3] - 2026-09-25

### 수정

- iPad Pro 가로 화면에서 관리 소프트웨어의 자동 업데이트 설정 영역이 실제 카드 폭보다 넓은 2열 레이아웃을 유지하면서 `설치 시각` 입력창이 카드 밖으로 밀려나던 문제를 수정했습니다.
- 자동 업데이트 설정은 viewport 기준 breakpoint 대신 해당 설정 영역의 실제 사용 가능 폭에 따라 열 수를 결정하도록 변경했으며, 업데이트 채널 행은 항상 전체 폭을 사용하도록 유지했습니다.
- iPadOS/WebKit의 native `time` 입력 요소가 가진 intrinsic width 때문에 좁은 Grid track을 넘지 않도록 inline 최소/최대 폭을 명시해 native 시간 선택 UI를 유지하면서 레이아웃 이탈을 방지했습니다.

### 테스트

- 업데이트 UI 계약 테스트에 자동 업데이트 설정의 container-width 반응형 Grid와 iPadOS/WebKit 시간 입력 폭 제한을 검증하는 회귀 테스트를 추가했습니다.

## [0.2.20-r2] - 2026-09-23

### 개선

- 펌웨어 업데이트 채널과 관리 소프트웨어 패키지 채널의 개념을 분리했습니다. 펌웨어 OTA 확인은 이제 설치된 `/usr/share/smartsafehub/firmware.json`의 `channel`(없으면 `smartsafehub.firmware.channel`, 최종 fallback은 `stable`)을 기준으로 동작하므로, 패키지 저장소를 Beta로 사용하더라도 Stable 펌웨어 장치가 잘못 Beta 펌웨어 제안을 받지 않습니다.
- 펌웨어 업데이트 카드의 사용 가능한 릴리스 표시는 resolve 응답의 릴리스 채널을 우선 사용하도록 정리해, UI가 패키지 저장소 채널과 펌웨어 채널을 혼동하지 않도록 했습니다.

### 수정

- 공유기 웹사이트 다크 모드에서 펌웨어 `Available firmware` 패널과 상태 배지에 사용되는 sky 계열 surface/text/ring 색상 매핑이 빠져 회색 블록처럼 보이던 문제를 수정했습니다. 라이트 모드 구조는 유지하면서 다크 모드에서도 강조 영역이 자연스럽게 보이도록 했습니다.

### 테스트 및 문서

- 펌웨어 helper/RPC 계약 테스트에 "패키지 저장소가 Beta여도 설치된 펌웨어 채널은 Stable로 유지된다"는 회귀 검증과 "펌웨어 채널은 저장소 파일이 아니라 펌웨어 metadata에서 읽는다"는 계약 검증을 추가했습니다.
- README의 업데이트 섹션에 펌웨어 채널과 패키지 채널을 분리한 규칙을 문서화했습니다.

## [0.2.20-r1] - 2026-09-22

### 기능

- 최근 활동 기록을 보여주는 기능을 추가하였습니다. 유료 멤버쉽의 경우 Cloud 동기화를 지원합니다.

### 개선

- [Beta] SK Broadband, LG U+ IPTV를 지원하는 기능의 베타 버전으로 추가하였습니다.
- 전체적인 UI를 다듬었습니다.

### 수정

- SafeShield refresh 로딩바를 다듬었습니다.

## [0.2.19-r21] - 2026-09-22

### 수정

- SafeShield 수동 갱신 단계의 회전 progress ring이 r18에서 두께는 정리되었지만 전체 지름은 여전히 약간 크게 보여 카드 안에서 시선이 과하게 쏠리던 점을 조정했습니다.
- ring SVG 반지름을 `18 → 17`로 줄이고 donut container를 `3.5rem → 3.35rem`으로 소폭 축소해, 기존 6단계 숫자 가독성과 진행감은 유지하면서 전체 존재감만 한 단계 낮췄습니다. 라이트/다크 모드의 stroke 폭과 glow 강도는 그대로 유지합니다.

### 테스트 및 문서

- SafeShield UI contract에 refresh donut의 반지름과 container 크기를 고정하는 회귀 검증을 추가해 이후 스타일 수정으로 전체 ring 크기가 다시 커지지 않도록 했습니다.
- README의 SafeShield 갱신 단계 설명을 현재의 약간 더 컴팩트한 ring 규칙에 맞게 갱신했습니다.

## [0.2.19-r20] - 2026-09-22

### 수정

- 로컬 Health 진단이 `dnsmasq`를 한 번만 확인한 뒤 즉시 `DNSMASQ_UNAVAILABLE` critical로 판정해 SafeShield 차단 목록 적용 중의 짧은 dnsmasq reload/restart 공백을 실제 장애로 오인하던 문제를 수정했습니다.
- dnsmasq가 첫 확인에서 보이지 않으면 2초 간격으로 최대 3회까지 짧게 재확인하고, 중간에 정상으로 돌아오면 정상 상태로 처리합니다. 세 번 모두 실행 상태를 확인하지 못한 경우에만 `DNSMASQ_UNAVAILABLE` critical과 Health activity event를 생성합니다. 정상 상태에서는 추가 대기나 재확인을 수행하지 않습니다.

### 테스트 및 문서

- 첫 확인 실패 후 두 번째 확인에서 복구되는 transient dnsmasq 상태는 critical/event를 만들지 않고, 3회 연속 실패는 실제 critical 및 `health.issue.started`로 기록되는 회귀 테스트를 추가했습니다.
- README의 로컬 Health 진단 설명에 dnsmasq 연속 확인/debounce 정책을 추가했습니다.

## [0.2.19-r19] - 2026-09-21

### 기능

- 공유기 `최근 활동` 화면의 Cloud 활동 기록 카드에 ON/OFF 스위치를 추가했습니다. Cloud 전송은 Pro/Ultimate에서 선택적으로 활성화할 수 있고, 로컬 `activity-history.jsonl`은 설정과 관계없이 계속 기록됩니다.
- 새 설치에서는 `smartsafehub.activity.cloud_sync_enabled=0`으로 시작합니다. r18 이하에서 이미 Cloud 활동 기록을 사용하던 업그레이드 장치는 해당 옵션이 없으면 기존 동작과의 호환을 위해 ON으로 해석하므로 업데이트만으로 기존 동기화가 갑자기 중단되지 않습니다.
- Cloud 전송을 끄면 `/tmp/smartsafehub/events.jsonl`의 전송 대기 데이터, wake marker, runtime upload credential을 즉시 정리합니다. OFF 상태에서 새 이벤트는 로컬 history에만 기록되며 Cloud outbox에는 들어가지 않으므로, 다시 켜도 OFF 기간의 이벤트를 소급 업로드하지 않습니다.
- Cloud 전송을 다시 켜면 현재 Pro/Ultimate entitlement를 로컬 license state로 확인한 뒤 설정을 저장하고 activity sync를 다시 시작합니다. credential은 기존 canonical `smartsafehub-license status-sync` 경로에서만 발급/저장하며 activity-sync는 upload/ack 책임만 유지합니다.
- Cloud ON/OFF 자체도 `settings.activity_cloud_sync.enabled/disabled` 직접 이벤트로 로컬 최근 활동에 기록합니다. OFF 이벤트는 로컬 전용이고 ON 이벤트는 이후 Cloud outbox에도 포함될 수 있습니다.

### 안정성 및 개인정보

- Activity Sync는 Cloud 전송이 꺼진 상태에서 license refresh나 `/activity/events` 업로드를 수행하지 않고 `disabled` 상태로 유지합니다. license daemon은 라이선스 reconciliation은 계속 수행하지만 Cloud 전송이 꺼져 있으면 optional activity credential을 runtime cache에 보관하지 않습니다.
- 설정 변경 RPC는 daemon을 중지한 뒤 runtime policy를 적용하고 다시 시작하여 명시적인 opt-out과 진행 중 uploader가 경쟁하지 않도록 했습니다. 로컬 recent activity는 이 과정에서 삭제하지 않습니다.
- 기존 r18 이하 설치에서는 preinst/postinst migration marker로 기존 암묵적 Cloud 전송 ON 상태를 보존해, opkg가 새 기본 설정 파일을 적용하더라도 동작이 갑자기 꺼지지 않도록 했습니다.

### 테스트 및 문서

- Cloud OFF에서 local history만 남고 outbox/wake/credential/network 호출이 생기지 않는지, license status-sync가 Cloud OFF에서도 라이선스 상태를 유지하면서 activity credential을 저장하지 않는지 회귀 테스트를 추가했습니다.
- UI/RPC/ACL 계약에 유료 entitlement, 접근 가능한 switch semantics, 신규 설치 기본 OFF와 구버전 upgrade 호환 정책을 고정하고 README의 Cloud 활동 기록 데이터 흐름을 갱신했습니다.

## [0.2.19-r18] - 2026-09-21

### 수정

- SafeShield 수동 갱신 단계의 원형 progress ring이 `track 4px / active arc 7px`와 비교적 강한 drop-shadow 조합으로 렌더링되어 라이트/다크 모드에서 진행 표시가 필요 이상으로 두껍게 보이던 문제를 수정했습니다. 확인 결과 이 두께는 Tailwind `border` utility가 아니라 SVG에 직접 지정된 `strokeWidth`와 glow에서 발생했습니다.
- 진행 ring의 track을 3px, active arc를 4px로 줄이고 light/dark theme의 glow도 함께 완화했습니다. 진행 단계 숫자와 6단계 구조, 회전 animation, 오류 상태 및 접근성 progressbar semantics는 그대로 유지합니다.
- 이 progress ring은 SVG `strokeWidth`를 명시적으로 사용하므로 Tailwind border utility 값과 독립적으로 동일한 두께를 유지합니다.

### 테스트 및 문서

- SafeShield UI contract에 track/arc stroke 폭과 라이트/다크 모드 shadow 강도를 고정하는 회귀 검증을 추가해 이후 Tailwind border/shadow 변경이 진행 ring의 시각 두께를 다시 키우지 않도록 했습니다.
- README의 SafeShield 갱신 단계 설명에 얇은 progress ring 시각 규칙을 추가했습니다.

## [0.2.19-r17] - 2026-09-21

### 수정

- Cloud 활동 기록 upload credential의 발급 책임을 `smartsafehub-license`로 통합했습니다. 기존에는 `smartsafehub-license`와 `smartsafehub-activity-sync`가 각각 `/api/v1/licenses/status` 요청/응답 해석을 별도로 구현해 동일한 라이선스 상태 API 계약이 두 곳에 중복되어 있었고, 실기기에서는 license status-sync가 정상인데 activity-sync의 중복 credential 획득 경로만 `ACTIVITY_STATUS_FAILED`로 실패하는 문제가 있었습니다.
- `smartsafehub-license status-sync`가 이미 정상 처리한 Hub `/licenses/status` 응답의 `activity_history` credential을 `/tmp/smartsafehub/activity-sync-credential.json`에 원자적으로 저장합니다. 토큰은 기존과 동일하게 `/tmp`에만 보관되며 재부팅 시 사라집니다.
- `smartsafehub-activity-sync`는 더 이상 `/licenses/status` 또는 `/licenses/resolve`를 직접 호출하거나 license key/device fingerprint를 다시 읽어 같은 entitlement 응답을 중복 파싱하지 않습니다. credential이 없거나 만료 임박하면 `smartsafehub-license status-sync`를 실행해 canonical license 경로를 갱신한 뒤 캐시된 upload credential만 소비합니다.
- 서버가 명시적으로 라이선스를 해제하거나 로컬 라이선스가 미설정 상태가 되면 license component가 activity credential을 함께 제거하고, activity sync는 Cloud-only outbox만 정리합니다. 반대로 Pro/Ultimate 상태는 정상인데 activity credential만 발급되지 않은 경우에는 `ACTIVITY_CREDENTIAL_UNAVAILABLE`로 outbox를 보존합니다. license status 자체를 확인하지 못한 경우는 `ACTIVITY_LICENSE_STATUS_FAILED`로 구분합니다.
- 기존에 발급된 유효한 activity credential은 r17 업그레이드 뒤에도 그대로 재사용하므로 즉시 추가 status 호출을 만들지 않습니다. Cloud event upload/ack, 15분 → 30분 → 60분 backoff, 로컬 최근 활동 history는 그대로 유지됩니다.

### 테스트 및 문서

- license status-sync가 paid 응답의 activity credential을 실제 runtime cache에 저장하고 revoke/clear 시 제거하는 계약을 추가했습니다. Activity Sync는 license API를 직접 호출하지 않고 `smartsafehub-license status-sync` 경계만 사용하며, cached credential 재사용·paid credential 누락·Free/revoked 처리·Cloud upload/ack·backoff가 유지되는지 회귀 테스트로 고정했습니다.
- README의 Cloud 활동 기록 구조를 `license = entitlement/credential owner`, `activity-sync = upload/ack consumer` 책임 분리와 향후 agent module 경계에 맞게 갱신했습니다.

## [0.2.19-r16] - 2026-09-21

### 수정

- Cloud 활동 기록 동기화가 upload credential을 얻기 위해 무거운 `/api/v1/licenses/resolve`를 호출하던 경로를 기존 조회 전용 `/api/v1/licenses/status`로 전환했습니다. Activity Sync는 더 이상 artifact resolve/download token 발급 경로를 건드리지 않으며, Hub의 다운로드 감사 로그와 Cloud 활동 credential 조회가 분리됩니다.
- `/licenses/status` 요청은 `license_key`와 `device.physical_fingerprint`만 전송합니다. Activity Sync 때문에 vendor/model/arch/SafeShield version 등 artifact resolve용 전체 device profile을 다시 조립하거나 전송하지 않습니다.
- Hub 1.4.86 이전처럼 유효한 Pro/Ultimate 상태이지만 `activity_history` 필드가 아직 없는 `/licenses/status` 응답은 `ACTIVITY_STATUS_UNSUPPORTED`로 처리하고 bounded Cloud outbox를 보존합니다. `/licenses/resolve`로 fallback하지 않으므로 단계적 배포 중에도 불필요한 artifact resolve가 다시 발생하지 않습니다.
- `license.is_licensed=false`, `device_action=clear_license` 또는 명시적인 Free 상태는 현재 Cloud 활동 기록 entitlement가 없는 것으로 처리해 Cloud-only outbox를 정리합니다. revoked/expired Pro 라이선스를 서버 오류로 오인해 무한 보존하지 않습니다.
- status API 통신 실패는 기존 15분 → 30분 → 60분 bounded backoff를 그대로 사용하며 `ACTIVITY_STATUS_FAILED`로 상태를 노출합니다. 기존 resolve 단계에서 발급된 유효한 activity credential도 만료 전까지 그대로 사용할 수 있어 업그레이드 시 전송이 끊기지 않습니다.

### 테스트 및 문서

- Activity Sync가 `/licenses/status`만 호출하고 `/licenses/resolve`를 호출하지 않는 계약, status body가 최소 identity만 포함하는 계약, 구 Hub paid 응답의 outbox 보존, revoked/Free outbox 정리, status 장애 backoff를 회귀 테스트로 고정했습니다.
- README의 Cloud 활동 기록 동기화 설명을 Hub 1.4.86의 조회 전용 status credential 구조와 단계적 배포 호환 정책에 맞게 갱신했습니다.

## [0.2.19-r15] - 2026-09-21

### 수정

- 로컬 `activity-history.jsonl`과 `smartsafehub-events history`에는 여러 이벤트가 정상적으로 존재하지만 `smartsafehub status` 응답에서는 1건만 반환되던 문제를 수정했습니다. `read_activity_history()`가 존재하지 않는 선택적 limit 인자를 숫자로 변환한 뒤 최소값 1로 보정하는 경로를 제거하고, 상태 RPC는 항상 최신 최대 128건의 로컬 활동 기록을 반환합니다.
- Hub Activity API가 미배포되었거나 통신할 수 없는 상태에서 `smartsafehub-activity-sync`가 5분마다 `/api/v1/licenses/resolve`를 반복 호출하던 동작을 개선했습니다. 실패 재시도는 15분 → 30분 → 60분으로 증가하고 60분에서 상한을 유지합니다.
- Cloud 동기화가 backoff 상태일 때 새 이벤트가 발생해 wake marker가 생성되더라도 backoff를 우회해 즉시 resolve 요청을 다시 보내지 않습니다. 로컬 history와 최대 128건 Cloud outbox는 그대로 누적되며, 수동 `sync-once`는 진단/배포 직후 확인을 위해 즉시 실행할 수 있습니다.

### 테스트 및 문서

- status RPC가 선택적 limit 인자에 의존하지 않고 최대 128건을 반환하는 계약과 Cloud resolve 실패의 15/30/60분 bounded backoff를 검증하는 회귀 테스트를 추가했습니다.
- README에 Cloud Activity API 장애/미배포 시 재시도 정책과 로컬 이벤트 기록이 Cloud 통신과 독립적이라는 점을 보강했습니다.

## [0.2.19-r14] - 2026-09-21

### 수정

- `smartsafehub-events`의 `mkdir` lock에서 lock 디렉터리 생성 직후 owner PID 파일이 기록되기 전의 짧은 구간을 stale lock으로 오인해 다른 writer가 lock을 삭제할 수 있던 race condition을 수정했습니다. 이 경쟁 상태에서는 둘 이상의 writer가 동시에 JSONL read-modify-replace 구간에 들어가 먼저 기록한 이벤트를 덮어쓸 수 있어 최근 활동에 마지막 일부 이벤트만 남을 수 있었습니다.
- lock 디렉터리는 생성 자체를 소유권 획득으로 취급하고, PID가 아직 없는 lock은 초기화 중인 busy 상태로 기다립니다. dead owner만 별도 reclaim lock 아래에서 회수하며, unlock도 현재 PID가 실제 owner일 때만 수행하도록 변경했습니다. 같은 안전한 lock 구현을 SafeShield 비동기 refresh observer state에도 적용했습니다.
- rpcd의 직접 이벤트 producer가 event helper 기록 실패를 더 이상 완전히 숨기지 않고 `logread`에서 확인할 수 있도록 `source`와 `event_type`을 포함한 경고를 남기며, bounded lock wait를 고려해 helper 호출 timeout을 늘렸습니다.

### 테스트 및 문서

- PID 파일이 아직 없는 초기화 중 lock을 경쟁 writer가 탈취하지 않는지 검증하는 회귀 테스트를 추가했습니다. 기존 동시 writer 및 local history/outbox 분리 테스트와 함께 여러 producer가 겹쳐도 이벤트가 덮어써지지 않는 계약을 검증합니다.
- README에 lock owner 게시 전 구간을 stale로 간주하지 않는 소유권 규칙과 event emit 실패 로그 정책을 문서화했습니다.

## [0.2.19-r13] - 2026-09-21

### 수정

- 여러 직접/관찰 이벤트가 가까운 시점에 발생할 때 `smartsafehub-events`의 local history/outbox lock이 사용 중이면 새 이벤트를 즉시 실패시키던 문제를 수정했습니다. event writer는 짧은 bounded retry로 lock을 기다린 뒤 직렬화해 저장하므로 설정 변경이나 observer 이벤트가 lock 경합 때문에 조용히 유실되지 않습니다.
- Cloud Activity API가 아직 배포되지 않았거나 `/api/v1/licenses/resolve`가 구 응답 형식을 반환하는 동안에도 Cloud outbox를 보존하도록 호환성을 강화했습니다. legacy top-level `plan`을 인식하고, 명시적인 `Free` 응답에서만 Cloud-only outbox를 정리하며, 누락/미지원/불완전 응답은 재시도 가능한 오류로 취급합니다.
- Cloud API 통신 실패 상태에서 wake marker가 남아 15초 daemon tick마다 resolve/upload를 반복하던 동작을 수정했습니다. wake marker를 원자적으로 소비해 이벤트 burst당 빠른 시도는 한 번만 수행하고, 실패 후에는 기본 5분 주기로 재시도합니다. 동기화 중 새 이벤트가 생기면 새 wake marker가 남아 다음 tick에서 다시 처리됩니다.

### 테스트 및 문서

- 살아 있는 lock owner가 잠깐 event store를 점유한 경우와 여러 event emit이 동시에 발생한 경우에도 모든 이벤트가 local history에 보존되는 회귀 테스트를 추가했습니다.
- Hub API 미배포/통신 실패, legacy paid resolve, plan 미확인 응답에서 outbox가 삭제되지 않고, 명시적인 Free 응답에서만 정리되는 계약을 추가했습니다.
- README에 로컬 history와 Cloud 전송 실패의 독립성, bounded lock wait, Cloud API rollout 이전의 retry 정책을 문서화했습니다.

## [0.2.19-r12] - 2026-09-21

### 기능

- SafeShield 보호 활성화/비활성화, 통계 수집, 사용자 allow/block 규칙처럼 사용자가 명시적으로 수행한 변경은 성공한 mutation 지점에서 즉시 이벤트로 기록하도록 전환했습니다. Health의 5분 snapshot diff에서 SafeShield 보호/차단 목록 이벤트 생성을 제거해 짧은 시간 안에 OFF→ON처럼 원상 복구된 변경도 놓치지 않습니다.
- SafeShield 차단 목록 갱신 완료/실패는 비동기 작업의 실제 결과를 알아야 하므로 `smartsafehub-events daemon`이 `last_success`/`last_failure` timestamp 변화를 추적합니다. 수동 갱신 요청은 수락 직후 같은 event helper의 watcher를 깨워 완료 결과를 빠르게 기록하고, daemon observer가 자동 갱신 결과도 보완합니다.
- 예약 재부팅, 관리 소프트웨어 업데이트 설정, 원격 상태 보고, 시간대, Wi-Fi, LAN/DHCP, IPTV 같은 주요 설정 저장 성공 시 `settings.*` 직접 이벤트를 추가했습니다. 주기적인 조회는 이벤트로 만들지 않습니다.
- Pro/Ultimate 사용자를 위한 `smartsafehub-activity-sync` daemon을 추가했습니다. `/api/v1/licenses/resolve`에서 Cloud 활동 기록 upload credential을 받아 `/tmp/smartsafehub/events.jsonl`을 최대 128건 batch로 전송하고, 서버가 `accepted`/`duplicates`/`expired`로 처리한 snapshot의 `event_id`만 ack합니다. 로컬 `activity-history.jsonl`은 Cloud ack와 무관하게 유지됩니다.
- 공유기 `최근 활동` 화면에 Cloud 동기화 상태, 멤버십, 전송 대기 건수, 마지막 성공 시각과 서버 보관 기간을 표시합니다. Free/비대상 장치는 Cloud outbox만 비우고 로컬 최근 활동은 그대로 사용할 수 있습니다.

### 안정성 및 보안

- 유료 플랜 resolve 응답에 activity upload credential이 누락된 경우 백엔드 배포 지연/불완전 응답으로 간주해 outbox를 삭제하지 않고 재시도하도록 했습니다. Free/비대상 응답에서만 Cloud 전송용 outbox를 정리합니다.
- 이벤트 발생 시 wake marker를 남겨 5분 주기만 기다리지 않고 activity sync daemon이 빠르게 전송을 시도하며, 네트워크/서버 실패 시 ack하지 않아 다음 동기화에서 재전송합니다.
- 직접 이벤트에는 `origin=direct`, WAN/Health 및 SafeShield 비동기 완료 관찰 이벤트에는 `origin=observer`를 기록해 producer 책임을 구분했습니다. SafeShield 비동기 observer는 별도 daemon을 추가하지 않고 `smartsafehub-events`에 통합해 로컬 이벤트 생성/보관 책임을 하나의 서비스로 유지합니다.

### 테스트 및 문서

- 유료 Cloud batch 업로드/ack, Free entitlement, 유료 credential 누락 시 outbox 보존, 직접/관찰 이벤트 소유권을 검증하는 `tests/test-activity-cloud-sync.sh`를 추가하고 ShellSpec/패키지/static validation 계약에 연결했습니다.
- README의 이벤트 생산 경로를 direct mutation과 observer transition으로 구분하고 Cloud 활동 기록 동기화/유료 entitlement/로컬 history 보존 정책을 문서화했습니다.

## [0.2.19-r11] - 2026-09-21

### 수정

- `최근 활동`의 `공유기 시작`을 `공유기 부팅 감지`로 변경하고, 전원이 켜진 경우와 재시작된 경우를 구분할 수 없는 이벤트 특성에 맞게 `공유기가 켜지거나 재시작된 것을 확인했습니다.`라고 안내하도록 수정했습니다.
- 인터넷 연결 끊김은 ISP/상위망 장애로 단정하지 않고 `인터넷 연결 끊김 감지`와 `공유기에서 인터넷 연결을 확인할 수 없었습니다.`로 표현합니다. 복구 이벤트의 `downtime_seconds`도 실제 장애 시간을 확정하는 값이 아니라 Health observer가 연결을 확인하지 못한 관측 구간이므로 `약 N초 동안 인터넷 연결이 확인되지 않았습니다.`로 정확도를 조정했습니다.
- SafeShield 보호 상태는 `켜짐/꺼짐` 대신 `활성화/비활성화`로 통일하고, 라이선스 서버 동기화에 따른 해제는 `라이선스 연결 해제`로 표현해 기능 장애나 라이선스 소멸로 오해하지 않도록 했습니다.
- Health 이벤트의 `장치 진단 정상화`/`장치 진단 상태 변경` 같은 기술적인 문구를 `장치 상태 정상으로 복구`, `확인이 필요한 장치 상태 변경` 등 사용자 중심 표현으로 정리했습니다.
- SafeShield/관리 소프트웨어/펌웨어 업데이트 실패 이벤트에서 오류 코드만 단독으로 표시하지 않고 사용자용 실패 설명을 먼저 보여준 뒤 오류 코드를 보조 정보로 표시하도록 변경했습니다.

### 테스트 및 문서

- 최근 활동 UI 계약 테스트에 부팅, 인터넷 연결, SafeShield 보호, 라이선스, Health 상태의 사용자 문구와 관측 기반 장애 시간 표현을 고정하고, 오해를 유발하던 기존 문구가 다시 들어오지 않는 회귀 검사를 추가했습니다.
- README에 최근 활동은 관측 데이터가 실제로 보장하는 범위만 표현하고 오류 코드는 사용자용 설명 뒤의 진단 정보로 노출한다는 정책을 문서화했습니다.

## [0.2.19-r10] - 2026-09-21

### 수정

- 공유기 웹사이트의 `최근 활동` 조회가 업데이트 직후 `요청 인자가 올바르지 않습니다.`(`UBUS_STATUS_INVALID_ARGUMENT`)로 실패할 수 있던 문제를 수정했습니다. 기존 `smartsafehub.status` RPC에 새 인자를 추가하지 않고, 기존의 무인자 RPC 계약을 그대로 유지하면서 최근 활동을 응답에 포함하도록 변경했습니다.
- 프론트엔드도 `include_activity_history`/`activity_limit` 인자를 더 이상 전송하지 않습니다. 따라서 업데이트 직후 rpcd에 이전 메서드 시그니처가 남아 있거나 기존 로그인 세션을 계속 사용하는 경우에도 새 인자 검증 때문에 최근 활동 조회가 거부되지 않습니다.
- rpcd reload 전의 이전 handler가 잠시 응답해 `activityHistory` 필드가 없더라도 오류 화면 대신 빈 최근 활동 상태로 안전하게 처리합니다.
- ucode에서 생략된 activity limit을 `int(null)`로 변환할 때 생길 수 있는 `NaN`을 유효한 숫자로 오인하지 않도록 보강해 기본 128건 제한이 안정적으로 적용되도록 했습니다.

### 호환성 및 이벤트 보존

- `0.2.19-r8`부터 event writer가 실제로 기록한 이벤트의 fallback/승계와 Cloud outbox/로컬 history 분리 동작은 그대로 유지합니다. 이벤트 시스템 도입 이전의 상태를 역산해 과거 이벤트로 생성하지 않습니다.
- `smartsafehub.status`는 계속 인자 없는 기존 RPC 계약을 유지하므로 이번 수정 때문에 신규 ACL 권한이나 재로그인이 필요하지 않습니다.

### 테스트 및 문서

- 최근 활동 계약 테스트에 `status` RPC가 인자 없이 유지되는지, 프론트엔드가 신규 status 인자를 전송하지 않는지, 이전 handler 응답을 안전하게 처리하는지, 생략된 limit이 `NaN`으로 흐르지 않는지 검증을 추가했습니다.
- README의 최근 활동 조회 구조를 인자 없는 기존 `status` RPC를 사용하는 현재 동작에 맞게 갱신했습니다.

## [0.2.19-r9] - 2026-09-21

### 기능

- 공유기 웹사이트에 `최근 활동` 화면을 추가했습니다. 인터넷 연결, SafeShield 보호/차단 목록, 관리 소프트웨어, 펌웨어, 라이선스와 Health 진단의 정규화 이벤트를 시간순으로 표시하며 `오늘`/`어제`/날짜 단위로 묶어 확인할 수 있습니다.
- 대시보드에도 최근 활동 3건을 요약해서 표시하고 `전체 보기`로 전용 화면에 이동할 수 있도록 연결했습니다. 이벤트 원본에는 UI 문구를 저장하지 않고 프론트엔드가 `event_type + metadata`를 사용자 문구로 렌더링하므로 이후 문구 변경과 다국어 확장을 그대로 유지합니다.
- 인증된 read-only `smartsafehub.activity_history` RPC를 추가했습니다. 최대 128건만 반환하고 손상된 개별 레코드는 건너뛰며, `0.2.19-r8`에서 이미 수집된 `events.jsonl`도 전용 history가 생기기 전까지 호환 fallback으로 읽습니다. 첫 r9 이벤트에서는 기존 r8 outbox를 bounded local history에 먼저 승계해 업그레이드 직후의 최근 활동이 history 생성 시 사라지지 않도록 했습니다.

### 안정성 및 저장 정책

- 향후 Cloud Console 업로드가 outbox의 event를 `ack`해도 공유기 웹사이트의 최근 활동이 사라지지 않도록 `/tmp/smartsafehub/events.jsonl` Cloud outbox와 `/tmp/smartsafehub/activity-history.jsonl` 로컬 표시 history를 분리했습니다. 두 저장소 모두 최대 128건의 휘발성 기록만 유지하며 flash에는 주기적으로 쓰지 않습니다.
- 로컬 최근 활동은 현재 부팅 세션 범위이며 재부팅하면 초기화됩니다. 주기적인 상태 조회 자체는 표시하지 않고 기존과 동일하게 실제 상태 전이가 발생한 경우에만 기록합니다.
- 라이트/다크 모드에서 info/success/warning/error 이벤트의 배경, 테두리, 아이콘과 텍스트 대비가 기존 SmartSafeHub 공통 theme token을 따르도록 구성했습니다.

### 테스트 및 문서

- `tests/test-activity-ui-contract.sh`를 추가해 activity RPC/ACL, r8 fallback, outbox/history 분리, ack 후 local history 보존, 대시보드 3건 요약, 전체 페이지, 모든 현재 event type renderer와 라이트/다크 모드 tone 계약을 검증합니다.
- 기존 event queue 테스트를 확장해 outbox와 local history가 함께 bounded retention을 적용하고, Cloud ack가 로컬 표시 history를 제거하지 않는지 검증합니다.
- README의 활동 이벤트 문서를 공유기 `최근 활동` UI와 Cloud outbox/local history 분리 구조에 맞게 갱신했습니다.

## [0.2.19-r8] - 2026-09-21

### 기능

- 향후 Cloud Console 활동 기록의 공통 원본이 되는 `/usr/libexec/smartsafehub-events`를 추가했습니다. 이벤트는 `event_type`, `severity`, `occurred_at`, `source`, `metadata` 중심의 schema v1 JSONL로 정규화하며 완성된 UI 문구를 저장하지 않습니다.
- `/tmp/smartsafehub/events.jsonl`에 최대 128개의 휘발성 이벤트를 보관하고 동시 writer lock, atomic replace, JSON object metadata 검증, `list`/`ack` 인터페이스를 제공합니다. 이벤트 수집을 위해 flash에 주기적으로 기록하지 않습니다.
- `smartsafehub-events` 부팅 서비스를 추가해 커널 `boot_id`마다 `system.booted`를 한 번만 기록합니다. 서비스가 같은 부팅 중 재시작되어도 중복 부팅 이벤트를 만들지 않습니다.
- 관리 소프트웨어 실제 설치 성공/실패, 펌웨어 설치 시작/설치 직전 실패, 라이선스 활성화/변경/서버 해제 결과를 정규화 이벤트로 연결했습니다.
- Health 진단 주기를 상태 observer로 재사용해 WAN 연결 끊김/복구, SafeShield 보호 활성/비활성, 차단 목록 갱신 성공/실패, Health 고유 이상 시작/변경/해소를 **상태가 실제로 바뀔 때만** 기록합니다. SafeShield 차단 목록 이벤트는 Health 관측 시각이 아니라 SafeShield의 실제 `last_success`/`last_failure` timestamp를 사용합니다.

### 안정성 및 개인정보

- Health observer의 첫 관측은 baseline으로만 저장해 공유기 시작이나 daemon 재시작 직후의 기존 상태를 새 사건으로 오인하지 않습니다. WAN/SafeShield/updater/firmware 문제는 전용 event type으로 분리해 일반 Health issue 이벤트와 중복되지 않도록 했습니다.
- 이벤트 metadata에는 라이선스 키를 기록하지 않으며 `device_uuid`는 로컬에서 임의로 채우지 않고 `null`로 유지합니다. 향후 Cloud 수집 시 인증된 장치 identity를 서버에서 연결하는 경계를 문서화했습니다.
- 현재 패치는 로컬 정규화/큐까지만 포함하며 Cloud 업로드, 유료 entitlement, 서버 보관, 웹사이트 활동 기록 UI는 활성화하지 않습니다.

### 테스트 및 문서

- 정규화 schema, metadata 검증, 큐 최대 개수/oldest eviction, `ack`, boot event 중복 방지와 생산 event source 계약을 검증하는 `tests/test-events.sh`를 추가하고 ShellSpec 전체 계약에 연결했습니다.
- Health 회귀 테스트에 첫 관측 무이벤트, WAN down 반복 polling 중복 방지, 인터넷 복구 중단 시간, SafeShield `last_success` 기반 갱신 이벤트를 검증하는 실행형 시나리오를 추가했습니다.
- 패키지 계약에 event helper/init script 실행 권한과 postinst 강제 enable을 추가하고 README에 이벤트 schema, 현재 source 범위, 휘발성 보관 정책과 향후 Cloud 연결 경계를 문서화했습니다.

## [0.2.19-r7] - 2026-09-21

### 개선

- 대시보드와 SafeShield 화면의 최근 24시간 통계에서 `차단` 수치를 동일한 teal 강조색으로 표시하도록 통일했습니다. DNS 요청 수와 차단율은 기존 기본 색상을 유지해 SafeShield가 실제로 처리한 차단 결과를 가장 먼저 인지할 수 있도록 정보 우선순위를 정리했습니다.
- 다크 모드에서도 기존 SmartSafeHub 테마 매핑을 사용해 차단 수치가 밝은 teal로 자연스럽게 표시됩니다.

### 테스트 및 문서

- 대시보드와 SafeShield 통계 계약 테스트에 최근 24시간 차단 수만 `text-teal-700` 강조를 사용하고, DNS 요청 및 차단율은 기본 텍스트 색상을 유지하는 회귀 검증을 추가했습니다.
- README에 대시보드/SafeShield 차단 수치 강조 정책을 문서화했습니다.

## [0.2.19-r6] - 2026-09-20

### 수정

- 접힌 데스크톱 사이드바의 IPTV Beta 표시를 전체 `Beta` 텍스트에서 단일 `β` 문자로 되돌렸습니다. 대신 `20x20px` 원형 배지와 `13px` 글꼴, 더 명확한 amber surface/테두리를 사용해 좁은 사이드바에서도 크기를 과도하게 차지하지 않으면서 문자가 뭉개지지 않도록 개선했습니다.

### 테스트 및 문서

- IPTV/내비게이션 계약 테스트에 접힌 사이드바가 반드시 단일 `β` 문자를 사용하고 `20x20px` 배지와 `13px` 글꼴을 유지하는지 검증하는 회귀 테스트를 추가했습니다. 기존의 `8px` 크기로 다시 작아지는 회귀도 차단합니다.
- README의 IPTV Beta 배지 설명을 접힌 사이드바의 단일 `β` 원형 배지 동작에 맞게 갱신했습니다.

## [0.2.19-r5] - 2026-09-20

### 수정

- 데스크톱 접힌 사이드바의 IPTV `Beta` 배지를 더 큰 pill 형태로 조정했습니다. 기존의 작은 `β` 단일 문자 배지 대신 읽기 쉬운 `Beta` 텍스트와 충분한 크기·대비를 사용해 라이트/다크 모드 모두에서 뭉개지지 않고 빠르게 인지할 수 있습니다.

### 테스트 및 문서

- IPTV/내비게이션 계약 테스트에 접힌 사이드바의 Beta 배지가 더 이상 `8px` 단일 문자 스타일을 사용하지 않고, 더 큰 pill 크기를 유지하는지 검증하는 회귀 테스트를 추가했습니다.
- README의 IPTV Beta 설명을 접힌 사이드바에서도 읽기 쉬운 Beta 배지를 유지하는 동작에 맞게 갱신했습니다.

## [0.2.19-r4] - 2026-09-20

### 개선

- IPTV Beta 화면에서 SK Broadband와 LG U+가 현재 동일한 IGMP Proxy/IGMP Snooping 프로파일을 사용한다는 점을 명확히 표시하면서도, 향후 KT처럼 별도 방식이 필요한 통신사를 확장할 수 있도록 provider 선택 구조는 유지했습니다.
- 통신사 선택 영역과 현재 지원 프로파일 설명을 카드 형태로 정리해 선택한 통신사와 실제 적용 방식을 한눈에 구분할 수 있도록 개선했습니다. KT는 현재 미지원임을 Beta 안내에서 명확히 표시합니다.
- IPTV 사용 여부 또는 통신사 선택이 저장된 설정과 달라지면 Wi-Fi/LAN/설정 화면과 동일한 amber 경고 아이콘과 `저장되지 않음` 상태를 표시합니다. 저장 전에는 런타임 카드가 마지막 적용 설정 기준이라는 안내도 함께 보여줍니다.

### 테스트 및 문서

- IPTV UI 계약 테스트에 `enabled`와 `provider`를 모두 포함한 dirty-state 판정, amber 경고 아이콘/`저장되지 않음` 표시, 저장된 런타임 기준 안내, SKB/LG U+ 공통 프로파일 설명을 고정하는 회귀 검증을 추가했습니다.
- README의 IPTV Beta 설명을 현재 provider/profile UI와 저장되지 않은 설정 경고 동작에 맞게 갱신했습니다.

## [0.2.19-r3] - 2026-09-20

### 수정

- 패키지 업그레이드 직후 `rpcd reload`가 성공으로 끝났지만 핵심 `smartsafehub` ubus 객체가 등록되지 않아 로그인 화면에서 `system_root_password_status`가 `Not found`가 되던 실기기 장애를 수정했습니다.
- postinst가 직접 `rpcd reload`만 호출하지 않고 `/usr/libexec/smartsafehub-rpcd-reconcile`을 실행하도록 변경했습니다. helper는 reload 후 핵심 ubus 객체가 실제 등록됐는지 확인하고, 등록되지 않은 경우에만 `rpcd restart`로 자동 복구합니다. 정상 reload에서는 restart하지 않아 기존 세션 영향을 최소화합니다.

### 테스트 및 문서

- 실기기에서 확인된 `reload 성공 + smartsafehub 객체 누락` 상태를 mock으로 재현하고 restart fallback으로 복구되는지 실행형 회귀 테스트를 추가했습니다. 정상 reload, reload 자체 실패, restart 후에도 미복구되는 오류 경로도 함께 검증합니다.
- 패키지 계약 테스트에 rpcd reconcile helper 사용을 고정하고 ShellSpec 전체 계약에 새 회귀 테스트를 연결했습니다.
- README에 패키지 업그레이드 시 rpcd self-heal 정책을 문서화했습니다.

## [0.2.19-r2] - 2026-09-20

### 기능

- 네트워크 메뉴에 `IPTV` Beta 화면을 추가하고 SK Broadband/LG U+의 일반적인 멀티캐스트 IPTV 구성을 지원합니다.
- IPTV 활성화 시 `igmpproxy`를 WAN upstream/LAN downstream으로 구성하고 upstream `altnet`을 `0.0.0.0/0`으로 설정하며, LAN bridge의 IGMP snooping을 함께 활성화합니다.
- IPTV 비활성화 시 IGMP Proxy 서비스를 중지·비활성화하고, IPTV 활성화 전에 사용하던 LAN bridge의 IGMP snooping 값을 복원합니다.

### 안정성

- IPTV 설정 적용 전에 SmartSafeHub/network/igmpproxy UCI 파일과 IGMP Proxy 서비스 상태를 스냅샷하고, commit 또는 runtime 적용에 실패하면 이전 설정과 서비스 상태로 복구합니다.
- rollback 파일 복원은 ucode `fs.writefile()`의 기록 바이트 수를 검증해 복구 성공 여부를 정확히 판정합니다.
- 기존 `igmpproxy`에 WAN 이외 upstream 또는 복수 upstream이 있으면 사용자의 커스텀 구성을 덮어쓰지 않고 충돌 오류를 반환합니다.
- 현재 OpenWrt igmpproxy의 runtime firewall 연동을 사용하므로 SmartSafeHub가 별도 firewall 규칙을 중복 생성하지 않습니다.

### 테스트 및 문서

- IPTV RPC/ACL, IGMP Proxy·IGMP snooping 구성, rollback, 서비스 lifecycle, Beta UI, SKB/LG U+ 선택 제한을 검증하는 회귀 테스트를 추가했습니다.
- README에 IPTV Beta 기능, 의존성, 적용 방식과 현재 지원 범위를 문서화했습니다.

## [0.2.19-r1] - 2026-09-20

### 개선

- select box의 커스텀하여, popup 위치의 일관성을 올렸고 사용성도 개선하였습니다.

### 수정

- 예약 재부팅 기능이 시작되지 않던 버그를 수정하였습니다.

## [0.2.18-r4] - 2026-09-20

### 수정

- 패키지 설치·업그레이드 시 `smartsafehub-maintenance` procd 서비스를 명시적으로 enable하도록 수정했습니다. maintenance 서비스가 추가되기 전 버전에서 업그레이드한 장치에서도 rc.d 시작 링크를 복구해 재부팅 이후 예약 재부팅 기능이 계속 동작하도록 합니다.
- postinst에서는 maintenance 서비스를 강제 restart하지 않고 enable만 수행해 패키지 설치 시 불필요한 중복 재시작을 피합니다.

### 테스트 및 문서

- 패키지 계약 테스트에 `smartsafehub-maintenance enable`이 항상 포함되고 `PKG_UPGRADE` 또는 기존 enabled 상태에 따라 조건부로 생략되지 않는지 검증하는 회귀 테스트를 추가했습니다.
- README에 maintenance 서비스의 업그레이드 복구 정책과 postinst 서비스 enable 동작을 문서화했습니다.

## [0.2.18-r3] - 2026-09-20

### 개선

- 공유기 웹사이트에 남아 있던 native `<select>`를 SmartSafeHub 공통 커스텀 드롭다운으로 교체했습니다. Wi-Fi 보안 방식, LAN 서브넷/DHCP 임대 시간, 시간대, 예약 재부팅 주기/요일, 관리 소프트웨어 업데이트 확인 주기가 운영체제별 native popup 대신 동일한 제품 UI를 사용합니다.
- 드롭다운 메뉴를 SmartSafeHub 앱 루트에 고정 위치로 렌더링해 카드의 overflow 영향 없이 트리거 폭과 위치에 맞추고, 화면 아래 공간이 부족하면 위쪽으로 자동 전환합니다. 선택 항목에는 teal 상태 표시를 사용하고 라이트/다크 모드 surface를 동일하게 유지합니다.
- 바깥 클릭, `Escape`, 방향키, `Home`/`End`, `Enter`/`Space`, `Tab` 키보드 조작을 지원하고 Shadow DOM 환경에서는 `composedPath()`를 사용해 내부 클릭이 외부 클릭으로 오인되지 않도록 처리했습니다.

### 테스트 및 문서

- 모든 frontend source에서 native `<select>`가 다시 추가되지 않는지, 공통 dropdown의 listbox/option 접근성·팝업 위치 보정·Shadow DOM 외부 클릭 처리·라이트/다크 모드 계약을 검증하는 회귀 테스트를 추가했습니다.
- 기존 Wi-Fi, 시스템 시간, 업데이트 UI 계약을 native select 스타일 검사 대신 공통 `CustomSelect` 사용 여부를 검증하도록 갱신했습니다.
- README의 선택 컨트롤 설명을 공통 커스텀 드롭다운 동작에 맞게 갱신했습니다.

## [0.2.18-r2] - 2026-09-20

### 수정

- 실제 기기에서 border가 보이지 않는 문제를 수정하였습니다.

### 테스트

- 다시 border 관련 문제가 발생하지 않도록 회귀 테스트 코드를 추가하였습니다.

## [0.2.18-r1] - 2026-09-20

### 개선

- 경험의 일관성을 위해 Cloud Console과 UI의 통일성을 맞췄습니다.
- 업데이트 확인과 관련 알림을 개선하였습니다.

### 수정

- Updater가 시작되지 않던 버그를 수정하였습니다.

## [0.2.17-r9] - 2026-09-20

### 개선

- SafeShield의 유료 멤버십 배지를 지속적으로 빛나는 프로모션 배지 대신 정적인 premium chip 형태로 정리했습니다. ULTIMATE의 하단 amber glow와 shine 애니메이션을 제거하고, 얕은 그림자·1px 테두리·절제된 bronze surface만 사용해 라이트 모드에서도 주변 카드와 자연스럽게 어울리도록 했습니다.
- PRO는 teal, ULTIMATE는 bronze, PLUS를 포함한 기타 유료 플랜은 blue 계열을 유지하되 모든 등급에서 외부 glow와 아이콘 glow를 제거했습니다. 다크 모드도 같은 색상 체계를 더 어두운 surface로 표현해 등급 구분은 유지하면서 과한 광택 효과를 없앴습니다.
- 중복으로 존재하던 다크 모드 멤버십 badge override를 한 군데로 통합해 이후 스타일 수정 시 실제 적용 규칙을 추적하기 쉽게 했습니다.

### 테스트 및 문서

- `tests/test-safeshield-page-contract.sh`에 정적 ULTIMATE/PRO/기타 유료 플랜 surface, glow·shine 제거, 다크 모드 ULTIMATE 규칙 단일 정의를 검증하는 소스 스타일 계약을 추가했습니다.
- README의 유료 플랜 표시 설명을 정적인 premium chip 디자인에 맞게 갱신했습니다.

## [0.2.17-r8] - 2026-09-20

### 개선

- 데스크톱 상단 헤더와 사이드바 브랜드 영역의 높이를 `72px`로 통일했습니다. 두 영역의 하단 경계선과 사이드바 접기/펼치기 버튼 중심선이 같은 위치에 오도록 맞춰 application shell의 일체감을 높였습니다.
- 높이는 줄였지만 `SMARTSAFEHUB` eyebrow, 굵은 페이지 제목, 한 줄 설명, `40x40px` 테마/새로고침 액션과 사이드바의 `40px` 브랜드 아이콘은 그대로 유지해 기존 공유기 UI의 빠른 현재 위치 인지와 강한 브랜드 표현을 보존했습니다.
- 모바일 상단 내비게이션과 모바일 페이지 헤더의 기존 높이/간격은 변경하지 않아 터치 영역과 safe-area 동작을 유지합니다.

### 테스트 및 문서

- `tests/test-navigation-contract.sh`에 데스크톱 제품 헤더와 사이드바 브랜드 영역이 정확히 `72px`를 사용하고, 사이드바 토글 기준선도 같은 `72px`에 맞는지 검증하는 회귀 계약을 추가했습니다.
- README에 데스크톱 application shell의 공통 `72px` 헤더 규칙과 유지되는 시각적 강조 요소를 문서화했습니다.

## [0.2.17-r7] - 2026-09-20

### 안정성

- 로컬 개발용 `SMARTSAFEHUB_DEV_ROUTER` 환경 변수를 Vite 설정 모듈 로드 시점에 읽지 않고 `command === 'serve'`인 경우에만 읽도록 변경했습니다. production build에서는 해당 환경 변수가 설정되어 있거나 잘못된 값이어도 읽거나 검증하지 않습니다.
- 개발용 `/cgi-bin/*` proxy 설정도 실제 dev proxy가 구성된 경우에만 Vite `server` 설정에 포함되도록 분리해 production build 설정과 개발 서버 설정의 경계를 명확히 했습니다.

### 테스트 및 문서

- 패키지 계약 테스트에 `SMARTSAFEHUB_DEV_ROUTER`가 `defineConfig` callback 안에서만 읽히는지, production build base가 기존 `/luci-static/smartsafehub/`로 유지되는지 검증하는 회귀 계약을 추가했습니다.
- README에 production build에서는 개발용 router 환경 변수를 읽거나 검증하지 않는다는 점을 명시했습니다.

## [0.2.17-r6] - 2026-09-20

### 수정

- 로컬 Vite 개발 서버가 production과 같은 `/luci-static/smartsafehub/` base를 사용하면서 `/cgi-bin/luci/*` 요청을 Vite 자체 경로로 처리해 `did you mean to visit /luci-static/smartsafehub/cgi-bin/...` 오류가 발생하던 문제를 수정했습니다.
- `npm run dev`에서는 Vite public base를 `/`로 사용하고, production build에서는 기존 `/luci-static/smartsafehub/` base를 그대로 유지하도록 분리했습니다. 이에 따라 로컬 개발 주소는 `http://localhost:5173/`가 되며 `/cgi-bin/*` 요청이 `SMARTSAFEHUB_DEV_ROUTER` proxy에 정상적으로 전달됩니다.
- 개발용 Shadow DOM stylesheet 경로도 root dev base에 맞춰 `/src/styles/`로 되돌렸습니다. production asset 경로와 빌드 결과물에는 영향을 주지 않습니다.

### 테스트 및 문서

- 패키지 계약 테스트에 Vite serve/build base 분리, 개발용 stylesheet root 경로, `/cgi-bin` proxy 계약을 추가했습니다.
- README의 로컬 개발 접속 주소를 `http://localhost:5173/`로 갱신하고 production base가 유지된다는 점을 명시했습니다.

## [0.2.17-r5] - 2026-09-20

### 개발 환경

- `SMARTSAFEHUB_DEV_ROUTER` 환경 변수를 지정해 `npm run dev`를 실행하면 Vite가 `/cgi-bin/*` 요청을 실제 SmartSafeHub 공유기로 프록시하도록 개발 서버 설정을 추가했습니다. 공유기 주소를 소스에 하드코딩하지 않으며 HTTP/HTTPS 장치를 모두 지원합니다.
- Vite의 `/luci-static/smartsafehub/` base 아래에서 Shadow DOM용 `app.css`가 정상 로드되도록 개발용 `index.html`의 asset base를 수정했습니다. 로컬 개발 화면에서 Tailwind 유틸리티가 빠져 SVG 아이콘과 레이아웃이 비정상적으로 커지는 문제를 방지합니다.
- 개발 proxy는 환경 변수가 있을 때만 실제 공유기로 요청을 전달하며 production build와 OpenWrt 런타임 경로에는 영향을 주지 않습니다.

### 테스트 및 문서

- 패키지 계약 테스트에 개발용 Shadow DOM stylesheet 경로, `SMARTSAFEHUB_DEV_ROUTER` 기반 proxy, `/cgi-bin` 전달, production base 유지 계약을 추가했습니다.
- README에 실제 공유기 API를 사용한 로컬 Vite 개발 방법과 최종 장치 검증이 필요한 범위를 문서화했습니다.

## [0.2.17-r4] - 2026-09-20

### 수정

- 공유기 웹사이트의 데스크톱 상단 테마 전환/새로고침 버튼에서 **테두리 색상만** SmartSafeHub Cloud Console과 동일하게 고정했습니다. 버튼 크기, 아이콘, 배경, 그림자, 간격, 헤더 배치는 변경하지 않습니다.
- 라이트 모드는 Cloud Console의 `slate-200`(`#e2e8f0`), 다크 모드는 `slate-700`(`#334155`)을 사용하고, hover 테두리도 각각 `teal-300`(`#5eead4`)과 `teal-700`(`#0f766e`)로 맞췄습니다.
- Shadow DOM 내부의 공통 테마 규칙이 버튼 전용 테두리 색을 덮어쓰지 않도록 전용 selector에서 해당 색상만 명시적으로 우선 적용합니다.

### 테스트 및 문서

- `tests/test-navigation-contract.sh`에서 라이트/다크 및 hover 상태의 상단 액션 테두리 색상이 Cloud Console 토큰과 일치하는지 검증합니다.
- README에 공유기 웹사이트와 Cloud Console의 상단 액션 테두리 색상 통일 정책을 반영했습니다.

## [0.2.17-r3] - 2026-09-20

### 개선

- 데스크톱 가용 폭이 본문 최대 폭인 `1600px`을 넘는 대화면에서 본문을 가운데 정렬하지 않고 사이드바 다음의 왼쪽 gutter 기준으로 유지하도록 변경했습니다. 상단 헤더는 전체 가용 폭을 사용하여 제목은 본문 시작선에 맞추고 테마·새로고침 액션은 화면 오른쪽 gutter에 유지합니다.
- 공유기 웹사이트의 데스크톱 테마·새로고침 버튼을 Cloud Console과 같은 `40x40px` 둥근 사각형 버튼, `20px` 아이콘, teal hover 상태로 통일했습니다. 다크 모드에서는 `slate-700` 수준의 테두리를 사용해 어두운 헤더 배경에서도 버튼 경계가 명확하게 보이도록 했습니다.

### 테스트

- 내비게이션 계약에 본문 최대 폭 유지/대화면 왼쪽 정렬, 헤더 전체 폭 사용, 오른쪽 액션 정렬, Cloud Console형 버튼 크기와 다크 모드 대비가 유지되는지 검증하는 회귀 테스트를 추가했습니다.

## [0.2.17-r2] - 2026-09-20

### 수정

- 자동 업데이트 확인이 6시간 주기로 활성화되어 있어도 마지막 성공 확인이 12시간 이상 지나면 대시보드에서만 `업데이트 확인 지연`으로 보이고 업데이트 페이지는 `최신 상태`/`최신 버전`으로 표시하던 상태 불일치를 수정했습니다. 두 화면이 동일한 freshness helper를 사용해 설정 주기의 2배(최소 2시간) 이상 지연되면 amber 경고 상태로 표시합니다.
- 기존 설치를 업그레이드하는 과정에서 `smartsafehub-updater` init script의 부팅 시작 링크가 누락될 수 있어 자동 확인이 실제로 실행되지 않는 경우를 방지하도록 runtime post-install hook이 updater 서비스를 항상 `enable`하도록 보강했습니다. updater가 자기 자신을 설치하는 도중 서비스를 재시작해 설치를 방해하지 않도록 post-install에서는 `restart`하지 않습니다.
- 지연 상태에서는 업데이트 페이지의 `Available` 값을 `확인 필요`로 표시하고, 기존의 초록색 `최신 버전을 사용 중입니다.` 결과 패널 대신 마지막 확인 시각과 수동 확인 안내가 포함된 amber 경고 패널을 표시합니다.

### 테스트

- 대시보드와 업데이트 페이지가 동일한 관리 소프트웨어 freshness helper를 사용하는지, 지연 상태에서 초록색 최신 상태를 표시하지 않는지 검증하는 UI 계약을 추가했습니다.
- 패키지 post-install hook이 `smartsafehub-updater enable`을 항상 수행하고 자기 업데이트 중 서비스 강제 재시작을 하지 않는지 검증하는 패키지 계약을 추가했습니다.

## [0.2.17-r1] - 2026-09-19

### 개선

- 구석구석 UI를 다듬어서 전반적인 사용성을 올렸습니다.
- 시스템 안정성을 개선하였습니다.

### 수정

- SafeShield의 최소 버전을 0.3.24 이상으로 올렸습니다.

## [0.2.16-r15] - 2026-09-19

### 수정

- SafeShield의 최소 버전을 0.3.24 이상으로 강제합니다.

## [0.2.16-r14] - 2026-09-19

### 개선

- 설정 페이지의 `시스템 관리` 영역을 데스크톱에서 2열 한 줄로 압축했습니다. 기존에 전체 폭을 차지하던 `설정 백업 및 복원` 카드를 절반 폭으로 줄이고 내부의 백업/복원 기능을 세로로 정리했습니다.
- 별도 카드였던 `공유기 재부팅`과 `고급 설정`을 `시스템 도구` 카드 하나로 통합했습니다. 재부팅은 기존 확인 절차를 유지하면서 compact action으로 표시하고, LuCI 고급 설정과 시스템 로그 진입점도 같은 카드에 배치했습니다.
- 재부팅 전용 카드가 사라지면서 더 이상 사용되지 않는 `ActionCard`의 danger 변형도 제거해 공통 카드 스타일 분기를 정리했습니다.
- 모바일에서는 두 카드가 기존처럼 한 열로 쌓이며, 라이트/다크 모드에서 기존 slate/rose 테마 토큰을 그대로 사용합니다.

### 테스트 및 문서

- `tests/test-settings-ui-contract.sh`에 백업 카드의 전체 폭 제거, compact 세로 레이아웃, 통합 시스템 도구 카드와 재부팅/고급 도구 접근성 계약을 추가했습니다.
- README의 설정 화면 설명을 새 시스템 관리 2열 레이아웃에 맞게 업데이트했습니다.

## [0.2.16-r13] - 2026-09-19

### 개선

- 업데이트 페이지의 `수동 펌웨어 설치` 펼침 영역에서 제목/설명과 안전 안내 사이의 세로 여백을 줄였습니다. 기존 한 줄 안전 안내 동작은 유지하면서 펼친 상태가 불필요하게 넓어 보이지 않도록 본문 상단 여백만 조정했습니다.

### 테스트 및 문서

- `tests/test-update-ui-contract.sh`에 수동 펌웨어 펼침 본문의 컴팩트한 상단 여백 계약을 추가했습니다.
- README의 수동 펌웨어 설치 UI 설명에 펼친 상태의 간격 정책을 반영했습니다.

## [0.2.16-r12] - 2026-09-19

### 개선

- 업데이트 페이지의 수동 펌웨어 설치 안내 문구가 넓은 화면에서도 좁은 최대 폭 때문에 두 줄로 나뉘던 문제를 수정했습니다. 데스크톱에서는 수동 설치 영역 전체 폭을 활용해 한 줄로 표시하고, 작은 화면에서는 기존처럼 자연스럽게 줄바꿈됩니다.

### 테스트 및 문서

- `tests/test-update-ui-contract.sh`에 수동 펌웨어 안전 안내의 데스크톱 한 줄 표시와 불필요한 `max-w-3xl` 제한 제거 계약을 추가했습니다.
- README의 수동 펌웨어 설치 UI 설명에 넓은 화면 한 줄 표시 동작을 반영했습니다.

## [0.2.16-r11] - 2026-09-19

### 개선

- 업데이트 페이지의 `펌웨어 업데이트`와 `관리 소프트웨어 업데이트` 소개 문구를 더 짧고 직접적인 표현으로 정리하고, 충분한 폭이 있는 데스크톱 레이아웃에서는 한 줄로 유지하도록 조정했습니다. 카드 우측 동작 버튼 때문에 마지막 몇 글자만 다음 줄로 떨어지는 어색한 줄바꿈을 방지합니다.
- 작은 화면에서는 기존처럼 자연스럽게 줄바꿈되므로 모바일 가독성과 반응형 동작은 유지합니다.

### 테스트 및 문서

- `tests/test-update-ui-contract.sh`에 두 업데이트 카드의 간결한 문구와 데스크톱 한 줄 표시 계약을 추가했습니다.
- README의 업데이트 UI 설명에 넓은 화면에서 소개 문구를 한 줄로 유지하는 동작을 반영했습니다.

## [0.2.16-r10] - 2026-09-19

### 개선

- 관리 소프트웨어의 자동 업데이트 설정에서 자동 확인 여부·확인 주기·자동 설치 여부·설치 시각을 변경해 저장된 값과 달라지면 카드 헤더에 amber 경고 아이콘과 `저장되지 않음` 상태를 표시하도록 개선했습니다. 원래 값으로 되돌리거나 저장에 성공하면 경고가 사라집니다.
- LAN 및 DHCP 설정에서도 공유기 주소, DHCP 범위, 서브넷, 임대 시간, DHCP 서버 사용 여부 중 하나라도 저장값과 다르면 같은 `저장되지 않음` 상태를 표시합니다. 편집 중에는 서버 상태 갱신이 입력값을 덮어쓰지 않으며 실제 변경이 있을 때만 `설정 저장` 버튼을 활성화합니다.
- Wi-Fi 설정은 각 무선 네트워크 카드별로 SSID, 사용 여부, 보안 방식 또는 새 비밀번호가 저장 상태와 다를 때 동일한 경고를 표시하고 실제 변경이 있을 때만 저장할 수 있도록 했습니다. 고급 보안 설정 유지로 되돌릴 때 적용할 수 없는 임시 비밀번호도 함께 비웁니다.
- 세 화면 모두 예약 재부팅과 같은 amber 경고 스타일, `AlertIcon`, `role="status"`, `aria-live="polite"`를 사용해 라이트/다크 모드와 접근성 표현을 일관되게 맞췄습니다.

### 테스트 및 문서

- 자동 업데이트, LAN/DHCP, Wi-Fi의 저장 전 변경 상태·원래 값 복원·저장 버튼 활성 조건·접근 가능한 경고 표시를 검증하는 계약 테스트를 보강했습니다.
- README의 LAN/DHCP, Wi-Fi, 업데이트 설명에 저장되지 않은 변경사항 표시 동작을 반영했습니다.

## [0.2.16-r9] - 2026-09-19

### 개선

- 예약 재부팅의 사용 토글, 주기, 요일, 재부팅 시각 중 하나라도 장치에 저장된 값과 달라지면 섹션 헤더에 amber 경고 아이콘과 `저장되지 않음` 상태를 표시하도록 개선했습니다. 토글을 켜거나 끈 직후 아직 저장하지 않은 상태를 실제 적용 상태로 오인하는 문제를 줄입니다.
- 변경값을 원래 저장된 값으로 되돌리거나 `예약 저장`이 성공해 저장 결과가 반영되면 경고가 자동으로 사라집니다. 저장 실패 시에는 기존 저장값과 차이가 유지되므로 경고도 함께 유지됩니다.
- 경고는 `role="status"`와 `aria-live="polite"`를 사용해 보조기기에서도 변경 상태를 확인할 수 있으며, 기존 amber 다크 테마 매핑을 재사용해 라이트/다크 모드 대비를 유지합니다.

### 테스트 및 문서

- 예약 재부팅 dirty state와 경고 아이콘/문구가 연결되어 있는지, 접근성 상태와 다크 모드 amber 토큰 계약이 유지되는지 테스트를 보강했습니다.
- README에 저장되지 않은 예약 재부팅 변경사항의 표시 동작을 추가했습니다.

## [0.2.16-r8] - 2026-09-19

### 개선

- `시스템 관리`에서 별도 전체 폭 카드로 표시하던 `예약 재부팅`을 `장치 설정 > 시간 및 시간대` 카드 하단의 하위 섹션으로 이동했습니다. 시간대와 예약 재부팅처럼 같은 기준 시각을 사용하는 설정을 한 곳에 모아 기능 관계를 명확하게 하고 설정 페이지의 세로 길이를 줄였습니다.
- 예약 재부팅의 사용 토글을 섹션 헤더와 결합하고 주기·요일·재부팅 시각 및 현재 예약 요약을 더 압축된 레이아웃으로 정리했습니다. 기존 저장 상태, 오류 피드백, 업데이트 작업 중 최대 2시간 연기 안내와 모바일 세로 배치는 유지합니다.
- `장치 설정`과 `시스템 관리` 설명 문구를 새 정보 구조에 맞게 조정했습니다. 기존 라이트/다크 테마 토큰을 그대로 사용해 두 테마의 배경·테두리·텍스트 대비가 유지됩니다.

### 테스트 및 문서

- `tests/test-settings-ui-contract.sh`와 `tests/test-scheduled-reboot.sh`에 예약 재부팅이 독립 시스템 관리 카드가 아니라 시간 및 시간대 카드 내부의 접근 가능한 하위 섹션으로 렌더링되는 계약을 추가했습니다.
- README에 예약 재부팅 설정의 새 배치와 반응형 동작을 반영했습니다.

## [0.2.16-r7] - 2026-09-18

### 기기별 통계 TOP 3 인지성 개선

- 기기별 통계의 기본 3개 미리보기 상태에 `차단 TOP 3` 배지를 추가해 전체 목록 중 일부만 표시 중이라는 점을 즉시 인지할 수 있도록 했습니다.
- 미리보기 목록 아래에 `전체 N개 기기 중 차단 수 기준 상위 3개를 표시하고 있습니다.` 안내를 추가해 TOP 3의 선정 기준과 전체 기기 수를 함께 설명합니다. 전체 보기 상태에서는 배지와 안내를 숨겨 중복 정보를 줄였습니다.
- 기존 라이트/다크 테마 토큰과 전체 보기/간단히 보기, 페이지네이션 동작은 그대로 유지합니다.

### 테스트 및 문서

- `tests/test-statistics-ui-contract.sh`에 TOP 3 배지와 차단 수 기준 안내 계약을 추가했습니다.
- README의 기기별 통계 설명에 TOP 3 표시와 선정 기준 안내를 반영했습니다.

## [0.2.16-r6] - 2026-09-18

### 기기별 통계 목록 압축

- SafeShield 기기별 통계를 기본적으로 차단 수 기준 상위 3개만 미리보기로 표시하도록 변경해 긴 기기 목록 때문에 보호 구성과 설정 영역까지 과도하게 스크롤해야 하던 문제를 줄였습니다.
- `전체 N개 기기 보기`로 기존 전체 목록을 펼칠 수 있으며, 전체 보기에서는 기존 10개 단위 페이지네이션을 그대로 유지합니다. `간단히 보기`로 다시 접으면 첫 페이지로 돌아가 3개 미리보기 상태가 됩니다.
- 전체 보기 토글에 `aria-expanded`와 `aria-controls`를 연결해 상태와 대상 목록을 보조 기술에서도 확인할 수 있도록 했습니다. 라이트/다크 모드 모두 기존 테마 토큰을 사용합니다.

### 테스트 및 문서

- `tests/test-statistics-ui-contract.sh`에 기본 3개 미리보기, 전체 보기 토글, 접근성 속성, 펼친 상태에서만 페이지네이션을 제공하는 계약을 추가했습니다.
- README에 기기별 통계의 미리보기/전체 보기 동작을 반영했습니다.

## [0.2.16-r5] - 2026-09-18

### 라이선스 daemon 종료 안정성

- `smartsafehub-license daemon`의 30초 startup/300초 상태 확인 대기를 interrupt 가능한 child `sleep` + `wait` 구조로 변경했습니다. SIGTERM/SIGINT를 받으면 대기 중인 child를 깨우고 scheduler loop를 종료해 서비스 stop/restart 시 장기 sleep 때문에 procd가 SIGKILL을 보내던 상황을 방지합니다.
- Hub 요청 timeout 10초보다 긴 `procd term_timeout 15`를 설정해 HTTP 요청 처리 중 종료가 들어온 경우에도 정상 정리 시간을 확보했습니다.

### 라이선스 진단 상태

- `/tmp/smartsafehub/license.json`에 `lastHttpStatus`, `lastActivationResult`, `lastActivationErrorCode`를 추가했습니다. 성공한 Hub JSON API 요청은 HTTP 200으로 기록하고 실제 상태 코드를 신뢰할 수 없는 fetch 실패는 `null`로 남깁니다.
- 마지막 명시적 activation의 성공/실패 결과와 오류 코드를 주기 `status-sync`, revoke 후 로컬 clear, unconfigured 전환과 분리해 보존하도록 했습니다. 현재 동작 상태와 마지막 사용자 activation 결과를 각각 확인할 수 있습니다.
- 평문 라이선스 키를 상태 파일에 저장하지 않는 기존 보안 계약과 atomic write 동작은 유지합니다.

### 테스트 및 문서

- `tests/test-license.sh`에 daemon 장기 sleep 중 SIGTERM 종료, Hub HTTP 진단 상태, activation 결과/오류 보존 계약을 추가했습니다.
- README와 아키텍처 문서에 daemon 종료 경계와 새 진단 필드 의미를 반영했습니다.

## [0.2.16-r4] - 2026-09-18

### 라이선스 활성화 안정성

- `smartsafehub.license_activate` RPC 안에서 `safeshield.status`를 동기 호출하던 경로를 제거했습니다. RPC는 라이선스 키를 mode 0600 임시 요청에 기록하고 detached `smartsafehub-license activate` helper를 시작한 뒤 즉시 반환하며, SafeShield 장치 identity 조회와 Hub `/licenses/activate` 요청은 helper 프로세스에서 수행합니다. 이로써 rpcd 내부의 nested ubus 대기로 라이선스 등록 요청이 20초 후 timeout되던 문제를 방지합니다.
- detached helper가 SafeShield의 authoritative physical fingerprint, configured vendor/model/arch/memory 및 SafeShield 버전을 읽어 기존 Hub activate payload를 동일하게 구성합니다. Hub activation이 성공한 뒤에만 SafeShield 공식 `license_update` API로 키를 저장하는 기존 보안 경계는 유지합니다.
- SafeShield identity/profile 조회 실패를 각각 `LICENSE_DEVICE_IDENTITY_UNAVAILABLE`, `LICENSE_DEVICE_PROFILE_UNAVAILABLE`로 상태 파일에 기록하고 Hub 요청이나 로컬 키 저장을 진행하지 않도록 했습니다.

### 라이선스 UI 피드백

- 라이선스 등록·조회·제거의 성공/오류 피드백을 페이지 상단 공통 배너가 아니라 사용자가 작업한 라이선스 카드 내부에 표시하도록 분리했습니다. 등록 중에는 카드 안에서 `라이선스를 확인하고 이 기기에 적용하고 있습니다…` 상태를 즉시 보여줍니다.
- 라이선스 status polling을 0.5초에서 1초 간격으로 완화하고, 각 상태 조회 timeout을 5초로 제한했습니다. 일시적인 timeout/네트워크 오류는 최대 2회 재시도하며, 최종 확인이 늦어지는 경우 실제 실패로 단정하지 않고 상태 확인 지연 안내를 표시합니다.
- 라이선스 카드의 진행 안내는 기존 teal 계열 테마 토큰을 사용해 라이트/다크 모드 모두에서 배경, 테두리와 텍스트 대비가 유지되도록 했습니다.

### 테스트 및 문서

- `tests/test-license.sh`에 rpcd 경로에서 SafeShield 동기 호출 금지, detached helper의 device payload 구성, identity 조회 실패 시 fail-closed 동작, 카드 내부 feedback routing과 완화된 polling 계약을 추가했습니다.
- README와 아키텍처 문서에 비동기 activation 경계와 라이선스 카드 피드백 동작을 반영했습니다.

## [0.2.16-r3] - 2026-09-18

### 테스트 안정성

- `tests/test-license.sh`의 라이선스 mock 상태를 각 시나리오 시작 전에 명시적으로 초기화하도록 변경해 macOS `/bin/sh`를 포함한 셸 구현 차이로 이전 실패 시나리오의 `MOCK_*` 값이 다음 stale-lock 복구 테스트에 영향을 주지 않도록 했습니다.
- stale activation lock 복구 시나리오는 `license_get`과 Hub status mock을 정상 상태로 명시한 뒤 lock 제거, 임시 activation request 정리, `/licenses/status` 재개까지 독립적으로 검증합니다.

## [0.2.16-r2] - 2026-09-18

### 라이선스 lifecycle 분리

- SmartSafeHub Hub의 `/api/v1/licenses/activate`와 `/api/v1/licenses/status`를 사용하는 `smartsafehub-license` procd daemon과 helper를 추가했습니다. 새 라이선스는 Hub activation이 성공한 뒤에만 SafeShield 공식 `license_update` API로 저장합니다.
- 기본 5분 주기의 상태 동기화가 서버의 명시적 `clear_license` 지시를 받았을 때만 로컬 라이선스를 제거하도록 했습니다. Hub 통신 오류나 비정상 응답만으로 기존 로컬 라이선스를 삭제하지 않습니다.
- Hub 요청의 physical fingerprint와 장치 프로필은 별도 계산하지 않고 `safeshield.status.device`의 authoritative identity를 재사용합니다. SafeShield UCI나 내부 파일은 직접 수정하지 않습니다.
- `daemon`, `activate`, `status-sync`, `status` 명령 경계와 `/tmp/smartsafehub/license.json` 상태 모델을 분리해 향후 `smartsafehub-agent license ...` 모듈로 옮길 수 있도록 구성했습니다. updater처럼 별도 상태 머신인 기능과는 결합하지 않습니다.

### 안정성 및 보안

- 명시적 activate와 주기 status-sync가 겹칠 때 activation single-flight lock을 우선해 상태 파일이나 로컬 키 갱신이 서로 덮어쓰지 않도록 했습니다. SafeShield `license_get` 실패는 라이선스 미설정으로 오인하지 않고 `LICENSE_LOCAL_READ_FAILED`로 기록합니다.
- 평문 라이선스 키를 helper command line이나 runtime 상태 파일에 넣지 않고 mode 0600의 일시 request file을 통해 전달하며 activate 처리 후 제거합니다.
- `license_status`와 `license_activate` RPC/ACL, 프런트엔드 activation polling을 추가하고 기존의 새 키 직접 `safeshield.license_update` 경로를 Hub activation 경로로 전환했습니다. 사용자의 명시적 로컬 라이선스 제거와 현재 키 불러오기는 기존 SafeShield 공식 API 계약을 유지합니다.

### 테스트 및 문서

- Hub activate 성공/거부, active/revoked status, `clear_license`, 서버 장애 fail-open, SafeShield 로컬 조회 실패, 미설정 상태와 activate/status 경쟁 조건을 검증하는 `test-license.sh`를 추가했습니다.
- RPC/ACL, 패키지 설치 서비스, shell 정적 검증 계약에 새 라이선스 모듈을 포함하고 README 및 아키텍처 문서를 갱신했습니다.

## [0.2.16-r1] - 2026-09-18

### 기능

- LAN 관리 기능을 추가하였습니다.
- 자가 진단 기능과 원격 전송 기능을 추가하였습니다.

### 개선

- 루트 url을 사용하여서 사용성을 개선하였습니다.
- 대시보드, 펌웨어 페이지의 UI를 개선하였습니다.
- 재부팅 후 진단 기능이 준비가 된 이후에 확인하도록 개선하였습니다.

## [0.2.15-r29] - 2026-09-18

### Health Reporter 상태 UI 개선

- 원격 상태 보고 토글을 변경하는 즉시 프런트엔드 상태를 낙관적으로 반영해 스위치와 `켜짐/꺼짐` 안내가 RPC 완료를 기다리지 않고 사용자 입력에 바로 반응하도록 했습니다. 저장 실패 시에는 이전 상태로 되돌립니다.
- Reporter를 켠 직후 런타임 상태 파일에 이전 `disabled` 값이 잠시 남아 있어도 `꺼짐`으로 표시하지 않고 `첫 보고 준비 중/진행 중`으로 표현합니다. 마지막 보고가 아직 없으면 `첫 보고 대기 중`으로 명확하게 표시합니다.
- 토글 성공 뒤 0.4~4초의 짧은 확인 조회를 수행해 detached Health cycle의 첫 서버 보고 결과를 60초 정규 polling보다 빠르게 화면에 반영합니다. 연속 토글 시 이전 확인 작업이 최신 상태를 덮어쓰지 않도록 mutation sequence를 사용합니다.
- 원격 상태 보고 영역에 현재 활성/비활성 상태를 설명하는 별도 상태 패널과 배지를 추가하고, Trial은 실제 플랜과 함께 `ULTIMATE · 체험`처럼 표시합니다. 라이트/다크 모드 모두 기존 테마 팔레트 매핑을 사용합니다.

### 테스트 및 문서

- Health 계약 테스트에 즉시 optimistic 상태 반영, 실패 시 rollback, 짧은 확인 polling, stale `disabled/never` 상태의 `첫 보고 준비 중` 표시와 명확한 켜짐/꺼짐 안내를 검증하는 회귀 계약을 추가했습니다.
- README와 아키텍처 문서에 Reporter 토글의 즉시 UI 반영과 첫 보고 확인 흐름을 반영했습니다.

## [0.2.15-r28] - 2026-09-18

### Health Reporter 라이선스 인증 수정

- Health Reporter가 SafeShield `license_get`의 실제 응답 구조인 `license.key`에서 평문 라이선스 키를 읽도록 수정했습니다. 유료/Trial eligibility 판정은 정상인데도 업로드 직전에 키를 찾지 못해 `HEALTH_REPORTER_LICENSE_UNAVAILABLE`이 발생하던 문제를 해결합니다.
- 이전 개발 빌드의 최상위 `key` 응답은 호환 fallback으로만 유지하며, 현재 중첩 응답을 우선 사용합니다. 라이선스 키를 런타임 상태 파일이나 Health payload에 기록하지 않는 기존 개인정보 보호 정책은 그대로 유지합니다.

### 테스트 및 문서

- Health 테스트의 `license_get` mock을 실제 SafeShield 중첩 응답과 동일하게 변경하고, 중첩 키가 `X-SafeShield-License-Key` 인증 헤더까지 전달되는 기존 통합 시나리오와 실제 응답 경로 계약을 회귀 검증합니다.
- README와 아키텍처 문서에 `license_get` 응답 구조와 Health Reporter 인증 경로를 반영했습니다.

## [0.2.15-r27] - 2026-09-18

### 새로고침 경로 유지

- `/#settings`, `/#system` 같은 유효한 SmartSafeHub hash route를 현재 탭의 `sessionStorage`에 저장하고, 브라우저 새로고침 과정에서 LuCI 진입 경로가 fragment를 잃은 경우 reload navigation에서만 마지막 route를 복원합니다.
- 주소창에서 `/`을 직접 열거나 새 탭으로 진입하는 일반 navigation에서는 저장된 route를 제거해 이전 화면이 의도치 않게 복원되지 않도록 했습니다. 잘못된 hash도 복원 대상으로 사용하지 않습니다.
- route 복원은 History API의 `replaceState()`를 사용해 추가 navigation이나 `hashchange`를 발생시키지 않으며, storage 사용이 제한된 브라우저에서는 기존 `home` fallback 동작을 유지합니다.

### 테스트 및 문서

- 내비게이션 계약 테스트에 `sessionStorage` 기반 유효 route 저장, Navigation Timing의 reload 판별, History API 복원, 일반 navigation 초기화 계약을 추가했습니다.
- README와 아키텍처 문서에 hash route 새로고침 보존 정책을 반영했습니다.

## [0.2.15-r26] - 2026-09-18

### 루트 URL 진입

- 공식 사용자 URL을 공유기 루트 `/`로 변경했습니다. uHTTPd `json_script` request handler가 `REQUEST_URI == "/"`인 요청만 `/cgi-bin/luci/`로 내부 rewrite하므로 브라우저에는 `/cgi-bin/luci`가 노출되지 않습니다.
- 이전 설계의 전역 `uhttpd.main.index_page` 변경은 사용하지 않습니다. `/www/index.html`도 덮어쓰지 않아 다른 디렉터리 index와 `/cgi-bin/cgi-upload`, `/ubus`, `/luci-static/...` 같은 명시적 endpoint의 기존 동작을 유지합니다.
- root-entry helper는 기존 `uhttpd.main.json_script` handler를 보존한 채 SmartSafeHub handler를 뒤에 추가하고, 패키지 제거 시 자기 항목만 제거합니다. 설정이 실제로 바뀐 경우에만 uHTTPd를 reload합니다.
- 패키지 설치/업그레이드는 `postinst`, 펌웨어 이미지에 기본 포함된 설치는 `uci-defaults`에서 같은 handler를 등록합니다. 기존 `/cgi-bin/luci/`, `/cgi-bin/luci/smartsafehub`, `/cgi-bin/luci/admin/smartsafehub`는 호환 경로로 유지하고 로드 후 브라우저 주소를 `/`로 정규화합니다.

### 테스트 및 문서

- exact-root rewrite JSON 계약, `index_page` 비변경, 기존 `json_script` 보존, 중복 설치/제거 idempotency, 선택적 uHTTPd reload를 검증하는 `test-root-url-rewrite.sh`를 추가했습니다.
- 패키지 설치/제거 hook과 공식 public URL 정규화에 대한 회귀 계약을 보강하고 README/아키텍처 문서를 갱신했습니다.

## [0.2.15-r25] - 2026-09-17

### UI 개선

- 대시보드 `INTERNET` 개요 카드의 정상 상태 동작 문구를 다른 개요 카드와 동일한 `자세히 보기 →`로 통일했습니다. WAN/LAN subnet 충돌이 감지된 경우에는 조치가 필요하다는 의미가 분명하도록 기존 `해결하기 →` 문구를 유지합니다.
- 부팅 직후 SafeShield가 첫 차단 목록 갱신을 수행하는 동안 로컬 장치 진단이 이를 장애로 오인하지 않도록 `initializing` 상태와 `준비 중` 표시를 추가했습니다. 라이트/다크 모드 모두 기존 teal 상태 톤을 사용합니다.

### Health 안정성

- Health에 `startup_grace_s=120` 기본값을 추가했습니다. 부팅 후 grace 구간에서 SafeShield가 `running`/갱신 stage이거나 DNS 런타임·차단 목록이 아직 준비되지 않은 경우 `SAFESHIELD_INITIALIZING`으로 기록하고 warning/critical issue를 생성하지 않습니다.
- grace 구간에 SafeShield ubus 상태 API 자체가 아직 등록되지 않은 경우도 일시적인 초기화 상태로 처리합니다. grace 종료 후에도 상태 API가 없거나 차단 목록/DNS 런타임이 준비되지 않으면 다시 실제 warning/critical 판정을 사용합니다.
- SafeShield 초기화 중에는 opt-in Health Reporter의 원격 보고를 보류해 재부팅 때마다 일시적인 장애/복구 이벤트가 서버에 쌓이지 않도록 했습니다.
- 첫 Health cycle이 `initializing`이면 정규 5분 진단 주기를 기다리지 않고 60초 daemon tick에서 다시 검사해 SafeShield 준비 완료 상태가 빠르게 반영되도록 했습니다.

### 테스트 및 문서

- Health 테스트에 부팅 grace 중 첫 갱신, grace 만료 후 장애 승격, SafeShield 상태 API 지연, 원격 Reporter 억제와 빠른 재검사 계약을 추가했습니다.
- 테스트용 `jsonfilter` stub이 JSON boolean `false`를 누락하지 않도록 수정해 실제 OpenWrt jsonfilter 동작에 더 가깝게 만들었습니다.
- 대시보드 계약 테스트에 정상 `자세히 보기` 문구와 장치 진단 `준비 중` 렌더링 계약을 추가하고 README/아키텍처 문서를 갱신했습니다.

## [0.2.15-r24] - 2026-09-17

### 수정

- 대시보드의 RFC1918 사설 WAN IPv4 판별 코드가 TypeScript `noUncheckedIndexedAccess` 환경에서 `octets[1]`을 `number | undefined`로 추론해 `TS2532`로 빌드가 실패하던 문제를 수정했습니다. 배열 길이/값 검증 뒤에도 직접 인덱스를 비교하지 않고 존재 여부를 확인한 `firstOctet`, `secondOctet` 변수를 사용합니다.

### 테스트

- 대시보드 계약 테스트에 사설 WAN 판별이 undefined-safe octet 변수를 사용하고 직접 배열 인덱스 비교를 다시 도입하지 않는 회귀 검사를 추가했습니다. 프런트엔드 CI의 기존 `npm run build`(`tsc --noEmit` 포함)와 함께 strict TypeScript 타입 오류를 차단합니다.

## [0.2.15-r23] - 2026-09-17

### UI 개선

- 대시보드 `INTERNET` 개요 카드에 WAN IP/프로토콜과 WAN-LAN subnet 충돌 상태를 함께 표시하도록 개선했습니다. 정상 상태에서는 `네트워크 충돌 없음`, 충돌 시에는 `네트워크 충돌`과 `해결하기` 동작을 표시하며 LAN 설정 화면으로 바로 이동할 수 있습니다.
- `네트워크 보호 활동 > 연결 상태` 카드의 연결 기기 집계 중복을 제거하고 상위 네트워크, LAN 네트워크, 대역 충돌 상태를 표시하도록 역할을 정리했습니다. 사설 WAN IPv4 주소는 `사설 네트워크`로 함께 표시합니다.
- 대시보드가 기존 LAN 설정 API를 함께 조회하도록 연결하고, 대시보드 재시도/전역 새로고침에도 LAN 대역 상태 갱신을 포함했습니다. LAN 조회 실패가 전체 대시보드 로딩을 막지는 않고 네트워크 대역 항목만 `확인 필요`로 표시합니다.

### 테스트 및 문서

- 대시보드 계약 테스트에 LAN 상태 조회/전달/새로고침, 정상·충돌 Internet 카드 문구, 상위/LAN 네트워크 상세, 사설 WAN 표시와 LAN 설정 이동 계약을 추가했습니다.
- README와 아키텍처 문서에 대시보드 Internet/LAN 상태 통합 방식을 반영했습니다.

## [0.2.15-r22] - 2026-09-17

### 개선

- LAN 설정의 공유기 IPv4 주소 입력을 하나의 텍스트 필드에서 4개의 octet 입력 필드로 분리해 주소 구조를 더 쉽게 이해하고 잘못된 구분자 입력을 방지했습니다. 각 octet은 숫자 최대 3자리만 입력할 수 있고, 0~255 범위는 저장 전 검증합니다.
- DHCP 시작/종료 주소는 공유기 IP 주소의 앞 3개 octet을 읽기 전용으로 고정하고 마지막 octet만 사용자가 변경하도록 단순화했습니다. 공유기 IP의 앞 3개 octet을 수정하면 기존 DHCP 시작/종료 host octet을 유지한 채 새 LAN prefix로 즉시 동기화됩니다.
- LAN 데이터를 처음 불러올 때도 DHCP 주소의 host octet만 유지하고 현재 공유기 IP prefix를 사용하도록 정규화해 UI에서 서로 다른 대역을 실수로 제출하기 어렵게 했습니다.

### 테스트 및 문서

- LAN 계약 테스트에 4-octet 공유기 주소 입력, 각 octet 3자리 제한, DHCP prefix 잠금, 공유기 주소 변경 시 DHCP 시작/종료 prefix 자동 동기화 계약을 추가했습니다.
- README와 아키텍처 문서에 LAN/DHCP 입력 UX와 동일 prefix 유지 원칙을 반영했습니다.

## [0.2.15-r21] - 2026-09-17

### 수정

- OpenWrt 25.12에서 `network.lan.ipaddr`가 `list ipaddr '192.168.1.1/24'` 형태로 저장되고 ucode `get_all()`에서는 `["192.168.1.1/24"]` 배열로 반환되는데, LAN backend가 문자열 `ipaddr`와 별도 `netmask`를 전제로 해 `LAN_CONFIG_READ_FAILED`를 반환하던 문제를 수정했습니다.
- LAN IPv4 파서를 문자열/배열과 CIDR/legacy `ipaddr + netmask` 형식을 모두 처리하도록 변경했습니다. 25.12 list 형식에서는 첫 IPv4 항목을 관리 주소로 사용하고 추가 주소 항목은 보존합니다.
- LAN 변경 시 현재 UCI 저장 형식을 고려해 OpenWrt 25.12 list 형식은 CIDR 값을 유지하고 별도 legacy `netmask` 옵션을 제거하며, 기존 scalar 형식은 호환성을 위해 기존 저장 방식을 유지합니다.
- 동일한 LAN/DHCP 값을 다시 저장할 때 배열 값을 문자열과 직접 비교해 항상 변경으로 판정하던 문제를 없애고, 파싱된 주소·prefix·DHCP 범위·임대 시간·사용 상태를 기준으로 변경 여부를 판단하도록 수정했습니다.

### 테스트 및 문서

- 실제 장치에서 확인된 OpenWrt 25.12 UCI fixture(`ipaddr: [ "192.168.1.1/24" ]`, `start=100`, `limit=150`)를 사용하는 `tests/test-lan-uci-runtime.sh`를 추가했습니다. host ucode와 `uci`/`ubus`/`fs` stub을 이용해 실제 `network-management.uc`를 실행하고 LAN 주소, `/24`, DHCP `.100~.249`가 정상 해석되는지 검증합니다.
- 동일한 25.12 fixture를 같은 값으로 업데이트했을 때 `changed=false`, `reloadScheduled=false`인지 확인해 list/CIDR 형식 때문에 불필요한 네트워크 reload가 발생하는 회귀도 방지합니다.
- GitHub Actions에서는 기존 `SMARTSAFEHUB_REQUIRE_UCODE=1` 계약에 의해 이 런타임 호환성 테스트도 ucode 없이 skip할 수 없도록 했습니다.
- README와 아키텍처 문서에 OpenWrt 25.12의 LAN list/CIDR 저장 형식과 호환성 테스트를 반영했습니다.

## [0.2.15-r20] - 2026-09-17

### 수정

- LAN 전용 `smartsafehub_network` RPC가 등록되지 않아 LAN 화면에서 `요청한 리소스를 찾을 수 없습니다.`가 표시되던 문제를 수정했습니다. 원인은 `network-management.uc`의 `export function` 선언 세 곳이 ucode 문법상 필요한 `};` 대신 `}`로 끝나 모듈 컴파일이 실패하던 것이었습니다.
- `read_lan_settings`, `update_lan_settings`, `apply_recommended_lan` export 함수를 기존 SmartSafeHub ucode 모듈과 동일한 종료 형식으로 수정해 `smartsafehub-network.uc`가 정상적으로 import 및 등록될 수 있도록 했습니다.

### 테스트 및 문서

- LAN 계약 테스트에 export 함수 종료 문법 검사를 추가해 `};` 누락을 개발 환경에서도 감지하도록 했습니다.
- 특정 LAN 진입점만 선택적으로 검사하던 방식에 더해 `tests/test-ucode-syntax.sh`를 추가했습니다. 실제 `ucode -c`로 모든 rpcd 최상위 진입점을 컴파일하고, 합성 모듈에서 `smartsafehub/` 아래의 모든 재사용 모듈을 import해 현재 호출되지 않는 모듈까지 문법 오류를 검사합니다.
- Backend CI가 OpenWrt 25.12와 동일 계열인 ucode `2026.01.16~85922056` 소스 revision(`8592205`)을 직접 빌드하고 `SMARTSAFEHUB_REQUIRE_UCODE=1`로 실제 컴파일 검사를 필수화했습니다. 로컬에 ucode가 없어 검사가 건너뛰어져도 CI에서는 누락을 허용하지 않습니다.
- host ucode에는 OpenWrt 전용 `ubus`/`uci` 동적 모듈이 없으므로 테스트 전용 최소 import stub으로 이름 해석만 제공하고, SmartSafeHub의 실제 ucode 소스와 상대 import graph는 대상 컴파일러가 그대로 검사하도록 했습니다.
- 과거 장애와 동일한 `export function`의 세미콜론 누락 코드를 테스트 중 의도적으로 컴파일해 대상 ucode 컴파일러가 이를 거부하는지도 확인합니다.
- LAN 기능 계약 테스트에서 별도로 실행하던 raw `ucode -c`를 제거했습니다. Host CI의 ucode에는 OpenWrt 전용 `ubus`/`uci`/`fs` 모듈이 없어 실제 소스 문법과 무관하게 import 해석에서 실패할 수 있으므로, 실제 컴파일은 전용 `test-ucode-syntax.sh`가 stub module search path를 구성한 뒤 단일하게 담당합니다.
- 정적 검증에 회귀 계약을 추가해 다른 기능별 테스트가 다시 raw `ucode -c`를 추가하지 못하도록 했습니다.
- README의 ucode 진단 및 배포 전 검사 절차를 새 CI 컴파일 계약에 맞게 갱신했습니다.

## [0.2.15-r19] - 2026-09-17

### 수정

- LAN 화면이 `smartsafehub.lan_settings`에서 같은 `rpcd` 프로세스 안의 `smartsafehub_network` 객체를 `safe_call()`로 동기 호출하면서 응답을 받지 못해 `LAN_BACKEND_UNAVAILABLE`로 표시되던 문제를 수정했습니다.
- 핵심 `smartsafehub` 객체에서 LAN 프록시 메서드를 제거하고 LAN 화면이 격리된 `smartsafehub_network` 객체를 직접 호출하도록 변경했습니다. 이 구조는 LAN 구현의 로드 실패가 대시보드 RPC로 전파되지 않는 격리 특성을 유지하면서 rpcd 내부 동기 중첩 ubus 호출도 피합니다.
- `smartsafehub_network`에 관리자 비밀번호 설정 상태 확인을 직접 적용하고 LuCI ACL에는 `lan_settings` 읽기와 `lan_update`/`lan_auto_subnet` 쓰기 권한만 명시적으로 허용했습니다.

### 테스트 및 문서

- LAN ACL 중복 노출 검사에서 `jq` 파이프와 `or`의 연산자 우선순위 때문에 배열을 ACL 최상위 객체처럼 다시 인덱싱하며 stderr를 출력하던 계약 테스트 오류를 수정했습니다. 각 ACL 배열 조회를 괄호로 분리하고 누락 키는 빈 배열로 처리해 ShellSpec의 `The error should be blank` 계약을 만족합니다.
- LAN 계약과 RPC 계약에 핵심 `smartsafehub` 객체가 `smartsafehub_network`를 동기 호출하거나 LAN 메서드를 중복 등록하지 않는지 검증하는 회귀 테스트를 추가했습니다.
- 프런트엔드가 LAN 전용 ubus 객체를 직접 사용하는지, LAN 객체 자체에 관리자 비밀번호 gate와 최소 ACL이 적용되는지 검증하도록 테스트를 보강했습니다.
- README와 아키텍처 문서의 LAN RPC 호출 흐름 및 진단 명령을 실제 구현과 일치하도록 갱신했습니다.

## [0.2.15-r18] - 2026-09-17

### 수정

- LAN/DHCP 구현을 별도 내부 `smartsafehub_network` ubus 객체로 격리해 LAN backend의 로드/컴파일 오류가 `system_root_password_status`와 대시보드 등 기존 `smartsafehub` RPC 전체로 전파되지 않도록 했습니다.
- 격리 과정에서 LAN 구현 모듈을 `network_management.uc`로 이름 변경하던 방식을 제거하고 기존 `network-management.uc` 경로를 그대로 유지했습니다. 패치 적용 또는 Git staging 과정에서 rename 대상 파일이 누락되면 LAN 계약, ucode import 계약, RPC 계약이 동시에 실패할 수 있던 문제를 방지합니다.
- 공개 `smartsafehub` 객체는 기존 LAN API 이름을 유지하면서 내부 backend를 프록시하고, 내부 객체가 없으면 `LAN_BACKEND_UNAVAILABLE`을 반환합니다.

### 테스트 및 문서

- LAN 구현 모듈이 공개 RPC 진입점에 직접 import되지 않는지, 내부 LAN RPC가 기존 canonical 모듈 경로를 사용하는지, 내부 객체가 브라우저 ACL에 노출되지 않는지 회귀 테스트를 보강했습니다.
- LAN RPC 격리 구조와 `ucode -c` 진단 방법을 README 및 아키텍처 문서에 반영했습니다.

## [0.2.15-r16] - 2026-09-17

### 기능

- `네트워크 > LAN` 화면을 추가해 SmartSafeHub 내부 IPv4 주소, DHCP 할당 시작/종료 주소를 제품 UI에서 직접 관리할 수 있도록 했습니다.
- WAN과 LAN의 IPv4 subnet이 겹치는지 자동으로 감지하고, 충돌 시 현재 활성 인터페이스와 겹치지 않는 안전한 `/24` 사설 대역을 추천해 한 번에 변경할 수 있도록 했습니다.
- 고급 DHCP 설정에서 서브넷 마스크(CIDR), DHCP 서버 사용 여부와 임대 시간을 관리할 수 있도록 했습니다. 일반 가정용 구성은 `/24`를 권장하되 backend는 `/8~30` 사설 LAN 입력을 검증합니다.
- LAN 주소를 변경한 경우 새 공유기 주소를 안내하고 바로 다시 접속할 수 있는 링크를 표시합니다.

### 안정성 및 보안

- LAN/DHCP 변경 RPC에서 사설 IPv4 여부, network/broadcast 주소, DHCP 범위, 공유기 주소와 DHCP pool 중복, WAN subnet 중복을 서버 측에서 다시 검증합니다.
- LAN 설정 변경은 잠금 파일로 직렬화하고 `network`와 `dhcp` UCI를 함께 저장한 뒤 2초 지연된 `reload_config`로 적용해 RPC 응답이 먼저 반환되도록 했습니다. 런타임 재적용 예약에 실패하면 이전 UCI 값을 복원합니다.
- 자동 추천은 WAN뿐 아니라 현재 활성화된 다른 IPv4 인터페이스 대역도 피하도록 해 게스트/VPN 등 기존 로컬 대역과의 추가 충돌 가능성을 낮췄습니다.

### 테스트 및 문서

- LAN RPC 등록/ACL, UCI 변경·롤백·지연 재적용, WAN/LAN 충돌 거부, 추천 대역 적용, 프런트엔드 route/API/hook/UI 계약을 검증하는 `test-lan-settings.sh`를 추가했습니다.
- 내비게이션/RPC/정적 검증 계약을 새 LAN 기능에 맞게 보강하고 README와 아키텍처 문서를 최신화했습니다.

## [0.2.15-r15] - 2026-09-17

### 수정

- 다크 모드에서 대시보드 `장치 진단`의 정상/주의/이상 요약 패널이 라이트 테마용 반투명 배경색을 그대로 사용해 밝은 회색·녹색 박스처럼 보이던 문제를 수정했습니다.
- `bg-emerald-50/70`, `bg-amber-50/70`, `bg-rose-50/70` 상태 배경을 다크 테마에서 낮은 투명도의 상태색으로 재매핑하고, 비정상 진단 세부 항목의 `bg-white/70`/`border-white/80`도 어두운 slate 계열로 재매핑해 전체 대시보드와 자연스럽게 어울리도록 했습니다.

### 테스트

- 대시보드 계약 테스트에 정상/주의/이상 장치 진단 배경과 세부 항목 배경·테두리의 다크 테마 매핑이 유지되는지 확인하는 회귀 검사를 추가했습니다.

## [0.2.15-r14] - 2026-09-17

### 수정

- 대시보드 `연결된 기기` 카드의 마지막 목록 확인 시각이 오래되었다는 이유만으로 카드 전체를 주의(노란색) 상태로 표시하던 동작을 제거했습니다. 대시보드의 연결 기기 조회는 의도적으로 주기 polling을 하지 않으므로 `목록 확인: N분 전`은 정보성 메타데이터로만 표시합니다.
- 연결 기기 데이터가 정상적으로 존재하면 마지막 확인 시각과 관계없이 정상 상태를 유지하고, 실제 연결 기기 조회가 실패한 경우에만 `확인 필요` 성격의 경고 상태를 사용합니다.

### 테스트

- 연결 기기 목록 확인 시각이 오래되어도 `metaWarning`이나 stale 기반 warning 상태를 적용하지 않는 계약을 추가했습니다.
- 연결 기기의 최근 확인 시각은 `목록 확인: 상대 시간` 형식으로 계속 표시되는지 검증합니다.

## [0.2.15-r13] - 2026-09-17

### UI 개선

- 대시보드 `시스템 상태 > 리소스 사용량` 카드의 남는 영역에 최신 로컬 장치 진단 요약을 추가했습니다. 정상 상태에서는 전체 진단 메시지와 마지막 진단 시각, 검사 항목 수를 간결하게 표시하고 주의·이상 상태에서는 비정상 항목을 최대 2건까지 바로 보여줍니다.
- 진단 결과가 아직 생성되지 않았거나 조회에 실패한 경우도 빈 공간으로 두지 않고 대기/확인 필요 상태를 표시하며, `상세 보기`에서 설정 페이지의 전체 진단 기능으로 이동할 수 있습니다. 원격 상태 보고의 활성화 여부는 대시보드에 노출하지 않고 기존 설정 페이지에서만 관리합니다.
- 대시보드의 수동 새로고침에 Health 상태 조회를 포함해 다른 대시보드 데이터와 함께 최신 진단 결과를 다시 불러오도록 했습니다.

### 테스트

- 대시보드가 `health_status`를 읽고 Health 데이터/오류/로딩 상태를 전달하며 전역 새로고침에도 Health를 포함하는지 검증하는 계약을 추가했습니다.
- 정상/주의·이상/대기 상태의 장치 진단 요약과 최대 2건의 이상 항목, 설정 페이지 상세 링크가 유지되는지 검증합니다.
- 수정한 대시보드 계약 테스트의 설명과 실패 메시지를 가능한 범위에서 한글화했습니다.

## [0.2.15-r12] - 2026-09-17

### 수정

- Health 진단의 CPU 부하 비율 계산에서 GNU awk가 내장 이름으로 사용하는 `load`를 `-v` 변수명으로 전달해 GitHub Actions의 gawk 환경에서 `cannot use gawk builtin 'load' as variable name` 오류가 발생하던 문제를 수정했습니다. awk 변수명을 `load_value`로 변경해 OpenWrt awk와 GNU awk 모두에서 동일하게 동작하도록 했습니다.

### 테스트

- `test-health.sh`에 GNU awk 예약 이름을 다시 `-v load=` 형태로 사용하지 못하도록 회귀 검사를 추가했습니다.
- GitHub Actions와 ShellSpec 출력에서 테스트 목적을 바로 확인할 수 있도록 ShellSpec 계약 테스트 이름을 가능한 범위에서 한글 설명으로 통일했고, Health 계약 테스트의 실패/성공 메시지도 한글화했습니다.

## [0.2.15-r11] - 2026-09-17

### 수정

- Health RPC와 ACL이 추가된 패키지로 업그레이드한 직후 기존 LuCI 세션이 새 ACL 권한을 아직 갖지 못한 상태에서 설정 화면의 `health_status`가 `Access denied`를 반환하면 이를 곧바로 세션 만료로 오인해 로그인 화면으로 전환하던 문제를 수정했습니다. Access denied가 발생하면 동일한 세션으로 기존 `system_root_password_status` RPC를 짧게 확인해 세션 자체가 만료된 경우에만 전역 로그인 화면으로 전환합니다.
- 정상적으로 실행된 SmartSafeHub RPC가 `{ ok: false }` 도메인 오류를 반환한 경우에는 이미 ubus 인증이 통과한 요청이므로 세션 만료로 재분류하지 않도록 수정했습니다.
- 패키지 설치/업그레이드 후 LuCI 메뉴 캐시를 정리하고 `rpcd reload`를 수행해 새 ucode RPC 메서드와 ACL 파일을 즉시 다시 읽도록 했습니다. `restart`가 아니라 OpenWrt의 표준 `reload` 경로를 사용해 기존 rpcd 세션을 가능한 한 유지합니다.

### 테스트

- 새 RPC 권한이 아직 반영되지 않은 기존 세션과 실제 만료 세션을 구분하는 런타임 테스트를 보강했습니다.
- 패키지 postinst가 LuCI 캐시 정리와 `rpcd reload`를 수행하는 계약 테스트를 추가했습니다.

## [0.2.15-r10] - 2026-09-17

### 기능

- 모든 사용자가 사용할 수 있는 로컬 Health 진단 엔진을 추가했습니다. 메모리 가용량, CPU 코어 대비 시스템 부하, `/overlay` 여유 공간, WAN, dnsmasq, SafeShield 런타임, 관리 소프트웨어/펌웨어 업데이트 상태와 시스템 시간을 5분 주기로 점검하고 결과를 `/tmp/smartsafehub/health.json`에만 보관합니다.
- 설정 화면의 기존 `진단 및 지원` 카드를 실제 진단 결과 중심으로 확장했습니다. 현재 정상/주의/이상 상태, 진단 항목 수, 주요 검사 결과와 마지막 진단 시각을 표시하고 `지금 진단`으로 즉시 다시 점검할 수 있습니다. 진단 JSON 다운로드에도 최신 Health 결과를 포함합니다.
- 유료 멤버십 또는 Trial 장치에서만 사용할 수 있는 Health Reporter를 추가했습니다. 기본값은 OFF이며 사용자가 설정 화면에서 직접 opt-in한 경우에만 30분 heartbeat와 이상 fingerprint 변경 시 보고합니다. 사용자는 언제든지 다시 OFF로 전환할 수 있습니다.
- Health Reporter 전송 실패 시 5분 backoff를 적용해 서버/네트워크 장애 중 매 분 재시도하지 않도록 했습니다.

### 보안 및 개인정보 보호

- 원격 상태 보고 payload는 whitelist 방식으로 별도 생성하며 메모리/부하/저장 공간 수치, 전체 진단 상태와 이상 코드만 포함합니다. 호스트명, WAN IP, Wi-Fi SSID/MAC, DNS 요청 내용, 시스템 로그 원문과 라이선스 키는 payload에 포함하지 않습니다.
- 평문 SafeShield 라이선스 키는 Health Reporter가 실제 HTTPS 보고를 전송할 때 인증 헤더를 구성하기 위해 메모리에서 일시적으로만 조회하며 파일이나 보고 payload에 저장하지 않습니다. 로컬 진단, 상태 조회와 진단 다운로드에서는 평문 키를 조회하지 않습니다.
- `reporter_enabled=0`에서는 heartbeat, 이상 보고와 복구 보고를 포함한 Health Reporter 네트워크 요청을 수행하지 않습니다. 로컬 Health 진단은 멤버십/Reporter 설정과 독립적으로 계속 동작합니다.

### 테스트

- FREE 사용자의 로컬 진단, 유료/Trial opt-in, 개인정보 필드 배제, 최초/주기/상태 변경 보고, 전송 실패 backoff와 opt-out 후 네트워크 요청 차단을 mock 기반으로 검증하는 `test-health.sh`를 추가했습니다.
- 새 Health RPC/ACL, UCI 기본값, procd 서비스, 프런트엔드 API/hook/UI와 패키지 post-install 활성화 계약을 기존 정적/패키지/RPC/UI contract에 추가했습니다.
- Health helper가 내부적으로 다른 ubus 객체를 호출하므로 rpcd handler에서 동기 실행하지 않고 detached process로 시작하는 회귀 계약을 추가해 rpcd 이벤트 루프 교착을 방지했습니다.

## [0.2.15-r9] - 2026-09-17

### UI 개선

- 설정 페이지의 `시스템 상태 > Firmware` 카드도 대시보드 장치 정보와 동일한 펌웨어 식별 정책을 사용하도록 변경했습니다. SmartSafeHub 커스텀 펌웨어가 설치된 경우 Hub가 resolve한 제품 릴리즈 버전을 `SmartSafeHub 1.0.2`처럼 표시하고, 설명에는 immutable build ID를 표시합니다.
- SmartSafeHub 펌웨어 메타데이터가 없는 기존 이미지에서만 OpenWrt 배포판/버전과 리비전을 fallback으로 표시하며, 커널은 계속 현재 장치에서 실제 실행 중인 커널 버전을 표시합니다.
- 설정 페이지를 열거나 새로고침할 때 로컬 펌웨어 상태 RPC도 함께 갱신해 대시보드와 설정 페이지 사이의 펌웨어 표시가 일치하도록 했습니다.

### 테스트

- 설정 페이지가 SmartSafeHub 제품 펌웨어 버전/build ID를 우선 표시하고 OpenWrt fallback 및 runtime kernel을 유지하는지 검증하는 UI contract를 추가했습니다.
- 설정 페이지의 전역 새로고침이 펌웨어 상태도 함께 갱신하는지 검증합니다.

## [0.2.15-r8] - 2026-09-17

### UI 개선

- 대시보드 개요 카드의 freshness 문구를 `차단 목록 갱신: 41분 전`, `목록 확인: 1분 전`, `마지막 확인: 42분 전`처럼 `항목: 상대 시간` 구조로 통일했습니다. 지연 상태도 `차단 목록 갱신 지연: 2시간 전`처럼 같은 구조를 사용해 정상/이상 상태를 빠르게 구분할 수 있습니다.
- 장치 정보는 `/usr/share/smartsafehub/firmware.json`이 있는 SmartSafeHub 커스텀 펌웨어에서 Hub가 resolve한 제품 릴리즈 버전을 `SmartSafeHub 1.0.2`처럼 우선 표시하고, OpenWrt 리비전 대신 immutable build ID를 표시합니다. 커스텀 펌웨어 메타데이터가 없는 기존 이미지에서만 OpenWrt 배포판/버전/리비전으로 fallback합니다.
- 커널은 제품 레이어의 별도 버전을 만들지 않고 현재 장치에서 실제 실행 중인 커널 버전을 그대로 표시합니다.

### 테스트

- Dashboard가 펌웨어 상태 RPC의 커스텀 firmware metadata를 함께 읽고 SmartSafeHub 제품 버전/build ID를 우선 사용하며 OpenWrt fallback과 실제 runtime kernel을 유지하는지 contract를 추가했습니다.
- freshness label과 상대 시간이 콜론으로 분리되는 UI 계약을 추가했습니다.

## [0.2.15-r7] - 2026-09-17

### UI 개선

- 대시보드 하단의 별도 `최근 상태 확인` 섹션을 제거하고 SafeShield 차단 목록, 연결 기기 목록, 관리 소프트웨어 업데이트의 최근 확인 정보를 각 시스템 개요 카드에 직접 배치했습니다.
- 최근 확인 시각은 절대 날짜/시각 대신 `방금 전`, `n분 전`, `n시간 전`, `n일 전` 상대 시간으로 표시하고 1분마다 화면 문자열만 갱신합니다. 정확한 시각은 각 상대 시간의 tooltip으로 유지합니다.
- 연결 기기 정보는 15분 이상 갱신되지 않으면 갱신 권장을 표시하고, SafeShield와 관리 소프트웨어는 각 확인 주기의 2배 이상 갱신되지 않았을 때 해당 개요 카드만 경고 상태로 전환합니다. 관리 소프트웨어 자동 확인이 꺼진 경우에는 오래된 확인 시각을 오류로 취급하지 않습니다.

### 테스트

- 대시보드에 별도 freshness 섹션이 다시 추가되지 않는지, 세 개의 개요 카드가 상대 시간 메타데이터를 사용하고 stale 상태를 개별 경고하는지 검증하도록 dashboard UI contract를 보강했습니다.
- 상대 시간 formatter가 `방금 전`/분/시간/일 단위를 제공하는 계약을 추가했습니다.

## [0.2.15-r6] - 2026-09-17

### 개선

- `/tmp` 최상위에 흩어져 있던 SmartSafeHub 런타임 파일을 `/tmp/smartsafehub/` 한 단계 아래로 통합했습니다. 관리 소프트웨어 업데이트 상태/릴리즈 노트/marker, 펌웨어 상태/resolve/image/lock, 예약 재부팅 상태, Wi-Fi 변경 lock, 설정 백업 업로드 파일이 모두 같은 제품 전용 런타임 디렉터리를 사용합니다.
- `smartsafehub-updater`, `smartsafehub-firmware`, `smartsafehub-maintenance`, `smartsafehub-backup` helper가 실행 전에 런타임 디렉터리를 직접 생성하도록 했고, procd init script도 부팅 후 `/tmp`가 초기화된 뒤 디렉터리를 다시 생성하도록 했습니다. 패키지 설치/업그레이드 직후의 수동 업로드를 위해 post-install hook에서도 디렉터리를 생성합니다.
- 펌웨어/설정 백업 CGI 업로드 경로와 rpcd ACL, ucode 상태 파일 경로, 프런트엔드 업로드 destination을 새 런타임 경로에 맞춰 함께 변경했습니다. 별도의 `updater/`, `firmware/` 하위 디렉터리는 추가하지 않습니다.

### 테스트

- production 소스에 `/tmp/smartsafehub-*` 형태의 최상위 런타임 경로가 다시 추가되지 않는지, 각 helper/init script가 `/tmp/smartsafehub/`를 생성하는지, rpcd/ACL/프런트엔드 업로드 경로가 동일한 디렉터리를 사용하는지 검증하는 runtime path contract를 추가했습니다.
- helper를 직접 실행하는 경우에도 지정한 runtime directory가 자동 생성되고 상태 파일이 그 아래에 기록되는지 검증합니다.

## [0.2.15-r5] - 2026-09-17

### 개선

- 펌웨어 업데이트 확인은 제품 정책상 항상 수행하므로 `smartsafehub.firmware.check_enabled` 설정과 펌웨어 helper의 활성화 분기를 제거했습니다. 부팅 초기 확인과 이후 주기 확인은 `check_interval_s`만 사용해 항상 실행됩니다. 기존 설치에 conffile로 남아 있을 수 있는 `smartsafehub.firmware.check_enabled` 값도 패키지 설치/업그레이드 시 제거합니다.
- 펌웨어 상태 RPC와 프런트엔드 펌웨어 타입에서 사용되지 않던 `checkEnabled` 필드를 제거해 실제 동작과 API 계약을 일치시켰습니다.
- 관리 소프트웨어 updater의 `smartsafehub.updates.check_enabled`와 UI 설정은 그대로 유지해 사용자가 관리 소프트웨어 업데이트 확인 여부를 계속 선택할 수 있습니다.

### 테스트

- 펌웨어 helper/config/API에 `check_enabled` 의존성이 다시 추가되지 않는지 검증하고, 동시에 관리 소프트웨어의 `check_enabled`가 유지되는지 확인하는 회귀 테스트를 추가했습니다.

## [0.2.15-r4] - 2026-09-17

### 수정

- 기존 설치를 업그레이드했을 때 새로 추가된 `smartsafehub-firmware` init script에 `S96smartsafehub-firmware` 시작 링크가 생성되지 않아 재부팅 후 펌웨어 자동 확인 데몬이 `inactive` 상태로 남을 수 있던 문제를 수정했습니다.
- `luci-app-smartsafehub`의 runtime post-install hook에서 설치와 업그레이드 시마다 `smartsafehub-firmware enable`을 강제로 실행하도록 변경했습니다. 이전 활성화 상태나 upgrade 여부를 보존하지 않으며, 패키지가 갱신될 때마다 펌웨어 자동 시작 상태를 복구합니다.

### 테스트

- package contract에 runtime post-install hook이 `smartsafehub-firmware enable`을 포함하고, `PKG_UPGRADE`나 기존 enabled 상태에 따라 실행을 건너뛰지 않는지 검증하는 회귀 테스트를 추가했습니다.

## [0.2.15-r3] - 2026-09-17

### UI 개선

- 데스크톱 사이드바 접기/펼치기 토글 아이콘을 패널 외곽선이 포함된 기존 아이콘에서 제품 공통 방향 아이콘과 동일한 단순 좌/우 chevron으로 변경했습니다. 접기 아이콘은 `m15 18-6-6 6-6`, 펼치기 아이콘은 `m9 18 6-6-6-6` 경로를 사용합니다.
- 접힘/펼침 상태 모두 동일한 `size-4` 크기를 사용해 상태 전환 시 아이콘 크기가 달라 보이지 않도록 정렬했습니다.

### 테스트

- 사이드바 토글이 지정된 좌/우 chevron SVG 경로와 동일한 크기를 유지하고, 기존 패널 외곽선 SVG가 다시 사용되지 않는지 검증하는 navigation contract를 추가했습니다.

## [0.2.15-r2] - 2026-09-17

### 개선

- 공유기 부팅 후 펌웨어 업데이트 확인을 기존 45초 대기에서 10초 뒤 시작하도록 앞당겨, 펌웨어 설치 후 재로그인했을 때 현재 버전과 설치 가능 버전이 `미확인`으로 오래 남는 시간을 줄였습니다.
- 관리 소프트웨어 업데이트 확인도 기존 30초 대기에서 20초 뒤 시작하도록 조정해 펌웨어와 관리 소프트웨어 상태가 부팅 직후 빠르게 채워지도록 했습니다.
- 두 업데이트 데몬 모두 부팅 초기 확인이 실패하면 60초 간격으로 최대 3회까지만 재시도하고, 이후에는 설정된 일반 확인 주기로 돌아가도록 했습니다. 펌웨어와 관리 소프트웨어의 첫 확인 시점을 10초 차이로 분산해 저사양 장치에서 두 작업이 동시에 시작되지 않도록 했습니다.
- 관리 소프트웨어 확인 실패 시 `last_attempt_at`을 기록하고 주기 판단에 사용해 저장소 또는 네트워크 장애가 지속되더라도 `apk update`가 매 분 반복되지 않도록 했습니다. 성공한 확인 시각인 `last_check_at`의 의미는 그대로 유지합니다.

### 테스트

- 펌웨어와 관리 소프트웨어의 부팅 초기 확인이 두 번째 시도에서 성공하면 즉시 중단되고, 연속 실패 시 정확히 3회에서 멈추는 회귀 테스트를 추가했습니다.
- 관리 소프트웨어 확인 실패 후 `last_attempt_at`이 기록되고, 일반 확인 주기가 지나기 전에는 추가 저장소 갱신을 실행하지 않는 회귀 테스트를 추가했습니다.

## [0.2.15-r1] - 2026-09-15

### 기능

- 펌웨어 업데이트 기능을 추가하였습니다.
- 설정 백업/복원 기능을 추가하였습니다.
- 예약 재부팅 기능을 추가하였습니다.
- 관리자 비밀번호를 필수로 설정하도록 변경하였습니다.

### 개선

- 일부 성능이 개선되었습니다.

## [0.2.14-r16] - 2026-09-15

### 수정

- 초기 관리자 비밀번호 설정 시 OpenWrt 25.12의 `luci.setPassword` RPC가 지원하지 않는 `oldpassword`와 `rpcd` 인자를 전달해 비밀번호 입력/확인 값이 일치하고 정책을 만족해도 `관리자 비밀번호를 설정하지 못했습니다.` 오류가 발생하던 문제를 수정했습니다.
- `luci.setPassword` 호출을 OpenWrt 25.12의 공통 계약인 `username`과 `password` 두 인자만 사용하도록 변경했습니다. 최신 LuCI에서도 추가 인자는 선택 사항이므로 동일 호출을 유지할 수 있습니다.

### 테스트

- 초기 비밀번호 설정 RPC가 `username`/`password`를 전달하고 OpenWrt 25.12에 없는 `oldpassword`/`rpcd` 인자를 다시 추가하지 않는 호환성 회귀 테스트를 추가했습니다.

## [0.2.14-r15] - 2026-09-15

### UI 개선

- 초기 보안 설정 화면의 왼쪽 제목을 `SmartSafeHub`와 `보호 시작` 두 줄로 명시적으로 분리해 화면 폭이나 폰트 렌더링에 따라 `보호 시작`이 어색하게 나뉘지 않도록 했습니다.
- 비밀번호 보안 안내 문구에서 내부 시스템 계정명인 `root`를 제거하고 `비밀번호는 현재 공유기에 직접 설정되며 외부 서버로 전송되지 않습니다.`로 안내하도록 변경했습니다. 실제 초기 비밀번호 설정 대상과 보안 게이트 동작은 기존과 동일합니다.

### 테스트

- 초기 설정 제목의 고정 2줄 구조와 보안 안내 문구에서 `root` 계정명이 노출되지 않는 계약을 회귀 테스트에 추가했습니다.

## [0.2.14-r14] - 2026-09-15

### 기능

- root 관리자 비밀번호가 비어 있는 공장 초기 상태에서는 일반 SmartSafeHub 화면을 열지 않고 전용 초기 보안 설정 화면을 강제로 표시하도록 했습니다. 로그인 화면은 초기 root 계정에 한해서만 빈 비밀번호 인증 시도를 허용하고, 인증 후 비밀번호 상태를 확인한 뒤 다른 애플리케이션 hook이나 polling을 시작하지 않습니다.
- 최초 root 비밀번호 정책을 `8자 이상 + 영문자 1자 이상 + 숫자 1자 이상`으로 적용하고 입력 중 각 조건과 비밀번호 확인 일치 여부를 표시합니다. 특수문자와 영문 대/소문자 혼합은 강제하지 않습니다.
- 초기 비밀번호 설정이 완료되면 현재 LuCI 세션을 폐기하고 새 비밀번호로 다시 로그인하도록 해, 빈 비밀번호로 생성된 기존 관리자 세션을 계속 사용하지 않도록 했습니다.

### 보안 및 안정성

- 비밀번호 정책을 프런트엔드뿐 아니라 rpcd ucode에서도 동일하게 검증하고, 실제 root 비밀번호 쓰기는 LuCI의 `setPassword` 구현에 위임한 뒤 `/etc/shadow` 상태를 다시 확인합니다.
- root 비밀번호가 이미 설정된 경우 초기 설정 RPC는 기존 비밀번호를 변경하지 않으며 LuCI 관리자 설정을 사용하도록 거부합니다. `/etc/shadow`의 `!`, `*` 같은 잠금 표시는 관리자가 의도한 상태로 간주해 초기 설정이 임의로 덮어쓰지 않습니다.
- root 비밀번호가 없는 동안에는 상태, Wi-Fi, 업데이트, 펌웨어, 백업/복원 등 일반 `smartsafehub` 관리 RPC를 `SYSTEM_ROOT_PASSWORD_REQUIRED`로 차단하고 비밀번호 상태 확인/최초 설정 RPC만 통과시켜 프런트엔드 우회를 막습니다.

### 테스트

- `/etc/shadow` 기반 상태 확인, 서버/프런트엔드 비밀번호 정책, 이미 설정된 비밀번호 덮어쓰기 방지, LuCI `setPassword` 위임과 결과 재검증, 일반 RPC 보안 게이트, 빈 root 로그인 진입, 설정 완료 후 세션 종료/재로그인 계약을 검증하는 전용 회귀 테스트를 추가했습니다.
- 새 RPC/ACL, package executable 목록, shell syntax/JSON validation 및 ShellSpec contract suite에 초기 비밀번호 설정 테스트를 연결했습니다.

## [0.2.14-r13] - 2026-09-15

### 기능

- 설정의 `시스템 관리` 영역에 `설정 백업 및 복원` 기능을 추가했습니다. 현재 OpenWrt가 보존 대상으로 관리하는 네트워크, Wi-Fi, 시스템, SmartSafeHub와 SafeShield 설정을 표준 `sysupgrade` `.tar.gz` 형식으로 다운로드할 수 있습니다.
- SmartSafeHub 또는 기본 LuCI에서 생성한 OpenWrt 설정 백업을 업로드해 검증한 뒤 복원할 수 있으며, 복원이 완료되면 변경된 네트워크·서비스 설정을 안전하게 적용하기 위해 공유기를 자동 재부팅합니다.

### 안전성

- 복원 업로드는 `/tmp/smartsafehub-config-backup.tar.gz` 고정 경로와 16MB 상한을 사용하고, gzip/tar 구조, `/etc/config` 포함 여부와 위험한 절대/상위 경로를 확인한 뒤에만 `sysupgrade --restore-backup`을 실행합니다.
- 관리 소프트웨어 업데이트 또는 펌웨어 확인·다운로드·검증·설치가 진행 중이거나 펌웨어 이미지가 준비된 상태에서는 설정 복원을 거부해 동시에 실행되는 시스템 변경 작업을 막습니다.
- 이전 펌웨어에서 만든 백업에 과거 `current_build_id`가 포함되어 있어도 복원 직후 현재 이미지의 `/usr/share/smartsafehub/firmware.json`을 다시 읽어 실제 설치된 펌웨어 build ID로 재동기화합니다.
- 복원 전에는 LAN 주소, Wi-Fi와 관리자 접속 정보가 바뀌어 연결이 끊길 수 있음을 명시적으로 다시 확인하며, 백업 파일에 Wi-Fi 비밀번호·관리자 설정·VPN 키·라이선스 정보 등 민감한 값이 들어갈 수 있음을 안내합니다.

### 테스트

- 정상 OpenWrt 백업 검증, 잘못된 gzip/설정 없는 archive 거부, `sysupgrade --restore-backup` 위임, 펌웨어 build ID 재동기화, 복원 후 재부팅, 업데이트/펌웨어 busy 차단, 실패 시 백업 보존과 재부팅 금지를 검증하는 shell 회귀 테스트를 추가했습니다.
- backup/restore RPC·ACL, `cgi-backup`/`cgi-upload` 경로, 프런트엔드 업로드→검증→최종 확인 계약과 설정 화면 노출을 기존 contract 테스트에 추가했습니다.

## [0.2.14-r12] - 2026-09-15

### 기능

- Hub의 펌웨어 `release_version` 연동을 추가했습니다. 공유기는 기존처럼 `/usr/share/smartsafehub/firmware.json`의 immutable `build_id`만 서버에 보내며, `POST /api/v1/firmware/resolve` 응답의 `current_version`과 `release.version`을 제품 펌웨어 버전으로 사용합니다.

### 개선

- 펌웨어 업데이트 화면의 `Current version`과 `Available version`에 `1.0.2` 형식의 제품 릴리즈 버전을 우선 표시하고, build ID와 OpenWrt 기반 버전은 별도의 진단 정보로 구분했습니다.
- 최신 펌웨어가 있는 경우 제품 펌웨어 버전, OpenWrt 기반 버전, 이미지 크기와 채널을 서로 구분해 표시합니다.
- 릴리즈 버전을 펌웨어 이미지 메타데이터에서 읽지 않도록 유지해, 관리자가 검증 후 게시 시점에 버전을 부여하더라도 테스트한 펌웨어 artifact와 SHA-256이 변경되지 않습니다.

### 테스트

- firmware resolve 응답의 `current_version`/`release.version` 보존, RPC의 현재 릴리즈 버전 매핑, UI의 제품 버전 우선 표시와 `firmware.json`에 release version을 의존하지 않는 계약을 회귀 테스트에 추가했습니다.

## [0.2.14-r11] - 2026-09-14

### 수정

- 수동 펌웨어 업로드 검증 RPC가 비동기로 시작된 직후 프런트엔드가 400ms 뒤 상태를 한 번만 다시 읽으면서, 이전 `FIRMWARE_IMAGE_INVALID` 상태를 다시 받아 활성 polling이 중단되고 실제 장치 상태가 `ready`여도 설치 버튼이 나타나지 않던 race condition을 수정했습니다.
- 업로드 검증 요청이 접수되면 최대 30초 동안 500ms 간격으로 firmware status를 추적하고, `ready` 상태와 준비된 이미지 정보를 확인한 뒤에만 업로드 절차를 성공으로 종료하도록 변경했습니다.
- 비동기 validator가 새 상태를 기록하기 전 잠깐 보일 수 있는 이전 terminal error는 3초 grace 구간 동안 stale snapshot으로 취급해 낡은 오류가 검증 중 UI를 덮어쓰지 않도록 했습니다.

### 개선

- 검증이 완료되면 `펌웨어 검증이 완료되었습니다. 설치 옵션을 확인해 주세요.` 안내를 표시하고 backend의 `prepared` 상태를 즉시 반영해 `현재 설정 유지`, `파일 삭제`, `펌웨어 설치` 동작이 페이지 새로고침 없이 나타나도록 했습니다.
- 검증 상태 확인이 장시간 완료되지 않거나 일시적인 상태 조회 오류가 계속되는 경우 명확한 오류를 반환하도록 timeout 처리를 추가했습니다.

### 테스트

- 수동 업로드 검증이 단발성 400ms refresh에 의존하지 않고 `ready`/`error` terminal state까지 추적하는지, stale error grace와 prepared image 확인 후 성공 처리 정책이 유지되는지 update UI contract 테스트를 보강했습니다.

## [0.2.14-r10] - 2026-09-14

### 수정

- 수동 펌웨어 업로드가 LuCI dispatcher 경로인 `/cgi-bin/luci/cgi-upload`로 잘못 전송되던 문제를 수정했습니다. `cgi-upload`는 dispatcher route가 아닌 CGI endpoint이므로 이제 `/cgi-bin/cgi-upload`로 요청합니다.
- `/cgi-bin/luci`가 경로 prefix 아래에 배치된 환경에서도 동일한 prefix를 유지하면서 CGI base를 계산하도록 `cgiBaseUrl()`/`cgiUrl()` URL helper를 분리했습니다.

### 개선

- 펌웨어 업로드의 네트워크 오류, HTTP 오류, 올바르지 않은 JSON 응답을 브라우저 콘솔에 endpoint·destination·파일명·파일 크기·HTTP 상태와 함께 기록해 현장 장애 원인을 구분하기 쉽게 했습니다. 사용자 오류 메시지에도 실제 업로드 endpoint와 HTTP 상태를 포함합니다.

### 테스트

- 수동 펌웨어 업로드가 `luciUrl('/cgi-upload')`를 다시 사용하지 않는지, `/cgi-bin` CGI base를 통해 업로드하는지와 업로드 실패 진단 로그가 유지되는지 update UI contract 테스트를 보강했습니다.

## [0.2.14-r9] - 2026-09-14

### 기능

- 설정의 `시스템 관리` 영역에 `예약 재부팅` 기능을 추가했습니다. 기본값은 비활성화이며, 필요할 때 `매일` 또는 `매주` 주기와 요일·시각을 선택해 공유기의 로컬 시간대 기준으로 자동 재부팅할 수 있습니다.
- 예약 재부팅은 별도 `smartsafehub-maintenance` procd daemon에서 실행되며 관리 소프트웨어 업데이트와 펌웨어 확인·다운로드·검증·설치 작업이 진행 중이면 재부팅을 즉시 수행하지 않고 15분 단위로 최대 2시간 연기합니다.
- 펌웨어가 설치 준비(`ready`) 상태인 경우에도 사용자가 준비한 이미지를 잃지 않도록 예약 재부팅을 연기합니다.
- 예약 시각 직전에 장치가 다시 부팅된 경우 최소 10분의 uptime 보호를 적용하고 같은 예약 key를 중복 실행하지 않아 재부팅 루프를 방지합니다.

### 개선

- 시간대 변경 시 관리 소프트웨어 updater뿐 아니라 maintenance daemon도 즉시 다시 시작해 예약 재부팅이 새 로컬 시간대를 바로 따르도록 했습니다.
- 기존 설정 파일에 `maintenance` section이 없는 업그레이드 장치는 maintenance init script가 안전한 기본값(꺼짐, 매주 일요일 04:00)으로 section을 한 번 생성합니다.
- 시스템 관리 UI에서 예약 재부팅을 전체 폭 카드로 배치하고 현재 시간대, 주기, 요일, 재부팅 시각과 업데이트 작업 충돌 시 연기 정책을 한 화면에서 확인하도록 구성했습니다.

### 테스트

- 예약 재부팅 비활성화 기본값, due schedule 실행, 동일 minute 중복 실행 방지, 최근 부팅 보호, 관리 소프트웨어/펌웨어 작업 중 연기, 연기 후 재시도, 2시간 timeout, UCI 입력 검증을 mock 기반 shell 테스트로 추가했습니다.
- scheduled reboot RPC/ACL, frontend hook/API, 시스템 관리 UI, maintenance init/helper 실행 권한과 시간대 변경 연동을 기존 contract 테스트에 추가했습니다.

## [0.2.14-r8] - 2026-09-14

### 기능

- 설정의 `시간 및 시간대` 카드에 `지금 동기화` 동작을 추가했습니다. NTP 자동 동기화가 활성화된 경우 OpenWrt `sysntpd`를 재시작해 설정된 NTP 서버로 즉시 새 동기화 요청을 보내고, 잠시 뒤 공유기 시간을 다시 조회해 화면에 반영합니다.
- 시간 설정 RPC 응답에 현재 공유기 epoch를 포함해 시간대 저장이나 수동 NTP 동기화 직후 별도의 전체 시스템 상태 갱신 없이 최신 장치 시간을 표시할 수 있도록 했습니다.

### 개선

- 시간대, Wi-Fi 보안 방식, 관리 소프트웨어 업데이트 주기 등 SmartSafeHub의 모든 `<select>`에 공통 드롭다운 화살표 스타일을 적용했습니다. 브라우저 기본 화살표 대신 오른쪽에서 `1rem` 안쪽에 고정하고 텍스트와 겹치지 않도록 우측 여백을 확보했습니다.
- NTP 동기화 또는 시간대 저장 중에는 다른 시간 설정 변경을 잠가 동시에 실행되는 시간 변경 요청을 방지합니다.

### 테스트

- `system_time_sync` RPC/ACL, NTP 비활성화 차단, `sysntpd restart`, 동기화 후 장치 시간 재조회와 UI 동작을 검증하도록 시스템 시간 contract를 확장했습니다.
- 공통 select 스타일이 native appearance를 제거하고 일관된 우측 inset 화살표와 padding을 유지하는지 네트워크/시간 설정 contract에 회귀 검증을 추가했습니다.

## [0.2.14-r7] - 2026-09-14

### 기능

- 설정 페이지에 `시간 및 시간대` 카드를 추가해 현재 장치 시간, IANA 시간대와 NTP 자동 동기화 사용 상태를 확인하고 시간대를 SmartSafeHub에서 직접 변경할 수 있도록 했습니다.
- 장치의 LuCI `getTimezones` 데이터베이스를 기준으로 선택 가능한 시간대를 제공하고, 브라우저 시간대가 지원되는 경우 빠르게 선택할 수 있는 동작을 추가했습니다.
- 시간대 저장 시 OpenWrt `system` UCI의 `zonename`과 대응 POSIX `timezone`을 함께 갱신하고 `/etc/init.d/system reload`로 즉시 적용합니다. 적용 실패 시 이전 값을 복원합니다.
- 시간대가 변경되면 관리 소프트웨어 자동 설치 marker와 재시도 시각을 초기화하고 updater를 재시작해 예약 설치가 새 로컬 날짜와 시각을 기준으로 다시 계산되도록 했습니다.

### 개선

- 설정 페이지의 중복 `업데이트 관리` 카드를 제거하고 `장치 설정`과 `시스템 관리` 두 영역으로 재구성했습니다.
- `장치 설정`에는 시간 및 시간대와 진단/지원 기능을, `시스템 관리`에는 공유기 재부팅과 LuCI 고급 설정 fallback을 배치해 각 기능의 목적을 명확하게 구분했습니다.
- 설정 라우트 설명을 시스템 상태·시간대·진단 중심으로 정리하고 카드 헤더에 기능별 아이콘을 적용해 다른 SmartSafeHub 화면과 시각적 계층을 맞췄습니다.

### 테스트

- 시간대 목록 조회, 지원하지 않는 시간대 차단, `zonename`/`timezone` 동시 저장, 시스템 reload, 실패 시 rollback, 자동 업데이트 일정 marker 초기화와 updater 재시작을 검증하는 전용 contract 테스트를 추가했습니다.
- 설정 페이지에서 중복 업데이트 진입점이 제거되고 시간대/진단/재부팅/고급 설정 영역이 유지되는지 검증하도록 UI contract와 RPC/ACL 검증을 보강했습니다.

## [0.2.14-r6] - 2026-09-14

### 개선

- 수동 펌웨어 설치의 브라우저 기본 파일 입력 UI를 SmartSafeHub 전용 파일 선택 행으로 교체해 `Browse...`/`No file selected.` 같은 브라우저·언어별 기본 문구와 깨진 정렬이 노출되지 않도록 개선했습니다.
- 선택 전에는 지원 이미지 안내와 `파일 선택` 버튼을 표시하고, 선택 후에는 파일명·크기와 `다른 파일 선택`, `업로드 및 검증` 동작을 한 행에서 확인할 수 있도록 정리했습니다.
- 업로드 진행률은 파일 선택 행 아래의 구분된 진행 영역에 표시해 작은 화면에서도 파일 정보와 동작 버튼이 자연스럽게 줄바꿈되도록 조정했습니다.

### 테스트

- 수동 펌웨어 입력이 시각적으로 숨겨진 실제 file input과 별도의 SmartSafeHub 파일 선택 컨트롤을 사용하는지, 한국어 파일 선택 상태와 업로드 검증 동작이 유지되는지 UI contract 테스트를 추가했습니다.

## [0.2.14-r5] - 2026-09-14

### 개선

- 업데이트 페이지를 `펌웨어 업데이트`와 `관리 소프트웨어 업데이트`의 두 제품 영역으로 단순화해 SmartSafeHub라는 제품명이 별도의 업데이트 종류처럼 보이는 혼동을 줄였습니다.
- 기존 `SmartSafeHub 업데이트`와 `SmartSafeHub 자동 업데이트` 명칭을 각각 `관리 소프트웨어 업데이트`, `자동 업데이트`로 정리하고, 자동 업데이트 설정을 관리 소프트웨어 카드 내부에 배치해 적용 범위를 구조 자체로 드러내도록 변경했습니다.
- 관리 소프트웨어의 현재 상태와 자동 업데이트 설정을 하나의 카드 내부 2열 영역으로 통합하고, 모바일에서는 한 열로 자연스럽게 쌓이도록 유지했습니다.
- 펌웨어 영역 제목을 `펌웨어 업데이트`로 명확히 하고, 설정/라우트 설명에서도 `SmartSafeHub 소프트웨어` 대신 `관리 소프트웨어` 용어를 사용하도록 통일했습니다.

### 테스트

- 관리 소프트웨어가 하나의 카드로 렌더링되는지, 현재 상태와 자동 업데이트 설정이 그 카드 내부에 함께 존재하는지, 이전 범위 경고와 `SmartSafeHub 자동 업데이트` 명칭이 다시 노출되지 않는지 contract 테스트를 보강했습니다.
- 펌웨어와 관리 소프트웨어의 고객용 제목 및 업데이트 페이지 설명 용어를 회귀 검증하도록 관련 UI contract를 갱신했습니다.

## [0.2.14-r4] - 2026-09-14

### 개선

- 수동 펌웨어 설치 영역을 펌웨어 카드의 내부 여백을 가진 하위 패널로 다시 배치해 온라인 펌웨어 상태와 같은 기능군이라는 점이 시각적으로 명확하게 보이도록 조정했습니다.
- `SmartSafeHub 소프트웨어` 제목을 `SmartSafeHub 업데이트`로 정리하고, 설정 카드 제목을 `SmartSafeHub 자동 업데이트`로 명시해 펌웨어 자동 업데이트로 오해하지 않도록 범위를 분명히 했습니다.
- 자동 업데이트 설정에 `SmartSafeHub 업데이트에만 적용되며 펌웨어는 자동 설치되지 않는다`는 범위 안내를 추가했습니다.
- SmartSafeHub가 최신 상태이거나 아직 확인 전인 상태 안내를 별도 카드로 분리하지 않고 SmartSafeHub 업데이트 카드 내부에 포함해 카드 간 관계와 정보 계층을 단순화했습니다.

### 테스트

- 수동 펌웨어 설치가 펌웨어 카드 내부의 inset subsection으로 유지되는지, SmartSafeHub 자동 업데이트 범위 문구가 존재하는지, 최신/미확인 상태 안내가 SmartSafeHub 업데이트 카드 밖으로 분리되지 않는지 contract 테스트를 보강했습니다.

## [0.2.14-r3] - 2026-09-14

### 개선

- 업데이트 페이지의 정보 계층을 재구성해 기기 펌웨어를 최상단의 주요 업데이트 영역으로 이동하고, 사용자용 명칭을 `OpenWrt 펌웨어` 대신 `펌웨어`로 단순화했습니다.
- 온라인 펌웨어 업데이트와 수동 `.bin` 업로드를 하나의 펌웨어 카드 안에 묶고, 수동 설치는 기본적으로 접힌 보조 영역으로 배치해 관련 기능의 맥락은 유지하면서 화면 밀도를 낮췄습니다.
- SmartSafeHub 소프트웨어 상태와 자동 업데이트 설정은 넓은 화면에서 2열로 배치하고 모바일에서는 기존처럼 1열로 쌓이도록 조정해 불필요한 전체 폭 카드 반복을 줄였습니다.
- 펌웨어 build ID 메타데이터가 없는 기존 이미지의 경고는 사용자 친화적인 설명을 먼저 보여주고, 파일 경로와 build ID 같은 구현 상세는 펼쳐보기 안으로 이동했습니다.

### 수정

- 이전 펌웨어 업데이트 UI 변경 과정에서 SmartSafeHub 소프트웨어 설명에 남은 중복 JSX 닫힘 태그를 정리했습니다.
- 업데이트/설정 페이지의 사용자용 설명에서 `OpenWrt 펌웨어` 표현을 `펌웨어`로 통일했습니다.

### 테스트

- 펌웨어 카드가 소프트웨어 카드보다 먼저 렌더링되는지, 수동 펌웨어 설치가 같은 카드 내부의 접이식 영역인지, 넓은 화면에서 소프트웨어 상태와 자동 업데이트 설정이 2열로 구성되는지 contract 테스트를 추가했습니다.
- 고객용 펌웨어 제목에 `OpenWrt 펌웨어` 표현이 다시 노출되지 않고, build ID 누락 시 기술 상세가 disclosure 안에 유지되는지 회귀 검증을 추가했습니다.

## [0.2.14-r2] - 2026-09-13

### 기능

- SmartSafeHub 업데이트 페이지에 OpenWrt 펌웨어 업데이트 영역을 추가했습니다. Hub의 `POST /api/v1/firmware/resolve`를 이용해 현재 장치·채널·빌드 기준 최신 Sysupgrade를 확인하고, 온라인 다운로드 또는 `.bin` 파일 직접 업로드 후 자체 화면에서 설치할 수 있습니다.
- 펌웨어 확인 전용 `smartsafehub-firmware` helper와 procd daemon, rpcd ucode API를 추가했습니다. 펌웨어 자동 확인은 기본 활성화하고 6시간 간격으로 실행하지만 펌웨어 자동 설치는 제공하지 않습니다.
- 신규 Stable 설치에서 SmartSafeHub 애플리케이션 자동 설치를 기본 활성화하고 Beta에서는 기본 비활성화했습니다. 기존 장치에 명시적으로 저장된 `auto_install` 값은 그대로 유지합니다.
- 업데이트 페이지에서 소프트웨어 업데이트와 펌웨어 업데이트를 함께 새로고침하도록 통합하고, 설정 페이지의 기존 LuCI 펌웨어 화면 링크는 자체 업데이트 페이지 링크로 교체했습니다.

### 보안 및 안정성

- 온라인 펌웨어는 Hub의 장치 코드·채널·빌드 식별자를 재검증하고 HTTPS 다운로드, 정확한 파일 크기, SHA-256, `system.validate_firmware_image`, `sysupgrade --test`를 모두 통과한 경우에만 설치할 수 있습니다. 설치 직전에도 SHA-256과 OpenWrt 검증을 다시 수행합니다. 펌웨어 확인이 실패하면 이전 resolve 응답을 즉시 폐기해 오래된 배포 정보를 재사용하지 않습니다.
- 수동 업로드도 온라인 이미지와 같은 OpenWrt 검증 경로를 사용하며, 강제 `sysupgrade` 옵션은 UI와 helper에서 제공하지 않습니다.
- 검증 결과가 설정 보존을 허용하는 경우에만 현재 설정 유지 설치를 허용하고, 펌웨어 설치 시작 뒤에는 공유기가 다시 응답할 때까지 현재 주소를 안전하게 재확인한 후 화면을 새로고침합니다.
- 지원 장치 식별을 `iptime-ax3000sm`, `gl-mt300n-v2`, `xiaomi-ax3000t`로 제한하고 `/usr/share/smartsafehub/firmware.json`의 `device_code`와 `build_id`를 우선 사용하도록 했습니다.

### 테스트

- Hub resolve 요청, 온라인 다운로드 무결성 검증, OpenWrt 이미지 검증, 수동 업로드, 준비 파일 정리와 강제 업그레이드 금지 동작을 mock 기반 shell 테스트로 추가했습니다.
- firmware RPC/ACL, 패키지 의존성, 업데이트 UI, 재부팅 후 reconnect/reload 안전성, Stable/Beta 자동 설치 기본값을 contract 테스트에 추가했습니다.

## [0.2.14-r1] - 2026-09-13

### 개선

- SafeShield 업그레이드 시 UI를 개선하여 진행 사항을 쉽게 파악할 수 있도록 하였습니다.
- 기타 사용성 개선을 하였습니다.

### 수정

- 업그레이드 시에 잘못된 로직을 수정하였습니다.

## [0.2.13-r8] - 2026-09-13

### 개선

- SafeShield 보호 요약의 유료 플랜 badge 옆에 중복으로 표시되던 `멤버십 활성` 상태 문구를 제거했습니다. PRO/ULTIMATE 등 유료 플랜은 premium badge의 아이콘과 색상만으로 상태를 인지하도록 단순화했습니다.
- FREE 플랜의 `기본 플랜` 보조 문구는 유지하여 무료 플랜과 유료 멤버십의 정보 계층을 구분했습니다.
- 유료 플랜에서 더 이상 사용하지 않는 tier별 status-caption CSS를 제거했습니다.

### 테스트

- SafeShield 페이지와 체크인된 `app.js`/`app.css`에서 유료 플랜의 `멤버십 활성` 문구와 관련 status-caption 스타일이 다시 노출되지 않는지 회귀 검증을 추가했습니다.

## [0.2.13-r7] - 2026-09-13

### 개선

- SafeShield 설정의 라이선스 요약 영역을 상단 멤버십 표시와 같은 디자인 언어로 다시 정리했습니다. FREE/유료 badge는 유지하면서, 미설정 상태는 `unlicensed` 같은 원문 대신 사용자용 문구로만 표시합니다.
- 라이선스가 등록되지 않은 경우에만 `라이선스 미설정` 보조 텍스트를 보여주고, 등록된 경우에는 불필요한 `active` 상태 문구를 제거해 상단 요약과 하단 설정 표현을 통일했습니다.
- 라이선스 키 입력/변경 영역을 별도 editor 카드로 정리하고 입력창, 현재 키 불러오기, 등록/변경, 제거 버튼의 시각적 계층과 여백을 함께 다듬었습니다.
- 라이트/다크 테마와 모바일 레이아웃에서 라이선스 요약·입력 UI의 시인성과 정렬을 개선했습니다.

### 테스트

- SafeShield 페이지 계약 테스트에 refined 라이선스 summary/editor 클래스와 정적 자산 반영 여부를 추가하고, `unlicensed`/`active` 같은 raw 상태 텍스트가 다시 노출되지 않도록 회귀 검증을 강화했습니다.

## [0.2.13-r6] - 2026-09-12

### 개선

- SafeShield 유료 멤버십 badge를 고대비 premium 스타일로 재설계했습니다. `ULTIMATE`는 dark-gold 기반 metallic gradient, 밝은 gold border/glow, jewel-style mark와 은은한 shine 효과를 적용해 라이트·다크 테마 모두에서 즉시 눈에 띄도록 개선했습니다.
- `PRO`와 기타 유료 플랜도 각각 teal 및 blue jewel-tone gradient로 대비를 강화하고, `멤버십 활성` 상태를 tier 색상의 작은 status pill로 표시해 유료 상태를 badge와 함께 명확하게 인지할 수 있도록 했습니다.
- 모션 감소 설정에서는 ULTIMATE shine 애니메이션을 비활성화하여 접근성을 유지합니다.

### 테스트

- SafeShield 페이지 계약 테스트에 premium badge의 high-contrast 색상, ULTIMATE shine keyframe, tier별 활성 caption 및 reduced-motion 대응이 소스와 체크인된 CSS에 유지되는지 검증을 추가했습니다.

## [0.2.13-r5] - 2026-09-12

### 수정

- 로컬 APK 설치로 `/etc/apk/world`에 남은 SmartSafeHub·SafeShield identity pin을 해제할 때 `apk add --upgrade --latest`를 실행하던 공격적인 정규화 경로를 제거했습니다. 이제 해당 두 패키지의 정확한 identity hash 항목만 일반 패키지 항목으로 직접 정규화합니다.
- identity pin 정규화 뒤에는 항상 `apk upgrade luci-app-smartsafehub` 한 번만 실행하도록 업데이트 경로를 단순화했습니다. SafeShield가 실제로 더 높은 최소 버전을 요구하는 경우에만 APK dependency resolver가 필요한 범위에서 함께 갱신합니다.
- SmartSafeHub 업데이트 때문에 관계없는 OpenWrt 패키지나 현재 펌웨어와 ABI가 다른 `kmod-*` 후보까지 불필요하게 해석되는 위험을 줄였습니다.

### 테스트

- SmartSafeHub와 SafeShield가 각각 로컬 APK identity pin 상태여도 `apk add --upgrade --latest`를 호출하지 않고 world 항목만 정규화한 뒤 target-only 업그레이드가 수행되는지 검증합니다.
- unrelated package의 버전 constraint와 identity pin이 그대로 보존되는지, updater 소스에 광범위한 `--latest`/`--available` 업그레이드 경로가 다시 추가되지 않는지 회귀 테스트를 강화했습니다.

## [0.2.13-r4] - 2026-09-12

### 개선

- SafeShield 보호 요약의 `PLAN` 값을 일반 텍스트 대신 멤버십 badge로 표시하도록 개선했습니다. `ULTIMATE`는 gold 계열, `PRO`는 teal 계열로 강조하고 기타 유료 플랜도 별도의 paid 스타일로 표시합니다.
- FREE 플랜에서는 보호 카드 하단에 SmartSafeHub 멤버십 안내 CTA를 표시하고 `https://www.smartsafehub.com/pricing/` 요금제 페이지를 새 탭으로 열 수 있도록 했습니다. 아직 출시 전인 유료 기능을 과장하지 않도록 `COMING SOON` 상태와 준비 중 안내 문구를 함께 표시합니다.
- 라이선스 설정 카드에서도 동일한 플랜 badge를 재사용하여 상단 요약과 플랜 표현을 일관되게 맞췄습니다.
- 라이트/다크 테마와 모바일 화면에 맞춘 유료 플랜 badge 및 FREE 업그레이드 CTA 스타일을 추가했습니다.

### 테스트

- SafeShield UI 계약 테스트에 전용 플랜 컴포넌트, FREE 전용 CTA 조건, pricing URL, 안전한 새 탭 링크 속성, 체크인된 `app.js`/`app.css` 멤버십 UI 포함 여부를 추가했습니다.

## [0.2.13-r3] - 2026-09-12

### 수정

- SafeShield 상태 재조회와 통계 재조회가 하나의 timeout 목록을 공유하던 구조를 분리했습니다. 상태 갱신 예약과 통계 갱신 예약이 서로의 지연 작업을 취소하지 않도록 각각 독립적으로 관리합니다.
- SafeShield의 보호 활성화/비활성화, 통계 설정, 라이선스 저장·제거 성공 안내는 4.5초 뒤 자동으로 사라지도록 변경했습니다. 오류 메시지는 기존처럼 사용자가 직접 닫을 때까지 유지합니다.
- 새 SafeShield 작업을 시작하거나 사용자가 피드백을 닫을 때 기존 성공 메시지 자동 닫기 timer를 정리하여 이전 작업의 timer가 이후 상태를 건드리지 않도록 했습니다.
- README의 SafeShield 최소 버전 설명을 실제 패키지 의존성인 `>= 0.3.20`과 일치시켰습니다.

### 테스트

- SafeShield UI 계약 테스트에 상태/통계 timer 독립성, 성공 메시지 자동 닫기, 오류 지속 정책, README 최소 버전 일치 여부를 추가했습니다.

## [0.2.13-r2] - 2026-09-12

### 수정

- SafeShield 차단 목록 수동 갱신을 시작했을 때 표시되던 성공 안내 배너를 제거했습니다. 갱신 진행 상태는 보호 카드의 단계별 진행 UI에서만 표시하여, 실제 갱신이 완료된 뒤에도 과거의 `갱신 작업을 시작했습니다` 메시지가 남아 있는 오해를 방지합니다.
- 이미 갱신 중인 경우를 포함해 차단 목록 갱신 요청의 비오류 안내 메시지는 유지하지 않습니다. 갱신 실패는 기존처럼 오류 피드백으로 계속 표시합니다.

### 테스트

- SafeShield UI 계약 테스트에서 수동 갱신의 일시적인 시작/진행 안내 문구가 소스와 배포 `app.js`에 다시 포함되지 않는지 검증합니다.

## [0.2.13-r1] - 2026-09-10

### 개선

- 자동 업데이트 관련 UI 및 사용성을 개선하였습니다.
- 로그인 세션이 만료 되었을때, 사용자에게 안내를 하고 로그인 페이지로 이동하도록 하였습니다.
- 일부 UI에 대한 시인성을 개선하였습니다.

## [0.2.12-r13] - 2026-09-10

### 개선

- SafeShield 갱신 진행 도넛에 진행률 링과 별도로 얇은 외곽 흰색 진행 띠를 추가했습니다. 갱신 중에는 외곽 띠가 부드럽게 회전하여 현재 작업이 계속 진행 중임을 더 직관적으로 전달합니다.
- 오류 상태에서는 외곽 회전 띠를 노출하지 않아 진행 중 상태와 실패 상태를 더 명확하게 구분합니다.
- `prefers-reduced-motion` 환경에서는 외곽 회전 애니메이션을 비활성화하여 접근성과 저사양 환경을 함께 고려했습니다.

### 테스트

- SafeShield 페이지 계약 테스트를 보강해 외곽 진행 띠 마크업, 회전 애니메이션 스타일, reduced-motion 대응이 체크인된 소스와 `app.css`에 모두 존재하는지 검증합니다.

## [0.2.12-r12] - 2026-09-10

### 수정

- 로컬 APK로 설치된 SafeShield가 `/etc/apk/world`의 `><Q...` identity hash로 고정된 경우 SmartSafeHub 업데이트의 의존성 해결이 실패하던 문제를 수정했습니다. SmartSafeHub 설치 전에 SafeShield의 identity pin만 선택적으로 정상화하여 최신 저장소 버전으로 전환할 수 있게 했습니다.
- 기존 SmartSafeHub 자체 identity pin 처리와 동일하게 `apk upgrade --available` 같은 전체 시스템 업그레이드 경로는 사용하지 않고, SmartSafeHub가 관리하는 `safeshield`와 `luci-app-smartsafehub`만 대상으로 처리합니다.

### 테스트

- SafeShield가 identity pin된 상태에서 최신 SmartSafeHub가 더 새로운 SafeShield를 요구하는 실제 실패 조건을 회귀 테스트로 추가했습니다. pin이 제거되고 SafeShield 의존성이 갱신된 뒤 SmartSafeHub 설치가 완료되는지 검증합니다.
- SafeShield identity pin 해제가 실패하면 `UPDATES_INSTALL_FAILED`로 남고 SmartSafeHub 설치를 진행하지 않는지, 다른 패키지의 world constraint 및 identity pin은 변경되지 않는지 검증합니다.

## [0.2.12-r11] - 2026-09-10

### 테스트

- 브라우저 전체 문서 reload/navigation 경로를 별도 안전 계약으로 고정했습니다. `frontend/src`에서 전체 페이지 이동은 self-update 완료 후의 단일 `window.location.reload()` 경로만 허용하며, RPC·세션·공통 polling·엔트리 부트스트랩 오류 경로에서 `reload/replace/assign/location.href`가 추가되면 테스트가 즉시 실패합니다.
- 과거에 발생했던 치명적인 무한 reload 회귀를 실제 `useSoftwareUpdates`의 `useEffect` 본문을 소스에서 추출해 실행하는 시나리오 테스트로 보강했습니다. 초기 `data=null`, 첫 실제 상태의 과거 `lastInstallAt`, stale asset/version mismatch, 정상적인 새 설치 완료, reload 후 새 document의 동일 완료 상태, 반복 관찰, 비-idle phase, 누락된 패키지/asset version, 동일 버전 등을 각각 검증합니다.
- self-update reload latch가 `window.location.reload()`보다 먼저 설정되고, 첫 실제 update state가 baseline만 구성하며, 설치 완료 시각이 바뀌지 않은 상태에서는 다시 reload하지 않는 제어 흐름의 순서도 검증합니다.
- 세션 만료 경로는 `Access denied`의 UBus/JSON-RPC/HTTP 401·403/문자열 변형을 실제 RPC 판별 함수 본문으로 검증하고, stale RPC가 새 세션을 만료시키지 않는지와 RPC 계층이 별도 session probe를 다시 시작하지 않는지를 회귀 테스트로 고정했습니다.
- LuCI session endpoint의 401/403, `X-LuCI-Login-Required`, plain `Access denied`, HTML 로그인 응답, redirect, 올바른 session ID, HTTP 500 및 잘못된 payload를 각각 실행해 인증/만료/통신 오류가 혼동되지 않도록 검증합니다. 같은 세션에서 동시에 여러 RPC가 실패해도 session-expired 이벤트가 한 번만 발생하고, 새 로그인 lifecycle에서는 다시 정상적으로 발생할 수 있는지도 실제 `sessionEvents.ts` 모듈로 검증합니다.
- ShellSpec 계약에 reload/session 안전 회귀 테스트를 추가하고, 정적 검증 및 패키지 계약에서 새 테스트 실행 파일의 존재와 실행 권한도 확인하도록 보강했습니다.

## [0.2.12-r10] - 2026-09-10

### 개선

- SafeShield 보호 카드 상단의 `보호 중` 상태 배지는 빠른 상태 인지를 위해 그대로 유지하면서, 하단 요약의 중복된 `PROTECTION / 보호 중` 항목을 `SAFESHIELD / <설치 버전>` 정보로 변경했습니다.
- 설명문 아래에 작게 단독 표시되던 SafeShield 버전 텍스트를 제거하고 요약 영역으로 이동해 버전 가독성과 정보 계층을 개선했습니다.

### 테스트

- 상단 상태 배지가 유지되고 하단 요약에는 중복 보호 상태 대신 SafeShield 버전이 표시되며, 설명 영역에 중복 버전 텍스트가 남지 않는지 UI contract를 보강했습니다.

## [0.2.12-r9] - 2026-09-10

### 수정

- 업데이트 상태 hook이 첫 렌더의 `data=null`을 `lastInstallAt=null` 기준값으로 저장한 뒤, 첫 실제 응답에 남아 있는 과거 `lastInstallAt`을 새 설치 완료로 오인하던 문제를 수정했습니다. 설치 버전과 로드된 asset 버전이 다른 상태에서는 이 오인이 매 페이지 로드마다 `window.location.reload()`를 실행해 `연결 확인 → Dashboard/Access denied → 연결 확인`이 반복될 수 있었습니다.
- 이제 첫 **실제** 업데이트 상태 응답의 `lastInstallAt`을 기준값으로만 저장하고 자동 새로고침하지 않습니다. 같은 페이지가 이후 updater의 새로운 설치 완료 시각을 실제로 관찰한 경우에만 한 번 새로고침하므로, 과거 update state와 asset version 불일치만으로는 reload loop가 발생하지 않습니다.

### 테스트

- 초기 `data=null`이 self-update reload 기준값으로 사용되지 않는지, 첫 실제 update state는 기준값만 설정하는지, 이후 새로운 `lastInstallAt` 변화에만 자동 새로고침 조건이 열리는지 update UI contract를 보강했습니다.

## [0.2.12-r8] - 2026-09-10

### 수정

- 세션 만료 후 SmartSafeHub RPC가 `Access denied`를 반환할 때 별도의 LuCI 세션 probe 결과를 기다리지 않고 해당 bootstrap 세션을 즉시 만료 처리하도록 변경했습니다. 보호된 session endpoint가 오래된 세션 ID를 다시 반환하는 경우 인증된 화면과 로그인 화면 사이를 반복하던 복구 루프를 제거했습니다.
- 소프트웨어 업데이트 화면이 `updates.state`의 설치 버전과 현재 asset version이 다르다는 이유만으로 매 페이지 로드마다 `window.location.reload()`를 실행하던 무한 새로고침 문제를 수정했습니다. 수동 APK 설치 뒤 남은 오래된 update state나 LuCI template cache로 버전 값이 일시적으로 어긋나도 reload하지 않고, 현재 탭에서 `lastInstallAt`이 새 값으로 바뀌어 실제 updater 설치 완료를 관찰한 경우에만 한 번 새로고침합니다.
- 세션 만료 이벤트는 기존처럼 로그인 화면과 만료 안내 toast로 즉시 전환하며, 이미 시작된 이전 화면의 polling은 App unmount와 함께 정리됩니다.

### 테스트

- RPC `Access denied`가 추가 session probe 없이 즉시 `SESSION_EXPIRED`로 전환되는지 contract를 보강했습니다.
- 초기 로드의 단순 asset/version mismatch는 reload하지 않고, 새 `lastInstallAt`을 관찰한 updater 완료 시점에만 한 번 reload하는 contract를 추가했습니다.

## [0.2.12-r7] - 2026-09-10

### 수정

- 세션 만료 후 RPC가 `Access denied`를 반환할 때 세션 확인 API가 `Access denied` 일반 텍스트를 돌려주는 경우 이를 잘못된 응답으로 처리해 기존 화면의 polling이 계속되던 무한 반복 문제를 수정했습니다. 해당 응답은 이제 즉시 비로그인 상태로 판정합니다.
- 세션 확인 API가 다른 새 세션 ID를 반환해도 기존 코드가 단순히 “세션 있음”으로 판단하면서 오래된 bootstrap session ID로 RPC를 계속 재시도할 수 있던 문제도 수정했습니다. 이제 세션 확인 결과가 현재 RPC에 사용한 session ID와 정확히 일치할 때만 세션이 유효한 것으로 판단합니다.
- 동시에 여러 RPC가 `Access denied`를 반환하는 경우 세션 확인 요청을 하나로 합쳐 불필요한 중복 probe를 방지하고, 이미 만료 처리가 시작된 세션은 추가 probe 없이 즉시 `SESSION_EXPIRED`로 처리합니다.
- 재로그인이 완료된 뒤 이전 세션에서 늦게 도착한 실패 응답이 새 로그인 세션을 다시 만료 처리하지 않도록 현재 bootstrap session ID를 재확인하는 race-condition 방어 로직을 추가했습니다.

### 테스트

- Access denied 처리 시 probe된 session ID와 bootstrap session ID를 정확히 비교하는지, 동시 probe deduplication과 stale-session race guard가 유지되는지 로그인 UI contract를 보강했습니다.

## [0.2.12-r6] - 2026-09-10

### 수정

- SafeShield 차단 목록 갱신 중 `resolve_api` 같은 내부 stage 값을 사용자 화면에 직접 노출하지 않고, 갱신 준비 → 최신 차단 목록 확인 → 다운로드 → 사용자 규칙 적용 → 보호 규칙 적용 → 보호 상태 확인의 6단계 사용자용 진행 상태로 묶어 표시하도록 개선했습니다.
- 갱신 단계는 작은 도넛형 진행 표시에서 `1/6`부터 `6/6`까지 실제 stage 변화에 맞춰 채워지며, 현재 단계 이름과 설명을 함께 표시합니다. 갱신 중에도 하단 `PROTECTION` 요약은 DNS 런타임 상태를 기준으로 `보호 중`을 유지해 작업 상태와 보호 상태가 중복되지 않도록 분리하고, 갱신 도중 API가 차단 규칙 수를 일시적으로 0으로 반환하면 직전에 확인한 적용 규칙 수를 유지해 불필요한 0개 표시를 피합니다.
- 갱신 실패 시 도넛을 오류 상태로 전환하고 다운로드, API 확인, 사용자 규칙, dnsmasq 재시작, 검증, 버전/라이선스 문제 등 오류 코드와 실패 단계를 사용자 친화적인 안내 문구로 변환해 표시합니다. 원본 오류 코드는 진단용 보조 정보로만 작게 유지합니다.

### 테스트

- 6단계 갱신 stage 매핑, 사용자용 진행 도넛, 내부 stage 비노출, 갱신 중 보호 상태 분리, 오류 코드의 사용자용 설명 contract를 추가했습니다.

## [0.2.12-r5] - 2026-09-10

### 수정

- 모바일 공통 터치 영역 규칙인 `.ssh-app button { min-height: 44px; }`가 SafeShield 통계 및 업데이트 설정의 switch track 높이까지 44px로 강제해 작은 화면에서 토글이 세로로 늘어나던 문제를 수정했습니다. switch 전용 selector의 우선순위를 높이고 width/height의 최소·최대값을 모두 고정해 화면 크기와 관계없이 48x28 geometry를 유지합니다.
- switch thumb도 20x20의 최소·최대 크기를 모두 고정해 flex, responsive 스타일 또는 브라우저 기본 button 스타일의 영향을 받아 원형이 찌그러지지 않도록 보강했습니다.

### 테스트

- 모바일 `button` 최소 높이 규칙보다 switch 전용 geometry selector가 우선하도록 CSS contract를 보강하고, track/thumb에 최대 크기 제한까지 존재하는지 검증합니다.

## [0.2.12-r4] - 2026-09-10

### 수정

- 장시간 미사용으로 LuCI 세션이 만료된 뒤 RPC 요청이 `Access denied`를 반환해도 오류 화면에서 재시도만 반복되던 문제를 수정했습니다. RPC 접근 거부가 발생하면 공개 세션 확인 경로로 실제 세션 만료 여부를 확인하고, 만료된 경우 SmartSafeHub 로그인 화면으로 즉시 전환합니다.
- 세션 만료로 로그인 화면으로 전환될 때 `로그인 세션이 만료되었습니다. 계속하려면 다시 로그인해 주세요.` 안내 toast를 표시하고 7초 후 자동으로 닫히도록 했습니다. 동시에 여러 RPC가 실패해도 같은 만료 세션에서는 전환 이벤트를 한 번만 발생시킵니다.
- 유효한 세션에서 ACL 권한 부족으로 발생한 접근 거부는 세션 만료로 오인하지 않고 기존 오류로 유지합니다. 업데이트 화면에만 있던 `Access denied` 강제 reload 처리는 제거하고 모든 SmartSafeHub RPC에 동일한 전역 세션 만료 처리를 적용했습니다.

### 테스트

- RPC 접근 거부 시 세션을 재확인한 뒤에만 만료 이벤트를 발생시키는지, 로그인 화면 전환 및 toast 표시가 연결되는지 UI contract를 추가했습니다.
- 업데이트 polling이 더 이상 `Access denied`를 별도로 reload하지 않고 전역 세션 만료 처리에 맡기는지 검증합니다.

## [0.2.12-r3] - 2026-09-09

### 수정

- 작은 화면에서 SafeShield 통계 수집 토글의 원형 thumb가 찌그러지거나 어둡게 보일 수 있던 문제를 수정했습니다. 토글 track/thumb 크기를 공용 고정 치수 스타일로 분리해 화면 폭과 flex 레이아웃에 관계없이 원형을 유지합니다.
- 다크 모드의 `bg-white` 유틸리티 색상 재매핑이 토글 thumb까지 적용되지 않도록 전용 `ssh-switch-thumb` 스타일을 사용해 밝은 원형 thumb가 일관되게 표시되도록 했습니다. 같은 형태를 사용하는 업데이트 설정 토글에도 공용 스타일을 적용했습니다.

### 테스트

- SafeShield 통계 및 업데이트 설정 토글이 공용 고정 geometry와 theme-safe thumb 스타일을 사용하는지 UI contract를 추가했습니다.

## [0.2.12-r2] - 2026-09-09

### 수정

- 기기별 SafeShield 통계가 많아져도 한 화면이 과도하게 길어지지 않도록 10개 단위의 페이지네이션을 추가했습니다.
- 통계가 갱신되어 전체 페이지 수가 줄어드는 경우 현재 페이지를 자동으로 유효한 범위로 보정합니다.

### 테스트

- 기기별 통계가 10개 단위로 분할되고 이전/다음 페이지 컨트롤을 제공하는 UI contract를 추가했습니다.

## [0.2.12-r1] - 2026-09-09

### 수정

- 업데이트 기능을 개선하였습니다.
- 성능 개선이 포함되었습니다.

## [0.2.11-r3] - 2026-09-09

### 추가

- 업데이트 설정 화면에 현재 SmartSafeHub 패키지 저장소의 배포 채널을 `Stable` 또는 `Beta`로 표시하도록 추가했습니다. `/etc/apk/repositories.d/smartsafehub.list`의 실제 저장소 경로를 기준으로 채널을 판별해 현재 업데이트 확인 대상과 UI 표시가 일치하도록 했습니다.
- 현재는 채널을 읽기 전용으로 표시하며, frontend의 업데이트 설정 모델에 `channel` 필드를 분리해 추후 Stable/Beta 선택 기능을 추가하기 쉽게 구성했습니다. 인식할 수 없는 저장소 경로는 `미확인`으로 표시합니다.

### 테스트

- `updates_status`가 SmartSafeHub 저장소 파일에서 업데이트 채널을 읽어 반환하는 contract를 추가했습니다.
- 업데이트 화면이 `Stable`/`Beta` 채널을 표시하면서 저장소 hostname 같은 내부 구현 정보는 노출하지 않는지 UI contract로 검증합니다.

## [0.2.11-r2] - 2026-09-08

### 수정

- SmartSafeHub 자체 업데이트 완료 후 `rpcd restart`로 기존 LuCI 세션이 사라져 업데이트 화면의 상태 polling이 `Access denied`를 반복하던 문제를 수정했습니다. 업데이트 후에는 `rpcd reload`를 사용해 RPC plugin/ACL을 다시 읽으면서 기존 세션을 유지합니다.
- 설치 중 기존 세션이 예외적으로 무효화되어 LuCI가 `Access denied`를 반환하면 무한 polling을 계속하지 않고 페이지를 다시 로드해 SmartSafeHub의 세션 확인/로그인 흐름으로 복구하도록 보강했습니다.
- 업데이트 상태의 실제 설치 버전과 현재 브라우저가 로드한 asset version이 달라지면 페이지를 한 번 자동으로 다시 로드해 새 `app.js`와 `app.css`를 즉시 사용하도록 했습니다. 자동 설치가 polling 사이에 완료된 경우에도 다음 상태 조회에서 버전 불일치를 감지합니다.

### 테스트

- self-update 완료 경로가 `rpcd restart`를 사용하지 않고 `rpcd reload`만 예약하는지 검증합니다.
- 업데이트 설치 중 `Access denied`가 발생하면 페이지 reload 복구 경로가 존재하고, 설치 완료 후 package/asset version 불일치에서도 새 frontend asset을 위한 reload가 수행되는지 UI contract로 검증합니다.

## [0.2.11-r1] - 2026-09-08

### 수정

- SafeShield의 최소 버전을 0.3.20 이상으로 설정하였습니다.

## [0.2.10-r5] - 2026-09-08

### 수정

- 내부에서 사용하는 패키지를 업데이트 하였습니다.

## [0.2.10-r4] - 2026-09-08

### 수정

- 로컬 `.apk` 파일로 SmartSafeHub를 설치해 `/etc/apk/world`에 `luci-app-smartsafehub><Q...` identity hash constraint가 남은 경우, 자동/수동 업데이트가 저장소 버전으로 전환되지 못하고 `UPDATES_INSTALL_VERSION_UNCHANGED`가 발생하던 문제를 수정했습니다.
- SmartSafeHub 자체에 identity pin이 있을 때만 `apk add --upgrade --latest luci-app-smartsafehub`로 해당 패키지의 world constraint를 저장소 기반 constraint로 정상화하고, 일반 상태에서는 기존 `apk upgrade luci-app-smartsafehub` 경로를 유지하도록 했습니다.
- 전체 world의 version constraint를 초기화해 OpenWrt의 다른 패키지까지 갱신할 수 있는 `apk upgrade --available`은 updater에서 사용하지 않도록 했습니다.
- identity pin 정상화 후에도 해당 pin이 남아 있으면 설치 성공으로 처리하지 않고 기존 `UPDATES_INSTALL_FAILED` 경로로 오류를 반환하도록 보강했습니다.

### 테스트

- 일반 repository 설치 상태에서는 기존 target-only `apk upgrade` 경로가 유지되는지 검증합니다.
- 로컬 APK identity pin이 있는 경우 SmartSafeHub 하나에 대해서만 `apk add --upgrade --latest`를 사용해 pin을 제거하고 목표 버전으로 올라가는지 검증합니다.
- updater가 `apk upgrade --available`을 사용하지 않는 contract를 추가해 다른 OpenWrt 패키지의 광범위한 업그레이드가 다시 도입되지 않도록 방지합니다.

## [0.2.10-r3] - 2026-09-08

### 수정

- 수동 업데이트 확인을 시작한 뒤 백엔드가 `checking` 상태인 동안 1초 간격으로 상태를 다시 조회하고, 확인 작업이 `idle` 또는 `error`로 끝나는 즉시 화면에 최종 상태와 버전 정보를 반영하도록 수정했습니다.
- 평상시에는 기존 5분 background polling을 유지하고 실제 설치 중에는 기존 3초 polling을 유지해, 업데이트 확인 중에만 짧은 polling이 추가되도록 했습니다.

### 테스트

- 업데이트 확인 단계가 1초 polling을 사용하고 설치 단계의 3초 polling 및 idle 상태의 5분 polling과 구분되는지 UI contract에서 검증합니다.

## [0.2.10-r2] - 2026-09-08

### 수정

- SmartSafeHub 자동/수동 패키지 설치에서 `apk add --upgrade` 대신 설치된 패키지를 실제로 갱신하는 `apk upgrade luci-app-smartsafehub`를 사용하도록 수정했습니다.
- APK 명령이 성공 코드(`0`)를 반환하더라도 설치 후 버전이 확인된 목표 버전과 일치하지 않으면 `UPDATES_INSTALL_VERSION_UNCHANGED` 오류로 처리하고 `last_install_at`을 갱신하지 않도록 보강했습니다.
- 자동 설치가 실패한 경우에는 해당 날짜의 완료 marker를 기록하지 않고 15분 cooldown 후 다시 시도하도록 수정해 일시적인 저장소/네트워크 오류에서는 복구하면서도 매 daemon tick마다 APK 작업을 반복하지 않도록 했습니다. lock 경합은 완료/재시도 marker를 소비하지 않습니다.
- 자동 설치 실패 재시도를 15분 간격으로 유지하면서 하루 최대 3회로 제한했습니다. 첫 예약 시도를 포함해 3회 모두 실패하면 해당 날짜에는 더 이상 APK 설치를 시도하지 않고 다음날 예약 시간부터 다시 시작합니다.
- updater lock 경합(`75`)은 실제 설치 시도로 계산하지 않으며, 성공 시에는 재시도 횟수/시간 marker를 함께 정리하도록 했습니다.
- 재시도 횟수 marker에 날짜를 함께 기록하고 날짜가 바뀌면 stale retry 상태를 정리해 다음날 재시도 횟수가 0부터 시작되도록 했습니다.

### 테스트

- `apk upgrade`가 exit code `0`을 반환하면서 실제 설치 버전을 변경하지 않는 no-op 상황을 회귀 테스트로 추가하고, 실패 상태/오류 코드/`last_install_at` 보존을 검증합니다.
- updater가 자동 설치 성공 시에만 날짜 marker를 기록하고 실패 재시도에는 15분 cooldown marker를 사용하는 contract를 검증합니다.
- 자동 설치 최대 시도 횟수(`3`), 15분 retry cooldown, lock 경합 제외, 성공 시 retry marker 정리, 날짜 변경 시 retry count 초기화 contract를 검증합니다.

## [0.2.10-r1] - 2026-09-07

### 변경

- 새로고침 아이콘을 개선하고 전체적으로 통일성 있게 적용하였습니다.
- 업데이트를 확인하는 로직을 수정하였습니다.

## [0.2.9-r9] - 2026-09-07

### 수정

- OpenWrt/APK 인덱스 갱신이 실패해도 `INSTALLED` 값은 캐시된 updater state가 아니라 로컬 APK 데이터베이스의 실제 `luci-app-smartsafehub` 설치 버전으로 다시 동기화하도록 수정했습니다.
- 수동 APK 설치 등으로 실제 설치 버전이 마지막 확인 시점과 달라졌을 때는 이전 `AVAILABLE` 버전과 릴리즈 노트를 재사용하지 않아 오래된 업데이트 대상을 현재 버전처럼 표시하지 않도록 보강했습니다.
- 업데이트 설치 시작 단계에서 인덱스 갱신이 실패하는 경우에도 동일하게 로컬 설치 버전을 state에 반영하도록 통일했습니다.
- 헤더, 업데이트 확인/설치, 공통 로딩 패널, SafeShield 통계 토글과 로그인 진행 상태의 로딩 표현을 동일한 원형 새로고침 아이콘으로 통일하고 진행 중에는 해당 아이콘 자체를 회전하도록 정리했습니다.

### 테스트

- 마지막 업데이트 확인 이후 로컬 패키지 버전이 변경된 상태에서 APK 인덱스 갱신이 실패해도 `INSTALLED`가 실제 로컬 버전으로 갱신되고 이전 릴리즈 노트 캐시는 제거되는지 검증합니다.
- 새로고침/로딩 상태가 공통 `ReloadIcon`을 사용하고 기존 `LoaderIcon`/`RefreshIcon` 변형이 다시 섞이지 않는지 UI contract에서 검증합니다.

## [0.2.9-r8] - 2026-09-07

### 수정

- OpenWrt/APK 인덱스 갱신이 일시적으로 실패해도 마지막으로 확인한 SmartSafeHub 설치/업데이트 버전 범위가 있으면 해당 정보를 사용해 릴리즈 노트 갱신을 계속 시도하도록 변경했습니다.
- 릴리즈 노트 재조회가 실패한 경우 설치 버전과 사용 가능 버전 범위가 동일한 마지막 정상 캐시는 유지하고, 범위가 달라진 오래된 캐시는 재사용하지 않도록 보강했습니다.

### 테스트

- APK 인덱스 갱신 실패 경로에서도 기존 package state로 beta/stable 릴리즈 노트를 다시 생성할 수 있는지 검증합니다.
- 릴리즈 노트 서버의 일시적인 장애에서는 같은 버전 범위의 정상 캐시가 유지되고, 버전 범위가 달라진 캐시는 제거되는지 검증합니다.

## [0.2.9-r7] - 2026-09-07

### 개선

- 업데이트 확인/설치 진행 중에는 상태 배지와 액션 버튼에 회전 spinner를 표시하고, 설치 단계에는 실제 진행률을 추정하지 않는 indeterminate progress bar를 추가해 작업이 계속 진행 중임을 명확하게 표시합니다.
- 설치 시작 직후의 안내를 수동 새로고침 요청 대신 `완료되면 화면이 자동으로 갱신됩니다`로 변경해 3초 상태 polling 동작과 UI 문구를 일치시켰습니다.
- 업데이트 실패 시 원본 APK/OpenWrt 저장소 오류 문자열을 바로 노출하지 않고 오류 코드별 사용자용 요약을 먼저 보여주며, URL과 원본 메시지는 `상세 정보 보기`에서 확인하도록 정리했습니다.

### 테스트

- 설치 중 spinner/indeterminate progress, 자동 갱신 안내, repository 오류 요약/상세 정보 분리와 기존 수동 새로고침 문구 제거를 update UI contract에서 검증합니다.

## [0.2.9-r6] - 2026-09-07

### 수정

- 소프트웨어 업데이트를 한 번도 확인하지 않은 상태에서 `최신 버전` 또는 성공 안내를 표시하지 않고 `미확인` 상태로 유지하도록 수정했습니다.
- `확인 전` 배지는 중립적인 색상으로 표시하고, 첫 확인 전에는 별도의 안내와 `지금 확인` 액션을 제공하도록 정리했습니다.

### 테스트

- 첫 업데이트 확인 전에는 최신 상태 success UI가 표시되지 않고 `AVAILABLE` 값이 `미확인`으로 유지되는 contract를 추가했습니다.

## [0.2.9-r5] - 2026-09-07

### 수정

- 대시보드 시스템 상태의 메모리 사용률 progress bar를 메모리 요약 카드 내부로 이동해 동일한 사용률 정보를 별도 영역에서 중복 표시하지 않도록 정리했습니다.
- 메모리 사용량 텍스트(`사용량 / 전체 용량`)는 그대로 유지하고 progress bar에 접근성용 progressbar 속성을 추가했습니다.

### 테스트

- 대시보드 contract에서 메모리 progress bar가 메모리 카드 내부에 존재하고 별도의 `메모리 사용률` 블록이 다시 추가되지 않는지 검증합니다.

## [0.2.9-r4] - 2026-09-07

### 수정

- 릴리즈 노트 채널을 전체 APK repository 목록의 탐색 순서로 결정하지 않고 SmartSafeHub 설정에 저장 된 channel URL에서 직접 결정하도록 수정했습니다.
- stable에서 beta로 전환한 뒤 다른 repository 파일에 stable URL이 남아 있어도 beta 채널의 릴리즈 인덱스와 릴리즈 노트만 조회하도록 수정했습니다.

### 테스트

- 별도의 repository 파일에 stable URL이 먼저 존재하고 `smartsafehub.list`는 beta를 가리키는 전환 시나리오에서 beta 릴리즈 노트 경로만 사용하는 회귀 테스트를 추가했습니다.

## [0.2.9-r3] - 2026-09-06

### 변경

- 소프트웨어 업데이트 상태의 일반 polling 주기를 60초에서 5분으로 늘리고, 실제 설치 진행 중에만 3초 간격으로 상태를 확인하도록 조정했습니다.
- 업데이트 상태 polling은 브라우저 탭이 숨겨져 있는 동안 중단하고, 다시 보이거나 창이 포커스를 얻었을 때 마지막 조회가 polling 주기보다 오래된 경우에만 즉시 최신 상태를 확인하도록 visibility/focus 기반 갱신을 보강했습니다.
- 수동 새로고침이나 짧은 탭 전환 직후에는 남은 polling 시간만 다시 예약해 focus/visibility 이벤트로 인한 불필요한 중복 RPC를 줄였습니다.

### 테스트

- 업데이트 polling 주기, 설치 단계 전용 3초 polling, visibility/focus 갱신과 이벤트 listener cleanup을 update UI contract에서 검증합니다.

## [0.2.9-r2] - 2026-09-06

### 테스트

- Shell 기반 contract 테스트를 ShellSpec suite로 통합하고 별도 `tests/run.sh` runner를 제거했습니다.
- 로컬과 GitHub Actions 모두 프로젝트 루트에서 `shellspec`을 직접 실행해 동일한 테스트 진입점을 사용합니다.
- 기존 package, navigation, document, login, dashboard, network input, update, settings, ucode import, RPC, rules, SafeShield, statistics, updater contract를 개별 ShellSpec example로 유지합니다.
- GitHub Actions에서는 ShellSpec 0.28.1을 고정 설치해 테스트 프레임워크 업데이트에 따른 비결정적 실패를 방지합니다.

## [0.2.9-r1] - 2026-09-03

### 변경

- 전체 레이아웃 구조를 변경하여 사용성과 메뉴 접근성을 향상시켰습니다.
- 다크 모드에 대한 지원을 추가하였습니다.

## [0.2.8-r16] - 2026-09-03

### 변경

- 업데이트 화면에서 시스템 상태와 시스템 관리 영역을 분리하고 SmartSafeHub 소프트웨어 업데이트와 자동 업데이트 설정만 남겼습니다.
- 사이드바의 System 그룹에 `설정` 메뉴를 업데이트 바로 아래 추가하고 시스템 상태, 펌웨어 관리, 진단 정보, 재부팅과 LuCI 보조 진입점을 새 설정 화면으로 이동했습니다.
- 사이드바와 모바일 drawer의 독립 `고급 설정` 링크를 제거해 제품 UI에서 LuCI로 바로 이탈하지 않도록 하고, 아직 SmartSafeHub가 제공하지 않는 항목만 설정 화면의 `LuCI 고급 설정 열기` 보조 액션으로 접근하도록 정리했습니다.
- 설정 화면의 설명을 SmartSafeHub 안에서 자주 사용하는 관리 기능을 우선 제공하고 LuCI 의존 범위를 점진적으로 줄이는 방향으로 명확히 했습니다.

### 테스트

- 업데이트/설정 route 분리, 메뉴 순서, 시스템 상태/관리 이동, 사이드바의 독립 고급 설정 링크 제거와 설정 화면 내부 LuCI fallback을 검증하는 UI contract를 보강했습니다.

## [0.2.8-r15] - 2026-09-03

### 변경

- 데스크톱 상단의 새로고침 액션을 텍스트 버튼에서 테마 전환과 동일한 크기의 아이콘 버튼으로 정리해 헤더의 전역 액션 밀도를 낮췄습니다.
- 모바일 상단에는 테마 전환, 새로고침, 햄버거 메뉴 순서로 액션을 배치해 현재 화면을 메뉴 진입 없이 즉시 갱신할 수 있도록 했습니다.
- 새로고침 중에는 Refresh 아이콘을 회전시키고 중복 요청을 방지하도록 버튼을 비활성화하며 `aria-busy`, `aria-label`, `title`로 상태를 전달합니다.

### 테스트

- 데스크톱/모바일 새로고침 버튼의 위치, 아이콘 전용 표현, loading/refreshing 비활성화와 회전 상태를 navigation contract에서 검증합니다.

## [0.2.8-r14] - 2026-09-03

### 변경

- Light/Dark Mode 전환을 사이드바 시스템 메뉴에서 제거하고 데스크톱 상단 새로고침 액션 옆의 아이콘 버튼으로 이동해 전역 화면 설정이라는 의미를 명확하게 했습니다.
- 모바일에서는 테마 전환 아이콘을 햄버거 메뉴 바로 왼쪽에 배치해 메뉴를 열지 않고도 테마를 즉시 변경할 수 있도록 개선했습니다.
- 테마 전환은 텍스트 없이 Sun/Moon 아이콘만 표시하되 `aria-label`, `title`을 유지해 접근성을 보존합니다.

### 테스트

- 데스크톱 헤더와 모바일 상단 내비게이션의 테마 토글 위치, 사이드바/모바일 drawer 내부의 중복 테마 액션 제거를 navigation contract에서 검증합니다.

## [0.2.8-r13] - 2026-09-03

### 변경

- 로그인 화면을 현재 SmartSafeHub Dashboard/SafeShield와 동일한 surface, form-control, teal focus 중심의 제품 디자인으로 정리했습니다.
- 사용자 이름과 비밀번호를 모두 입력할 수 있는 LuCI 인증 흐름을 유지하고, 향후 관리자 계정명이 변경되어도 별도 인증 로직 수정 없이 사용할 수 있도록 했습니다.
- 비밀번호 표시/숨김을 텍스트 액션에서 아이콘 버튼으로 개선하고, 빈 사용자 이름/비밀번호 제출 시 올바른 입력 필드로 포커스를 복원하도록 보강했습니다.
- 로그인 화면에 Light/Dark Mode 전환을 추가하고 인증 후 App Shell과 동일한 `smartsafehub.theme` 설정을 공유하도록 테마 상태 관리를 공통 유틸리티로 정리했습니다.
- 모바일에서는 제품 로고와 로그인 폼을 하나의 full-height surface로 표시하고, 로그인 중/세션 확인/오류/기본 LuCI fallback 상태가 Light/Dark Mode에서 일관되게 표시되도록 정리했습니다.

### 테스트

- 사용자 이름/비밀번호 필드, autocomplete, form submit, 비밀번호 표시 토글, 공통 theme 저장/복원, 로그인 Dark Mode와 form-control 스타일을 검증하는 로그인 UI contract 테스트를 추가했습니다.

## [0.2.8-r12] - 2026-09-03

### 추가

- Dashboard에 SafeShield 최근 24시간 차단 활동 차트를 추가해 보호 동작 추이를 첫 화면에서 바로 확인할 수 있도록 했습니다.
- 차트와 함께 최근 24시간 DNS 요청, 차단 수와 차단율을 요약하고 현재 WAN/연결 기기 구성을 나란히 표시하는 네트워크 보호 활동 영역을 추가했습니다.

### 변경

- Dashboard의 SafeShield statistics 조회는 진입 시 한 번만 수행하고 사용자가 새로고침할 때만 다시 조회하도록 구성해 상세 SafeShield 페이지의 60초 polling이 Dashboard로 확장되지 않도록 했습니다.
- 연결 기기 one-shot 조회가 `exactOptionalPropertyTypes` 설정과 호환되도록 polling 비활성화 시 `pollInterval` 프로퍼티 자체를 생략하도록 정리했습니다.

### 테스트

- Dashboard 차트 재사용, SafeShield statistics one-shot 조회, 통합 새로고침과 polling 비활성화 계약을 검증하도록 Dashboard UI contract 테스트를 보강했습니다.

## [0.2.8-r11] - 2026-09-03

### 변경

- Dashboard를 다른 제품 페이지와 동일한 eyebrow, 한글 제목/설명, 흰색 rounded surface 중심의 시각 언어로 재구성했습니다.
- 첫 화면에서 인터넷 연결, SafeShield 보호 상태, 현재 연결 기기 수와 SmartSafeHub 업데이트 상태를 함께 확인할 수 있도록 핵심 운영 정보를 보강했습니다.
- 시스템 리소스 영역에 메모리 사용량, 1/5/15분 부하와 실행 시간을 정리하고 장치 정보에 커널, WAN IP와 보드 정보를 추가했습니다.
- SafeShield 최근 차단 목록 갱신, 연결 기기 목록 생성, 소프트웨어 업데이트 확인 시각을 별도 상태 freshness 영역에서 확인할 수 있도록 추가했습니다.
- Dashboard의 연결 기기 목록은 진입 시 한 번만 조회하고, 기존 15초 polling은 연결된 기기 상세 페이지에서만 유지해 Dashboard 추가 정보로 인한 주기 부하를 제한했습니다.

### 테스트

- Dashboard의 SafeShield/연결 기기/업데이트 요약, 일회성 기기 조회와 통합 새로고침 동작을 검증하는 UI contract 테스트를 추가했습니다.

## [0.2.8-r10] - 2026-09-03

### 추가

- 브라우저 탭과 북마크에서 SmartSafeHub를 식별할 수 있도록 제품 로고의 shield/check 디자인을 재사용한 SVG favicon을 추가했습니다.
- 로그인 전/후 동일한 SmartSafeHub 문서에서 favicon이 적용되도록 public entry template의 `<head>`에 favicon을 등록하고 패키지 revision 기반 cache key를 적용했습니다.

### 변경

- `LoadingPanel`을 spinner 위주의 세로 레이아웃에서 compact 가로 레이아웃으로 변경해 로딩 문구 위에 과도한 공간이 생기던 문제를 수정했습니다.
- public entry template에 SmartSafeHub 설명, application name, 검색 엔진 비노출 정책과 light/dark color scheme 메타데이터를 추가했습니다.
- 브라우저의 주소창/탭 UI가 현재 SmartSafeHub 테마와 자연스럽게 어울리도록 `theme-color`를 추가하고 앱의 Light/Dark Mode 전환과 동기화했습니다.

### 테스트

- LoadingPanel의 compact layout과 필수 document metadata 및 theme-color 동기화를 contract 테스트로 검증합니다.

## [0.2.8-r9] - 2026-09-03

### 변경

- 업데이트 화면을 현재 상태, 설치/사용 가능 버전, 마지막 확인과 자동 설치 상태를 한눈에 확인할 수 있는 제품형 요약 카드로 재구성했습니다.
- 업데이트 확인과 설치 액션을 상단에 배치하고, 릴리즈 노트와 자동 업데이트 설정을 별도 surface로 분리해 정보 계층을 명확하게 정리했습니다.
- 자동 업데이트 확인 주기와 설치 시각 입력에 Wi-Fi/사용자 규칙과 동일한 2px 테두리, 배경 대비, inset shadow와 teal focus 상태를 적용했습니다.
- 자동 확인/자동 설치 설정을 명확한 switch control로 변경하고 내부 저장소/패키지 이름 같은 구현 세부 정보는 제품 화면에서 숨겼습니다.
- 업데이트를 페이지의 첫 번째 주요 영역으로 이동하고 시스템 상태와 시스템 관리 기능을 후속 섹션으로 구분했습니다.

### 테스트

- 업데이트 요약 카드, 명확한 update action, form control, switch와 페이지 정보 계층을 검증하는 UI contract 테스트를 추가했습니다.

## [0.2.8-r8] - 2026-09-03

### 수정

- Wi-Fi 보안 방식 선택 상자에도 SSID/비밀번호 입력과 동일한 2px 테두리, 배경 대비, inset shadow와 teal focus 상태를 적용해 form control 표현을 통일했습니다.
- Wi-Fi의 SSID/비밀번호 입력 필드와 연결된 기기 검색창에도 사용자 규칙과 동일한 2px 테두리, 배경 대비, inset shadow와 teal focus 상태를 적용해 text input 표현을 통일했습니다.
- 연결된 기기 검색창의 돋보기 아이콘을 transform 기반 위치 계산 대신 고정 폭 flex 래퍼로 수직 중앙 정렬했습니다.
- 사용자 규칙의 새 도메인 입력 필드에 SafeShield 라이선스 입력과 동일한 2px 테두리, 배경 대비, inset shadow와 focus 상태를 적용해 입력 필드임을 더 명확하게 표시합니다.
- 허용/차단 목록 검색창의 돋보기 아이콘을 transform 기반 위치 계산 대신 고정 폭 flex 래퍼로 수직 중앙 정렬해 LuCI 환경에서 아이콘이 비뚤어져 보이던 문제를 수정했습니다.
- 검색 입력 필드도 새 도메인 입력과 동일한 제품형 input surface로 통일했습니다.

## [0.2.8-r7] - 2026-09-02

### 변경

- SafeShield 페이지를 보호 상태, 최근 24시간 핵심 통계, 활동 차트, 보호 구성, 설정 순서의 제품형 정보 구조로 재구성했습니다.
- 시간별 통계 bucket을 기준으로 최근 24시간 DNS 요청, 차단 요청과 차단율을 계산해 현재 통계의 의미를 더 명확하게 표시합니다.
- DNS 런타임, 차단 목록, 갱신 일정과 health 정보를 2열 보호 구성 카드로 정리하고 라이선스, 아티팩트, 로컬 규칙을 별도 설정 영역으로 분리했습니다.
- 기존 SafeShield status/statistics RPC와 polling 주기는 변경하지 않아 UI 개편으로 추가 장비 부하가 발생하지 않습니다.
- 사이드바 접기/펼치기 버튼을 브랜드 헤더 하단 경계에 유지하면서 기본 색상과 shadow를 낮추고 hover 시에만 teal로 강조하도록 조정했습니다.

### 테스트

- SafeShield 제품형 페이지 계층과 최근 24시간 통계 표시 계약, 사이드바 경계 토글의 위치와 저강도 기본 스타일을 검증합니다.

## [0.2.8-r6] - 2026-09-02

### 수정

- 데스크톱 사이드바 접기/펼치기 버튼을 화면 중앙에서 브랜드 헤더 하단과 사이드바 오른쪽 경계선이 만나는 위치로 이동했습니다.
- 토글 버튼에 SmartSafeHub 포인트 컬러 배경과 흰색 아이콘, 강조 shadow를 적용해 라이트/다크 모드 모두에서 더 쉽게 식별할 수 있도록 개선했습니다.

## [0.2.8-r5] - 2026-09-02

### 수정

- 데스크톱 사이드바 접기/펼치기 버튼을 확장/축소 상태와 관계없이 오른쪽 경계선 중앙에 걸쳐 표시하도록 변경했습니다.
- 경계형 토글을 원형 버튼으로 통일해 사이드바 너비 전환 동작을 더 명확하게 표시합니다.

## [0.2.8-r4] - 2026-09-02

### 추가

- 데스크톱 좌측 사이드바를 16rem 확장 상태와 5rem 축소 상태로 전환하는 접기/펼치기 기능을 추가했습니다.
- 축소 상태에서도 SmartSafeHub 로고 마크를 항상 유지하고, 메뉴는 아이콘 중심의 compact navigation으로 표시합니다.
- 라이트/다크 모드 전환 기능을 추가하고 선택한 테마를 브라우저 `localStorage`에 저장합니다.
- 저장된 테마가 없으면 브라우저의 `prefers-color-scheme` 설정을 초기값으로 사용합니다.
- 모바일 메뉴에도 동일한 테마 전환 기능을 제공합니다.

## [0.2.8-r3] - 2026-09-02

### 추가

- 데스크톱 좌측 사이드바를 16rem 확장 상태와 5rem 축소 상태로 전환하는 접기/펼치기 버튼을 추가했습니다.
- 축소 상태에서는 메뉴 그룹명과 텍스트를 숨기고 아이콘 중심의 compact navigation으로 표시합니다.
- 축소 상태의 메뉴에는 `title`과 `aria-label`을 유지하고 업데이트 개수 badge를 아이콘 우측 상단에 표시합니다.
- 사용자가 선택한 사이드바 상태를 브라우저 `localStorage`에 저장해 페이지 이동과 다음 접속에서도 유지합니다.
- 모바일 navigation drawer는 기존 동작을 그대로 유지합니다.

## [0.2.8-r2] - 2026-09-02

### 수정

- 데스크톱 AppShell에서 좌측 사이드바와 콘텐츠 영역을 2열 grid로 배치하도록 수정했습니다.
- ProductNavigation이 콘텐츠 `<main>` 내부에서 전체 너비를 차지해 Dashboard가 아래로 밀리던 레이아웃 회귀를 수정했습니다.
- 헤더와 Dashboard를 우측 workspace에 함께 배치해 사이드바가 화면 왼쪽에 고정되는 구조를 복원했습니다.

## [0.2.8-r1] - 2026-09-02

### 변경

- 데스크톱 제품 내비게이션을 상단 탭 구조에서 고정 좌측 사이드바 구조로 변경했습니다.
- 메뉴를 Overview, Network, Security, System 영역으로 그룹화해 기능이 늘어나도 확장 가능한 정보 구조를 적용했습니다.
- 모바일에서는 기존 햄버거 흐름을 유지하면서 같은 메뉴 그룹과 제품 브랜딩을 사용하는 drawer 형태로 정리했습니다.
- 페이지 상단의 대형 hero를 compact header로 변경해 콘텐츠 밀도를 높이고 관리 콘솔 형태를 강화했습니다.
- Dashboard를 KPI 중심 System overview, System health, Device details 구조로 재설계했습니다.
- 기존 상태/업데이트 RPC 계약은 변경하지 않고 현재 로드되는 데이터만 재구성해 저사양 장비의 추가 호출을 만들지 않습니다.

## [0.2.7-r1] - 2026-09-02

safeshield의 최소 버전을 0.3.19 이상으로 설정하였습니다.

## [0.2.6-r3] - 2026-08-30

### 변경

- backend CI에서 개별적으로 실행하던 shell syntax, JSON, package/RPC/ucode/statistics/updater 검증을 `tests/run.sh` 하나로 통합했습니다.
- 로컬에서도 `./tests/run.sh`로 GitHub Actions backend job과 동일한 테스트 흐름을 실행할 수 있습니다.

## [0.2.6-r2] - 2026-08-30

safeshield의 최소 버전을 0.3.17 이상으로 설정하였습니다.

## [0.2.6-r1] - 2026-08-30

safeshield의 최소 버전을 0.3.15 이상으로 설정하였습니다.

## [0.2.5-r5] - 2026-08-30

### 변경

- SafeShield `0.3.14-r8`의 statistics-only runtime reconciliation에 맞춰 통계 토글 후 전체 SafeShield 상태를 장시간 재조회하지 않고 통계 상태만 짧게 확인합니다.
- 통계 설정 RPC와 첫 통계 재조회가 끝날 때까지 토글의 busy 상태를 유지해 변경이 진행 중임을 명확하게 표시합니다.
- 통계 수집 활성화/비활성화 중 스위치 knob에 spinner를 표시하고 통계 카드에 wait cursor를 적용합니다.
- 토글 직후에는 목표 상태를 스위치에 즉시 반영하고 `활성화하는 중…` 또는 `비활성화하는 중…` 상태 문구를 표시합니다.
- SafeShield 최소 의존성을 `0.3.14-r8`로 올려 통계 토글이 refresh daemon을 재시작하지 않는 backend 동작을 요구합니다.

### 테스트

- statistics reconciliation 응답, spinner/wait cursor, 목표 상태 표시와 statistics-only 후속 polling 계약을 테스트합니다.

## [0.2.5-r4] - 2026-08-29

### 추가

- SafeShield 차단 통계 카드에 통계 수집 활성화/비활성화 스위치를 추가했습니다.
- 통계 수집 상태와 collector 실행 상태를 함께 표시하고, 비활성화 상태에서는 로컬 집계 방식 안내를 표시합니다.

### 변경

- 통계 설정 변경은 SafeShield 공식 `config_update` RPC에서 `statistics_enabled` 옵션만 갱신하며, 변경 후 상태와 통계를 즉시 다시 조회합니다.

### 테스트

- 통계 토글의 ACL, RPC payload, collector 상태 정규화와 접근성 switch 계약을 테스트에 추가합니다.

## [0.2.5-r3] - 2026-08-29

### 추가

- SafeShield 통계 화면에 기기별 DNS 요청, 차단 수와 차단율을 표시합니다.
- DHCP lease로 식별된 기기는 hostname, 현재 IP와 MAC 주소를 함께 보여주고, lease가 없는 기기는 IP 임시 식별 상태로 표시합니다.
- SafeShield가 개별 기기 추적 한도를 초과한 경우 `기타 기기` 합산과 추적 한도 안내를 표시합니다.

### 변경

- 기기별 통계와 AWK array 초기화 안정성 수정이 포함된 SafeShield `0.3.14-r7` 이상을 최소 의존성으로 요구합니다.

### 테스트

- 통계 RPC의 `devices`, `device_limit`, `devices_truncated` 정규화와 기기별 통계 UI 연결을 계약 테스트에 추가합니다.

## [0.2.5-r2] - 2026-08-29

### 변경

- SafeShield 최근 24시간 시간대별 차단 요청 그래프를 CSS 높이 계산 방식에서 Chart.js 4.5.1 기반 Bar 차트로 변경했습니다.
- `chart.js/auto` 대신 Bar 차트에 필요한 controller, element, scale, tooltip만 등록하여 불필요한 차트 기능이 번들에 포함되지 않도록 했습니다.
- 60초 통계 갱신 시 기존 Chart.js 인스턴스의 데이터를 갱신해 막대 높이가 자연스럽게 전환되도록 했습니다.
- 운영체제의 `prefers-reduced-motion` 설정을 존중하여 모션 감소 사용자는 차트 애니메이션을 사용하지 않습니다.
- 기존 24시간 범위, 3시간 간격 시간 라벨과 차단/DNS 요청 tooltip 정보를 유지하면서 Y축 눈금을 추가했습니다.

## [0.2.5-r1] - 2026-08-29

### 추가

- SafeShield 페이지에 로컬 DNS 통계 카드를 추가해 전체 DNS 요청, 차단 요청, 차단율, 현재 시간 차단 수를 표시합니다.
- 최근 24시간의 시간대별 차단 요청을 외부 차트 라이브러리 없이 경량 막대 그래프로 표시합니다.
- `safeshield statistics` RPC를 60초 간격으로 별도 polling하고 브라우저 탭이 숨겨져 있을 때는 기존 resource hook 정책에 따라 polling을 중지합니다.
- SafeShield 통계 RPC 읽기 ACL과 UI/RPC 연결 계약 테스트를 추가합니다.

### 변경

- 통계 collector lifecycle 수정이 포함된 SafeShield `0.3.14-r2` 이상을 최소 의존성으로 요구합니다.
- APK dependency 문법에 맞게 `EXTRA_DEPENDS`의 버전 조건에서 연산자 뒤 공백을 제거합니다.

## [0.2.4-r2] - 2026-08-30

빌드 오류를 수정하였습니다.

## [0.2.4-r1] - 2026-08-28

safeshield의 성능 개선 버전인 0.3.13 버전을 기본 버전으로 설정하였습니다.

### 성능

- safeshield의 최소 버전을 0.3.13로 올렸습니다.

## [0.2.3-r2] - 2026-08-28

설치된 SmartSafeHub가 여러 릴리즈를 건너뛰어 업데이트될 때 그 사이의 릴리즈 노트를 함께 확인할 수 있도록 누적 릴리즈 노트 표시를 추가했습니다.

### 추가

- 저장소의 `releases/luci-app-smartsafehub/index.json`에서 릴리즈 순서를 확인하고 현재 설치 버전 이후부터 최신 버전까지 필요한 릴리즈 노트만 내려받습니다.
- 여러 릴리즈를 건너뛰는 경우 업데이트 화면에서 최신 릴리즈부터 순서대로 버전, 배포일, 요약과 상세 변경 사항을 함께 표시합니다.
- 홈 업데이트 배너는 실제 최신 업데이트 버전과 일치하는 릴리즈 노트 요약을 우선 표시합니다.

### 안전성

- 릴리즈 index와 개별 릴리즈 노트는 계속 화면 표시용 보조 정보로만 사용하며 APK 업데이트 판단과 설치에는 영향을 주지 않습니다.
- index를 가져오지 못하면 최신 버전의 릴리즈 노트 하나만 시도하고, 일부 중간 릴리즈 노트 다운로드가 실패하면 가져온 노트는 표시하면서 불완전 상태를 함께 전달합니다.
- 장치에서는 한 번에 최대 32개 릴리즈와 최대 1 MiB bundle만 캐시하여 비정상적인 메타데이터가 과도한 자원을 사용하지 않도록 제한합니다.
- safeshield의 최소 버전을 0.3.11로 올렸습니다.

### 테스트

- mock release index를 기준으로 `0.2.1-r1`에서 최신 버전으로 업데이트할 때 중간 릴리즈 노트를 모두 선택하는지 검증합니다.
- 릴리즈 메타데이터 전체 다운로드 실패가 업데이트 확인과 설치를 막지 않는 기존 fail-open 계약을 유지합니다.

## [0.2.3-r1] - 2026-08-28

SmartSafeHub 업데이트 화면에서 새 버전의 릴리즈 노트를 함께 확인할 수 있도록 저장소 릴리즈 메타데이터 연동을 추가했습니다.

### 추가

- `packages.adb`에서 `luci-app-smartsafehub` 새 버전을 확인한 뒤 같은 release channel의 `releases/luci-app-smartsafehub/<version>.json`을 표시용 메타데이터로 가져옵니다.
- 릴리즈 노트는 `/tmp/smartsafehub-release-note.json`에 atomic cache하며 업데이트 버전과 일치하는 JSON만 rpcd가 반환합니다.
- 업데이트 화면에 릴리즈 요약, 배포일과 섹션별 변경 사항을 표시하고 홈 업데이트 배너에도 요약을 노출합니다.
- SmartSafeHub가 직접 릴리즈 메타데이터를 내려받으므로 `uclient-fetch`를 runtime dependency로 추가했습니다.

### 안전성

- 릴리즈 노트 JSON은 화면 표시용 보조 정보이며 업데이트 가능 여부와 설치 대상은 계속 APK 저장소 메타데이터를 기준으로 결정합니다.
- 릴리즈 노트 다운로드나 JSON 파싱이 실패해도 업데이트 확인과 `apk add --upgrade luci-app-smartsafehub` 설치 흐름은 계속 동작합니다.
- rpcd는 schema, package, version을 검증하고 문자열·섹션·항목 길이를 제한한 뒤 프런트엔드에 전달합니다.
- updater는 등록된 `repo.smartsafehub.com/<channel>/packages/.../smartsafehub/packages.adb` URL에서 channel base를 유도하므로 stable과 beta를 별도 설정하지 않습니다.

### 테스트

- mock `uclient-fetch`를 추가해 저장소 URL에서 릴리즈 노트 URL을 올바르게 유도하는지 검증합니다.
- 릴리즈 노트 다운로드 실패가 업데이트 확인 실패로 전파되지 않는 fail-open 동작을 검증합니다.
- 설치 완료 후 이전 릴리즈 노트 cache가 제거되는지 검증합니다.

## [0.2.2-r1] - 2026-08-28

GitHub Actions CI에서 SmartSafeHub 패키지 계약과 배포 산출물 회귀를 더 일찍 감지하도록 자동 검증 범위를 확장했습니다.

### 추가

- `tests/test-package-contract.sh`를 추가해 실행 권한, `PKG_VERSION`과 frontend package 버전 동기화, SafeShield dependency 형식, `/etc/config/smartsafehub` conffile 선언을 검증합니다.
- `tests/test-rpc-contract.sh`를 추가해 updater RPC 등록과 ACL 권한, 단일 `luci-app-smartsafehub` 업데이트 대상, 전체 시스템 `apk upgrade` 금지 계약을 검증합니다.
- `tests/test-ucode-imports.sh`를 추가해 분리된 rpcd ucode 모듈의 상대 import 대상이 실제 파일로 존재하는지 검증합니다.
- frontend production build 후 커밋된 `app.js`와 `app.css`가 실제 소스 빌드 결과와 일치하는지 확인하는 CI 검사를 추가했습니다.
- updater init script를 포함한 shell syntax 검사와 JSON 구문 검사를 보강했습니다.

### CI

- CI에서 `chmod`로 실행 권한을 보정하지 않고 저장소의 executable bit 자체를 검증합니다.
- `npm run build`가 이미 TypeScript typecheck를 포함하므로 중복된 별도 typecheck step을 제거했습니다.
- Vite production output에 `app.js`와 `app.css`가 존재하고 배포용 `index.html`이 생성되지 않는 계약을 검증합니다.

## [0.2.1-r1] - 2026-08-28

`luci-app-smartsafehub` 업데이트를 감지하고, 사용자가 선택한 경우 공유기에서 예약 자동 설치할 수 있는 SmartSafeHub 업데이트 관리 기능을 추가했습니다.

### 추가

- `repo.smartsafehub.com`이 등록된 APK 저장소를 갱신하고 `luci-app-smartsafehub`의 업데이트를 확인하는 updater를 추가했습니다.
- 업데이트 감지·설치 대상은 `luci-app-smartsafehub` 하나이며 `safeshield`는 `EXTRA_DEPENDS:=safeshield (>= 0.3.10)` 버전 제약을 통해 함께 관리합니다.
- 홈 화면 업데이트 알림, 데스크톱·모바일 업데이트 메뉴 badge, SmartSafeHub 현재/신규 버전 표시를 추가했습니다.
- 수동 업데이트 확인과 명시적 확인이 필요한 수동 설치 기능을 추가했습니다.
- 자동 확인 주기와 자동 설치 여부·시각을 `/etc/config/smartsafehub`에 저장하고 `smartsafehub-updater` procd 서비스가 브라우저와 독립적으로 실행하도록 구성했습니다.
- 업데이트 상태는 `/tmp/smartsafehub-updates.state`에 atomic write하여 rpcd가 네트워크 작업 없이 즉시 조회합니다.
- `updates_status`, `updates_check`, `updates_install`, `updates_settings_update` rpcd API와 ACL을 추가했습니다.
- mock `apk`/`uci`를 사용하는 `tests/test-updater.sh` 회귀 테스트를 추가했습니다.
- Github Actions CI를 추가하였습니다.

### 안전성

- 전체 시스템 `apk upgrade`는 실행하지 않으며, 업데이트가 확인된 경우에만 `apk add --upgrade luci-app-smartsafehub`를 실행합니다. 설치된 `safeshield`가 최소 `0.3.10` 조건을 만족하지 않으면 APK dependency resolver가 함께 갱신합니다.
- 패키지 저장소 작업은 rpcd 프로세스에서 직접 수행하지 않고 별도 updater 프로세스에서 실행해 LuCI API 이벤트 루프 차단을 방지합니다.
- updater는 PID 기반 잠금으로 수동 확인, 수동 설치와 예약 작업의 동시 실행을 방지합니다.
- 자동 설치는 기본적으로 꺼져 있으며 기본 예약 시각은 `03:00`, 자동 확인 기본 주기는 6시간입니다.
- OpenWrt 펌웨어 업그레이드는 기존 LuCI 펌웨어 관리 화면에 계속 위임합니다.

## [0.2.0-r1] - 2026-08-21

SmartSafeHub 전용 사용자 화면과 rpcd 백엔드를 처음 정식 배포하는 릴리스입니다. `0.2.0` 개발 과정에서 사용한 중간 package revision은 정식 배포 기준점인 `r1`으로 squash했습니다.

### 추가

- Preact, TypeScript, Vite와 Tailwind CSS 기반의 SmartSafeHub 전용 LuCI 사용자 화면을 추가했습니다.
- 홈, Wi-Fi, 연결된 기기, SafeShield, 사용자 규칙, 업데이트 및 시스템 화면을 추가했습니다.
- 데스크톱 내비게이션과 모바일 햄버거 메뉴, 최소 44px 터치 영역, iPhone 안전 영역을 지원합니다.
- `/cgi-bin/luci/smartsafehub` 공개 Preact shell과 `/cgi-bin/luci/smartsafehub/session` 보호 세션 endpoint를 추가했습니다.
- LuCI가 비밀번호 검증과 cookie session 발급을 담당하고, Preact는 같은 URL에서 로그인 화면과 인증된 제품 화면을 전환합니다.
- 장치 모델, OpenWrt 버전, 커널, 부팅 시각, 부하, 메모리와 WAN 상태를 표시하는 대시보드를 추가했습니다.
- 관리 대상 기본 LAN AP의 SSID, 보안 방식, 비밀번호와 사용 여부를 변경하는 Wi-Fi 관리 기능을 추가했습니다.
- DHCP lease, ARP, `network.wireless`와 hostapd 정보를 결합하는 연결 기기 조회 기능을 추가했습니다.
- SafeShield 사용 여부, 상태, 차단 목록 수동 갱신, 아티팩트와 차단 통계를 표시합니다.
- SafeShield 라이선스 키 등록·변경·제거를 지원하고, 사용자가 명시적으로 요청한 경우에만 `safeshield.license_get`으로 현재 키를 불러옵니다.
- 사용자 허용·차단 도메인 규칙을 조회·추가·삭제하고 SafeShield 엔진의 local apply 완료 상태를 확인합니다.
- 장치, Wi-Fi와 SafeShield 상태를 결합한 JSON 진단 정보 다운로드를 추가했습니다.
- 명시적인 확인 절차가 포함된 공유기 재부팅과 기존 LuCI의 펌웨어 관리, 고급 설정, 시스템 로그 진입점을 추가했습니다.

### 아키텍처

- SmartSafeHub 제품 화면을 Shadow DOM에 마운트해 LuCI 테마와 제품 스타일의 충돌을 줄였습니다.
- `smartsafehub.uc`는 RPC 등록만 담당하고 `core`, `devices`, `system`, `wifi`, `wifi-management` ucode 모듈로 기능을 분리했습니다.
- 공통 프런트엔드 API 계층과 hook 계층을 두고 페이지가 직접 JSON-RPC를 호출하지 않도록 구성했습니다.
- SmartSafeHub는 SafeShield의 UCI, 규칙 파일과 init script를 직접 다루지 않고 공식 `safeshield` ubus API를 직접 사용합니다.
- `safeshield.config_update`는 SmartSafeHub에서 사용하지 않으며 ACL에도 부여하지 않습니다.
- 평문 라이선스 키를 반환하는 `safeshield.license_get`은 일반 상태 polling과 분리하고 민감 권한으로 취급해 write ACL에 포함했습니다.
- 사용자 규칙의 저장, 직렬화, debounce, cached-artifact merge와 dnsmasq 적용은 SafeShield 엔진이 authoritative source로 담당합니다.
- 시스템 상태 수집은 rpcd 이벤트 루프를 막지 않도록 deferred ubus 호출과 `request.reply()` 흐름을 사용합니다.
- 별도 프런트엔드 build ID 없이 패키지 버전 `0.2.0-r1`을 JavaScript와 CSS 캐시 무효화 키로 사용합니다.

### 성능 및 안정성

- 동일 리소스의 중복 요청을 single-flight 방식으로 합치고 완료 기반 `setTimeout()` 폴링으로 요청 중첩을 방지합니다.
- 브라우저 탭이 숨겨진 동안 폴링을 중단하고 다시 표시될 때 즉시 갱신합니다.
- 모든 프런트엔드 RPC에 기본 20초 타임아웃과 응답 형식 검증을 적용하고 Wi-Fi 변경에는 35초 제한을 사용합니다.
- Wi-Fi 변경 작업은 잠금 파일로 직렬화하고 적용 실패 시 이전 UCI 설정으로 롤백합니다.
- 연결 기기 조회는 `network.wireless`에 station 정보가 있을 때 불필요한 hostapd 조회를 생략합니다.
- 진단 생성은 이미 로드된 시스템 상태를 재사용하고 Wi-Fi와 SafeShield 상태를 병렬 조회하며 부분 실패를 허용합니다.
- SafeShield 규칙 변경 후 `last_local_apply` / `last_local_apply_failure`를 확인해 실제 DNS 적용 결과를 구분합니다.
- 라이선스 키는 기본 상태·진단 흐름에 평문으로 포함하지 않고 사용자의 명시적 조회에서만 가져옵니다.

### 수정

- SafeShield가 실행 중인데 화면에 대기 상태로 표시되던 상태 매핑을 수정했습니다.
- 시스템 실행 시간을 부팅 시각으로 잘못 표시하던 문제를 수정했습니다.
- Wi-Fi 변경 시 기존 WPA2/WPA3 비밀번호를 재사용하는 경우에도 형식을 검증하도록 수정했습니다.
- Wi-Fi 적용 실패 시 이전 설정 복원과 reload 재시도를 수행하도록 보강했습니다.
- 시스템 진단의 복합 RPC 오류를 제거하고 프런트엔드에서 기존 API 응답을 안전하게 결합하도록 변경했습니다.
- 공개 SmartSafeHub route에서 stock LuCI 로그인이나 `403 Forbidden`이 제품 로그인 UI보다 먼저 노출되는 문제를 해결했습니다.
- 로그인 성공 후 페이지를 이동하지 않고 같은 SmartSafeHub URL에서 인증된 Preact 애플리케이션으로 전환하도록 정리했습니다.
- 프런트엔드와 ucode 모듈의 TypeScript/ucode 컴파일 오류와 누락된 import를 수정했습니다.

### 제거 및 정리

- SmartSafeHub 내부의 SafeShield UCI/init script/local rule 직접 제어 코드와 obsolete SafeShield proxy RPC를 제거했습니다.
- 사용하지 않는 `system_diagnostics` RPC, ACL 권한과 진단 전용 백엔드 코드를 제거했습니다.
- 사용하지 않는 `safeshield.config_update` 프런트엔드 코드와 LuCI write 권한을 제거했습니다.
- 기존 LuCI view loader와 중복된 로그인/session bootstrap 코드를 제거했습니다.
- package-time `Build/Prepare` 문자열·파일 계약 검사와 중복 source/dist/rpcd 검사 스크립트를 제거했습니다.
- 프런트엔드 빌드는 `tsc --noEmit`과 Vite 빌드로 단순화했습니다.
- Vite production entry를 `frontend/src/main.tsx`로 직접 지정하고, 사용하지 않는 배포용 `root/www/luci-static/smartsafehub/index.html` 생성을 제거했습니다. `frontend/index.html`은 개발 서버용 shell로만 유지합니다.

### 검증

- 프런트엔드는 Node.js 24 이상에서 `npm run typecheck`와 `npm run build`로 검증합니다.
- OpenWrt buildroot에서 패키지 clean/compile을 수행합니다.
- 실제 장치에서는 `ucode -c`, rpcd 재시작, `ubus -v list smartsafehub`와 주요 RPC 호출로 최종 확인합니다.
