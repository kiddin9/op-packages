'use strict';
'require rpc';
'require poll';
'require view';

var callBoard = rpc.declare({ object: 'system', method: 'board', expect: { '': {} } });
var callInfo = rpc.declare({ object: 'system', method: 'info', expect: { '': {} } });
var callInterfaces = rpc.declare({ object: 'network.interface', method: 'dump', expect: { '': {} } });
var callServices = rpc.declare({ object: 'service', method: 'list', params: [ 'name' ], expect: { '': {} } });

var callDevices = rpc.declare({ object: 'network.device', method: 'status', expect: { '': {} } });

var callWifiDevices = rpc.declare({ object: 'iwinfo', method: 'devices', expect: { '': {} } });
var callWifiInfo = rpc.declare({ object: 'iwinfo', method: 'info', params: ['device'], expect: { '': {} } });
var callWifiStations = rpc.declare({ object: 'iwinfo', method: 'assoclist', params: ['device'], expect: { '': {} } });
var callClients = rpc.declare({ object: 'rmm.dashboard', method: 'clients', expect: { '': {} } });
var callVendors = rpc.declare({object:'rmm.dashboard',method:'vendors',params:['macs'],expect:{'':{}}});
var callSetName = rpc.declare({object:'rmm.dashboard',method:'set_name',params:['mac','name','previous'],expect:{'':{}}});
var callCanName = rpc.declare({object:'session',method:'access',params:['scope','object','function'],expect:{access:false}});
var callDNS = rpc.declare({object:'network.rrdns',method:'lookup',params:['addrs','timeout','limit'],expect:{'':{}}});
var callLeases = rpc.declare({ object: 'luci-rpc', method: 'getDHCPLeases', expect: { '': {} } });

var callConfig = rpc.declare({ object: 'uci', method: 'get', params: [ 'config', 'section' ], expect: { values: {} } });

var russian = {
	"Vendor": "Производитель",
	"Locally administered MAC": "Локально назначенный MAC",
	"Unknown vendor": "Производитель неизвестен",
	"Local vendor database unavailable": "Локальная база производителей недоступна",
	"Client observation history": "История наблюдений клиентов",
	"History covers this open page; a record does not prove an active connection.": "История собирается, пока открыта страница. Наличие записи не подтверждает подключение.",
	"First observed": "Впервые замечен",
	"Last observed": "Последнее наблюдение",
	"First observation": "Первое наблюдение",
	"Observed again": "Замечен снова",
	"IP addresses changed": "Изменились IP-адреса",
	"Connection path changed": "Изменился путь подключения",
	"No longer reported": "Больше не отображается в источниках",
	"Observation history": "История наблюдений",
	"No observations yet": "Наблюдений пока нет",
	"Client traffic": "Трафик клиента",
	"Received / sent in accounting period": "Принято / отправлено за период учёта",
	"Accounting average RX / TX": "Средняя скорость учёта RX / TX",
	"nlbwmon not installed": "nlbwmon не установлен",
	"nlbwmon is not running": "nlbwmon не запущен",
	"Traffic accounting unavailable": "Учёт трафика недоступен",
	"No traffic record": "Нет записи о трафике",
	"Accounting may omit offloaded and bridged traffic.": "Учёт может не включать трафик аппаратного ускорения и мостов.",
	"More clients": "Все клиенты",

	"Edit display name": "Изменить имя",
	"Display name": "Имя устройства",
	"Manual name": "Ручное имя",
	"Reverse DNS": "Обратный DNS",
	"Name follows this MAC; DHCP and network settings are unchanged.": "Имя привязано к MAC. Настройки DHCP и сети не меняются.",
	"Save name": "Сохранить имя",
	"Use automatic name": "Использовать автоматическое имя",
	"Saving name": "Сохранение имени…",
	"Name saved": "Имя сохранено",
	"Unable to save name": "Не удалось сохранить имя",
	"Name storage unavailable": "Хранилище имён недоступно",
	"Checking permission": "Проверка доступа…",
	"Read-only access": "Доступ только для чтения",
	"Invalid display name": "Недопустимое имя устройства",
	"DNS names": "Имена из DNS",
	"Resolve unnamed clients through the router DNS.": "Определять имена неизвестных клиентов через DNS роутера.",
	"DNS disabled": "DNS выключен",
	"Looking up DNS names": "Поиск имён в DNS…",
	"DNS names unavailable": "Имена из DNS недоступны",
	"DNS cache updated": "Кэш DNS обновлён",
	"Name changed elsewhere; reopen the editor.": "Имя изменено в другой сессии. Откройте редактор заново.",

	"+%s IP": "+%s IP",
	"Name source": "Источник имени",
	"Matched by": "Сопоставлено по",
	"IPv6 neighbor record": "IPv6-запись NDP",

	"No FDB observations": "Наблюдений FDB нет",
	"FDB observations": "По данным FDB",
    "Ethernet path": "Через Ethernet",
    "Neighbor records": "ARP/NDP-записи",
    "Via %s": "Через %s",
    "Port ambiguous": "Несколько портов",
    "Recently reachable": "Недавно доступен",
    "Cached observation": "Запись в кэше",
    "Static neighbor": "Статический сосед",
    "Neighbor unreachable": "Сосед недоступен",
    "Neighbor state": "Состояние ARP/NDP",
    "Bridge / VLAN": "Мост / VLAN",
    "FDB path; direct cable connection unconfirmed": "Путь по FDB; прямое подключение кабелем не подтверждено",
    "Client inventory truncated": "Список клиентов ограничен",
    "Port link down": "Линк порта отключён",

	"Connection unconfirmed": "Подключение не подтверждено",
	"Customize dashboard": "Настроить обзор",
	"Visible blocks and order": "Блоки и порядок",
	"Compact mode": "Компактный режим",
	"Reset layout": "Сбросить вид",
	"Move up": "Выше",
	"Move down": "Ниже",
	"Preferences unavailable; changes last until this page closes.": "Хранилище недоступно; изменения действуют до закрытия страницы.",
	"Clients": "Клиенты",
	"Known DHCP clients": "Известные DHCP-клиенты",
	"DHCP lease; connection unconfirmed": "DHCP-аренда; подключение не подтверждено",
	"Wi-Fi association": "Wi-Fi-подключение",
	"Connection evidence": "Источник состояния",
	"DHCP clients may use wired or wireless links; a lease does not prove an active connection.": "DHCP-клиенты могут быть проводными или беспроводными; аренда не подтверждает активное подключение.",
	"History period": "Период истории",
	"Last 1 minute": "Последняя минута",
	"Last 15 minutes": "Последние 15 минут",
	"Counter reset": "Сброс счётчика",
	"Data gap": "Пропуск данных",
	"Last observation": "Последнее наблюдение",
	"More interfaces": "Другие интерфейсы",
	"Wi-Fi data unavailable": "Данные Wi-Fi недоступны",
	"All clients": "Все клиенты",
	"Connection type": "Тип записи",
	"DHCP records": "DHCP-записи",
	"Shown / total clients": "Показано / всего клиентов",

	"Close": "Закрыть",
	"Details": "Подробности",
	"Sort clients": "Сортировка",
	"By name": "По имени",
	"Strongest signal": "Сначала сильный сигнал",
	"Fastest link": "Сначала быстрое соединение",
	"Group clients": "Группировка",
	"No grouping": "Без группировки",
	"By SSID": "По SSID",
	"Received": "Принято",
	"Sent": "Отправлено",
	"Inspect samples with arrow keys": "Выбирайте измерения стрелками",
	"Data is not reported": "Данные не получены",
	"Attention required": "Требует внимания",
	"No reported issues": "По полученным данным проблем нет",
	"Memory usage ≥ 90%": "Занято памяти ≥ 90%",
	"Object is no longer reported": "Объект больше не указан в данных",
	"Refresh issues": "Проблемы обновления",
	"Resource summary": "Состояние ресурсов",

	"Gateway": "Шлюз", "Local interfaces": "Локальные интерфейсы",
	"Reported network path": "Связи по данным роутера",
	"Logical interfaces and Wi-Fi associations": "Логические интерфейсы и подключения Wi-Fi",

	"Router overview": "Обзор роутера", "Wi-Fi clients": "Клиенты Wi-Fi", "Memory": "Память",
	"WAN traffic": "Трафик WAN", "Network interfaces": "Сетевые интерфейсы",
	"Router details": "Детали роутера", "Reported radios": "Доступные радиомодули",
	"No WAN device reported": "Устройство WAN не указано", "Summary": "Сводка",

	"Network relationships": "Связи сети",
	"Local router": "Локальный роутер",
	"Default route gateway": "Шлюз маршрута по умолчанию",
	"No default gateway reported": "Шлюз по умолчанию не указан",
	"Operating mode": "Режим работы",
	"Access point": "Точка доступа",
	"Station mode": "Режим станции",
	"Open station details": "Открыть детали станции",
	"Only reported routes and Wi-Fi associations are shown; physical cabling and Internet reachability are not inferred.": "Показаны указанные маршруты и Wi-Fi-подключения; физическая коммутация и доступ в Интернет не определяются.",
	"Search clients": "Поиск клиентов",
	"All bands": "Все диапазоны",
	"All signals": "Любой сигнал",
	"Signal ≥ -67 dBm": "Сигнал ≥ -67 dBm",
	"Signal -68…-75 dBm": "Сигнал -68…-75 dBm",
	"Signal < -75 dBm": "Сигнал < -75 dBm",
	"Unknown signal": "Сигнал неизвестен",
	"Clear filters": "Сбросить фильтры",
	"No matching stations": "Нет станций по выбранным фильтрам",
	"Station details": "Детали станции",
	"Signal history": "История сигнала",
	"Station traffic": "Трафик станции",
	"Station noise": "Шум станции",
	"Shown / total stations": "Показано / всего станций",
	"Search by name, MAC, IP or SSID": "Поиск по имени, MAC, IP или SSID",
	"Signal bands are filters, not a connection quality score.": "Диапазоны сигнала служат фильтром, а не оценкой качества соединения.",
	"Wireless": "Беспроводная сеть",
	"Associated stations": "Подключённые станции",
	"Radio": "Радиомодуль",
	"Band": "Диапазон",
	"Channel": "Канал",
	"Channel mode": "Режим канала",
	"TX power": "Мощность TX",
	"Noise": "Шум",
	"Signal": "Сигнал",
	"Link rate RX / TX": "Скорость соединения RX / TX",
	"MAC address": "MAC-адрес",
	"Connected time": "Время подключения",
	"No associated stations": "Нет подключённых станций",
	"No wireless interfaces reported": "Беспроводные интерфейсы не найдены",
	"No local DHCP record": "Нет локальной DHCP-записи",
	"Wireless interfaces visible to iwinfo are shown; disabled radios are not inventoried.": "Показаны интерфейсы, доступные iwinfo; выключенные радиомодули не входят в этот список.",
	"Link rates are negotiated Wi-Fi rates, not measured traffic.": "Скорость Wi-Fi-соединения не равна фактическому трафику.",
	"Invalid station records": "Некорректные записи станций",
	'Traffic history': 'История трафика', 'Memory history': 'История памяти',
	'Last 5 minutes': 'Последние 5 минут', 'Peak': 'Максимум',
	'History starts when this page opens. Gaps indicate unavailable data.': 'История начинается при открытии страницы. Разрывы означают отсутствие данных.',
	'Partial data': 'Часть данных недоступна', 'Loading': 'Загрузка', 'Current': 'Актуально', 'Stale': 'Устаревшие данные',
	'Access denied': 'Нет доступа', 'Last successful update': 'Последнее успешное обновление',
	'Never updated': 'Ещё не обновлялось', 'Retry': 'Повторить', 'Refreshing': 'Обновление',
	'Memory used': 'Занято памяти', 'Network': 'Сеть', 'Device': 'Устройство',
	'Received / sent': 'Принято / отправлено', 'RX / TX rate': 'Скорость RX / TX',
	'Collecting': 'Накопление данных', 'Not installed': 'Не установлен',
	'No interfaces': 'Нет интерфейсов', 'Sources': 'Источники',
	'Traffic counters belong to devices; shared devices are not summed.': 'Счётчики относятся к устройствам; общие устройства не суммируются.',
	'Unavailable': 'Недоступно',
	'No address': 'Нет адреса',
	'Not configured': 'Не настроено',
	'Connected': 'Подключено',
	'Disconnected': 'Отключено',
	'Running': 'Работает',
	'Stopped': 'Остановлен',
	'Disabled': 'Выключен',
	'Router': 'Роутер',
	'Hostname': 'Имя устройства',
	'Model': 'Модель',
	'Firmware': 'Прошивка',
	'Uptime': 'Время работы',
	'System': 'Система',
	'Load (1 / 5 / 15 min)': 'Нагрузка (1 / 5 / 15 мин)',
	'Memory total': 'Всего памяти',
	'Memory available': 'Доступно памяти',
	'WAN connection': 'Подключение WAN',
	'Status': 'Состояние',
	'Interface': 'Интерфейс',
	'IP address': 'IP-адрес',
	'RMM agent': 'Агент RMM',
	'Heartbeat interval': 'Интервал heartbeat',
	'Connectivity check interval': 'Интервал проверки связи',
	'RMM overview': 'Обзор RMM',
	'Updates every 30 seconds': 'Обновление каждые 30 секунд',
	'WAN status shows the interface link state; it does not test Internet reachability.': 'Состояние WAN показывает состояние интерфейса, но не проверяет доступ в Интернет.',
	'SYSTEM / OVERVIEW': 'СИСТЕМА / ОБЗОР',
	'd': 'д',
	'h': 'ч',
	'm': 'мин',
	's': 'с'
};

// LuCI append() stringifies null array entries and treats scalar strings as HTML.
// Keep optional children absent and all telemetry/copy as text nodes.
function element(tag, attrs, children) {
	var safe = (Array.isArray(children) ? children : [children]).filter(function(child) { return child !== null && child !== undefined; });
	return E(tag, attrs || {}, safe);
}

function tr(message) {
	return /^ru(?:-|$)/i.test(document.documentElement.lang) && russian[message] || _(message);
}

function requested(call, valid) {
	return Promise.resolve().then(call).then(function(value) {
		if (!value || typeof value !== 'object' || Array.isArray(value) || valid && !valid(value))
			throw new Error('Invalid response');
		return { value: value, at: Date.now() };
	}).catch(function(error) { return { error: error || new Error('Unavailable') }; });
}

function finite(value) { return typeof value === 'number' && Number.isFinite(value) && value >= 0; }
function failure(error) {
	return tr(error && (error.code === 6 || error.code === 403 || /permission|access denied/i.test(error.message || '')) ? 'Access denied' : 'Unavailable');
}
function clock(at) { return at ? new Date(at).toLocaleTimeString(document.documentElement.lang || undefined) : tr('Never updated'); }
function rate(current, previous, elapsed) {
	if (!finite(current)) return tr('Unavailable');
	return finite(previous) && current >= previous && elapsed > 0 ? formatTraffic((current - previous) / elapsed) + '/s' : tr('Collecting');
}

