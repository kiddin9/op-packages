'use strict';

'require baseclass';
'require ui';
'require podman.constants as c';

const AbstractInputField = ui.Textfield.extend({
	__name__: 'Podman.UI.AbstractInputField',

	inputType: 'text',

	__init__(value, options) {
		this.value = value;
		this.options = Object.assign({ min: '', max: '' }, options);
	},

	render() {
		const frameEl = E('div', { id: this.options.id });
		const inputEl = E('input', {
			id: this.options.id ? `widget.${this.options.id}` : null,
			name: this.options.name,
			type: this.inputType,
			class: 'cbi-input-text',
			readonly: this.options.readonly ? '' : null,
			disabled: this.options.disabled ? '' : null,
			min: this.options.min,
			max: this.options.max,
			placeholder: this.options.placeholder,
			value: this.value,
		});

		frameEl.appendChild(inputEl);

		return this.bind(frameEl);
	},
});

const UINumberfield = AbstractInputField.extend({
	__name__: 'Podman.UI.Numberfield',
	inputType: 'number',
});

const UIDatefield = AbstractInputField.extend({
	__name__: 'Podman.UI.Datefield',
	inputType: 'date',
});

const UIBase = baseclass.extend({
	__name__: 'Podman.UI',

	alert(text, type, timeLimited) {
		timeLimited = timeLimited === true ? c.NOTIFICATION_TIMEOUT : timeLimited;
		type = type || 'info';

		if (Array.isArray(text) !== true) {
			text = E('p', {}, text);
		}

		if (parseInt(timeLimited) > 0) {
			ui.addTimeLimitedNotification(type.toUpperCase(), text, timeLimited, type);
			return;
		}

		ui.addNotification(type.toUpperCase(), text, type);
	},

	showSpinningModal(title, text) {
		ui.showModal(title, [E('div', { class: 'spinning' }, text)], 'loading-modal');
	},
});

const UITooltip = baseclass.extend({
	__name__: 'Podman.UI.Tooltip',

	node: '',
	tooltip: '',
	options: {},

	__init__(node, tooltip, options) {
		this.node = node || '';
		this.tooltip = tooltip || '';
		this.options = options || {};
	},

	render() {
		const cssClass = 'cbi-tooltip-container';
		const cls = this.options.class ? `${this.options.class} ${cssClass}` : cssClass;
		const options = Object.assign({}, this.options, { class: cls });

		return E('div', options, [
			this.node,
			E('div', { class: 'cbi-tooltip' }, this.tooltip),
		]);
	}
});

const UISecretText = baseclass.extend({
	__name__: 'Podman.UI.SecretText',

	value: '',
	censoredValue: '',
	show: false,

	__init__(value, censoredValue) {
		this.value = value;
		this.censoredValue = censoredValue;
	},

	render() {
		const me = this;

		return new UITooltip(
			me.censoredValue,
			_('Click to reveal/hide value'),
			{
				class: 'tooltip',
				click() {
					if (me.show) {
						me.show = false;
						this.childNodes[0].nodeValue = me.censoredValue;

						return;
					}

					me.show = true;
					this.childNodes[0].nodeValue = me.value;
				},
			}
		).render();
	}
});

const UIButton = baseclass.extend({
	__name__: 'Podman.UI.Button',

	__init__(text, href, cssClass, tooltip) {
		this.text = text;
		this.href = href;
		this.cssClass = cssClass;
		this.tooltip = tooltip;
	},

	render() {
		const attrs = {
			class: this.cssClass ? 'cbi-button cbi-button-' + this.cssClass : 'cbi-button',
			click: typeof this.href === 'function' ? this.href : (ev) => {
				ev.preventDefault();
				window.location.href = this.href;
			}
		};

		if (this.tooltip) {
			attrs.title = this.tooltip;
		}

		return E('button', attrs, this.text || '');
	}
});

const UIButtonNew = baseclass.extend({
	__name__: 'Podman.UI.ButtonNew',

	__init__(text, options) {
		this.options = Object.assign({
			text: text || '',
			// class: ''
			type: '',
			href: '',
			click: () => { },
			tooltip: '',
		}, options);
	},

	render() {
		const click = this.options.href
			? ui.createHandlerFn(this, (event) => {
				event.preventDefault();
				window.location.href = this.options.href;
			})
			: this.options.click;

		const button = E('button', {
			class: `cbi-button cbi-button-${this.options.type}`,
			click,
		}, this.options.text);

		if (this.options.tooltip) {
			return new UITooltip(button, this.options.tooltip).render();
		}

		return button;
	}
});

