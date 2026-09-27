export type AppRoute =
  | 'home'
  | 'activity'
  | 'lan'
  | 'wifi'
  | 'iptv'
  | 'devices'
  | 'safeshield'
  | 'rules'
  | 'system'
  | 'settings';

export interface RouteDefinition {
  route: AppRoute;
  hash: `#${string}`;
  label: string;
  title: string;
  description: string;
}

export const ROUTES: readonly RouteDefinition[] = [
  {
    route: 'home',
    hash: '#home',
    label: '대시보드',
    title: '대시보드',
    description: '네트워크, 장치와 시스템 상태를 한눈에 확인합니다.',
  },
  {
    route: 'activity',
    hash: '#activity',
    label: '최근 활동',
    title: '최근 활동',
    description: '현재 부팅 이후 인터넷, 보호, 업데이트와 진단 상태 변화를 확인합니다.',
  },
  {
    route: 'lan',
    hash: '#lan',
    label: 'LAN',
    title: 'LAN',
    description: '내부 네트워크 주소, DHCP 범위와 상위 네트워크 충돌을 관리합니다.',
  },
  {
    route: 'wifi',
    hash: '#wifi',
    label: 'Wi-Fi',
    title: 'Wi-Fi',
    description: '기본 무선 네트워크의 이름, 보안과 사용 상태를 관리합니다.',
  },
  {
    route: 'iptv',
    hash: '#iptv',
    label: 'IPTV',
    title: 'IPTV',
    description: 'SK Broadband와 LG U+ 멀티캐스트 IPTV를 설정합니다.',
  },
  {
    route: 'devices',
    hash: '#devices',
    label: '연결된 기기',
    title: '연결된 기기',
    description: '네트워크에서 확인된 기기와 연결 방식을 살펴봅니다.',
  },
  {
    route: 'safeshield',
    hash: '#safeshield',
    label: 'SafeShield',
    title: 'SafeShield',
    description: 'DNS 보호 상태를 확인하고 차단 목록을 관리합니다.',
  },
  {
    route: 'rules',
    hash: '#rules',
    label: '사용자 규칙',
    title: '사용자 규칙',
    description: '직접 허용하거나 차단할 도메인을 관리합니다.',
  },
  {
    route: 'system',
    hash: '#system',
    label: '업데이트',
    title: '업데이트',
    description: '기기의 펌웨어와 관리 소프트웨어 업데이트를 관리합니다.',
  },
  {
    route: 'settings',
    hash: '#settings',
    label: '설정',
    title: '설정',
    description: '시스템 상태와 시간대를 확인하고 장치 관리 및 진단 기능을 설정합니다.',
  },
] as const;

export const ROUTE_BY_NAME = Object.fromEntries(
  ROUTES.map((definition) => [definition.route, definition]),
) as Record<AppRoute, RouteDefinition>;
