# SafeShield statistics low-resource test guide

SafeShield 통계 수집과 SmartSafeHub 통계 UI가 저사양 OpenWrt 장치에서 DNS 처리 성능을 의미 있게 떨어뜨리지 않는지 확인하기 위한 테스트 절차입니다.

## 1. 사전 확인

테스트 장치는 가능하면 지원 장비 중 사양이 가장 낮은 모델을 사용합니다. 동일한 펌웨어, 차단 목록과 클라이언트 조건에서 통계 OFF/ON을 비교합니다.

```sh
apk info safeshield
apk info luci-app-smartsafehub
/etc/init.d/safeshield status
/etc/init.d/safeshield statistics
```

SmartSafeHub는 SafeShield `0.3.15-r1` 이상을 요구합니다.

통계가 활성화된 상태에서는 collector가 한 세트만 있어야 합니다.

```sh
ps w | grep -E '[s]afeshield-statsd|[l]ogread -f'
```

정상 예시는 `safeshield-statsd` 하나와 그 자식 `logread -f -l 0` 하나입니다.

## 2. UI 기능 확인

SmartSafeHub의 `SafeShield` 화면에서 다음 항목을 확인합니다.

- 전체 DNS 요청
- 차단 요청
- 차단율
- 현재 시간 차단 수
- 최근 24시간 시간대별 차단 막대
- 수집 시작 시각과 보존 시간
- 기기별 DNS 요청, 차단 수, 차단율, IP/MAC 및 식별 상태

DNS 요청을 발생시킨 뒤 최대 한 번의 통계 snapshot/polling 주기인 약 60초 이내에 값이 갱신되는지 확인합니다.

브라우저 개발자 도구의 Network 탭에서는 SafeShield 화면을 열어 둔 동안 `/admin/ubus` 요청이 약 60초 간격으로 발생하는지 확인합니다. 다른 메뉴로 이동하거나 브라우저 탭을 숨긴 상태에서는 통계 polling이 계속 발생하지 않아야 합니다.

## 3. 카운터 안정성 확인

같은 부팅 세션에서는 `totals.queries`와 `totals.blocked`가 감소하면 안 됩니다.

```sh
for i in 1 2 3 4 5; do
  date
  /etc/init.d/safeshield statistics
  sleep 65
done
```

확인 항목:

- `started_at`이 collector 재시작 없이 유지됨
- `queries`가 증가하거나 동일함
- `blocked`가 증가하거나 동일함
- hourly 합계가 totals와 일관됨
- 시간 경계가 바뀌면 새로운 hourly bucket이 생성됨

## 4. 통계 OFF baseline

먼저 통계 수집을 끄고 baseline을 측정합니다.

```sh
uci set safeshield.config.statistics_enabled='0'
uci commit safeshield
/etc/init.d/safeshield restart
```

확인:

```sh
ps w | grep -E '[s]afeshield-statsd|[l]ogread -f'
ubus call system info
```

통계 collector와 통계용 `logread` 프로세스가 없어야 합니다.

LAN의 별도 PC에서 공유기를 DNS 서버로 지정해 동일한 DNS 부하를 발생시킵니다. 부하 생성 도구는 공유기 자체가 아니라 외부 PC에서 실행해야 테스트 도구의 CPU 사용량이 공유기 측정에 섞이지 않습니다.

`dnsperf`를 사용할 수 있다면 예를 들어 다음 단계로 측정합니다.

```sh
dnsperf -s <ROUTER_LAN_IP> -d queries.txt -l 300 -Q 20
dnsperf -s <ROUTER_LAN_IP> -d queries.txt -l 300 -Q 50
```

장비가 안정적이면 100 qps도 추가할 수 있습니다.

각 단계에서 기록할 값:

- dnsperf 평균 응답시간
- 질의 손실/timeout 수
- `ubus call system info`의 load와 memory
- 웹 UI 응답성

## 5. 통계 ON 비교

같은 조건에서 통계를 다시 켭니다.

```sh
uci set safeshield.config.statistics_enabled='1'
uci commit safeshield
/etc/init.d/safeshield restart
```

collector가 한 세트인지 확인합니다.

```sh
ps w | grep -E '[s]afeshield-statsd|[l]ogread -f'
```

OFF 테스트와 같은 query 파일, 같은 qps, 같은 시간으로 반복합니다.

```sh
dnsperf -s <ROUTER_LAN_IP> -d queries.txt -l 300 -Q 20
dnsperf -s <ROUTER_LAN_IP> -d queries.txt -l 300 -Q 50
```

동시에 SmartSafeHub SafeShield 화면을 열어 실제 UI polling이 존재하는 상태에서도 한 번 측정합니다.

## 6. 차단 hit 검증

차단 목록에 실제 존재하는 도메인을 사용합니다. 없는 도메인을 사용하면 NXDOMAIN과 SafeShield 차단을 구분하기 어렵습니다.

라우터에서 차단 목록 일부를 확인할 수 있습니다.

```sh
sed -n 's#^address=/\([^/]*\)/#$#\1#p' /tmp/dnsmasq.d/safeshield.blocklist | head
```

선택한 도메인을 LAN 클라이언트에서 반복 조회한 뒤 `blocked`가 증가하는지 확인합니다.

```sh
nslookup <BLOCKED_DOMAIN> <ROUTER_LAN_IP>
```

정상 도메인도 함께 조회해 `queries`는 증가하지만 모든 요청이 `blocked`로 계산되지 않는지 확인합니다.

## 7. UI/RPC 비용 확인

라우터에서 통계 RPC 자체의 응답시간도 확인합니다.

```sh
time ubus call safeshield statistics >/dev/null
```

10회 정도 반복해 눈에 띄는 지연이 없는지 확인합니다. 통계 JSON은 최대 168개의 hourly bucket만 포함하므로 응답 크기가 지속적으로 무제한 증가해서는 안 됩니다.

```sh
ubus call safeshield statistics | wc -c
```

## 8. 장시간 안정성

최소 몇 시간, 가능하면 24시간 이상 일반적으로 사용한 뒤 다음을 다시 확인합니다.

```sh
ps w | grep -E '[s]afeshield-statsd|[l]ogread -f'
/etc/init.d/safeshield statistics
ubus call system info
```

다음을 실패로 봅니다.

- orphan `logread`가 추가로 생김
- totals 값이 감소함
- hourly bucket이 retention 설정 이상으로 계속 증가함
- DNS timeout 또는 packet loss가 통계 ON에서만 반복적으로 발생함
- collector 또는 dnsmasq의 메모리 사용이 시간에 따라 계속 증가함

## 9. 권장 판정 기준

다음 값은 제품 검증을 위한 초기 권장 기준이며 실제 장비 측정 후 조정할 수 있습니다.

| 항목 | 권장 기준 |
| --- | --- |
| DNS packet loss | OFF/ON 모두 0% 목표 |
| 평균 DNS latency 증가 | 통계 ON에서 5% 이내 또는 절대 1 ms 이내 목표 |
| statsd 메모리 | 수 MB 이하, 시간에 따른 지속 증가 없음 |
| idle CPU 영향 | 지속적인 CPU 점유가 관찰되지 않을 것 |
| 통계 RPC | LAN에서 체감 지연 없이 응답할 것 |
| collector process | statsd 1개 + logread 1개 |
| totals | 같은 부팅 세션에서 단조 증가 |
| UI polling | SafeShield 화면에서만 약 60초 간격 |

특히 GL-MT300N-V2에서 이 기준을 만족하면 상위 장비에서도 기본 활성화하기에 충분한 근거가 됩니다.
