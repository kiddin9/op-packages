'use strict';

'require baseclass';
'require ui';
'require form';

'require podman.ui as podmanUI';
'require podman.utils as podmanUtil';

const FormMemoryValue = form.Value.extend({
	placeholder: '512m, 1g, -1',
	validate(_section_id, value) {
		if (!value) return true;
		if (value === '-1' || value === '0') return true;
		if (!/^\d+(?:\.\d+)?\s*[kmg]b?$/i.test(value)) {
			return _('Expecting: %s').format(_('512m, 1g, or -1 for unlimited'));
		}
		return true;
	},
});

/**
 *
 */
const FormDummyValue = form.DummyValue.extend({
	__name__: 'Podman.Form.DummyValue',

	cfgformatter: (cfg, _data) => cfg,
	cfgdatavalue: (_data) => '',
	cfgtt: (_cfg, _data) => '',

	cfgvalue(section_id, set_value) {
		if (section_id == null)
			L.error('TypeError', 'Section ID required');

		const data = this.map.data.data[section_id];
		const dataValue = this.cfgdatavalue(data);

		if (dataValue) {
			return this._renderValue(dataValue, data);
		}

		if (arguments.length === 2 && set_value) {
			this.data ??= {};
			this.data[section_id] = set_value;
		}

		return this._renderValue(this.data?.[section_id], data);
	},

	_renderValue(value, data) {
		const tooltip = this.cfgtt(value, data);
		const formatted = this.cfgformatter(value, data);
		return tooltip ? new podmanUI.Tooltip(formatted, tooltip).render() : formatted;
	},
});

/**
 *
 */
const FormSelectDummyValue = form.DummyValue.extend({
	__name__: 'Podman.Form.SelectDummyValue',

	cfgvalue(sectionId) {
		return new ui.Checkbox(0, { hiddenname: sectionId }).render();
	}
});

/**
 *
 */
const FormLinkDummyValue = FormDummyValue.extend({
	__name__: 'Podman.Form.LinkDummyValue',

	url: '#',
	click: undefined,

	cfgformatter(cfg, model) {
		return E('a', {
			class: 'text-bold',
			href: this.url,
			click: (ev) => {
				if (typeof this.click === 'function') {
					ev.preventDefault();
					this.click(cfg, model);
				}
			}
		}, cfg);
	}
});

/**
 *
 */
const FormDateDummyValue = FormDummyValue.extend({
	__name__: 'Podman.Form.DateDummyValue',
	cfgformatter: podmanUtil.format.date,
});

/**
 *
 */
const FormTimestampDummyValue = FormDateDummyValue.extend({
	__name__: 'Podman.Form.TimestampDummyValue',
	cfgformatter: (value) => podmanUtil.format.date(parseInt(value)),
});

/**
 *
 */
const FormByteDummyValue = FormDummyValue.extend({
	__name__: 'Podman.Form.ByteDummyValue',
	cfgformatter: podmanUtil.format.bytes,
});

const FormEditableField = baseclass.extend({
	__name__: 'Podman.Form.EditableField',
	name: null,
	formField: null,

	__init__(name, formField, onSubmit) {
		this.name = name;
		this.formField = formField;
		if (onSubmit) {
			this.onSubmit = onSubmit;
		}
	},

	render() {
		return E('div', { class: `editable-field editable-field-${this.name}` }, [
			this.formField,
			new podmanUI.Button(
				_('Update'),
				() => this.onSubmit(document.querySelector(`.editable-field-${this.name} [name="${this.name}"]`).value),
				'apply'
			).render()
		]);
	},

	onSubmit(_value) {}
});

return baseclass.extend({
	__name__: 'Podman.Form',

	EditableField: FormEditableField,
	field: {
		MemoryValue: FormMemoryValue,
		DummyValue: FormDummyValue,
		ByteDummyValue: FormByteDummyValue,
		DateDummyValue: FormDateDummyValue,
		LinkDummyValue: FormLinkDummyValue,
		SelectDummyValue: FormSelectDummyValue,
		TimestampDummyValue: FormTimestampDummyValue,
	},
});