const UIJsonArea = baseclass.extend({
	__name__: 'Podman.UI.JsonArea',

	__init__(data) {
		this.data = data || this.data;
	},

	render() {
		const el = E('pre', { class: 'json-area' });
		const json = JSON.stringify(this.data, null, 2);
		const nodes = [];
		let last = 0;
		json.replace(
			/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
			(match, _p1, _p2, _p3, _p4, offset) => {
				if (offset > last)
					nodes.push(document.createTextNode(json.slice(last, offset)));
				let cls = 'number';
				if (/^"/.test(match))          cls = /:$/.test(match) ? 'key' : 'string';
				else if (/true|false/.test(match)) cls = 'boolean';
				else if (/null/.test(match))       cls = 'null';
				nodes.push(E('span', { 'class': cls }, match));
				last = offset + match.length;
			}
		);
		if (last < json.length)
			nodes.push(document.createTextNode(json.slice(last)));
		for (const node of nodes) el.appendChild(node);
		return el;
	},
});

const UIBashCodeArea = baseclass.extend({
	__name__: 'Podman.UI.BashCodeArea',

	code: '',

	__init__(code) {
		this.code = code || this.code;
	},

	render() {
		const el = E('pre', { class: 'code-area bash' });
		const code = this.code || '';
		const nodes = [];
		let last = 0;
		const bashRegex = /(#[^\n]*)|("(?:\\.|[^\\"])*"|'(?:\\.|[^\\'])*')|(\$\w+|\$\{[^}]+\})|\b(if|then|else|elif|fi|case|esac|for|while|do|done|in|break|continue|exit|return|stop_service|start_service)\b|(\b\d+\b)/g;
		code.replace(bashRegex, (match, comment, string, variable, keyword, number, offset) => {
			if (offset > last)
				nodes.push(document.createTextNode(code.slice(last, offset)));
			let cls = null;
			if (comment)  cls = 'comment';
			else if (string)   cls = 'string';
			else if (variable) cls = 'variable';
			else if (keyword)  cls = 'keyword';
			else if (number)   cls = 'number';
			nodes.push(cls ? E('span', { 'class': cls }, match) : document.createTextNode(match));
			last = offset + match.length;
		});
		if (last < code.length)
			nodes.push(document.createTextNode(code.slice(last)));
		for (const node of nodes) el.appendChild(node);
		return el;
	},
});

/**
 * Scrolling text log for streaming output. Each append() is one logical
 * update: lines containing CR overwrite the last line (Podman pull progress
 * uses CR to refresh "Copying blob X 50%"); plain lines append. Sticky
 * auto-scroll: jumps to bottom on append unless the user scrolled up.
 */
const UIStreamLog = baseclass.extend({
	__name__: 'Podman.UI.StreamLog',

	maxLines: 2000,
	autoScroll: true,

	__init__(opts) {
		opts = opts || {};
		if (typeof opts.maxLines === 'number')  this.maxLines  = opts.maxLines;
		if (typeof opts.autoScroll === 'boolean') this.autoScroll = opts.autoScroll;
		this._container    = E('div', { class: 'podman-stream-log' });
		this._lastLineNode = null;
		this._lineCount    = 0;
	},

	append(text) {
		if (text == null) return this;
		const stripped = String(text).replace(/\n+$/, '');
		if (!stripped) return this;

		const stick = this.autoScroll && this._isAtBottom();
		const cr    = stripped.lastIndexOf('\r');
		const isProgress = cr >= 0;
		const display    = isProgress ? stripped.slice(cr + 1) : stripped;

		if (isProgress && this._lastLineNode) {
			this._lastLineNode.textContent = display;
		} else {
			this._appendLine(display);
		}

		if (stick) this._container.scrollTop = this._container.scrollHeight;
		return this;
	},

	appendBlock(lines) {
		if (Array.isArray(lines)) for (const l of lines) this.append(l);
		return this;
	},

	clear() {
		while (this._container.firstChild) this._container.removeChild(this._container.firstChild);
		this._lastLineNode = null;
		this._lineCount = 0;
		return this;
	},

	render() {
		return this._container;
	},

	_appendLine(text) {
		const node = E('div', { class: 'log-line' }, [text || ' ']);
		this._container.appendChild(node);
		this._lastLineNode = node;
		this._lineCount++;
		while (this._lineCount > this.maxLines && this._container.firstChild) {
			const removed = this._container.firstChild;
			this._container.removeChild(removed);
			this._lineCount--;
			if (this._lastLineNode === removed) this._lastLineNode = this._container.lastChild;
		}
	},

	_isAtBottom() {
		const el = this._container;
		return (el.scrollHeight - el.scrollTop - el.clientHeight) < 5;
	}
});

/**
 * Table builder with header and row chaining.
 */
const UITable = baseclass.extend({
	__name__: 'Podman.UI.Table',

	options: { class: 'table' },

	headers: [],
	rows: [],

	__init__(options) {
		this.headers = [];
		this.rows = [];

		const baseClass = this.options.class;
		this.options = Object.assign({}, this.options, options);
		if (options?.class) this.options.class = `${baseClass} ${options.class}`;
	},

	addHeader(header, options) {
		this.headers.push({
			inner: header,
			options: Object.assign({ class: 'th' }, options || {}),
		});

		return this;
	},

	setHeaders(headers) {
		this.headers = headers;

		return this;
	},

	addRow(cells, options) {
		this.rows.push({
			cells,
			options: Object.assign({ class: 'tr' }, options || {}),
		});

		return this;
	},

	setRows(rows) {
		this.rows = rows;

		return this;
	},

	render() {
		let headerRow = '';

		if (Array.isArray(this.headers) && this.headers.length > 0) {
			headerRow = E('tr', { class: 'tr table-titles' },
				this.headers.map((header) => E('th', header.options, header.inner))
			);
		}

		let rows = '';

		if (Array.isArray(this.rows) && this.rows.length > 0) {
			rows = this.rows.map((row) => E('tr', row.options,
				row.cells.map((cell) => E('td', Object.assign({ class: 'td' }, cell.options || {}), cell.inner))
			));
		}

		return E('table', this.options, [headerRow].concat(rows));
	}
});

const UITableList = UITable.extend({
	__name__: 'Podman.UI.TableList',

	options: { class: 'table table-list' },

	addRow(label, value, rowOptions) {
		return this.super('addRow', [[
			{ inner: label },
			{ inner: value }
		], rowOptions]);
	},
});

/**
 * Tabbed interface using LuCI tabs API.
 */
const UITabs = baseclass.extend({
	__name__: 'Podman.UI.Tabs',

	tabs: [],
	activeTab: null,

	__init__(activeTab) {
		this.tabs = [];
		this.activeTab = activeTab || null;
	},

	addTab(id, title, content, active) {
		this.tabs.push({
			id,
			title,
			content,
			active: active || false
		});

		return this;
	},

	render() {
		const tabPanes = this.tabs.map((tab, index) => {
			const isActive = tab.active || (!this.activeTab && index === 0) || (this.activeTab === tab.id);

			return E('div', {
				class: 'tab-pane',
				'data-tab': tab.id,
				'data-tab-title': tab.title,
				'data-tab-active': isActive ? 'true' : null
			}, [tab.content || E('div', { class: 'cbi-section' }, E('div', { class: 'cbi-section-node' }))]);
		});

		const tabContainer = E('div', { class: 'cbi-section' }, [
			E('div', { class: 'cbi-section-node' }, [
				E('div', { class: 'tab-panes' }, tabPanes)
			])
		]);

		requestAnimationFrame(() => {
			const panes = tabContainer.querySelectorAll('.tab-pane');
			ui.tabs.initTabGroup(panes);
		});

		return tabContainer;
	}
});

const UIModal = baseclass.extend({
	__name__: 'Podman.UI.Modal',

	title: '',
	content: null,
	extraClasses: [],

	__init__(title, content, extraClasses) {
		this.title = title || this.title;
		this.content = content || this.content;
		this.extraClasses = extraClasses || this.extraClasses;
	},

	render() {
		ui.showModal(this.title, [
			E('div', {}, this.getContent()),
			E('div', { class: 'd-flex justify-end mt-sm gap-5' }, this.getButtons()),
		], ...this.extraClasses);
	},

	getContent() {
		return this.content;
	},

	getButtons() {
		const buttons = [];

		if (typeof this.handleClose === 'function') {
			buttons.push(this.getCloseButton());
		}

		if (typeof this.handleSubmit === 'function') {
			buttons.push(this.getOkButton());
		}

		return buttons;
	},

	async handleClose() {
		ui.hideModal();
	},

	async handleSubmit() {
		ui.hideModal();
	},

	getOkButton() {
		return new UIButtonNew(_('OK'), {
			click: ui.createHandlerFn(this, 'handleSubmit'),
			type: 'positive',
		}).render();
	},

	getCloseButton() {
		return new UIButtonNew(_('Close'), {
			click: ui.createHandlerFn(this, 'handleClose'),
			type: 'negative',
		}).render();
	},
});

const PodmanUI = UIBase.extend({
	__name__: 'Podman.UI',

	Modal: UIModal,

	Button: UIButton,
	ButtonNew: UIButtonNew,
	// MultiButton: UIMultiButton,

	Numberfield: UINumberfield,
	Datefield: UIDatefield,

	SecretText: UISecretText,

	JsonArea: UIJsonArea,
	BashCodeArea: UIBashCodeArea,

	Table: UITable,
	TableList: UITableList,
	Tabs: UITabs,
	Tooltip: UITooltip,

	StreamLog: UIStreamLog,
});

return PodmanUI;
