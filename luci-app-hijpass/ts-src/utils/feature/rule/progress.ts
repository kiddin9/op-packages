import type { UpdateProgress } from '../../backend';

export function formatUpdateProgress(progress: UpdateProgress): string {
    const phases: Record<string, string> = {
        prepare: _('Preparing update...'), metadata: _('Fetching release information...'),
        download: _('Downloading...'), verify: _('Verifying files...'),
        extract: _('Extracting files...'), install: _('Installing files...'),
        restart: _('Restarting service...'),
    };
    const resources: Record<string, string> = {
        gfw_list: _('GFW List'), chn_domain_list: _('CHN Domain List'),
        chn_v4_route: _('CHN IPv4 Route'), chn_v6_route: _('CHN IPv6 Route'),
        geoip: 'GeoIP', geosite: 'GeoSite',
    };
    const parts = [phases[progress.phase] || _('Updating...')];
    if (progress.resource) parts.push(resources[progress.resource] || progress.resource);
    if (progress.phase === 'download' && typeof progress.bytes === 'number') {
        parts.push(progress.bytes >= 1048576 ? (progress.bytes / 1048576).toFixed(1) + ' MiB'
            : Math.round(progress.bytes / 1024) + ' KiB');
    }
    if ((progress.attempt || 0) > 1) parts.push(_('Attempt %s').format(String(progress.attempt)));
    return parts.join(' · ');
}
