'use strict';
'require baseclass';

/* luci-mod-status requires its includes as 'view.status.include.<name>' and
 * sorts those module names, so the .js suffix takes no part in the ordering.
 * Sorting the raw file names instead would place '20_x.js' and '20_x-y.js' in
 * the opposite order and shift the whole widget-to-section mapping. The
 * comparison stays code-unit based to match the plain Array.sort() upstream
 * uses; localeCompare would reorder names per browser locale. */
function compareWidgets(left, right) {
	left = left.replace(/\.js$/, '');
	right = right.replace(/\.js$/, '');
	return left < right ? -1 : (left > right ? 1 : 0);
}

function parseLayout(text) {
	var result = { order: [], hidden: [] };
	(text || '').replace(/\r/g, '').split('\n').forEach(function(line) {
		var equal = line.indexOf('=');
		if (equal < 1)
			return;
		var key = line.slice(0, equal);
		if (key !== 'order' && key !== 'hidden')
			return;
		result[key] = line.slice(equal + 1).trim().split(/\s+/).filter(Boolean);
	});
	return result;
}

function styles() {
	return E('style', {}, [ `
		.overview-manager-page {
			--ovm-accent: #4f7dff;
			--ovm-accent-2: #8b5cf6;
			--ovm-grad: linear-gradient(135deg, #4f7dff, #8b5cf6);
			--ovm-border: rgba(128, 128, 128, .22);
			--ovm-border-strong: rgba(128, 128, 128, .34);
			--ovm-surface: rgba(128, 128, 128, .06);
			--ovm-surface-2: rgba(128, 128, 128, .11);
			--ovm-muted: rgba(128, 128, 128, .85);
			--ovm-good: #16a34a;
			--ovm-warn: #d97706;
			--ovm-bad: #e11d48;
			--ovm-radius: 16px;
			--ovm-radius-sm: 11px;
			--ovm-shadow: 0 1px 2px rgba(0, 0, 0, .05),
				0 10px 30px -18px rgba(0, 0, 0, .45);
			max-width: 1040px;
		}
		.overview-manager-page * { box-sizing: border-box; }
		.overview-manager-header {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: 1rem;
			margin: 0 0 1.4rem;
		}
		.overview-manager-header h2 {
			margin: 0 0 .35rem;
			font-size: clamp(1.45rem, 2.6vw, 1.85rem);
			font-weight: 750;
			letter-spacing: -.015em;
		}
		.overview-manager-subtitle,
		.overview-manager-muted {
			color: var(--ovm-muted);
			line-height: 1.5;
		}
		.overview-manager-subtitle { margin: 0; max-width: 760px; }
		.overview-manager-section {
			margin: 1rem 0;
			padding: 1.2rem 1.3rem;
			border: 1px solid var(--ovm-border);
			border-radius: var(--ovm-radius);
			background: var(--ovm-surface);
			box-shadow: var(--ovm-shadow);
		}
		.overview-manager-section-head {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: 1rem;
			margin-bottom: 1rem;
		}
		.overview-manager-section-head h3 { margin: 0 0 .3rem; }
		.overview-manager-section-head p {
			margin: 0;
			color: var(--ovm-muted);
			line-height: 1.5;
		}
		.overview-manager-list {
			display: grid;
			gap: .6rem;
		}
		.overview-manager-row {
			display: grid;
			grid-template-columns: auto minmax(0, 1fr) auto auto;
			align-items: center;
			gap: .75rem;
			min-width: 0;
			padding: .75rem .85rem;
			border: 1px solid var(--ovm-border);
			border-radius: var(--ovm-radius-sm);
			background: color-mix(in srgb, currentColor 3%, transparent);
			transition: border-color .14s ease, background .14s ease,
				transform .14s ease, opacity .14s ease;
		}
		.overview-manager-row[draggable="true"] { cursor: grab; }
		.overview-manager-row.dragging { opacity: .45; }
		.overview-manager-row.drag-over {
			border-color: var(--ovm-accent);
			background: color-mix(in srgb, var(--ovm-accent) 9%, transparent);
		}
		.overview-manager-row.hidden-widget { opacity: .64; }
		.overview-manager-handle {
			color: var(--ovm-muted);
			font-size: 1.25rem;
			letter-spacing: -.25rem;
			user-select: none;
		}
		.overview-manager-widget-title {
			display: block;
			overflow: hidden;
			font-weight: 680;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		.overview-manager-widget-file {
			display: block;
			margin-top: .2rem;
			overflow: hidden;
			color: var(--ovm-muted);
			font-family: monospace;
			font-size: .75rem;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		.overview-manager-switch {
			display: inline-flex;
			align-items: center;
			gap: .45rem;
			white-space: nowrap;
			cursor: pointer;
		}
		.overview-manager-switch input { margin: 0; }
		.overview-manager-order-buttons {
			display: inline-flex;
			gap: .3rem;
		}
		.overview-manager-actions {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: .6rem;
			margin-top: 1rem;
		}
		.overview-manager-result { color: var(--ovm-muted); }
		.overview-manager-result.good { color: var(--ovm-good); }
		.overview-manager-result.bad { color: var(--ovm-bad); }
		.overview-manager-note {
			margin-top: 1rem;
			padding: .85rem 1rem;
			border: 1px solid color-mix(in srgb, var(--ovm-warn) 30%, var(--ovm-border));
			border-left: .26rem solid var(--ovm-warn);
			border-radius: var(--ovm-radius-sm);
			background: color-mix(in srgb, var(--ovm-warn) 7%, transparent);
			line-height: 1.5;
		}
		.overview-manager-page .cbi-button {
			padding: .5rem .8rem;
			border: 1px solid var(--ovm-border);
			border-radius: var(--ovm-radius-sm);
			background: var(--ovm-surface-2);
			font-weight: 620;
			line-height: 1.2;
			cursor: pointer;
			transition: transform .12s ease, border-color .14s ease,
				filter .14s ease;
		}
		.overview-manager-page .cbi-button:hover {
			border-color: var(--ovm-border-strong);
			transform: translateY(-1px);
		}
		.overview-manager-page .cbi-button-positive {
			border-color: transparent;
			background-image: var(--ovm-grad);
			color: #fff;
		}
		.overview-manager-page button[disabled] {
			opacity: .55;
			cursor: wait;
			transform: none;
		}
		@media (max-width: 650px) {
			.overview-manager-header,
			.overview-manager-section-head { flex-direction: column; }
			.overview-manager-row {
				grid-template-columns: auto minmax(0, 1fr) auto;
			}
			.overview-manager-order-buttons {
				grid-column: 2 / -1;
				justify-self: end;
			}
		}
	` ]);
}

return baseclass.extend({
	compareWidgets: compareWidgets,
	parseLayout: parseLayout,
	styles: styles
});
