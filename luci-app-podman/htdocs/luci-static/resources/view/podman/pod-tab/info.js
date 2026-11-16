'use strict';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.utils as podmanUtil';
'require podman.model.Container as Container';

const DASH = '-';

function joinOrDash(values) {
	return Array.isArray(values) && values.length > 0 ? values.join(', ') : DASH;
}

function valueOrDash(value) {
	return (value === undefined || value === null || value === '') ? DASH : value;
}

return podmanView.tabContent.extend({
	tab: 'info',
	pod: null,

	render(pod) {
		this.pod = pod;

		const sections = [
			this.basicSection(),
			this.configSection(),
			this.resourcesSection(),
			this.networkSection(),
		];

		const labels = this.labelsSection();
		if (labels) sections.push(labels);

		return sections;
	},

	basicSection() {
		const table = new podmanUI.TableList();

		table
			.addRow(_('Name'),    this.pod.getName())
			.addRow(_('ID'),      (this.pod.getID() || '').substring(0, 64))
			.addRow(_('Status'),  this.pod.getStatusBadge())
			.addRow(_('Created'), podmanUtil.format.date(this.pod.getCreatedAt()));

		return E('div', {}, [
			E('h4', {}, _('Basic Information')),
			table.render(),
		]);
	},

	configSection() {
		const table = new podmanUI.TableList();

		const infraId = this.pod.getInfraId();
		const infraIdCell = infraId
			? E('a', { href: L.url('admin/podman/container', infraId) }, infraId.substring(0, 12))
			: DASH;

		table
			.addRow(_('Hostname'),          valueOrDash(this.pod.Hostname))
			.addRow(_('Cgroup parent'),     valueOrDash(this.pod.CgroupParent))
			.addRow(_('Exit policy'),       valueOrDash(this.pod.ExitPolicy))
			.addRow(_('Restart policy'),    valueOrDash(this.pod.RestartPolicy))
			.addRow(_('Shared namespaces'), joinOrDash(this.pod.SharedNamespaces))
			.addRow(_('Infra container'),   infraIdCell);

		return E('div', {}, [
			E('h4', {}, _('Configuration')),
			table.render(),
		]);
	},

	resourcesSection() {
		const table = new podmanUI.TableList();

		const memLimit = this.pod.memory_limit;
		const memLimitDisplay = memLimit > 0 ? podmanUtil.format.bytes(memLimit) : _('Unlimited');

		const cpuQuota = this.pod.cpu_quota;
		const cpuQuotaDisplay = (cpuQuota === undefined || cpuQuota < 0) ? _('Unlimited') : `${cpuQuota} µs`;

		const cpuPeriod = this.pod.cpu_period;
		const cpuPeriodDisplay = cpuPeriod > 0 ? `${cpuPeriod} µs` : DASH;

		table
			.addRow(_('CPU period'), cpuPeriodDisplay)
			.addRow(_('CPU quota'),  cpuQuotaDisplay)
			.addRow(_('CPU shares'), valueOrDash(this.pod.cpu_shares))
			.addRow(_('CPU set'),    valueOrDash(this.pod.cpuset_cpus))
			.addRow(_('Memory limit'), memLimitDisplay);

		return E('div', {}, [
			E('h4', {}, _('Resources')),
			table.render(),
		]);
	},

	networkSection() {
		const table = new podmanUI.TableList();
		const infra = this.pod.InfraConfig || {};

		table
			.addRow(_('Networks'),     joinOrDash(infra.Networks || this.pod.getNetworks()))
			.addRow(_('Static IPv4'),  valueOrDash(infra.StaticIP))
			.addRow(_('Static MAC'),   valueOrDash(infra.StaticMAC))
			.addRow(_('DNS servers'),  joinOrDash(infra.DNSServer))
			.addRow(_('DNS search'),   joinOrDash(infra.DNSSearch))
			.addRow(_('DNS options'),  joinOrDash(infra.DNSOption))
			.addRow(_('Extra hosts'),  joinOrDash(infra.HostAdd))
			.addRow(_('Host network'), infra.HostNetwork ? _('Yes') : _('No'));

		return E('div', {}, [
			E('h4', {}, _('Network')),
			table.render(),
		]);
	},

	labelsSection() {
		const labels = this.pod.getLabels();
		const keys = Object.keys(labels || {});
		if (keys.length === 0) return null;

		const table = new podmanUI.TableList();
		for (const key of keys) {
			table.addRow(key, labels[key]);
		}

		return E('div', {}, [
			E('h4', {}, _('Labels')),
			table.render(),
		]);
	},
});