function formatDuration(seconds) {
	if (typeof seconds !== 'number' || !isFinite(seconds) || seconds < 0)
		return tr('Unavailable');
	var days = Math.floor(seconds / 86400);
	var hours = Math.floor(seconds % 86400 / 3600);
	var minutes = Math.floor(seconds % 3600 / 60);
	return (days ? '%d %s '.format(days, tr('d')) : '') + '%d %s %d %s'.format(hours, tr('h'), minutes, tr('m'));
}

function formatBytes(bytes) {
	if (typeof bytes !== 'number' || !isFinite(bytes) || bytes < 0)
		return tr('Unavailable');
	return _('%s MiB').format((bytes / 1048576).toFixed(1));
}

function formatTraffic(bytes) {
	if (!finite(bytes)) return tr('Unavailable');
	var units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ], index = 0;
	while (bytes >= 1024 && index < units.length - 1) { bytes /= 1024; index++; }
	return bytes.toFixed(index ? 1 : 0) + ' ' + units[index];
}

// Up to fifteen minutes in this view instance only; no router storage or extra timer.
var historyWindow = 900000;
var historyLimit = 181;
function remember(samples, sample, now) {
	var recent = samples.filter(function(point) { return point.at >= now - historyWindow && point.at <= now; });
	var previous = recent[recent.length - 1];
	if (previous && sample.at < previous.at) return recent;
	// Manual Retry may be frequent: retain the latest sample per five-second bucket.
	if (previous && Math.floor(sample.at / 5000) === Math.floor(previous.at / 5000)) recent[recent.length - 1] = sample;
	else recent.push(sample);
	return recent.slice(-historyLimit);
}
function sourceFresh(source, now) { return !source.error && finite(source.at) && source.at <= now && now - source.at <= 65000; }
function byteRate(current, previous, elapsed) {
	return finite(current) && finite(previous) && current >= previous && elapsed > 0 && elapsed <= 65 ? (current - previous) / elapsed : null;
}
function svgElement(tag, attributes, children) {
	var node = document.createElementNS('http://www.w3.org/2000/svg', tag);
	Object.keys(attributes || {}).forEach(function(key) { node.setAttribute(key, attributes[key]); });
	(children || []).forEach(function(child) { node.appendChild(child); });
	return node;
}
function historyChart(title, samples, series, fixedMax, format, now, period) {
	period = period || 300000;
	samples = samples.filter(function(point) { return point.at >= now-period && point.at <= now; });
	var latest = samples[samples.length - 1];
	var peak = Math.max.apply(null, [0].concat(samples.flatMap(function(point) { return series.map(function(entry) { return finite(point[entry.key]) ? point[entry.key] : 0; }); })));
	var max = fixedMax || Math.max(1, peak);
	var hasValues = samples.some(function(point) { return series.some(function(entry) { return finite(point[entry.key]); }); });
	var summary = series.map(function(entry) { return entry.label + ': ' + (latest && finite(latest[entry.key]) ? format(latest[entry.key]) : tr('Unavailable')); }).join(' · ');
	var figure = element('figure', { 'class': 'rmm-dashboard-chart' }, [
		element('figcaption', {}, [element('span', { 'class': 'rmm-dashboard-chart-title' }, title), element('span', {}, tr(period === 60000 ? 'Last 1 minute' : period === 900000 ? 'Last 15 minutes' : 'Last 5 minutes'))]),
		element('p', { 'class': 'rmm-dashboard-chart-summary' }, summary)
	]);
	var svg = svgElement('svg', { viewBox: '0 0 600 140', preserveAspectRatio: 'none', role: 'img', 'aria-label': title + ' · ' + summary + ' · ' + tr('Peak') + ': ' + (hasValues ? format(peak) : tr('Unavailable')) });
	[12, 64, 116].forEach(function(y) { svg.appendChild(svgElement('line', { x1: '8', x2: '592', y1: y, y2: y, 'class': 'rmm-dashboard-chart-grid' })); });
	series.forEach(function(entry) {
		var commands = [], previous = null;
		samples.forEach(function(point) {
			if (!finite(point[entry.key])) { previous = null; return; }
			var x = 8 + Math.max(0, Math.min(1, (point.at - (now - period)) / period)) * 584;
			var y = 116 - Math.min(1, point[entry.key] / max) * 104;
			commands.push((previous && point.at - previous.at <= 65000 ? 'L' : 'M') + x.toFixed(2) + ',' + y.toFixed(2));
			previous = point;
		});
		if (commands.length) svg.appendChild(svgElement('path', { d: commands.join(' '), 'class': 'rmm-dashboard-chart-line rmm-dashboard-chart-' + entry.key, fill: 'none', 'vector-effect': 'non-scaling-stroke' }));
	});
	samples.forEach(function(point) {
		if (!point.reset && series.every(function(entry) { return finite(point[entry.key]); })) return;
		var x=8+Math.max(0,Math.min(1,(point.at-(now-period))/period))*584;
		var marker=svgElement('line',{x1:x,x2:x,y1:12,y2:116,'class':'rmm-dashboard-chart-gap'});
		var titleNode=svgElement('title',{});titleNode.textContent=tr(point.reset ? 'Counter reset' : 'Data gap')+' · '+clock(point.at);marker.appendChild(titleNode);svg.appendChild(marker);
	});
	var readout = element('p',{'class':'rmm-dashboard-chart-readout'},tr('Inspect samples with arrow keys'));
	var cursor = svgElement('line',{y1:12,y2:116,'class':'rmm-dashboard-chart-cursor',visibility:'hidden'});
	svg.appendChild(cursor);
	svg.setAttribute('tabindex','0');
	svg.setAttribute('data-chart-title',title);
	svg.setAttribute('aria-label',svg.getAttribute('aria-label') + ' · ' + tr('Inspect samples with arrow keys'));
	var selected = Math.max(0,samples.length - 1);
	function inspect(index) {
		if (!samples.length) return;
		selected = Math.max(0,Math.min(samples.length - 1,index));
		var point = samples[selected], x = 8 + Math.max(0,Math.min(1,(point.at - (now-period))/period))*584;
		cursor.setAttribute('x1',x);cursor.setAttribute('x2',x);cursor.setAttribute('visibility','visible');
		readout.textContent = clock(point.at) + ' · ' + series.map(function(entry) { return entry.label + ': ' + (finite(point[entry.key]) ? format(point[entry.key]) : tr('Data is not reported')); }).join(' · ');
	}
	svg.addEventListener('pointermove',function(event) {
		var rect=svg.getBoundingClientRect(), target=now-period + Math.max(0,Math.min(1,((event.clientX-rect.left)/rect.width*600-8)/584))*period;
		var closest=0; samples.forEach(function(point,index) { if (Math.abs(point.at-target)<Math.abs(samples[closest].at-target)) closest=index; });inspect(closest);
	});
	svg.addEventListener('pointerdown',function() { svg.focus({preventScroll:true}); });
	svg.addEventListener('keydown',function(event) {
		if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
		event.preventDefault();inspect(event.key==='Home' ? 0 : event.key==='End' ? samples.length-1 : selected+(event.key==='ArrowLeft' ? -1 : 1));
	});
	figure.appendChild(element('div',{'class':'rmm-dashboard-chart-legend'},series.map(function(entry) { return element('span',{'data-series':entry.key},entry.label + (entry.key==='rx' ? ' · '+tr('Received') : entry.key==='tx' ? ' · '+tr('Sent') : '')); })));
	figure.appendChild(svg);
	figure.appendChild(readout);
	figure.appendChild(element('p', { 'class': 'rmm-dashboard-chart-scale' }, [element('span', {}, format(0)), element('span', {}, format(max))]));
	figure.appendChild(element('p', { 'class': 'rmm-dashboard-chart-times' }, [element('span', {}, clock(now - period)), element('span', {}, clock(now))]));
	if (samples.filter(function(point) { return series.some(function(entry) { return finite(point[entry.key]); }); }).length < 2)
		figure.appendChild(element('p', { 'class': 'rmm-dashboard-note' }, tr('Collecting')));
	return figure;
}

// Local Tabler registry; MIT attribution is shipped with this package.
function dashboardIcon(name) {
	return svgElement('svg', {viewBox:'0 0 24 24','class':'rmm-dashboard-icon','aria-hidden':'true',focusable:'false',fill:'none',stroke:'currentColor','stroke-width':2,'stroke-linecap':'round','stroke-linejoin':'round'},[svgElement('use',{href:L.resource('view/status/rmm-dashboard-icons.svg') + '#icon-' + name})]);
}

function item(label, value, state) {
	return element('div', { 'class': 'rmm-dashboard-row' }, [
		element('dt', {}, label),
		element('dd', { 'class': state ? 'rmm-dashboard-value rmm-dashboard-' + state : 'rmm-dashboard-value' }, value)
	]);
}

function reportedText(value) { return typeof value === 'string' && value.length ? value : tr('Unavailable'); }

function firstAddress(iface) {
	var ipv4 = iface && iface['ipv4-address'];
	var ipv6 = iface && iface['ipv6-address'];
	var addresses = Array.isArray(ipv4) && ipv4.length ? ipv4 : ipv6;
	return Array.isArray(addresses) && addresses.length && addresses[0] && typeof addresses[0].address === 'string' ? addresses[0].address : tr('No address');
}

function wifiLoad() {
	return callWifiDevices().then(function(reply) {
		if (!reply || !Array.isArray(reply.devices) || reply.devices.length > 64 || reply.devices.some(function(name) { return typeof name !== 'string' || !/^[A-Za-z0-9_.:-]{1,64}$/.test(name); })) throw new Error('Invalid wireless interfaces');
		return Promise.all(Array.from(new Set(reply.devices)).sort().map(function(device) {
			return Promise.all([requested(function() { return callWifiInfo(device); }, function(info) { return typeof info.phy === 'string' || typeof info.ssid === 'string' || typeof info.mode === 'string'; }),
				requested(function() { return callWifiStations(device); }, function(reply) { return Array.isArray(reply.results); })]).then(function(results) { return {device:device,info:results[0],stations:results[1]}; });
		})).then(function(interfaces) { return {interfaces:interfaces}; });
	});
}
function cachedResult(result, previous) { return result.error ? {value:previous && previous.value,at:previous && previous.at,error:result.error} : result; }
function signalValue(value) {
	if (typeof value !== 'number' || !Number.isInteger(value)) return null;
	if (value > 2147483647 && value <= 4294967295) value -= 4294967296;
	return value < 0 && value >= -127 ? value : null;
}
function signalText(value) {
	var signal = signalValue(value);
	return signal === null ? tr('Unavailable') : signal + ' dBm';
}
function bandName(info) {
	var frequency = info.frequency;
	return finite(frequency) ? frequency >= 2400 && frequency < 2500 ? '2.4 GHz' : frequency >= 4900 && frequency < 5925 ? '5 GHz' : frequency >= 5925 && frequency <= 7125 ? '6 GHz' : frequency >= 57000 && frequency <= 71000 ? '60 GHz' : tr('Unavailable') : tr('Unavailable');
}
function linkRate(value) { return value && finite(value.rate) && value.rate > 0 ? (value.rate / 1000).toFixed(1) + ' Mbit/s' : tr('Unavailable'); }
function resultLine(label, result, parentError) {
	var error = parentError || result.error;
	var stale = result.value && (error || !sourceFresh(result, Date.now()));
	var state = stale ? tr('Stale') + (error ? ' · ' + failure(error) : '') : error ? failure(error) : tr('Current');
	return element('p', { 'class':'rmm-dashboard-source' }, [label + ': ' + state + ' · ' + tr('Last successful update') + ': ', element('time', {datetime:result.at ? new Date(result.at).toISOString() : ''}, clock(result.at))]);
}
function stationList(reply) { return reply && Array.isArray(reply.results) ? reply.results.filter(function(row) { return row && typeof row.mac === 'string' && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/i.test(row.mac); }) : []; }
function clientMac(value) {
	return typeof value === 'string' && /^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$/i.test(value) && !(parseInt(value.slice(0,2),16)&1) && !/^00:00:00:00:00:00$/.test(value) ? value.toUpperCase() : null;
}
// Canonical comparison keys handle compressed IPv6 and DHCP prefix suffixes.
function addressKey(value) {
	if (typeof value !== 'string') return null;
	var parts=value.trim().split('/'), address=parts[0].toLowerCase(), ipv6=address.includes(':');
	if (parts.length>2 || parts.length===2 && (!/^\d+$/.test(parts[1]) || Number(parts[1])>(ipv6?128:32))) return null;
	if (!ipv6) return /^(?:\d{1,3}\.){3}\d{1,3}$/.test(address) && address.split('.').every(function(n) { return Number(n)<=255; }) ? address.split('.').map(Number).join('.') : null;
	if (address.includes('.')) {
		var tail=address.slice(address.lastIndexOf(':')+1), v4=addressKey(tail);
		if (!v4 || v4.includes(':')) return null;
		var octets=v4.split('.').map(Number);
		address=address.slice(0,address.lastIndexOf(':')+1)+((octets[0]<<8)|octets[1]).toString(16)+':'+((octets[2]<<8)|octets[3]).toString(16);
	}
	var halves=address.split('::');
	if (halves.length>2) return null;
	var left=halves[0]?halves[0].split(':'):[], right=halves.length===2 && halves[1]?halves[1].split(':'):[];
	if (!left.concat(right).every(function(n) { return /^[0-9a-f]{1,4}$/.test(n); })) return null;
	var missing=8-left.length-right.length;
	if (halves.length===1 && missing!==0 || halves.length===2 && missing<1) return null;
	return left.concat(Array(halves.length===2?missing:0).fill('0'),right).map(function(n) { return n.padStart(4,'0'); }).join(':');
}
function addClientAddress(host,value) {
	var key=addressKey(value);
	if (key && !host.addresses.some(function(address) { return addressKey(address)===key; })) host.addresses.push(value.trim().split('/')[0]);
}
function clientAddressSummary(addresses, fallback) {
	addresses=addresses || [];
	var primary=addresses.find(function(address) { return !address.includes(':'); }) || addresses.find(function(address) { return !/^fe[89ab]/i.test(address); }) || addresses[0];
	return primary ? primary + (addresses.length>1 ? ' · '+tr('+%s IP').format(addresses.length-1) : '') : tr(fallback);
}
function clientIdentityItems(host) {
	return host.name ? [item(tr('Name source'),tr(host.nameSource)),item(tr('Matched by'),tr(host.matchMethod))] : [];
}
function leaseMap(reply, owners) {
	var hosts = Object.create(null);
	['dhcp_leases','dhcp6_leases'].forEach(function(key) {
		(Array.isArray(reply[key]) ? reply[key] : []).slice(0,1024).forEach(function(lease) {
			if (!lease) return;
			var addresses=[lease.ipaddr,lease.ip6addr].concat(Array.isArray(lease.ip6addrs) ? lease.ip6addrs : []), mac=clientMac(lease.macaddr), matched='MAC address';
			// DUIDs and EUI-64 identifiers alone do not prove the current interface MAC.
			if (!mac && key==='dhcp6_leases' && owners) {
				var candidates=new Set(), ambiguous=false;
				addresses.forEach(function(address) {
					var ip=addressKey(address), owner=ip && ip.includes(':') && owners[ip];
					if (!owner) return;
					if (owner.macs.size!==1) ambiguous=true;
					else if (owner.confirmed.size===1) candidates.add(Array.from(owner.confirmed)[0]);
				});
				if (!ambiguous && candidates.size===1) { mac=Array.from(candidates)[0];matched='IPv6 neighbor record'; }
			}
			if (!mac) return;
			var host = hosts[mac] || (hosts[mac] = {addresses:[]});
			if (!host.name && typeof lease.hostname==='string' && lease.hostname.trim() && lease.hostname.trim()!=='*') {
				host.name=lease.hostname.trim();host.nameSource=key==='dhcp_leases'?'DHCPv4':'DHCPv6';host.matchMethod=matched;
			}
			addresses.forEach(function(address) { addClientAddress(host,address); });
		});
	});
	return hosts;
}

