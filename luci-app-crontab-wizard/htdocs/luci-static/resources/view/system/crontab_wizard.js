'use strict';
'require baseclass';
'require form';
'require ui';
'require view';
'require fs';
'require tools.widgets as widgets';

/*

  Copyright 2025 Rafał Wabik - IceG - From eko.one.pl forum
  
  MIT License
  
*/

function popTimeout(a, message, timeout, severity) {
  ui.addTimeLimitedNotification(a, message, timeout, severity)
}

return view.extend({
  colors: {
    light: {
      minute: '#fdd2d6',
      hour:   '#cfead1',
      day:    '#ffd8ad',
      month:  '#bbdefb',
      weekday:'#e1bee7'
    },
    dark: {
      minute: '#5b2f35',
      hour:   '#2f4732',
      day:    '#4a3828',
      month:  '#30475e',
      weekday:'#3a2f41'
    }
  },

  getCurrentColors: function() {
    const isDarkMode = document.documentElement.getAttribute('data-darkmode') === 'true';
    return isDarkMode ? this.colors.dark : this.colors.light;
  },

  getBadgeTextColor: function() {
    const isDarkMode = document.documentElement.getAttribute('data-darkmode') === 'true';
    return isDarkMode ? '#ffffff' : '#111111';
  },

  _weekdayNames: function(){
    return [
      _('Sunday'), _('Monday'), _('Tuesday'), _('Wednesday'), _('Thursday'), _('Friday'), _('Saturday')
    ];
  },
  _monthNames: function(){
    return [
      '', _('January'), _('February'), _('March'), _('April'), _('May'), _('June'),
      _('July'), _('August'), _('September'), _('October'), _('November'), _('December')
    ];
  },

  _formatRange: function(a, b){
    return a + '-' + b;
  },

  _parseSegments: function(expr, base) {
    if (!expr || expr === '*') return { type: 'any' };
    if (/^\*\/\d+$/.test(expr)) return { type: 'step', step: parseInt(expr.slice(2), 10) };

    const segs = [];
    expr.split(',').forEach(function(part){
      const m = part.match(/^(\d+)-(\d+)$/);
      if (m) {
        const a = parseInt(m[1],10), b = parseInt(m[2],10);
        segs.push({ kind:'range', a:a, b:b });
      } else {
        const v = parseInt(part,10);
        if (!isNaN(v)) segs.push({ kind:'single', v:v });
      }
    });
    return { type:'list', segs:segs };
  },

  _expand: function(parsed, minVal, maxVal) {
    if (parsed.type === 'any') return null;
    const vals = new Set();
    if (parsed.type === 'step') {
      const n = parsed.step;
      for (let i=minVal; i<=maxVal; i+=n) vals.add(i);
      return Array.from(vals).sort(function(a,b){ return a-b; });
    }
    parsed.segs.forEach(function(s){
      if (s.kind==='single') { if (s.v>=minVal && s.v<=maxVal) vals.add(s.v); }
      else { for (let i=s.a; i<=s.b; i++) if (i>=minVal && i<=maxVal) vals.add(i); }
    });
    return Array.from(vals).sort(function(a,b){ return a-b; });
  },

  _humanList: function(parsed, labeller) {
    if (parsed.type === 'any')  return null;
    if (parsed.type === 'step') return null;
    const self = this;
    const items = parsed.segs.map(function(s){
      if (s.kind==='single') return labeller(s.v, false);
      return self._formatRange(labeller(s.a,false), labeller(s.b,true));
    });
    return items.join(', ');
  },

  _pluralMin:  function(n){ return (n===1) ? _('minute')  : _('minutes'); },
  _pluralHour: function(n){ return (n===1) ? _('hour')    : _('hours');   },
  _pluralDay:  function(n){ return (n===1) ? _('day')     : _('days');    },

  _pad2: function(n){ return (n<10 ? '0'+n : ''+n); },

  _enumerateTimes: function(minExpr, hourExpr) {
    const pm = this._parseSegments(minExpr,0), ph = this._parseSegments(hourExpr,0);
    const mins  = (pm.type==='any' || pm.type==='step') ? null : this._expand(pm,0,59);
    const hours = (ph.type==='any' || ph.type==='step') ? null : this._expand(ph,0,23);
    if (!mins || !hours) return null;

    const combos = [];
    for (let i=0;i<hours.length;i++){
      for (let j=0;j<mins.length;j++){
        combos.push(this._pad2(hours[i])+':'+this._pad2(mins[j]));
      }
    }
    if (combos.length===1) return { single: combos[0], list: null };
    if (combos.length>0 && combos.length<=12) return { single: null, list: combos.join(', ') };
    return null;
  },

  _timeOfDayPhrase: function(minExpr, hourExpr) {
    const pm = this._parseSegments(minExpr,0), ph = this._parseSegments(hourExpr,0);

    const times = this._enumerateTimes(minExpr, hourExpr);
    if (times) {
      if (times.single) return _('at time: %s').format(times.single);
      return _('at times: %s').format(times.list);
    }

    let parts = [];

    // Minutes
    if (pm.type==='step') {
      parts.push(_('runs every %d %s').format(pm.step, this._pluralMin(pm.step)));
    } else if (pm.type==='list') {
      const list = this._humanList(pm, function(n){ return String(n); });
      if (list) parts.push(_('in minutes: %s').format(list));
    }

    // Hours
    if (ph.type==='step') {
      parts.push(_('runs every %d %s').format(ph.step, this._pluralHour(ph.step)));
    } else if (ph.type==='list') {
      const listH = this._humanList(ph, function(n){ return String(n); });
      if (listH) parts.push(_('in hours: %s').format(listH));
    }

    return parts.length > 0 ? parts.join('; ') : null;
  },

  _descDayOfMonth: function(expr){
    if (expr === '*') return null;
    const p = this._parseSegments(expr,1);

    if (p.type==='step') {
      return _('runs every %d %s of the month').format(p.step, this._pluralDay(p.step));
    }

    const listStr = this._humanList(p, function(n){ return String(n); });
    if (!listStr) return null;
    return _('on day(s): %s').format(listStr);
  },

  _descMonth: function(expr){
    if (expr === '*') return null;
    const p = this._parseSegments(expr,1);
    if (p.type==='step') return _('runs every %d month(s)').format(p.step);
    const months = this._monthNames();
    const list = this._humanList(p, function(n){ return months[n]; });
    return list ? _('in month(s): %s').format(list) : null;
  },

  _descWeekday: function(expr){
    if (expr === '*') return null;
    const p = this._parseSegments(expr,0);
    if (p.type==='step') return _('runs every %d day of the week').format(p.step);
    const days = this._weekdayNames();
    const list = this._humanList(p, function(n){ return days[n===7?0:n]; });
    return list ? _('on weekday(s): %s').format(list) : null;
  },

  _describeCron: function(minute, hour, day, month, weekday, command){
    const parts = [];

    const isMinuteChanged = minute !== '*';
    const isHourChanged = hour !== '*';
    const isDayChanged = day !== '*';
    const isMonthChanged = month !== '*';
    const isWeekdayChanged = weekday !== '*';

    // Nothing changed
    if (!isMinuteChanged && !isHourChanged && !isDayChanged && !isMonthChanged && !isWeekdayChanged) {
      const prefix = command ? _('Command "%s" ').format(command) : _('Command');
      return prefix + ' ';
    }

    // Time (hour and minute)
    const timePart = this._timeOfDayPhrase(minute, hour);
    if (timePart) parts.push(timePart);

    // Month
    const monthPart = this._descMonth(month);
    if (monthPart) parts.push(monthPart);

    // Day of month
    const dayPart = this._descDayOfMonth(day);
    if (dayPart) parts.push(dayPart);

    // Day of week
    const weekdayPart = this._descWeekday(weekday);
    if (weekdayPart) parts.push(weekdayPart);

    const prefix = command ? _('Command "%s" will run').format(command) : _('Command will run');
    
    if (parts.length === 0) {
      return prefix + '.';
    }
    
    return prefix + ' ' + parts.join('; ') + '.';
  },

  addStyles: function() {
    const style = document.createElement('style');
    style.type = 'text/css';
    style.textContent = `
    .ifacebox .span-40  { grid-column: span 2; }
    .ifacebox .span-80  { grid-column: span 4; }
    .ifacebox .span-160 { grid-column: span 8; }
    .ifacebox .span-320 { grid-column: span 8; }
    @media (max-width: 560px) {
      .ifacebox .span-320 { grid-column: span 8 !important; }
    }
    :root {
      --tile-free: #eceff1;
      --tile-active: #34c759;
      --tile-text: #263238;
      --tile-text-on-active: #ffffff;
      --iface-head-bg: #f8f8f8;
      --app-id-font-color: #454545;
      --border-color-soft: #eceff1;
      --border-color-medium: #cfd8dc;
      --border-color-strong: #90a4ae;
      --tile-border: #b0bec5;
      --cron-minute: #fdd2d6;
      --cron-hour: #cfead1;
      --cron-day: #ffd8ad;
      --cron-month: #bbdefb;
      --cron-weekday: #e1bee7;
      --badge-text: #111111;
      --badge-border: rgba(0,0,0,.15);
      --badge-shadow: rgba(0,0,0,.06);

      --multiselect-bg: var(--border-color-low);
      --multiselect-text: #263238;
      --multiselect-border: #cfd8dc;
      --multiselect-selected-bg: #e3f2fd;
      --multiselect-selected-text: #1565c0;
      --multiselect-hover-bg: #f5f5f5;
    }
    :root[data-darkmode="true"] {
      --tile-free: #2a2f34;
      --tile-active: #2ecc71;
      --tile-text: #e5e7eb;
      --tile-text-on-active: #ffffff;
      --iface-head-bg: #1f2327;
      --border-color-soft: #2a2f34;
      --border-color-medium: #3a4146;
      --border-color-strong: #6b737a;
      --app-id-font-color: #f6f6f6;
      --tile-border: #54616b;

      --cron-minute: #8b4f5a;
      --cron-hour:   #4f6b52;
      --cron-day:    #7a5838;
      --cron-month:  #4a6b8e;
      --cron-weekday:#5a4f71;

      --badge-text: #ffffff;
      --badge-border: rgba(255,255,255,.2);
      --badge-shadow: rgba(0,0,0,.35);

      --multiselect-bg: var(--border-color-low);
      --multiselect-text: #e5e7eb;
      --multiselect-border: #3a4146;
      --multiselect-hover-bg: #3a4146;
    }

    .cron-minute-head { background: var(--cron-minute) !important; }
    .cron-hour-head   { background: var(--cron-hour)   !important; }
    .cron-day-head    { background: var(--cron-day)    !important; }
    .cron-month-head  { background: var(--cron-month)  !important; }
    .cron-weekday-head{ background: var(--cron-weekday)!important; }

    :root .cron-minute-head { color: #263238 !important; }
    :root .cron-hour-head   { color: #263238 !important; }
    :root .cron-day-head    { color: #263238 !important; }
    :root .cron-month-head  { color: #263238 !important; }
    :root .cron-weekday-head{ color: #263238 !important; }

    :root[data-darkmode="true"] .cron-minute-head { color: #ffcdd2 !important; }
    :root[data-darkmode="true"] .cron-hour-head   { color: #c8e6c9 !important; }
    :root[data-darkmode="true"] .cron-day-head    { color: #ffe0b2 !important; }
    :root[data-darkmode="true"] .cron-month-head  { color: #bbdefb !important; }
    :root[data-darkmode="true"] .cron-weekday-head{ color: #e1bee7 !important; }

    .ifacebox .tile { font-weight: normal; }

    .cron-badge {
      display: inline-block;
      padding: 3px 6px;
      border-radius: 6px;
      border: 1px solid var(--badge-border);
      box-shadow: 0 1px 1px var(--badge-shadow), inset 0 1px 0 rgba(255,255,255,.08);
      font-weight: 600;
      letter-spacing: .2px;
    }

    .cbi-input-text { text-align: left !important; }
    #cron_preview_text { text-align: left !important; }

    #cron_preview {
      height: 40px !important;
      min-height: 40px !important;
      max-height: 40px !important;
      background-color: var(--multiselect-bg) !important;
      border: 1px solid var(--badge-border);
      line-height: 26px;
      display: flex;
      align-items: center;
    }

    .cron-actions {
      margin-top: 1em;
      display: flex;
      justify-content: flex-end;
      gap: .6em;
    }

    .cron-multiselect {
      width: 100%;
      min-height: 140px;
      background-color: var(--multiselect-bg) !important;
      color: var(--multiselect-text) !important;
      border: 1px solid var(--multiselect-border) !important;
      border-radius: 4px;
      padding: 4px;
      font-family: inherit;
      font-size: 13px;
      line-height: 1.4;
      outline: none;
      transition: border-color 0.2s, box-shadow 0.2s;
    }

    .cron-multiselect:focus {
      border-color: var(--tile-active) !important;
      box-shadow: 0 0 0 2px rgba(52, 199, 89, 0.2) !important;
    }

    :root:not([data-darkmode="true"]) .cron-multiselect option {
      padding: 4px 8px; border: none; outline: none;
      background-color: revert !important; color: revert !important;
    }
    :root:not([data-darkmode="true"]) .cron-multiselect option:not(:checked):hover {
      background-color: var(--multiselect-hover-bg) !important;
    }

    /* Dark mode */
    :root[data-darkmode="true"] .cron-multiselect option {
      background-color: var(--multiselect-bg) !important;
      color: var(--multiselect-text) !important;
      padding: 4px 8px; border: none; outline: none;
    }
    :root[data-darkmode="true"] .cron-multiselect option:hover {
      background-color: var(--multiselect-hover-bg) !important;
    }
    :root[data-darkmode="true"] #minute_select  option:checked { background-color: var(--cron-minute)  !important; color: #ffffff !important; font-weight: 600; }
    :root[data-darkmode="true"] #hour_select    option:checked { background-color: var(--cron-hour)    !important; color: #ffffff !important; font-weight: 600; }
    :root[data-darkmode="true"] #day_select     option:checked { background-color: var(--cron-day)     !important; color: #ffffff !important; font-weight: 600; }
    :root[data-darkmode="true"] #month_select   option:checked { background-color: var(--cron-month)   !important; color: #ffffff !important; font-weight: 600; }
    :root[data-darkmode="true"] #weekday_select option:checked { background-color: var(--cron-weekday) !important; color: #ffffff !important; font-weight: 600; }

    :root[data-darkmode="true"] #minute_select  option:checked:hover { background-color: var(--cron-minute)  !important; color: #ffffff !important; }
    :root[data-darkmode="true"] #hour_select    option:checked:hover { background-color: var(--cron-hour)    !important; color: #ffffff !important; }
    :root[data-darkmode="true"] #day_select     option:checked:hover { background-color: var(--cron-day)     !important; color: #ffffff !important; }
    :root[data-darkmode="true"] #month_select   option:checked:hover { background-color: var(--cron-month)   !important; color: #ffffff !important; }
    :root[data-darkmode="true"] #weekday_select option:checked:hover { background-color: var(--cron-weekday) !important; color: #ffffff !important; }

    :root[data-darkmode="true"] .cron-multiselect::-webkit-scrollbar { width: 8px; }
    :root[data-darkmode="true"] .cron-multiselect::-webkit-scrollbar-track { background: #1a1e22; border-radius: 4px; }
    :root[data-darkmode="true"] .cron-multiselect::-webkit-scrollbar-thumb { background: #4a5158; border-radius: 4px; }
    :root[data-darkmode="true"] .cron-multiselect::-webkit-scrollbar-thumb:hover { background: #5a6168; }

    :root .cron-multiselect::-webkit-scrollbar { width: 8px; }
    :root .cron-multiselect::-webkit-scrollbar-track { background: #f1f1f1; border-radius: 4px; }
    :root .cron-multiselect::-webkit-scrollbar-thumb { background: #c1c1c1; }
    :root .cron-multiselect::-webkit-scrollbar-thumb:hover { background: #a8a8a8; }
    `;
    document.head.appendChild(style);
  },

  badge: function(bg, content){
    const color = this.getBadgeTextColor();
    return '<span class="cron-badge" style="background:' + bg + '; color:' + color + '">' + content + '</span>';
  },

  getSelectedValues: function(selectId) {
    const sel = document.getElementById(selectId);
    if (!sel) return [];
    const vals = Array.from(sel.selectedOptions || [])
      .map(function(o){ return o.value; })
      .filter(function(v){ return v !== undefined && v !== null; });
    return vals;
  },

  normalizeSelection: function(values) {
    if (!values || values.length === 0) return ['*'];
    if (values.includes('*')) return ['*'];
    const uniq = Array.from(new Set(values.map(function(v){ return parseInt(v, 10); })));
    return uniq.sort(function(a,b){ return a-b; }).map(function(x){ return String(x); });
  },

  compressValues: function(values) {
    if (!values || values.length === 0) return '*';
    if (values.length === 1) return values[0];

    const nums = values.map(function(v){ return parseInt(v,10); });
    let parts = [];
    let start = nums[0];
    let prev = nums[0];

    for (let i = 1; i < nums.length; i++) {
      const cur = nums[i];
      if (cur === prev + 1) { prev = cur; continue; }
      parts.push(start === prev ? String(start) : (start + '-' + prev));
      start = prev = cur;
    }
    parts.push(start === prev ? String(start) : (start + '-' + prev));
    return parts.join(',');
  },

  buildCronField: function(selectId, checkboxId /*, isPeriod*/) {
    const valuesRaw = this.getSelectedValues(selectId);
    const values = this.normalizeSelection(valuesRaw);

    if (checkboxId) {
      const cb = document.getElementById(checkboxId);
      if (cb && cb.checked) {
        const sel = values[0];
        if (sel === '*' || sel === undefined) return '*';
        return '*/' + sel;
      }
    }
    if (values.length === 0 || values[0] === '*') return '*';
    return this.compressValues(values);
  },

  updateCronPreview: function() {
    const minute  = this.buildCronField('minute_select',  'minute_checkbox',  true);
    const hour    = this.buildCronField('hour_select',    'hour_checkbox',    true);
    const day     = this.buildCronField('day_select',     'day_checkbox',     true);
    const month   = this.buildCronField('month_select');
    const weekday = this.buildCronField('weekday_select');

    const cmdInput = document.getElementById('cron_command_input');
    const command = cmdInput ? (cmdInput.value || '') : '';

    const isMinuteChanged  = minute  !== '*';
    const isHourChanged    = hour    !== '*';
    const isDayChanged     = day     !== '*';
    const isMonthChanged   = month   !== '*';
    const isWeekdayChanged = weekday !== '*';
    const isCommandChanged = command !== '';

    const colors = this.getCurrentColors();

    let cronHtml = '';
    cronHtml += isMinuteChanged  ? this.badge(colors.minute,  minute)  : minute;  cronHtml += ' ';
    cronHtml += isHourChanged    ? this.badge(colors.hour,    hour)    : hour;    cronHtml += ' ';
    cronHtml += isDayChanged     ? this.badge(colors.day,     day)     : day;     cronHtml += ' ';
    cronHtml += isMonthChanged   ? this.badge(colors.month,   month)   : month;   cronHtml += ' ';
    cronHtml += isWeekdayChanged ? this.badge(colors.weekday, weekday) : weekday; cronHtml += ' ';
    cronHtml += isCommandChanged ? '<span class="cron-badge" style="background: var(--border-color-medium, var(--border-color-strong)); color:var(--badge-text)">' + command + '</span>'
  : command

    document.getElementById('cron_preview').innerHTML = cronHtml;

    const plain = minute + ' ' + hour + ' ' + day + ' ' + month + ' ' + weekday + ' ' + command;
    document.getElementById('cron_preview_text').value = plain;

    const human = this._describeCron(minute, hour, day, month, weekday, command);
    const humanEl = document.getElementById('cron_human_text');
    if (humanEl) humanEl.value = human;
  },

  appendCronLine: function() {
    const input = document.getElementById('cron_preview_text');
    if (!input) {
      ui.addNotification(null, E('p', _('Please enter the command')), 'info');
      return;
    }

    const cronLine = (input.value || '').trim();
    const isDefault = cronLine === '* * * * *' || cronLine === '';
    const parts = cronLine.split(/\s+/);

    if (isDefault) {
      ui.addNotification(null, E('p', _('Check the cron entry, it must contain (time + command)')), 'info');
      return;
    }
    if (parts.length < 6) {
      ui.addNotification(null, E('p', _('Please enter the command')), 'info');
      return;
    }

    return fs.read('/etc/crontabs/root').then(function(content) {
      let current = (content || '').replace(/\r\n/g, '\n');

      const haystack = '\n' + current + (current.endsWith('\n') ? '' : '\n');
      const needle   = '\n' + cronLine + '\n';
      if (haystack.indexOf(needle) !== -1) {
        ui.addNotification(null, E('p', _('This entry already exists in cron') + ': ' + cronLine));
        return Promise.resolve('duplicate');
      }

      if (!current.endsWith('\n') && current.length > 0) current += '\n';
      current += cronLine + '\n';

      return fs.write('/etc/crontabs/root', current).then(function(){ return 'written'; });
    }).then(function(state) {
      if (state === 'duplicate') return;

      return fs.exec('/etc/init.d/cron', ['restart']).then(function() {
        popTimeout(null, E('p', _('Added entry to cron') + ': ' + cronLine), 5000, 'info');
      });
    }).catch(function(e) {
      ui.addNotification(null, E('p', _('Error: %s').format(e.message)));
    });
  },

  generateOptions: function(start, end, labels) {
    const opts = [];
    opts.push(E('option', { value: '*', selected: true }, '*'));

    if (labels) {
      for (let i = 0; i < labels.length; i++) {
        opts.push(E('option', { value: (start + i).toString() }, labels[i]));
      }
    } else {
      for (let i = start; i <= end; i++) {
        opts.push(E('option', { value: i.toString() }, i.toString()));
      }
    }
    return opts;
  },

  resetMulti: function(id) {
    const sel = document.getElementById(id);
    if (!sel) return;
    Array.from(sel.options).forEach(function(o){ o.selected = (o.value === '*'); });
  },

  render: function(){
    this.addStyles();

    const root = E('div', { class:'cbi-map' }, [
      E('h4', {}, [ _('Graphical Crontab Configurator') ]),
      E('div', { 'class': 'cbi-section-descr fade-in' }, [_('A super simple graphical configurator for crontab.') ]),

      E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit, minmax(200px, 1fr));margin-bottom:1em;gap:1em' }, [
        E('div', { 'class': 'ifacebox', 'style': 'margin:.25em;width:100%' }, [
          E('div', { 'class': 'ifacebox-head cron-minute-head', 'style': 'font-weight:bold;padding:8px;color:#ffffff;' }, [ _('Minute') ]),
          E('div', { 'class': 'ifacebox-body', 'style': 'padding:8px' }, [
            E('select', {
              'id': 'minute_select',
              'class': 'cbi-input-select cron-multiselect',
              'multiple': true,
              'size': 8,
              'change': ui.createHandlerFn(this, 'updateCronPreview')
            }, this.generateOptions(0, 59)),
            E('div', { 'style': 'display:flex; align-items:center; gap:5px; margin-top:6px' }, [
              E('input', {
                'type': 'checkbox',
                'id': 'minute_checkbox',
                'change': ui.createHandlerFn(this, 'updateCronPreview')
              }),
              E('label', { 'for': 'minute_checkbox', 'style': 'font-size:12px' }, _('every specified minute period'))
            ])
          ])
        ]),

        E('div', { 'class': 'ifacebox', 'style': 'margin:.25em;width:100%' }, [
          E('div', { 'class': 'ifacebox-head cron-hour-head', 'style': 'font-weight:bold;padding:8px;color:#ffffff;' }, [ _('Hour') ]),
          E('div', { 'class': 'ifacebox-body', 'style': 'padding:8px' }, [
            E('select', {
              'id': 'hour_select',
              'class': 'cbi-input-select cron-multiselect',
              'multiple': true,
              'size': 8,
              'change': ui.createHandlerFn(this, 'updateCronPreview')
            }, this.generateOptions(0, 23)),
            E('div', { 'style': 'display:flex; align-items:center; gap:5px; margin-top:6px' }, [
              E('input', {
                'type': 'checkbox',
                'id': 'hour_checkbox',
                'change': ui.createHandlerFn(this, 'updateCronPreview')
              }),
              E('label', { 'for': 'hour_checkbox', 'style': 'font-size:12px' }, _('every specified hour period'))
            ])
          ])
        ]),

        E('div', { 'class': 'ifacebox', 'style': 'margin:.25em;width:100%' }, [
          E('div', { 'class': 'ifacebox-head cron-day-head', 'style': 'font-weight:bold;padding:8px;color:#ffffff;' }, [ _('Day') ]),
          E('div', { 'class': 'ifacebox-body', 'style': 'padding:8px' }, [
            E('select', {
              'id': 'day_select',
              'class': 'cbi-input-select cron-multiselect',
              'multiple': true,
              'size': 8,
              'change': ui.createHandlerFn(this, 'updateCronPreview')
            }, this.generateOptions(1, 31)),
            E('div', { 'style': 'display:flex; align-items:center; gap:5px; margin-top:6px' }, [
              E('input', {
                'type': 'checkbox',
                'id': 'day_checkbox',
                'change': ui.createHandlerFn(this, 'updateCronPreview')
              }),
              E('label', { 'for': 'day_checkbox', 'style': 'font-size:12px' }, _('every specified day period'))
            ])
          ])
        ]),

        E('div', { 'class': 'ifacebox', 'style': 'margin:.25em;width:100%' }, [
          E('div', { 'class': 'ifacebox-head cron-month-head', 'style': 'font-weight:bold;padding:8px;color:#ffffff;' }, [ _('Month') ]),
          E('div', { 'class': 'ifacebox-body', 'style': 'padding:8px' }, [
            E('select', {
              'id': 'month_select',
              'class': 'cbi-input-select cron-multiselect',
              'multiple': true,
              'size': 8,
              'change': ui.createHandlerFn(this, 'updateCronPreview')
            }, this.generateOptions(1, 12, [
              _('January'), _('February'), _('March'), _('April'), _('May'), _('June'),
              _('July'), _('August'), _('September'), _('October'), _('November'), _('December')
            ]))
          ])
        ]),

        E('div', { 'class': 'ifacebox', 'style': 'margin:.25em;width:100%' }, [
          E('div', { 'class': 'ifacebox-head cron-weekday-head', 'style': 'font-weight:bold;padding:8px;color:#ffffff;' }, [ _('Weekday') ]),
          E('div', { 'class': 'ifacebox-body', 'style': 'padding:8px' }, [
            E('select', {
              'id': 'weekday_select',
              'class': 'cbi-input-select cron-multiselect',
              'multiple': true,
              'size': 8,
              'change': ui.createHandlerFn(this, 'updateCronPreview')
            }, this.generateOptions(0, 6, [
              _('Sunday'), _('Monday'), _('Tuesday'), _('Wednesday'), _('Thursday'), _('Friday'), _('Saturday')
            ]))
          ])
        ])
      ]),

      E('label', { 'style': 'font-weight:bold; display:block; margin-bottom:5px;' }, _('Command to execute:')),
      E('input', {
        'id': 'cron_command_input',
        'class': 'cbi-input-text',
        'style': 'width:100%; margin-bottom:10px; text-align:center;',
        'blur': ui.createHandlerFn(this, 'updateCronPreview')
      }),

      E('div', { 'style': 'margin-top:1em;' }, [
        E('label', { 'style': 'font-weight:bold; display:block; margin-bottom:5px;' }, _('Command preview:')),
        E('div', {
          'id': 'cron_preview',
          'style': 'width:100%; margin-bottom:10px; font-family:monospace; border:1px solid var(--border-color-medium); padding:8px; background:var(--tile-free); border-radius:6px; color:var(--tile-text);'
        }),
      ]),

      // Desc
      E('div', { 'style': 'margin-top:1em;' }, [
        E('label', { 'style': 'font-weight:bold; display:block; margin-bottom:5px;' }, _('Description:')),
        E('textarea', {
          'id': 'cron_human_text',
          'class': 'cbi-input-textarea',
          'style': 'width:100%; min-height:60px; resize:vertical;',
          'readonly': true
        })
      ]),

      E('div', { 'style': 'margin-top:1em;' }, [
        E('label', { 'style': 'font-weight:bold; display:block; margin-bottom:5px;' }, _('Generated cron command:')),
        E('input', {
          'id': 'cron_preview_text',
          'class': 'cbi-input-text',
          'style': 'width:100%; margin-bottom:10px; font-family:monospace;',
          'readonly': true,
          'data-tooltip': _('Cron command for copying'),
          'value': '* * * * * '
        })
      ]),

      E('div', { 'class': 'cron-actions' }, [
        E('button', {
          'class': 'cbi-button cbi-button-positive',
          'click': ui.createHandlerFn(this, 'appendCronLine')
        }, _('Add to cron')),
        E('button', {
          'class': 'cbi-button cbi-button-neutral',
          'click': ui.createHandlerFn(this, function(){
            this.resetMulti('minute_select');
            this.resetMulti('hour_select');
            this.resetMulti('day_select');
            this.resetMulti('month_select');
            this.resetMulti('weekday_select');
            document.getElementById('cron_command_input').value = '';

            const minuteCheckbox = document.getElementById('minute_checkbox');
            const hourCheckbox   = document.getElementById('hour_checkbox');
            const dayCheckbox    = document.getElementById('day_checkbox');
            if (minuteCheckbox) minuteCheckbox.checked = false;
            if (hourCheckbox) hourCheckbox.checked = false;
            if (dayCheckbox) dayCheckbox.checked = false;

            this.updateCronPreview();
          })
        }, _('Reset changes'))
      ])
    ]);

    setTimeout(() => this.updateCronPreview(), 0);
    return root;
  },

  handleSaveApply: null,
  handleSave: null,
  handleReset: null
});