// Only local interfaces can contribute client observations. Default-route uplinks are excluded.
function clientMap(leases, observations, interfaces, matchNeighbors) {
    var hosts=Object.create(null), local=new Set(), uplinks=new Set();
    (Array.isArray(interfaces.interface)?interfaces.interface:[]).forEach(function(entry){
        if(!entry || typeof entry.l3_device!=='string')return;
        var wan=/^wan[0-9]*$/.test(entry.interface || '') || (entry.route || []).some(function(route){return route && (route.target==='0.0.0.0' || route.target==='::') && Number(route.mask)===0;});
        (wan?uplinks:local).add(entry.l3_device);
    });
    uplinks.forEach(function(name){local.delete(name);});
    function host(row){
        if(!row || !clientMac(row.mac))return null;
        var mac=row.mac.toUpperCase();return hosts[mac] || (hosts[mac]={addresses:[]});
    }
    (Array.isArray(observations.fdb)?observations.fdb:[]).slice(0,1024).forEach(function(row){
        if(!row || (!local.has(row.bridge) && !(Number.isInteger(row.vlan) && local.has(row.bridge+'.'+row.vlan))) || uplinks.has(row.bridge) || uplinks.has(row.bridge+'.'+row.vlan) || uplinks.has(row.port) || typeof row.port!=='string')return;
        var value=host(row);if(!value)return;
        if(!value.paths)value.paths=[];
        if(!value.paths.some(function(path){return path.port===row.port && path.bridge===row.bridge && path.vlan===row.vlan;}))value.paths.push(row);
    });
    (Array.isArray(observations.neighbors)?observations.neighbors:[]).slice(0,1024).forEach(function(row){
        if(!row || !local.has(row.device) || !addressKey(row.address) || !['reachable','stale','delay','probe','permanent','failed','incomplete','unknown'].includes(row.state))return;
        var value=host(row);if(!value)return;
        addClientAddress(value,row.address);
        if(!value.neighbors)value.neighbors=[];
        value.neighbors.push(row);
    });
    var owners=Object.create(null);
    if (matchNeighbors) Object.keys(hosts).forEach(function(mac) {
        (hosts[mac].neighbors || []).forEach(function(row) {
            var ip=addressKey(row.address);if (!ip || !ip.includes(':')) return;
            var owner=owners[ip] || (owners[ip]={macs:new Set(),confirmed:new Set()});
            owner.macs.add(mac);if (row.state==='reachable' || row.state==='permanent') owner.confirmed.add(mac);
        });
    });
    var leased=leaseMap(leases,matchNeighbors?owners:null);
    Object.keys(leased).forEach(function(mac) {
        var value=hosts[mac] || (hosts[mac]={addresses:[]}), lease=leased[mac];
        // Prefer DHCP IPv4 addresses in the summary, retaining all observed IPv6.
        var observed=value.addresses;value.addresses=lease.addresses.slice();observed.forEach(function(address) { addClientAddress(value,address); });
        if (lease.name) { value.name=lease.name;value.nameSource=lease.nameSource;value.matchMethod=lease.matchMethod; }
    });
    return hosts;
}

function validDisplayName(value) {
    try { return typeof value === 'string' && !/[\x00-\x1f\x7f]/.test(value) && encodeURIComponent(value).replace(/%[A-F\d]{2}|./g,'x').length <= 256; } catch(err) { return false; }
}
function clientNames(reply) {
    var result=Object.create(null), names=reply && reply.names;
    if (!names || typeof names!=='object' || Array.isArray(names)) return result;
    Object.keys(names).slice(0,512).forEach(function(mac) { if(clientMac(mac)===mac && validDisplayName(names[mac]) && names[mac].trim())result[mac]=names[mac]; });
    return result;
}
function dnsAddress(value) {
    var key=addressKey(value);
    if (!key || /^fe[89ab]/i.test(key) || /^ff/i.test(key) || key==='0000:0000:0000:0000:0000:0000:0000:0000' || key==='0000:0000:0000:0000:0000:0000:0000:0001') return null;
    if(value.indexOf(':')===-1 && (Number(value.split('.')[0])===0 || Number(value.split('.')[0])===127 || Number(value.split('.')[0])>=224 || /^169\.254\./.test(value)))return null;
    return key;
}

return view.extend({
	load: function() {
		if (this.pending) return this.pending;
		this.pending = Promise.all([
			requested(callBoard, function(v) { return typeof v.hostname === 'string' || typeof v.model === 'string'; }),
			requested(callInfo, function(v) { return finite(v.uptime) && !!v.memory; }),
			requested(callInterfaces, function(v) { return Array.isArray(v.interface); }),
			requested(function() { return callServices('rmm-agent'); }),
			requested(function() { return callConfig('rmm-agent', 'main').then(function(v) {
				if (!v || !Object.keys(v).length) throw new Error('No agent configuration');
				return { enabled: v.enabled, heartbeat: v.interval_seconds, connectivity: v.connectivity_check_interval_seconds };
			}); }),
			requested(callDevices),
			requested(wifiLoad),
			requested(callLeases, function(reply) { return Array.isArray(reply.dhcp_leases) || Array.isArray(reply.dhcp6_leases); }),
			requested(callClients, function(reply) { return !reply.error && Array.isArray(reply.fdb) && Array.isArray(reply.neighbors); })
		]).finally(L.bind(function() { this.pending = null; }, this));
		return this.pending;
	},

	render: function(data) {
		if (!document.getElementById('rmm-dashboard-styles'))
			document.head.appendChild(element('link', { id: 'rmm-dashboard-styles', rel: 'stylesheet', href: L.resource('view/status/rmm-dashboard.css') + '?v=0.10.1' }));
		this.sources = [];
		this.history = { memory: [], devices: Object.create(null) };
		this.slots = {};
		this.preferences = this.readPreferences();
		this.clientJournal=new Map();this.clientTraffic=new Map();this.vendorPrefixes=new Map();this.vendorRetryAt=0;
        this.nameEditors=Object.create(null);this.nameSequence=0;
        this.dnsCache=new Map();this.dnsGeneration=0;this.dnsRetryAt=0;
        try { this.dnsEnabled=window.localStorage.getItem('rmm-dashboard-dns-v1')==='true'; } catch(err) { this.dnsEnabled=false; }
        this.knownNodes = Object.create(null);
		this.stationHistory = Object.create(null);
		this.stationNodes = Object.create(null);
		this.radioNodes = Object.create(null);
		this.relationshipNodes = Object.create(null);
		this.status = element('span', { 'class': 'rmm-dashboard-refresh', role: 'status', 'aria-live': 'polite' }, tr('Loading'));
		this.retry = element('button', { 'class': 'btn', type: 'button', click: L.bind(function() { return this.refresh(); }, this) }, tr('Retry'));
		this.layoutToggle=element('button',{type:'button','class':'btn','aria-controls':'rmm-dashboard-layout','aria-expanded':'false',click:L.bind(function(){this.layoutPanel.open=!this.layoutPanel.open;},this)},tr('Customize dashboard'));
		var root = element('div', { 'class': 'rmm-dashboard' });
		this.root=root;
		this.identity = element('p', {'class':'rmm-dashboard-identity'});
		this.overview = element('section', {'class':'rmm-dashboard-overview','aria-label':tr('Summary')});
		this.agentSummary = element('div', {'class':'rmm-dashboard-agent-summary'});
		this.healthSummary = element('section',{'class':'rmm-dashboard-health','aria-label':tr('Resource summary')});
		this.trafficChart = element('div', {'class':'rmm-dashboard-history-panel'});
		this.memoryChart = element('div', {'class':'rmm-dashboard-history-panel'});
		this.memoryDisclosure = element('details', {'class':'rmm-dashboard-memory rmm-dashboard-disclosure'},[element('summary',{},tr('Memory history')),this.memoryChart]);
		if (typeof window === 'undefined' || !window.matchMedia || !window.matchMedia('(max-width: 767px)').matches) this.memoryDisclosure.setAttribute('open','');
		this.radioContent = element('div', {'class':'rmm-dashboard-radios'});
		function section(title, content) { return element('section', {'class':'rmm-dashboard-section'}, [element('h2',{},[dashboardIcon(title === 'Wireless' ? 'router' : title === 'Wi-Fi clients' ? 'layout-grid' : 'network'),element('span',{},tr(title))]),content]); }
		var disclosures = [['system','Router details'],['network','Network interfaces'],['agent','RMM agent']].map(L.bind(function(entry) {
			this.slots[entry[0]] = element('div', {'class':'rmm-dashboard-content'});
			return element('details', {'class':'rmm-dashboard-disclosure'}, [element('summary',{},tr(entry[1])),this.slots[entry[0]]]);
		},this));
		this.slots.wireless = element('div', {'class':'rmm-dashboard-content'});
		this.slots.topology = element('div', {'class':'rmm-dashboard-content'});
		root.appendChild(element('div', {'class':'rmm-dashboard-heading'}, [
			element('div', {}, [element('div', {'class':'rmm-dashboard-eyebrow'},tr('SYSTEM / OVERVIEW')),element('h1',{},[dashboardIcon('router'),element('span',{},tr('Router overview'))]),this.identity]),
			element('div', {'class':'rmm-dashboard-toolbar'}, [this.status,this.retry,this.layoutToggle])
		]));
		this.blockContainer=element('div',{'class':'rmm-dashboard-blocks'});
		root.appendChild(this.blockContainer);
		this.blocks={};
		root.insertBefore(this.createLayoutPanel(),this.blockContainer);
		this.blockContainer.appendChild(this.overview);
		this.blockContainer.appendChild(this.agentSummary);
		root.insertBefore(this.healthSummary,this.blockContainer);
		var pathSection = section('Network relationships',this.slots.topology);
		pathSection.classList.add('rmm-dashboard-network-path');
		this.blocks.topology=pathSection;
		this.historyPeriod=element('select',{id:'rmm-history-period',change:L.bind(function(){this.preferences.period=Number(this.historyPeriod.value);this.savePreferences();this.update(this.root,this.sources,true);},this)},[[60000,'Last 1 minute'],[300000,'Last 5 minutes'],[900000,'Last 15 minutes']].map(function(entry){return element('option',{value:entry[0]},tr(entry[1]));}));
		this.historyPeriod.value=String(this.preferences.period);
		this.blocks.charts=element('section',{'class':'rmm-dashboard-chart-section'},[element('label',{for:'rmm-history-period','class':'rmm-dashboard-period'},[tr('History period'),this.historyPeriod]),element('div',{'class':'rmm-dashboard-charts'}, [this.trafficChart,this.memoryDisclosure])]);
		this.blocks.wireless=section('Wireless',this.radioContent);
		this.blocks.clients=section('Clients',this.slots.wireless);
		this.blocks.details=element('div', {'class':'rmm-dashboard-expert'}, disclosures);
		this.applyLayout();
		root.appendChild(element('details', {'class':'rmm-dashboard-disclosure rmm-dashboard-help'}, [
			element('summary',{},tr('Sources')),
			element('p', {'class':'rmm-dashboard-note'},tr('Updates every 30 seconds')),
			element('p', {'class':'rmm-dashboard-note'},tr('History starts when this page opens. Gaps indicate unavailable data.')),
			element('p', {'class':'rmm-dashboard-note'},tr('WAN status shows the interface link state; it does not test Internet reachability.')),
			element('p', {'class':'rmm-dashboard-note'},tr('Traffic counters belong to devices; shared devices are not summed.')),
			element('p', {'class':'rmm-dashboard-note'},tr('Signal bands are filters, not a connection quality score.')),
			element('p', {'class':'rmm-dashboard-note'},tr('Wireless interfaces visible to iwinfo are shown; disabled radios are not inventoried.')),
			element('p', {'class':'rmm-dashboard-note'},tr('Link rates are negotiated Wi-Fi rates, not measured traffic.'))
		]));
		this.detailTitle=element('h2',{id:'rmm-dashboard-detail-title'});
		this.detailContent=element('div',{'class':'rmm-dashboard-detail-content'});
		this.detailClose=element('button',{type:'button','class':'btn',click:L.bind(function(){this.detailDialog.close();},this)},tr('Close'));
		this.detailDialog=element('dialog',{'class':'rmm-dashboard-inspector','aria-labelledby':'rmm-dashboard-detail-title',close:L.bind(this.restoreDetails,this)},[element('div',{'class':'rmm-dashboard-detail-header'},[this.detailTitle,this.detailClose]),this.detailContent]);
		root.appendChild(this.detailDialog);
		var filterChange = L.bind(this.filterStations, this);
		function field(id, label, control) { return element('label', {for:id}, [element('span',{},tr(label)),control]); }
		function select(id, options) { return element('select',{id:id,change:filterChange}, options.map(function(option) { return element('option',{value:option[0]},tr(option[1])); })); }
		this.clientSearch = element('input',{id:'rmm-client-search',type:'search',maxlength:128,input:filterChange,placeholder:tr('Search by name, MAC, IP or SSID')});
		this.clientBand = select('rmm-client-band',[['all','All bands'],['2.4 GHz','2.4 GHz'],['5 GHz','5 GHz'],['6 GHz','6 GHz'],['60 GHz','60 GHz']]);
		this.clientSignal = select('rmm-client-signal',[['all','All signals'],['strong','Signal ≥ -67 dBm'],['medium','Signal -68…-75 dBm'],['weak','Signal < -75 dBm'],['unknown','Unknown signal']]);
		this.clientSort=select('rmm-client-sort',[['name','By name'],['signal','Strongest signal'],['rate','Fastest link']]);
		this.clientGroup=select('rmm-client-group',[['none','No grouping'],['ssid','By SSID']]);
		this.clientType=select('rmm-client-type',[['all','All clients'],['wifi','Wi-Fi association'],['wired','Ethernet path'],['neighbor','Neighbor records'],['dhcp','DHCP records']]);
		this.clientCount = element('p',{'class':'rmm-dashboard-source',role:'status','aria-live':'polite'});
		this.clientEmpty = element('p',{'class':'rmm-dashboard-source',hidden:''},tr('No matching stations'));
		this.wirelessContent = element('div',{});
		this.slots.wireless.appendChild(element('div',{'class':'rmm-dashboard-filters'},[
			field('rmm-client-search','Search clients',this.clientSearch),field('rmm-client-type','Connection type',this.clientType),field('rmm-client-band','Band',this.clientBand),field('rmm-client-signal','Signal',this.clientSignal),field('rmm-client-sort','Sort clients',this.clientSort),field('rmm-client-group','Group clients',this.clientGroup),
			element('button',{type:'button','class':'btn',click:L.bind(function() { this.clientSearch.value='';this.clientBand.value='all';this.clientSignal.value='all';this.clientType.value='all';this.filterStations(); },this)},tr('Clear filters'))
		]));
		this.dnsToggle=element('input',{type:'checkbox',change:L.bind(function(){
            this.dnsEnabled=this.dnsToggle.checked;this.dnsGeneration++;
            try { window.localStorage.setItem('rmm-dashboard-dns-v1',String(this.dnsEnabled)); } catch(err) { this.preferenceNotice.hidden=false; }
            this.dnsStatus.textContent=tr(this.dnsEnabled?'Loading':'DNS disabled');
            this.update(this.root,this.sources,true);
            if(this.dnsEnabled)this.lookupNames(this.clientHosts,Date.now());
        },this)});this.dnsToggle.checked=this.dnsEnabled;
        this.dnsStatus=element('span',{role:'status','aria-live':'polite','class':'rmm-dashboard-source'},tr(this.dnsEnabled?'Loading':'DNS disabled'));
        this.slots.wireless.appendChild(element('div',{'class':'rmm-dashboard-name-options'},[element('label',{},[this.dnsToggle,tr('DNS names')]),element('span',{'class':'rmm-dashboard-note'},tr('Resolve unnamed clients through the router DNS.')),this.dnsStatus]));
        this.slots.wireless.appendChild(this.clientCount);
		this.slots.wireless.appendChild(this.clientEmpty);

		this.slots.wireless.appendChild(element('div',{'class':'rmm-dashboard-client-heading','aria-hidden':'true'},[
			element('span',{},tr('Device')),element('span',{},tr('IP address')),element('span',{},tr('Band')),element('span',{},tr('Signal')),element('span',{},tr('Link rate RX / TX')),element('span',{},tr('Station details'))
		]));
		this.slots.wireless.appendChild(this.wirelessContent);
		this.slots.wireless.appendChild(element('p',{'class':'rmm-dashboard-note'},tr('DHCP clients may use wired or wireless links; a lease does not prove an active connection.')));
		this.journalList=element('ol',{'class':'rmm-dashboard-journal'});
        this.slots.wireless.appendChild(element('details',{'class':'rmm-dashboard-disclosure'},[element('summary',{},tr('Client observation history')),element('p',{'class':'rmm-dashboard-note'},tr('History covers this open page; a record does not prove an active connection.')),this.journalList]));
        this.update(root, data);
		this.root = root;
		poll.add(L.bind(this.refresh, this), 30);
		return root;
	},

	refresh: function() {
		this.retry.disabled = true;
		this.retry.textContent = tr('Refreshing');
		return this.load().then(L.bind(function(data) { this.update(this.root, data); }, this)).finally(L.bind(function() {
			this.retry.disabled = false;
			this.retry.textContent = tr('Retry');
		}, this));
	},

	update: function(root, data, repaint) {
		var activeChart = document.activeElement && document.activeElement.getAttribute('data-chart-title');
		var previousDevices = repaint ? this.previousDevices : this.sources[5];
		if(!repaint)this.previousDevices=previousDevices;
		var previousInfo = repaint ? this.previousInfo : this.sources[1];
		if(!repaint)this.previousInfo=previousInfo;
		var previousWireless = this.sources[6];
		data.forEach(L.bind(function(result, index) {
			var previous = this.sources[index];
			this.sources[index] = result.error ? { value: previous && previous.value, at: previous && previous.at, error: result.error } : result;
		}, this));
		var sources = this.sources;
		if (sources[6].value && !sources[6].error) {
			var oldWireless = Object.create(null);
			((previousWireless && previousWireless.value && previousWireless.value.interfaces) || []).forEach(function(entry) { oldWireless[entry.device] = entry; });
			sources[6] = Object.assign({}, sources[6], {value:{interfaces:sources[6].value.interfaces.map(function(entry) {
				var previous = oldWireless[entry.device];
				return {device:entry.device,info:cachedResult(entry.info,previous && previous.info),stations:cachedResult(entry.stations,previous && previous.stations)};
			})}});
		}

		function state(index) {
			var source = sources[index];
			var stale = !!source.value && (!!source.error || Date.now() - source.at > 65000);
			return stale ? tr('Stale') + (source.error ? ' · ' + failure(source.error) : '') : source.error ? failure(source.error) : tr('Current');
		}
		function sourceLine(label, index) {
			return element('p', { 'class': 'rmm-dashboard-source' + (sources[index].error ? ' rmm-dashboard-warning' : '') }, [
				element('span', {}, label + ': ' + state(index) + ' · ' + tr('Last successful update') + ': '),
				element('time', { datetime: sources[index].at ? new Date(sources[index].at).toISOString() : '' }, clock(sources[index].at))
			]);
		}
		var board = sources[0].value || {}, info = sources[1].value || {}, memory = info.memory || {};
		var interfaces = sources[2].value || {}, services = sources[3].value || {}, config = sources[4].value || {};
		var devices = sources[5].value || {};
		var entries = Array.isArray(interfaces.interface) ? interfaces.interface.filter(function(e) { return e && typeof e.interface === 'string'; }) : [];
		var wan = entries.filter(function(e) { return e.interface === 'wan' || e.interface === 'wan6' || Array.isArray(e.route) && e.route.some(function(route) { return route && route.mask === 0 && (route.target === '0.0.0.0' || route.target === '::'); }); });
		var agent = services['rmm-agent'];
		var running = !!(agent && agent.instances && Object.keys(agent.instances).some(function(k) { return agent.instances[k] && agent.instances[k].running; }));
		var used = finite(memory.total) && memory.total > 0 && finite(memory.available) && memory.available <= memory.total ? memory.total - memory.available : null;
		var rebooted = !repaint && previousInfo && finite(previousInfo.value && previousInfo.value.uptime) && finite(info.uptime) && info.uptime < previousInfo.value.uptime;
		var now = Date.now();
		if (rebooted) { this.clientTraffic.clear(); this.history = { memory: [], devices: Object.create(null) }; this.stationHistory = Object.create(null); }
		var history = this.history;
		if(!repaint) history.memory = remember(history.memory, { at: now, used: sourceFresh(sources[1], now) && used !== null ? used / memory.total * 100 : null }, now);
		var load = Array.isArray(info.load) && info.load.every(finite) ? info.load.map(function(v) { return (v / 65536).toFixed(2); }).join(' / ') : tr('Unavailable');
		this.slots.system.replaceChildren(sourceLine('system.board', 0), sourceLine('system.info', 1), element('dl', {}, [
			item(tr('Hostname'), reportedText(board.hostname)), item(tr('Model'), reportedText(board.model)),
			item(tr('Firmware'), reportedText(board.release && board.release.description)), item(tr('Uptime'), formatDuration(info.uptime)),
			item(tr('Load (1 / 5 / 15 min)'), load), item(tr('Memory total'), formatBytes(memory.total)),
			item(tr('Memory available'), formatBytes(memory.available)), item(tr('Memory used'), used === null ? tr('Unavailable') : formatBytes(used) + ' (' + (used / memory.total * 100).toFixed(1) + '%)')
		]));
		this.memoryChart.replaceChildren(historyChart(tr('Memory history'), history.memory, [{key: 'used', label: tr('Memory used')}], 100, function(value) { return value.toFixed(1) + '%'; }, now, this.preferences.period));
		var period=this.preferences.period;
		var seenDevices = Object.create(null), wanCharts = [];
		var networkRows = [sourceLine('network.interface.dump', 2), sourceLine('network.device.status', 5), sourceLine('rmm.dashboard.clients', 8), element('dl', {}, [
			item(tr('WAN connection'), sources[2].error && !sources[2].value ? failure(sources[2].error) : !wan.length ? tr('Not configured') : wan.some(function(e) { return e.up; }) ? tr('Connected') : tr('Disconnected'))
		])];
		entries.forEach(function(entry) {
			var name = entry.l3_device || entry.device;
			var stats = devices[name] && devices[name].statistics || {};
			var before = previousDevices && previousDevices.value && previousDevices.value[name] && previousDevices.value[name].statistics || {};
			var elapsed = previousDevices ? (sources[5].at - previousDevices.at) / 1000 : 0;
			var fresh = !sources[5].error && !sources[2].error && !rebooted;
			networkRows.push(element('h3', {}, entry.interface), element('dl', {}, [
				item(tr('Status'), entry.up ? tr('Connected') : tr('Disconnected'), entry.up ? 'ok' : 'warning'),
				item(tr('Device'), reportedText(name)), item(tr('IP address'), firstAddress(entry)),
				item(tr('Received / sent'), formatTraffic(stats.rx_bytes) + ' / ' + formatTraffic(stats.tx_bytes)),
				item(tr('RX / TX rate'), fresh ? rate(stats.rx_bytes, before.rx_bytes, elapsed) + ' / ' + rate(stats.tx_bytes, before.tx_bytes, elapsed) : tr('Unavailable'))
			]));
			if (typeof name === 'string' && !seenDevices[name]) {
				seenDevices[name] = true;
				var validBaseline = fresh && sourceFresh(sources[1], now) && sourceFresh(sources[2], now) && sourceFresh(sources[5], now) && previousDevices && !previousDevices.error && previousInfo && !previousInfo.error;
				if(!repaint) history.devices[name] = remember(history.devices[name] || [], { at: now,
					rx: validBaseline ? byteRate(stats.rx_bytes, before.rx_bytes, elapsed) : null,
					tx: validBaseline ? byteRate(stats.tx_bytes, before.tx_bytes, elapsed) : null,
					reset: !!(rebooted || validBaseline && (finite(stats.rx_bytes) && stats.rx_bytes < before.rx_bytes || finite(stats.tx_bytes) && stats.tx_bytes < before.tx_bytes)) }, now);
				var chart = historyChart(tr('Traffic history') + ' · ' + name, history.devices[name], [{key:'rx',label:'RX'}, {key:'tx',label:'TX'}], null, function(value) { return formatTraffic(value) + '/s'; }, now, period);
				if (wan.some(function(iface) { return (iface.l3_device || iface.device) === name; })) wanCharts.push(chart);
				else networkRows.push(element('details',{'class':'rmm-dashboard-disclosure'},[element('summary',{},tr('Traffic history') + ' · ' + name),chart]));
			}
		});
		Object.keys(history.devices).forEach(function(name) { if (!seenDevices[name]) delete history.devices[name]; });
		if (!entries.length) networkRows.push(element('p', { 'class': 'rmm-dashboard-source' }, sources[2].error ? failure(sources[2].error) : tr('No interfaces')));
		this.slots.network.replaceChildren.apply(this.slots.network, networkRows);
		this.trafficChart.replaceChildren.apply(this.trafficChart,wanCharts.length ? wanCharts : [element('h2',{},tr('WAN traffic')),element('p',{'class':'rmm-dashboard-source'},sources[2].error ? failure(sources[2].error) : tr('No WAN device reported'))]);
		var wirelessRows = [], radioRows = [], seenRadios = Object.create(null);
		if (sources[6].error) wirelessRows.push(sourceLine('iwinfo.devices',6));
		if (sources[7].error) wirelessRows.push(sourceLine('luci-rpc.getDHCPLeases',7));
		var wireless = sources[6].value && sources[6].value.interfaces || [];
		var hosts = clientMap(sources[7].value || {}, sources[8].value || {}, sources[2].value || {}, sourceFresh(sources[7],now) && sourceFresh(sources[8],now) && sourceFresh(sources[2],now));
		if (sources[8].error || !sourceFresh(sources[8],now)) wirelessRows.push(resultLine('rmm.dashboard.clients',sources[8]));
		if (sources[8].value && sources[8].value.truncated) wirelessRows.push(element('p',{'class':'rmm-dashboard-note'},tr('Client inventory truncated')));
		var seenStations = Object.create(null);
		var focused = document.activeElement;
		this.clientRecords = [];
		var self = this;
		wireless.forEach(function(entry) {
			var info = entry.info.value || {}, stations = stationList(entry.stations.value);
			var radioMetrics = element('dl',{},[
				item(tr('Interface'),entry.device),item(tr('Radio'),reportedText(info.phy)),item('SSID',reportedText(info.ssid)),item(tr('Band'),bandName(info)),
				item(tr('Channel'),finite(info.channel) && info.channel > 0 ? String(info.channel) : tr('Unavailable')),
				item(tr('Channel mode'),reportedText(info.htmode)),item(tr('TX power'),finite(info.txpower) ? info.txpower + ' dBm' : tr('Unavailable')),
				item(tr('Noise'),signalText(info.noise)),item(tr('Associated stations'),entry.stations.value ? String(stations.length) : failure(entry.stations.error))
			]);
			var radioNode = self.radioNodes[entry.device] || (self.radioNodes[entry.device] = element('details',{'class':'rmm-dashboard-radio rmm-dashboard-disclosure'}));
			seenRadios[entry.device] = true;
			var radioSummary = radioNode.querySelector('summary') || element('summary',{});
			radioSummary.replaceChildren(
					element('span',{'class':'rmm-dashboard-radio-name'},reportedText(info.ssid) + ' · ' + bandName(info)),
					element('span',{'class':'rmm-dashboard-radio-meta'},tr('Channel') + ' ' + (finite(info.channel) && info.channel > 0 ? info.channel : tr('Unavailable')) + ' · ' + reportedText(info.htmode)),
					element('span',{'class':'rmm-dashboard-radio-count'},entry.stations.value ? String(stations.length) + ' · ' + tr('Associated stations') : failure(entry.stations.error)),
					element('span',{'class':'rmm-dashboard-radio-state'},sources[6].error || entry.info.error || entry.stations.error ? (entry.info.value || entry.stations.value ? tr('Stale') + ' · ' : '') + failure(sources[6].error || entry.info.error || entry.stations.error) : tr('Current'))
				);
			radioNode.replaceChildren(radioSummary,radioMetrics,resultLine('iwinfo.info',entry.info,sources[6].error),resultLine('iwinfo.assoclist',entry.stations,sources[6].error));
			radioRows.push(radioNode);
			if (entry.stations.value && entry.stations.value.results.length !== stations.length) wirelessRows.push(element('p',{'class':'rmm-dashboard-source rmm-dashboard-warning'},tr('Invalid station records') + ': ' + (entry.stations.value.results.length - stations.length)));
			stations.forEach(function(station) {
				var mac = station.mac.toUpperCase(), host = hosts[mac] || (hosts[mac]={addresses:[]}), key = entry.device + '/' + mac;
                self.decorateClient(mac,host,now);
				seenStations[key] = true;
				var previous = self.stationHistory[key], fresh = sourceFresh(sources[6],now) && sourceFresh(entry.stations,now);
				if (previous && fresh && finite(station.connected_time) && finite(previous.connected) && station.connected_time < previous.connected) previous = null;
				var points = repaint && previous ? previous.points : remember(previous && previous.points || [], {at:now,signal:fresh ? signalValue(station.signal) : null},now);
				self.stationHistory[key] = {points:points,connected:fresh ? station.connected_time : previous && previous.connected,lastSeen:now};
				var nodes = self.stationNodes[key];
				if (!nodes) {
					nodes = {root:element('div',{'class':'rmm-dashboard-station'}),title:element('span',{'class':'rmm-dashboard-client-name'}),address:element('span',{'class':'rmm-dashboard-client-address'}),band:element('span',{'class':'rmm-dashboard-client-band'}),signal:element('span',{'class':'rmm-dashboard-client-signal'}),link:element('span',{'class':'rmm-dashboard-client-link'}),metrics:element('dl',{}),summary:element('summary',{'aria-label':tr('Station details')}),body:element('div',{})};
					nodes.details = element('details',{'class':'rmm-dashboard-station-details'},[nodes.summary,nodes.body]);
					nodes.summary.append(nodes.title,nodes.address,nodes.band,nodes.signal,nodes.link);
					if (typeof self.detailDialog.showModal==='function') nodes.summary.setAttribute('aria-haspopup','dialog');nodes.root.appendChild(nodes.details);
					nodes.summary.addEventListener('click',function(event) { if (self.openDetails('station/'+key,nodes.title.textContent,nodes.body,nodes.details,nodes.summary)) event.preventDefault(); });
					self.stationNodes[key] = nodes;
				}
				nodes.title.textContent = host.name || mac;
				nodes.address.textContent = clientAddressSummary(host.addresses,'No local DHCP record');
				nodes.address.title=(host.addresses || []).join(' / ');
				nodes.band.textContent = bandName(info);
				nodes.link.setAttribute('data-label',tr('Link rate RX / TX'));
				nodes.link.textContent = linkRate(station.rx) + ' / ' + linkRate(station.tx);
				nodes.signal.textContent = signalText(station.signal) + (sources[6].error || entry.stations.error ? ' · ' + tr('Stale') : '');
				nodes.summary.setAttribute('aria-label',tr('Station details') + ': ' + nodes.title.textContent);
				nodes.metrics.replaceChildren.apply(nodes.metrics,[item(tr('MAC address'),mac),item(tr('IP address'),host.addresses && host.addresses.length ? host.addresses.join(' / ') : tr('No local DHCP record')),
					...clientIdentityItems(host),item(tr('Signal'),signalText(station.signal)),item(tr('Link rate RX / TX'),linkRate(station.rx) + ' / ' + linkRate(station.tx)),item(tr('Connected time'),formatDuration(station.connected_time))]);
				nodes.body.replaceChildren(nodes.metrics,resultLine('iwinfo.assoclist',entry.stations,sources[6].error),resultLine('luci-rpc.getDHCPLeases',sources[7]),...(host.neighbors || host.paths ? [resultLine('rmm.dashboard.clients',sources[8])] : []),element('dl',{},[
					item(tr('Interface'),entry.device),item(tr('Radio'),reportedText(info.phy)),item('SSID',reportedText(info.ssid)),item(tr('Band'),bandName(info)),
					item(tr('Station noise'),signalText(station.noise)),item(tr('Station traffic'),tr('Unavailable'))
				]),historyChart(tr('Signal history'),points.map(function(point) { return {at:point.at,used:point.signal === null ? null : point.signal + 127}; }),[{key:'used',label:tr('Signal')}],127,function(value) { return (value - 127).toFixed(0) + ' dBm'; },now,self.preferences.period));
				nodes.body.appendChild(self.nameEditor('station/'+key,mac));
                self.clientRecords.push({fresh:fresh && sourceFresh(entry.info,now),path:entry.device+(info.ssid?' / '+info.ssid:''),type:'wifi',mac:mac,key:key,name:nodes.title.textContent,ssid:reportedText(info.ssid),node:nodes.root,addresses:host.addresses || [],band:bandName(info),signal:signalValue(station.signal),rate:station.rx && finite(station.rx.rate) || station.tx && finite(station.tx.rate) ? Math.max(station.rx && finite(station.rx.rate) ? station.rx.rate : 0,station.tx && finite(station.tx.rate) ? station.tx.rate : 0) : null,search:[host.name,mac,entry.device,info.ssid].concat(host.addresses || []).filter(function(value) { return typeof value === 'string'; }).join(' ').toLowerCase()});
				wirelessRows.push(nodes.root);
			});
			if (entry.stations.value && !entry.stations.value.results.length) wirelessRows.push(element('p',{'class':'rmm-dashboard-source'},tr('No associated stations')));
		});
		if (!wireless.length) wirelessRows.push(element('p',{'class':'rmm-dashboard-source'},sources[6].error ? failure(sources[6].error) : tr('No wireless interfaces reported')));

		Object.keys(this.stationHistory).forEach(function(key) {
			if (!seenStations[key]) {
				var history = self.stationHistory[key];
				history.points = remember(history.points,{at:now,signal:null},now);
				if (now - history.lastSeen > historyWindow) delete self.stationHistory[key];
				delete self.stationNodes[key];
			}
		});
		// Bound identities as well as points on networks with high station churn.
		Object.keys(this.stationHistory).sort(function(a,b) { return self.stationHistory[b].lastSeen - self.stationHistory[a].lastSeen; }).slice(256).forEach(function(key) { delete self.stationHistory[key]; });
		Object.keys(this.radioNodes).forEach(function(key) { if (!seenRadios[key]) delete self.radioNodes[key]; });
		this.radioContent.replaceChildren.apply(this.radioContent,radioRows.length ? radioRows : [element('p',{'class':'rmm-dashboard-source'},sources[6].error ? failure(sources[6].error) : tr('No wireless interfaces reported'))]);
		this.stationMessages=wirelessRows.filter(function(row) { return !row.classList.contains('rmm-dashboard-station'); });
		this.wirelessContent.replaceChildren.apply(this.wirelessContent,wirelessRows);
		if (focused && focused.isConnected && (this.wirelessContent.contains(focused) || this.radioContent.contains(focused)) && typeof focused.focus === 'function') focused.focus();
		this.renderKnownClients(hosts,now);
        this.updateClientInsights(now,repaint);
        if(!repaint)this.lookupVendors(now);
		this.filterStations();
		this.renderRelationships();
		var agentStatus = !sources[3].value ? failure(sources[3].error) : !agent ? tr('Not installed') : running ? tr('Running') : !sources[4].value ? failure(sources[4].error) : config.enabled === '1' ? tr('Stopped') : tr('Disabled');
		this.slots.agent.replaceChildren(sourceLine('service.list', 3), sourceLine('uci rmm-agent', 4), element('dl', {}, [
			item(tr('Status'), agentStatus, running ? 'ok' : agent ? 'warning' : ''),
			item(tr('Heartbeat interval'), sources[4].value ? (config.heartbeat || '30') + ' ' + tr('s') : failure(sources[4].error)),
			item(tr('Connectivity check interval'), sources[4].value ? (config.connectivity || '300') + ' ' + tr('s') : failure(sources[4].error))
		]));
		this.identity.textContent = reportedText(board.hostname) + ' · ' + reportedText(board.release && board.release.description) + ' · ' + tr('Uptime') + ': ' + formatDuration(info.uptime);
		var wanStatus = !sources[2].value ? failure(sources[2].error) : !wan.length ? tr('Not configured') : wan.some(function(entry) { return entry.up === true; }) ? tr('Connected') : wan.every(function(entry) { return entry.up === false; }) ? tr('Disconnected') : tr('Unavailable');
		var countKnown = !!sources[6].value && wireless.every(function(entry) { return !!entry.stations.value; });
		var count = wireless.reduce(function(total,entry) { return total + stationList(entry.stations.value).length; },0);
		function metric(label,value,description,indices) {
			var bad = indices.some(function(index) { return !sourceFresh(sources[index],now); });
			return element('div',{'class':'rmm-dashboard-metric'},[
				element('span',{'class':'rmm-dashboard-metric-label'},[dashboardIcon(label === 'WAN connection' ? 'network' : label === 'Memory' ? 'terminal-2' : label === 'Wi-Fi clients' ? 'router' : 'activity-heartbeat'),element('span',{},tr(label))]),element('strong',{'class':'rmm-dashboard-metric-value'},value),
				element('span',{'class':'rmm-dashboard-metric-description'},description),
				bad ? element('span',{'class':'rmm-dashboard-warning'},indices.map(function(index) { return state(index); }).filter(function(value) { return value !== tr('Current'); }).join(' · ')) : null
			]);
		}
		this.overview.replaceChildren(
			metric('WAN connection',wanStatus,wan.map(function(entry) { return entry.interface; }).join(' / ') || tr('No interfaces'),[2]),
			metric('Memory',used === null ? tr('Unavailable') : formatBytes(used) + ' / ' + formatBytes(memory.total),used === null ? tr('Unavailable') : (used / memory.total * 100).toFixed(1) + '%',[1]),
			metric('Load (1 / 5 / 15 min)',load,'load average',[1]),
			metric('Wi-Fi clients',countKnown ? String(count) : tr('Unavailable'),tr('Interface') + ': ' + wireless.length + (wireless.some(function(entry) { return entry.info.error || entry.stations.error; }) ? ' · ' + tr('Partial data') : ''),[6])
		);
		this.agentSummary.replaceChildren(dashboardIcon('activity-heartbeat'),element('strong',{},tr('RMM agent')),element('span',{'class':running ? 'rmm-dashboard-ok' : 'rmm-dashboard-warning'},agentStatus),element('span',{},tr('Heartbeat interval') + ': ' + (sources[4].value ? (config.heartbeat || '30') + ' ' + tr('s') : failure(sources[4].error))),element('span',{'class':'rmm-dashboard-warning'},[3,4].filter(function(index) { return !sourceFresh(sources[index],now); }).map(state).join(' · ')));
		var nestedErrors = wireless.some(function(entry) { return entry.info.error || entry.stations.error; });
		var errors = sources.filter(function(s) { return s.error; }).length;
		var cachedWirelessError = wireless.some(function(entry) { return entry.info.error && entry.info.value || entry.stations.error && entry.stations.value; });
		var stateCode = sources.some(function(s) { return s.value && !sourceFresh(s, Date.now()); }) || cachedWirelessError ? 'Stale' : errors === sources.length ? 'Unavailable' : errors || nestedErrors ? 'Partial data' : 'Current';
		// Announce only state transitions, not every successful telemetry poll.
		var statusText = tr(stateCode);
		if (this.status.textContent !== statusText) this.status.textContent = statusText;
		var issues=[];
		if (used===null) issues.push(tr('Memory')+': '+tr('Unavailable'));
		if (wanStatus!==tr('Connected')) issues.push(tr('WAN connection')+': '+wanStatus);
		if (used!==null && memory.total>0 && used/memory.total>=.9) issues.push(tr('Memory usage ≥ 90%'));
		if (!running && agentStatus!==tr('Disabled') && agentStatus!==tr('Not installed')) issues.push(tr('RMM agent')+': '+agentStatus);
		if (stateCode!=='Current') {
			var sourceNames=['system.board','system.info','network.interface.dump','service.list','uci rmm-agent','network.device.status','iwinfo.devices','luci-rpc.getDHCPLeases','rmm.dashboard.clients'];
			sources.forEach(function(source,index) { if (!sourceFresh(source,now)) issues.push(sourceNames[index]+': '+(source.value ? tr('Stale')+' · ' : '')+(source.error ? failure(source.error) : tr('Data is not reported'))); });
			if (nestedErrors || cachedWirelessError) issues.push(tr('Wireless')+': '+tr('Partial data'));
		}
		if (wireless.some(function(entry){return entry.info.error || entry.stations.error;})) issues.push(tr('Wi-Fi data unavailable'));
		this.healthSummary.classList.toggle('rmm-dashboard-warning',issues.length>0);
		this.healthSummary.replaceChildren(element('strong',{},tr(issues.length ? 'Attention required' : 'No reported issues')));
		this.healthSummary.appendChild(element('span',{'class':'rmm-dashboard-health-time'},tr('Last observation')+': '+clock(sources.some(function(source){return source.at;}) ? Math.min.apply(null,sources.filter(function(source){return source.at;}).map(function(source){return source.at;})) : null) ));
		if (issues.length) this.healthSummary.appendChild(element('ul',{},issues.map(function(issue){
			var target=issue.indexOf(tr('WAN connection'))===0 ? 'network' : issue.indexOf(tr('RMM agent'))===0 ? 'agent' : issue.indexOf(tr('Memory'))===0 || issue===tr('Memory usage ≥ 90%') ? 'system' : null;
			return element('li',{},[element('span',{},issue),element('button',{type:'button','class':'btn',click:function(){if(target){var parent=self.slots[target].parentElement;if(parent.tagName==='DETAILS'){parent.open=true;}self.preferences.visible.details=true;self.applyLayout();parent.scrollIntoView({block:'nearest'});}else{self.preferences.visible.wireless=true;self.applyLayout();self.blocks.wireless.scrollIntoView({block:'nearest'});}}},tr('Details'))]);
		})));
		this.healthSummary.classList.toggle('rmm-dashboard-warning',issues.length>0);
		if (this.activeDetails) {
			var selected=this.activeDetails, record=selected.key.indexOf('station/')===0 ? this.stationNodes[selected.key.slice(8)] : selected.key.indexOf('known/')===0 ? this.knownNodes[selected.key.slice(6)] : this.relationshipNodes[selected.key];
			if (!record) this.detailContent.replaceChildren(element('p',{'class':'rmm-dashboard-warning'},tr('Object is no longer reported')));
			else {
				if (record.body!==selected.body) { selected.parent.appendChild(selected.body);selected.body=record.body;selected.parent=record.details || record.root;this.detailContent.replaceChildren(record.body); }
				this.detailTitle.textContent=(record.label || record.title).textContent;
			}
		}
		Object.keys(this.nameEditors).forEach(function(key){if(!self.clientRecords.some(function(record){return (record.type==='wifi'?'station/':'known/')+record.key===key;}) && !self.nameEditors[key].pending)delete self.nameEditors[key];});
        this.clientHosts=hosts;
        if (!repaint) this.lookupNames(hosts,now);
        if (focused && focused.isConnected && this.detailContent.contains(focused) && typeof focused.focus==='function') focused.focus({preventScroll:true});
		if (activeChart) Array.from((this.detailDialog.open ? this.detailDialog : root).querySelectorAll('svg[data-chart-title]')).some(function(svg) { if (svg.getAttribute('data-chart-title')!==activeChart) return false;svg.focus({preventScroll:true});return true; });
	},


    decorateClient: function(mac,host,now) {
        var manual=clientNames(this.sources[8].value)[mac];
        if(manual){host.name=manual;host.nameSource='Manual name';host.matchMethod='MAC address';return;}
        if(!this.dnsEnabled || host.name)return;
        (host.addresses || []).some(function(address){
            var key=dnsAddress(address),record=key && this.dnsCache.get(mac+'/'+key);
            if(!record || record.expires<=now || !record.name)return false;
            host.name=record.name;host.nameSource='Reverse DNS';host.matchMethod='IP address';return true;
        },this);
    },

    nameEditor: function(key,mac) {
        var self=this, editor=this.nameEditors[key];
        if(!editor){
            var id='rmm-client-name-'+(++this.nameSequence);
            editor={mac:mac,previous:'',dirty:false,pending:false,allowed:false};
            editor.input=element('input',{id:id,type:'text',maxlength:256,input:function(){editor.dirty=true;}});
            editor.notice=element('p',{role:'status','aria-live':'polite','class':'rmm-dashboard-note'});
            editor.save=element('button',{type:'submit','class':'btn primary',disabled:''},tr('Save name'));
            editor.reset=element('button',{type:'button','class':'btn',disabled:'',click:function(){return self.saveClientName(editor,'');}},tr('Use automatic name'));
            editor.form=element('form',{hidden:'',submit:function(event){event.preventDefault();return self.saveClientName(editor,editor.input.value);}},[
                element('label',{for:id},tr('Display name')),editor.input,
                element('p',{'class':'rmm-dashboard-note'},tr('Name follows this MAC; DHCP and network settings are unchanged.')),
                element('div',{'class':'rmm-dashboard-name-actions'},[editor.save,editor.reset]),editor.notice]);
            editor.toggle=element('button',{type:'button','class':'btn','aria-controls':id+'-form','aria-expanded':'false',click:function(){
                editor.form.hidden=!editor.form.hidden;editor.toggle.setAttribute('aria-expanded',String(!editor.form.hidden));
                if(editor.form.hidden)return;
                if(!editor.pending){editor.previous=clientNames(self.sources[8].value)[mac] || '';editor.input.value=editor.previous;editor.dirty=false;}
                editor.notice.textContent=tr('Checking permission');editor.allowed=false;editor.save.disabled=true;editor.reset.disabled=true;
                return callCanName('ubus','rmm.dashboard','set_name').then(function(access){
                    editor.allowed=access===true;editor.notice.textContent=editor.allowed?'':tr('Read-only access');self.syncNameEditor(editor);editor.input.focus();
                }).catch(function(){editor.allowed=false;editor.notice.textContent=tr('Read-only access');self.syncNameEditor(editor);});
            }},tr('Edit display name'));
            editor.form.id=id+'-form';editor.root=element('div',{'class':'rmm-dashboard-name-editor'},[editor.toggle,editor.form]);
            this.nameEditors[key]=editor;
        }
        this.syncNameEditor(editor);
        return editor.root;
    },
    syncNameEditor: function(editor) {
        var source=this.sources[8], names=clientNames(source.value), current=names[editor.mac] || '';
        var unavailable=!!(source.error || source.value && source.value.names_error || !sourceFresh(source,Date.now()));
        if(!editor.dirty && !editor.pending && editor.form.hidden){editor.input.value=current;editor.previous=current;}
        editor.save.disabled=editor.reset.disabled=editor.pending || !editor.allowed || unavailable;
        editor.input.disabled=editor.pending || !editor.allowed;
        if(unavailable)editor.notice.textContent=tr('Name storage unavailable');
    },
    saveClientName: function(editor,name) {
        this.syncNameEditor(editor);
        if(editor.pending || editor.save.disabled || !editor.allowed)return Promise.resolve();
        try { if(!validDisplayName(name))throw new Error('Invalid display name'); }
        catch(err){editor.notice.textContent=tr('Invalid display name');return Promise.resolve();}
        editor.pending=true;editor.notice.textContent=tr('Saving name');this.syncNameEditor(editor);
        var self=this;
        return callSetName(editor.mac,name,editor.previous).then(function(reply){
            if(!reply || reply.error || !reply.names || typeof reply.names!=='object' || Array.isArray(reply.names))throw new Error(reply && reply.error || 'Invalid response');
            var names=clientNames(reply);
            if((names[editor.mac] || '')!==name.trim())throw new Error('Invalid response');
            self.sources[8].value.names=names;editor.previous=names[editor.mac] || '';editor.input.value=editor.previous;editor.dirty=false;
            editor.notice.textContent=tr('Name saved');self.update(self.root,self.sources,true);
        }).catch(function(err){editor.notice.textContent=/name changed/i.test(String(err.message || err))?tr('Name changed elsewhere; reopen the editor.'):tr('Unable to save name')+' · '+String(err.message || err);})
          .finally(function(){editor.pending=false;self.syncNameEditor(editor);});
    },

    lookupNames: function(hosts,now) {
        if(!this.dnsEnabled || this.dnsPending || now<this.dnsRetryAt)return;
        // Only fresh local telemetry can schedule PTR queries. No scans or public DNS overrides.
        if(![2,7,8].every(function(index){return sourceFresh(this.sources[index],now);},this))return;
        var self=this,batch=[],owners=Object.create(null),manual=clientNames(this.sources[8].value);
        this.dnsCache.forEach(function(record,key){if(record.expires<=now)self.dnsCache.delete(key);});
        Object.keys(hosts || {}).sort().forEach(function(mac){
            var host=hosts[mac];if(!clientMac(mac))return;
            (host.addresses || []).forEach(function(address){
                var key=dnsAddress(address);if(!key)return;
                if(!owners[key])owners[key]=new Set();owners[key].add(mac);
            });
        });
        var keys=Object.keys(owners).sort(),start=keys.findIndex(function(key){return key>(self.dnsCursor || '');});
        if(start<0)start=0;
        keys.slice(start).concat(keys.slice(0,start)).some(function(key){
            if(owners[key].size!==1)return false;
            var mac=Array.from(owners[key])[0],host=hosts[mac];
            if(manual[mac] || host.name && host.nameSource!=='Reverse DNS' || self.dnsCache.has(mac+'/'+key))return false;
            var address=(hosts[mac].addresses || []).find(function(value){return dnsAddress(value)===key;});
            batch.push({mac:mac,key:key,address:address});return batch.length===8;
        });
        if(!batch.length){this.dnsStatus.textContent=tr('DNS cache updated');return;}
        this.dnsCursor=batch[batch.length-1].key;
        var generation=this.dnsGeneration;
        this.dnsStatus.textContent=tr('Looking up DNS names');
        this.dnsPending=callDNS(batch.map(function(entry){return entry.address;}),1000,8).then(function(reply){
            if(!self.dnsEnabled || generation!==self.dnsGeneration)return;
            if(!reply || typeof reply!=='object' || Array.isArray(reply) || reply.error)throw new Error('Invalid DNS response');
            var answers=Object.create(null);
            Object.keys(reply).forEach(function(address){
                var key=dnsAddress(address),name=reply[address];
                if(key && batch.some(function(entry){return entry.key===key;}) && typeof name==='string' && name.length<=253 && /^[a-z0-9_](?:[a-z0-9_.-]*[a-z0-9_.])?$/i.test(name) && !addressKey(name))answers[key]=name.replace(/\.$/,'');
            });
            batch.forEach(function(entry){var name=answers[entry.key] || '';self.dnsCache.set(entry.mac+'/'+entry.key,{name:name,expires:Date.now()+(name?600000:120000)});});
            while(self.dnsCache.size>256)self.dnsCache.delete(self.dnsCache.keys().next().value);
            self.dnsStatus.textContent=tr('DNS cache updated');self.update(self.root,self.sources,true);
        }).catch(function(){if(generation===self.dnsGeneration){self.dnsRetryAt=Date.now()+30000;self.dnsStatus.textContent=tr('DNS names unavailable');}})
          .finally(function(){self.dnsPending=null;});
        return this.dnsPending;
    },


    vendorText: function(mac) {
        if(parseInt(mac.slice(0,2),16)&2)return tr('Locally administered MAC');
        var inventory=this.sources[8].value || {},vendor=inventory.vendors && inventory.vendors[mac] || this.vendorPrefixes.get(mac.slice(0,8));
        return typeof vendor==='string' && vendor.length<=1024 && !/[\x00-\x1f\x7f]/.test(vendor)?vendor:tr(inventory.vendor_error || this.vendorError?'Local vendor database unavailable':'Unknown vendor');
    },
    lookupVendors: function(now) {
        if(this.vendorPending || now<this.vendorRetryAt || !sourceFresh(this.sources[8],now))return;
        var self=this,wanted=[],prefixes=new Set(),vendors=(this.sources[8].value || {}).vendors || {};
        this.clientRecords.forEach(function(record){
            var mac=clientMac(record.mac);if(!mac || parseInt(mac.slice(0,2),16)&2)return;
            var prefix=mac.slice(0,8),value=vendors[mac];
            if(typeof value==='string' && value.length<=1024)self.vendorPrefixes.set(prefix,value);
            if(self.vendorPrefixes.has(prefix) || prefixes.has(prefix) || wanted.length>=64)return;
            prefixes.add(prefix);wanted.push(mac);
        });
        if(!wanted.length)return;
        this.vendorPending=callVendors(wanted).then(function(reply){
            if(!reply || reply.error || reply.vendor_error || !reply.vendors || typeof reply.vendors!=='object' || Array.isArray(reply.vendors))throw new Error('Vendor database unavailable');
            wanted.forEach(function(mac){var name=reply.vendors[mac];self.vendorPrefixes.set(mac.slice(0,8),typeof name==='string' && name.length<=1024 && !/[\x00-\x1f\x7f]/.test(name)?name:'');});
            while(self.vendorPrefixes.size>1024)self.vendorPrefixes.delete(self.vendorPrefixes.keys().next().value);
            self.vendorError=false;self.update(self.root,self.sources,true);
        }).catch(function(){self.vendorError=true;self.vendorRetryAt=Date.now()+60000;self.update(self.root,self.sources,true);}).finally(function(){self.vendorPending=null;});
        return this.vendorPending;
    },
    updateClientInsights: function(now,repaint) {
        var self=this,grouped=new Map(),allFresh=[2,6,7,8].every(function(index){return sourceFresh(self.sources[index],now);}) && this.clientRecords.length<512 && !(this.sources[8].value || {}).truncated && !((this.sources[6].value || {}).interfaces || []).some(function(entry){return !sourceFresh(entry.stations,now) || !sourceFresh(entry.info,now) || !Array.isArray((entry.stations.value || {}).results) || stationList(entry.stations.value).length!==entry.stations.value.results.length;});
        this.clientRecords.forEach(function(record){
            if(!clientMac(record.mac))return;
            var combined=grouped.get(record.mac) || {name:record.name,addresses:[],paths:[],fresh:true};
            record.addresses.forEach(function(address){var key=addressKey(address);if(key && !combined.addresses.includes(key))combined.addresses.push(key);});
            if(record.path && !combined.paths.includes(record.path))combined.paths.push(record.path);combined.fresh=combined.fresh && record.fresh;
            grouped.set(record.mac,combined);
        });
        function event(entry,type,before,after) {entry.events.push({at:now,type:type,before:before || '',after:after || ''});if(entry.events.length>32)entry.events.shift();}
        if(!repaint){
            grouped.forEach(function(record,mac){
                if(!record.fresh)return;
                var entry=self.clientJournal.get(mac),addresses=record.addresses.sort().join(' / '),path=record.paths.sort().join(' / ');
                if(!entry){entry={mac:mac,name:record.name,first:now,last:now,events:[],present:true,addresses:addresses,path:path};self.clientJournal.set(mac,entry);event(entry,'First observation');}
                else {
                    if(!entry.present)event(entry,'Observed again');
                    if(entry.addresses!==addresses)event(entry,'IP addresses changed',entry.addresses,addresses);
                    if(entry.path!==path)event(entry,'Connection path changed',entry.path,path);
                    entry.name=record.name;entry.last=now;entry.present=true;entry.addresses=addresses;entry.path=path;
                }
            });
            if(allFresh)this.clientJournal.forEach(function(entry,mac){if(!grouped.has(mac) && entry.present){entry.present=false;event(entry,'No longer reported');}});
            if(this.clientJournal.size>512){var oldest=Array.from(this.clientJournal.values()).sort(function(a,b){return a.last-b.last;});oldest.slice(0,this.clientJournal.size-512).forEach(function(entry){self.clientJournal.delete(entry.mac);});}
        }
        var recent=[];
        this.clientJournal.forEach(function(entry){entry.events.forEach(function(value){recent.push({entry:entry,event:value});});});
        recent.sort(function(a,b){return b.event.at-a.event.at;});
        this.journalList.replaceChildren.apply(this.journalList,recent.slice(0,30).map(function(record){return element('li',{},[
            element('time',{datetime:new Date(record.event.at).toISOString()},clock(record.event.at)),element('strong',{},record.entry.name || record.entry.mac),
            element('span',{},tr(record.event.type)),record.event.before || record.event.after ? element('span',{'class':'rmm-dashboard-technical'},record.event.before+' → '+record.event.after) : null]);}));
        if(!recent.length)this.journalList.appendChild(element('li',{},tr('No observations yet')));
        var traffic=(this.sources[8].value || {}).traffic || {status:'unavailable',reason:'Traffic accounting unavailable'},trafficAt=Number(traffic.at)*1000;
        this.clientRecords.forEach(function(record){
            var nodes=record.type==='wifi'?self.stationNodes[record.key]:self.knownNodes[record.key];if(!nodes)return;
            var vendor=self.vendorText(record.mac),entry=self.clientJournal.get(record.mac),count=traffic.clients && traffic.clients[record.mac];
            nodes.title.title=vendor;record.search+=' '+vendor.toLowerCase();
            var valid=count && Number.isSafeInteger(count.rx_bytes) && Number.isSafeInteger(count.tx_bytes) && count.rx_bytes>=0 && count.tx_bytes>=0;
            var fresh=sourceFresh(self.sources[8],now) && traffic.status==='current' && finite(trafficAt) && trafficAt<=now && now-trafficAt<=65000;
            var previous=self.clientTraffic.get(record.mac),rates=valid && fresh && previous && previous.at===trafficAt?previous.rates:null;
            if(valid && fresh && previous && previous.at<trafficAt && trafficAt-previous.at<=65000) {
                var rx=byteRate(count.rx_bytes,previous.rx,(trafficAt-previous.at)/1000),tx=byteRate(count.tx_bytes,previous.tx,(trafficAt-previous.at)/1000);
                if(rx!==null && tx!==null)rates=formatTraffic(rx)+'/s / '+formatTraffic(tx)+'/s';
            }
            if(!repaint){if(valid && fresh){if(!previous || previous.at!==trafficAt)self.clientTraffic.set(record.mac,{at:trafficAt,rx:count.rx_bytes,tx:count.tx_bytes,rates:rates});}else self.clientTraffic.delete(record.mac);}
            var totals=valid && fresh?formatTraffic(count.rx_bytes)+' / '+formatTraffic(count.tx_bytes):tr(valid?'Stale':traffic.status==='current'?'No traffic record':traffic.reason || 'Traffic accounting unavailable');
            var items=[item(tr('Vendor'),vendor),item(tr('Received / sent in accounting period'),totals),item(tr('Accounting average RX / TX'),rates || tr('Unavailable'))];
            if(entry){items.push(item(tr('First observed'),new Date(entry.first).toLocaleString()),item(tr('Last observed'),new Date(entry.last).toLocaleString()));}
            var events=entry ? entry.events.slice(-8).reverse().map(function(value){return element('li',{},[element('time',{datetime:new Date(value.at).toISOString()},clock(value.at)),element('span',{},tr(value.type)),value.before || value.after?element('span',{'class':'rmm-dashboard-technical'},value.before+' → '+value.after):null]);}) : [];
            nodes.body.appendChild(element('section',{'class':'rmm-dashboard-client-insights'},[element('dl',{},items),element('p',{'class':'rmm-dashboard-note'},tr('Accounting may omit offloaded and bridged traffic.')),
                events.length ? element('details',{'class':'rmm-dashboard-disclosure'},[element('summary',{},tr('Observation history')),element('ol',{'class':'rmm-dashboard-journal'},events)]) : null]));
        });
        this.clientTraffic.forEach(function(value,mac){if(!grouped.has(mac))self.clientTraffic.delete(mac);});
    },
    openClient: function(mac) {
        var record=this.clientRecords.find(function(value){return value.mac===mac;});if(!record)return;
        if(record.type==='wifi'){this.openStation(record.key);return;}
        var nodes=this.knownNodes[record.key];
        if(!this.openDetails('known/'+record.key,nodes.title.textContent,nodes.body,nodes.details,document.activeElement)){nodes.details.open=true;nodes.details.scrollIntoView({block:'nearest'});}
    },
    clientPreview: function(macs,label,device) {
        var self=this,items=[];
        Array.from(new Set(macs)).slice(0,3).forEach(function(mac){
            var record=self.clientRecords.find(function(value){return value.mac===mac && (!device || value.key===device+'/'+mac);});if(!record)return;
            var nodes=record.type==='wifi'?self.stationNodes[record.key]:self.knownNodes[record.key];
            // A separate button avoids moving inspector contents into the diagram.
            if(!nodes.previewButton)nodes.previewButton=element('button',{type:'button','class':'btn',click:function(){if(device)self.openStation(device+'/'+mac);else self.openClient(mac);}});
            nodes.previewButton.textContent=record.name;nodes.previewButton.title=(record.addresses || []).join(' / ');nodes.previewButton.setAttribute('aria-label',tr('Details')+': '+record.name+' · '+mac);
            items.push(element('li',{},nodes.previewButton));
        });
        return element('div',{'class':'rmm-dashboard-client-preview'},[label?element('span',{'class':'rmm-dashboard-technical'},label):null,element('ul',{'class':'rmm-dashboard-path-clients'},items)]);
    },

	readPreferences: function() {
		var defaults={version:1,compact:false,period:300000,order:['topology','charts','wireless','clients','details'],visible:{topology:true,charts:true,wireless:true,clients:true,details:true}};
		try {
			var saved=JSON.parse(window.localStorage.getItem('rmm-dashboard-layout-v1'));
			if (!saved || saved.version!==1) return defaults;
			defaults.compact=saved.compact===true;
			if ([60000,300000,900000].includes(saved.period)) defaults.period=saved.period;
			if (Array.isArray(saved.order) && saved.order.length===5 && new Set(saved.order).size===5 && saved.order.every(function(key){return defaults.order.includes(key);})) defaults.order=saved.order;
			defaults.order.forEach(function(key){if(saved.visible && typeof saved.visible[key]==='boolean') defaults.visible[key]=saved.visible[key];});
		} catch (_) { this.storageUnavailable=true; }
		return defaults;
	},
	savePreferences: function() {
		try { window.localStorage.setItem('rmm-dashboard-layout-v1',JSON.stringify(this.preferences)); }
		catch (_) { this.storageUnavailable=true; }
		if(this.preferenceNotice) this.preferenceNotice.hidden=!this.storageUnavailable;
	},
	applyLayout: function() {
		var self=this;
		this.root.classList.toggle('rmm-dashboard-compact',this.preferences.compact);
		this.preferences.order.forEach(function(key){var block=self.blocks[key];if(!block)return;block.hidden=!self.preferences.visible[key];self.blockContainer.appendChild(block);});
	},
	createLayoutPanel: function() {
		var self=this, names={topology:'Network relationships',charts:'Traffic history',wireless:'Wireless',clients:'Clients',details:'Details'};
		var rows=element('div',{'class':'rmm-dashboard-layout-options'});
		function paint() {
			rows.replaceChildren();
			self.preferences.order.forEach(function(key,index){
				var check=element('input',{type:'checkbox',change:function(){self.preferences.visible[key]=check.checked;self.savePreferences();self.applyLayout();}});check.checked=self.preferences.visible[key];
				function move(delta){var order=self.preferences.order;[order[index],order[index+delta]]=[order[index+delta],order[index]];self.savePreferences();self.applyLayout();paint();rows.querySelector('[data-block="'+key+'"] button:not(:disabled)').focus();}
				var up=element('button',{type:'button','class':'btn','aria-label':tr('Move up')+': '+tr(names[key]),click:function(){move(-1);}},tr('Move up'));up.disabled=index===0;
				var down=element('button',{type:'button','class':'btn','aria-label':tr('Move down')+': '+tr(names[key]),click:function(){move(1);}},tr('Move down'));down.disabled=index===4;
				rows.appendChild(element('div',{'data-block':key},[element('label',{},[check,tr(names[key])]),up,down]));
			});
		}
		var compact=element('input',{type:'checkbox',change:function(){self.preferences.compact=compact.checked;self.savePreferences();self.applyLayout();}});compact.checked=this.preferences.compact;
		this.preferenceNotice=element('p',{'class':'rmm-dashboard-note',role:'status'},tr('Preferences unavailable; changes last until this page closes.'));this.preferenceNotice.hidden=!this.storageUnavailable;
		this.layoutPanel=element('details',{id:'rmm-dashboard-layout','class':'rmm-dashboard-disclosure rmm-dashboard-layout',toggle:function(){self.layoutToggle.setAttribute('aria-expanded',self.layoutPanel.open?'true':'false');}},[element('summary',{},tr('Visible blocks and order')),element('label',{'class':'rmm-dashboard-layout-density'},[compact,tr('Compact mode')]),rows,element('button',{type:'button','class':'btn',click:function(){self.preferences={version:1,compact:false,period:300000,order:['topology','charts','wireless','clients','details'],visible:{topology:true,charts:true,wireless:true,clients:true,details:true}};compact.checked=false;self.historyPeriod.value='300000';self.savePreferences();self.applyLayout();paint();self.update(self.root,self.sources,true);}},tr('Reset layout')),this.preferenceNotice]);
		paint();return this.layoutPanel;
	},
	renderKnownClients: function(hosts, now) {
		var self=this, associated=new Set(this.clientRecords.map(function(record){return record.mac;})), seen=new Set();
		Object.keys(hosts).sort().slice(0,512).forEach(function(mac){
			if(associated.has(mac))return;
			var host=hosts[mac],key='dhcp/'+mac,nodes=self.knownNodes[key];seen.add(key);
            self.decorateClient(mac,host,now);
			if(!nodes){
				nodes={root:element('div',{'class':'rmm-dashboard-station'}),summary:element('summary',{}),title:element('span',{'class':'rmm-dashboard-client-name'}),address:element('span',{'class':'rmm-dashboard-client-address'}),band:element('span',{'class':'rmm-dashboard-client-band'}),signal:element('span',{'class':'rmm-dashboard-client-signal'}),link:element('span',{'class':'rmm-dashboard-client-link'}),body:element('div',{})};
				nodes.summary.append(nodes.title,nodes.address,nodes.band,nodes.signal,nodes.link);nodes.details=element('details',{'class':'rmm-dashboard-station-details'},[nodes.summary,nodes.body]);nodes.root.appendChild(nodes.details);
				nodes.summary.addEventListener('click',function(event){if(self.openDetails('known/'+key,nodes.title.textContent,nodes.body,nodes.details,nodes.summary))event.preventDefault();});self.knownNodes[key]=nodes;
			}
			var paths=host.paths || [],neighbors=host.neighbors || [],observed=paths.length || neighbors.length,ports=Array.from(new Set(paths.map(function(path){return path.port;}))),type=paths.length?'wired':neighbors.length?'neighbor':'dhcp';
            var fresh=sourceFresh(self.sources[observed?8:7],now) && (!observed || sourceFresh(self.sources[2],now));
            var status=neighbors.some(function(row){return row.state==='reachable';})?tr('Recently reachable'):neighbors.length && neighbors.every(function(row){return row.state==='permanent';})?tr('Static neighbor'):neighbors.length && neighbors.every(function(row){return row.state==='failed' || row.state==='incomplete';})?tr('Neighbor unreachable'):observed?tr('Cached observation'):tr('Connection unconfirmed');
            if(paths.length && paths.every(function(path){return path.link_up===false;}))status=tr('Port link down');
            nodes.title.textContent=host.name || mac;nodes.address.textContent=clientAddressSummary(host.addresses,'No address');nodes.address.title=host.addresses.join(' / ');nodes.band.textContent=tr(type==='wired'?'Ethernet path':type==='neighbor'?'Neighbor records':'DHCP records');nodes.signal.textContent=fresh?status:tr('Stale');nodes.link.textContent=ports.length===1?tr('Via %s').format(ports[0]):ports.length>1?tr('Port ambiguous'):nodes.band.textContent;nodes.link.setAttribute('data-label',tr('Connection evidence'));nodes.summary.setAttribute('aria-label',tr('Details')+': '+nodes.title.textContent);
			nodes.body.replaceChildren(element('dl',{},[item(tr('MAC address'),mac),item(tr('IP address'),host.addresses.join(' / ') || tr('No address')),...clientIdentityItems(host),item(tr('Connection evidence'),tr(paths.length?'FDB path; direct cable connection unconfirmed':neighbors.length?'Neighbor records':'DHCP lease; connection unconfirmed')),paths.length?item(tr('Bridge / VLAN'),paths.map(function(path){return path.bridge+' / '+(path.vlan==null?'—':path.vlan)+' → '+path.port;}).join('; ')):null,neighbors.length?item(tr('Neighbor state'),neighbors.map(function(row){return row.address+' · '+row.state;}).join('; ')):null]),resultLine(observed?'rmm.dashboard.clients':'luci-rpc.getDHCPLeases',self.sources[observed?8:7]),...(observed && /^DHCP/.test(host.nameSource || '') ? [resultLine('luci-rpc.getDHCPLeases',self.sources[7])] : []));
			nodes.body.appendChild(self.nameEditor('known/'+key,mac));
            self.clientRecords.push({fresh:fresh && sourceFresh(self.sources[7],now),path:ports.join(' / ') || type,type:type,mac:mac,key:key,name:nodes.title.textContent,ssid:nodes.band.textContent,node:nodes.root,addresses:host.addresses,band:'dhcp',signal:null,rate:null,search:[host.name,mac].concat(host.addresses,ports).filter(Boolean).join(' ').toLowerCase()});
		});
		Object.keys(this.knownNodes).forEach(function(key){if(!seen.has(key))delete self.knownNodes[key];});
	},

	openStation: function(key) {
		var nodes = this.stationNodes[key];
		if (!nodes) return;
		if (this.openDetails('station/'+key,nodes.title.textContent,nodes.body,nodes.details,document.activeElement)) return;
		this.clientSearch.value = '';this.clientBand.value = 'all';this.clientSignal.value = 'all';this.filterStations();
		nodes.details.setAttribute('open','');
		if (typeof nodes.summary.focus === 'function') nodes.summary.focus();
		if (typeof nodes.summary.scrollIntoView === 'function') nodes.summary.scrollIntoView({block:'nearest',behavior:'auto'});
	},

	openDetails: function(key,title,body,parent,invoker) {
		if (typeof this.detailDialog.showModal !== 'function') return false;
		var restore=this.activeDetails && this.activeDetails.invoker || invoker;
		this.restoreDetails(false);
		this.activeDetails={key:key,body:body,parent:parent,invoker:restore};
		this.detailTitle.textContent=title;this.detailContent.replaceChildren(body);
		if (!this.detailDialog.open) this.detailDialog.showModal();
		this.detailClose.focus();
		return true;
	},
	restoreDetails: function(focus) {
		var selected=this.activeDetails;if (!selected) return;
		selected.parent.appendChild(selected.body);this.activeDetails=null;
		if (focus!==false) {
			var invoker=selected.invoker && selected.invoker.isConnected ? selected.invoker : this.retry;
			if (typeof invoker.focus==='function') invoker.focus({preventScroll:true});
		}
	},

	renderRelationships: function() {
		var self = this, sources = this.sources, board = sources[0].value || {}, focused = document.activeElement;
		var interfaces = sources[2].value && sources[2].value.interface || [];
		var wireless = sources[6].value && sources[6].value.interfaces || [];
		var seen = Object.create(null), gateways = [], local = [], radios = Object.create(null), branches = [];
		var metadata = [resultLine('system.board',sources[0]),resultLine('network.interface.dump',sources[2]),resultLine('iwinfo.devices',sources[6]),resultLine('luci-rpc.getDHCPLeases',sources[7])];
		function state(result, parentError) {
			var error = parentError || result.error;
			return result.value && (error || !sourceFresh(result,Date.now())) ? tr('Stale') + (error ? ' · ' + failure(error) : '') : error ? failure(error) : tr('Current');
		}
		// Keep native disclosures and their summaries stable during telemetry polls.
		function node(key, label, subtitle, content, status) {
			var record = self.relationshipNodes[key];
			if (!record) {
				record = {root:element('details',{'class':'rmm-dashboard-path-node rmm-dashboard-path-' + (key === 'router' ? 'device' : key.indexOf('ssid/') === 0 ? 'ssid' : key === 'sources' ? 'sources' : 'interface')}),summary:element('summary',{}),label:element('span',{'class':'rmm-dashboard-topology-label'}),subtitle:element('span',{'class':'rmm-dashboard-path-subtitle'}),status:element('span',{'class':'rmm-dashboard-path-status'}),body:element('div',{'class':'rmm-dashboard-path-details'})};
				record.summary.append(dashboardIcon(key === 'router' ? 'router' : key.indexOf('ssid/') === 0 ? 'layout-grid' : key === 'sources' || key === 'ethernet' ? 'terminal-2' : 'network'),record.label,record.subtitle,record.status);
				record.root.append(record.summary,record.body);
				if (key!=='sources' && typeof self.detailDialog.showModal==='function') record.summary.setAttribute('aria-haspopup','dialog');
				if (key!=='sources') record.summary.addEventListener('click',function(event) { if (self.openDetails(key,record.label.textContent,record.body,record.root,record.summary)) event.preventDefault(); });
				self.relationshipNodes[key] = record;
			}
			seen[key] = true;
			record.label.textContent = label;
			record.subtitle.textContent = subtitle;
			record.status.textContent = status || '';
			record.status.classList.toggle('rmm-dashboard-warning',!!status && (status.includes(tr('Stale')) || status.includes(tr('Unavailable')) || status.includes(tr('Access denied')) || status.includes(tr('Disconnected'))));
			record.body.replaceChildren.apply(record.body,content);
			return record.root;
		}
		interfaces.forEach(function(iface) {
			if (!iface || typeof iface.interface !== 'string' || iface.interface === 'loopback') return;
			var next = (Array.isArray(iface.route) ? iface.route : []).filter(function(route) {
				return route && route.mask === 0 && (route.target === '0.0.0.0' || route.target === '::') && typeof route.nexthop === 'string' && route.nexthop.length && route.nexthop !== '0.0.0.0' && route.nexthop !== '::';
			}).map(function(route) { return route.nexthop; });
			var up = typeof iface.up === 'boolean' ? tr(iface.up ? 'Connected' : 'Disconnected') : tr('Unavailable');
			var isUplink = next.length || iface.interface === 'wan' || iface.interface === 'wan6';
			var label = isUplink ? tr('Gateway') + ' · ' + iface.interface : tr('Interface') + ': ' + iface.interface;
			var details = [element('dl',{},[item(tr('Device'),reportedText(iface.l3_device || iface.device)),item(tr('Status'),up),item(tr('IP address'),firstAddress(iface))])];
			if (isUplink) details.push(element('dl',{},[item(tr('Default route gateway'),next.length ? Array.from(new Set(next)).join(' / ') : tr('No default gateway reported'))]));
			var gatewaysUnique=Array.from(new Set(next));
			var entry = node('interface/' + iface.interface,label,isUplink ? next.length ? gatewaysUnique[0] + (gatewaysUnique.length>1 ? ' · +'+(gatewaysUnique.length-1) : '') : tr('No default gateway reported') : reportedText(iface.l3_device || iface.device),details,up + (state(sources[2]) !== tr('Current') ? ' · ' + state(sources[2]) : ''));
			(isUplink ? gateways : local).push(element('li',{},entry));
		});
		wireless.forEach(function(entry) {
			var info = entry.info.value || {}, phy = typeof info.phy === 'string' && info.phy.length ? info.phy : null;
			var key = phy ? 'radio/' + phy : 'interface/' + entry.device;
			if (!radios[key]) radios[key] = {phy:phy,interfaces:[],bands:[]};
			if (!radios[key].bands.includes(bandName(info))) radios[key].bands.push(bandName(info));
			var mode = info.mode === 'Master' ? tr('Access point') : info.mode === 'Client' ? tr('Station mode') : reportedText(info.mode);
			var stations = stationList(entry.stations.value).map(function(station) {
				var nodes = self.stationNodes[entry.device + '/' + station.mac.toUpperCase()];
				if (!nodes) return null;
				if (!nodes.topologyButton) nodes.topologyButton = element('button',{type:'button','class':'btn',click:L.bind(function() { this.openStation(entry.device + '/' + station.mac.toUpperCase()); },self)});
				nodes.topologyButton.textContent = nodes.title.textContent;
				nodes.topologyButton.setAttribute('aria-label',tr('Open station details') + ': ' + nodes.title.textContent + ' · ' + station.mac.toUpperCase());
				return element('li',{},nodes.topologyButton);
			}).filter(Boolean);
			var contents = [element('dl',{},[item(tr('Interface'),entry.device),item(tr('Radio'),reportedText(phy)),item(tr('Band'),bandName(info)),item(tr('Operating mode'),mode),item(tr('Channel'),finite(info.channel) && info.channel > 0 ? String(info.channel) : tr('Unavailable'))]),
				stations.length ? element('ul',{'class':'rmm-dashboard-path-clients'},stations) : element('p',{'class':'rmm-dashboard-source'},entry.stations.error && !entry.stations.value ? failure(entry.stations.error) : entry.stations.value && entry.stations.value.results.length === 0 ? tr('No associated stations') : tr('Unavailable'))];
			var subtitle = bandName(info) + ' · ' + (entry.stations.value ? String(stations.length) + ' · ' + tr('Wi-Fi clients') : failure(entry.stations.error));
			var branch=node('ssid/' + entry.device,reportedText(info.ssid),subtitle,contents,Array.from(new Set([state(entry.info,sources[6].error),state(entry.stations,sources[6].error)])).filter(function(value) { return value !== tr('Current'); }).join(' · '));
            branches.push(element('li',{'class':'rmm-dashboard-path-branch'},[branch,self.clientPreview(stationList(entry.stations.value).map(function(station){return station.mac.toUpperCase();}),null,entry.device)]));
			metadata.push(resultLine('iwinfo.info',entry.info,sources[6].error),resultLine('iwinfo.assoclist',entry.stations,sources[6].error));
		});
		var radioRows = Object.keys(radios).map(function(key) { return element('div',{},[element('h3',{'class':'rmm-dashboard-topology-label'},tr('Radio') + ': ' + reportedText(radios[key].phy)),element('span',{'class':'rmm-dashboard-path-subtitle'},radios[key].bands.join(' / '))]); });
		var router = node('router',reportedText(board.hostname),reportedText(board.model),[element('dl',{},[item(tr('Firmware'),reportedText(board.release && board.release.description)),item(tr('Uptime'),formatDuration(sources[1].value && sources[1].value.uptime))])],Array.from(new Set([state(sources[0]),state(sources[1])])).filter(function(value) { return value !== tr('Current'); }).join(' · '));
		var sourceRecord = node('sources',tr('Sources'),'',[element('p',{'class':'rmm-dashboard-source'},tr('Only reported routes and Wi-Fi associations are shown; physical cabling and Internet reachability are not inferred.'))].concat(radioRows,metadata,resultLine('rmm.dashboard.clients',sources[8])));
		if (!this.localBranches) this.localBranches=element('details',{'class':'rmm-dashboard-local-branches'},[element('summary',{},tr('More interfaces')),element('ul',{'class':'rmm-dashboard-path-list'})]);
		this.localBranches.querySelector('ul').replaceChildren.apply(this.localBranches.querySelector('ul'),local);
		this.localBranches.querySelector('summary').textContent=tr('Local interfaces')+' · '+local.length;
		var observations = sources[8].value || {}, ports = Object.create(null);
		var hosts = clientMap({},observations,sources[2].value || {});
		Object.keys(hosts).forEach(function(mac) {
			(hosts[mac].paths || []).forEach(function(row) {
				if (!ports[row.port]) ports[row.port] = new Set();
				ports[row.port].add(mac);
			});
		});
		var portNames = Object.keys(ports).sort(), ethernetDetails = [element('p',{'class':'rmm-dashboard-note'},tr('FDB path; direct cable connection unconfirmed'))];
		portNames.forEach(function(port) { ethernetDetails.push(element('dl',{},[item(tr('Device'),port),item('MAC',String(ports[port].size))]),element('ul',{'class':'rmm-dashboard-path-clients'},Array.from(ports[port]).slice(0,512).map(function(mac){var record=self.clientRecords.find(function(value){return value.mac===mac;});return element('li',{},element('button',{type:'button','class':'btn',click:function(){self.openClient(mac);}},record?record.name:mac));}))); });
		if (local.length) ethernetDetails.push(this.localBranches);
		ethernetDetails.push(resultLine('rmm.dashboard.clients',sources[8]));
		var ethernet = node('ethernet',tr('Ethernet path'),portNames.length ? portNames.map(function(port) { return port + ' · ' + ports[port].size + ' MAC'; }).join(' / ') : sources[8].value ? tr('No FDB observations') : failure(sources[8].error),ethernetDetails,state(sources[8]) === tr('Current') ? tr('FDB observations') : state(sources[8]));
		var previews=portNames.slice(0,8).map(function(port){return self.clientPreview(Array.from(ports[port]).filter(function(mac){return self.knownNodes['dhcp/'+mac];}),port);});
        branches.unshift(element('li',{'class':'rmm-dashboard-path-branch'},[ethernet].concat(previews)));
		if (!wireless.length) branches.push(element('li',{'class':'rmm-dashboard-path-branch rmm-dashboard-path-empty'},element('p',{'class':'rmm-dashboard-source'},sources[6].error ? failure(sources[6].error) : tr('No wireless interfaces reported'))));
		if (!this.relationshipPath) {
			this.relationshipLines = svgElement('svg',{'class':'rmm-dashboard-path-lines','aria-hidden':'true',focusable:'false'});
			this.relationshipPath = element('div',{'class':'rmm-dashboard-path','role':'group','aria-label':tr('Reported network path')});
			if (typeof window.ResizeObserver === 'function') this.relationshipObserver = new window.ResizeObserver(function() { self.scheduleRelationshipLines(); });
			else window.addEventListener && window.addEventListener('resize',function() { self.scheduleRelationshipLines(); });
		}
		this.relationshipPath.style.setProperty('--path-columns',String(2 + branches.length));
		this.relationshipPath.replaceChildren(this.relationshipLines,
			element('section',{'class':'rmm-dashboard-path-uplink'},gateways.length ? element('ul',{'class':'rmm-dashboard-path-list'},gateways) : element('p',{'class':'rmm-dashboard-source'},sources[2].error ? failure(sources[2].error) : tr('No default gateway reported'))),
			element('section',{'class':'rmm-dashboard-path-router'},router),
			element('ul',{'class':'rmm-dashboard-path-branches rmm-dashboard-path-list'},branches));
		this.slots.topology.replaceChildren(element('p',{'class':'rmm-dashboard-path-caption'},tr('Logical interfaces and Wi-Fi associations')),this.relationshipPath,sourceRecord);
		if (this.relationshipObserver) {
			this.relationshipObserver.disconnect();
			this.relationshipObserver.observe(this.relationshipPath);
			this.relationshipPath.querySelectorAll('.rmm-dashboard-path-node').forEach(function(card) { self.relationshipObserver.observe(card); });
		}
		this.scheduleRelationshipLines();
		Object.keys(this.relationshipNodes).forEach(function(key) { if (!seen[key]) delete self.relationshipNodes[key]; });
		if (focused && focused.isConnected && this.slots.topology.contains(focused) && typeof focused.focus === 'function') focused.focus();
	},


	scheduleRelationshipLines: function() {
		var self = this;
		if (typeof window.requestAnimationFrame !== 'function' || this.relationshipFrame) return;
		this.relationshipFrame = window.requestAnimationFrame(function() { self.relationshipFrame = null; self.drawRelationshipLines(); });
	},

	drawRelationshipLines: function() {
		var path = this.relationshipPath, svg = this.relationshipLines;
		if (!path || !path.isConnected || !path.getBoundingClientRect().width) return;
		var branches = Array.from(path.querySelectorAll('.rmm-dashboard-path-branch'));
		var desktop = path.clientWidth >= (branches.length + 2) * 160 + (branches.length + 1) * 24;
		if (path.getAttribute('data-layout') !== (desktop ? 'desktop' : 'mobile')) path.setAttribute('data-layout',desktop ? 'desktop' : 'mobile');
		var bounds = path.getBoundingClientRect();
		function rect(el) {
			var r = el.getBoundingClientRect();
			return {left:Math.round(r.left-bounds.left),right:Math.round(r.right-bounds.left),top:Math.round(r.top-bounds.top),bottom:Math.round(r.bottom-bounds.top),x:Math.round((r.left+r.right)/2-bounds.left),y:Math.round((r.top+r.bottom)/2-bounds.top)};
		}
		var router = rect(path.querySelector('.rmm-dashboard-path-device > summary'));
		var leaves = branches.map(function(branch) { return rect(branch.querySelector('summary') || branch); });
		var routes = [], gateways = Array.from(path.querySelectorAll('.rmm-dashboard-path-uplink summary'));
		function line(points) { routes.push(svgElement('polyline',{points:points.map(function(p) { return p.join(','); }).join(' ')})); }
		gateways.forEach(function(card) {
			var g = rect(card);
			if (desktop) { var mid = Math.round((g.right+router.left)/2); line([[g.right,g.y],[mid,g.y],[mid,router.y],[router.left,router.y]]); }
			else line([[g.x,g.bottom],[g.x,router.top-12],[router.x,router.top-12],[router.x,router.top]]);
		});
		if (desktop) {
			// The bus stays below every card, including native inline disclosures.
			var bus = Math.max.apply(null,[rect(path.querySelector('.rmm-dashboard-path-device')).bottom].concat(gateways.map(function(card) { return rect(card.parentElement).bottom; }),branches.map(function(branch) { return rect(branch).bottom; }))) + 16;
			line([[router.x,router.bottom],[router.x,bus],[leaves[leaves.length-1].x,bus]]);
			leaves.forEach(function(leaf) { line([[leaf.x,leaf.bottom],[leaf.x,bus]]); });
		} else {
			var trunk = leaves[0].left-16;
			line([[router.x,router.bottom],[router.x,router.bottom+12],[trunk,router.bottom+12],[trunk,leaves[leaves.length-1].y]]);
			leaves.forEach(function(leaf) { line([[trunk,leaf.y],[leaf.left,leaf.y]]); });
		}
		svg.setAttribute('viewBox','0 0 ' + Math.round(bounds.width) + ' ' + Math.round(bounds.height));
		svg.replaceChildren.apply(svg,routes);
	},

	filterStations: function() {
		var query = (this.clientSearch.value || '').trim().toLowerCase(), band = this.clientBand.value || 'all', signal = this.clientSignal.value || 'all';
		var shown = 0, records = this.clientRecords || [];
		records.forEach(function(record) {
			var matchesSignal = signal === 'all' || signal === 'unknown' && record.signal === null || record.signal !== null && (signal === 'strong' && record.signal >= -67 || signal === 'medium' && record.signal < -67 && record.signal >= -75 || signal === 'weak' && record.signal < -75);
			var visible = ((this.clientType.value || 'all') === 'all' || this.clientType.value === record.type) && (!query || record.search.includes(query) || addressKey(query) && (record.addresses || []).some(function(address) { return addressKey(address)===addressKey(query); })) && (band === 'all' || record.band === band) && matchesSignal;
			record.node.hidden = !visible;if (visible) shown++;
		},this);
		var focus=document.activeElement, order=this.clientSort.value || 'name', group=this.clientGroup.value==='ssid';
		var sorted=records.slice().sort(function(a,b) {
			if (group && a.ssid!==b.ssid) return a.ssid.localeCompare(b.ssid);
			if (order==='signal' || order==='rate') {
				var av=a[order],bv=b[order];
				if (av===null && bv!==null) return 1;if (bv===null && av!==null) return -1;
				if (av!==null && bv!==null && av!==bv) return bv-av;
			}
			return a.name.localeCompare(b.name) || a.key.localeCompare(b.key);
		});
		var rows=[],previous=null;
		sorted.forEach(function(record) {
			if (group && !record.node.hidden && previous!==record.ssid) { rows.push(element('h3',{'class':'rmm-dashboard-client-group'},'SSID · '+record.ssid));previous=record.ssid; }
			rows.push(record.node);
		});
		this.wirelessContent.replaceChildren.apply(this.wirelessContent,rows.concat(this.stationMessages || []));
		if (focus && focus.isConnected && this.wirelessContent.contains(focus) && typeof focus.focus==='function') focus.focus({preventScroll:true});
		var count = tr('Shown / total clients') + ': ' + shown + ' / ' + records.length;
		if (this.clientCount.textContent !== count) this.clientCount.textContent = count;
		this.clientEmpty.hidden = shown > 0 || records.length === 0;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
