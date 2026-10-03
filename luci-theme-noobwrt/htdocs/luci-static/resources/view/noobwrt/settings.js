'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var callSetCustomWallpaper = rpc.declare({
    object: 'luci.noobwrt_wallpaper',
    method: 'set_custom',
    expect: { result: -1 }
});

var callRemoveCustomWallpaper = rpc.declare({
    object: 'luci.noobwrt_wallpaper',
    method: 'remove_custom',
    expect: { result: -1 }
});

return view.extend({
    load: function () {
        return uci.load('noobwrt').catch(function () {
            /* /etc/config/noobwrt is absent (fresh install or missing defaults).
             * Seed an in-memory named section 'global' so form.NamedSection
             * can render without firing uci/get RPCs that return code 4.
             * uci.add() returns the internal sid; setting .name promotes it
             * to a named section that form.NamedSection('global') will find. */
            var sid = uci.add('noobwrt', 'global');
            uci.set('noobwrt', sid, '.name', 'global');
            uci.set('noobwrt', sid, 'mode', 'normal');
            uci.set('noobwrt', sid, 'primary', '#5e72e4');
            uci.set('noobwrt', sid, 'dark_primary', '#7c8ff5');
            uci.set('noobwrt', sid, 'blur', '10');
            uci.set('noobwrt', sid, 'blur_dark', '10');
            uci.set('noobwrt', sid, 'transparency', '0.8');
            uci.set('noobwrt', sid, 'transparency_dark', '0.8');
            uci.set('noobwrt', sid, 'online_wallpaper', 'none');
            uci.set('noobwrt', sid, 'auto_dark_mode', '0');
        });
    },

    render: function () {
        var m, s, o;

        m = new form.Map('noobwrt', _('NoobWrt Theme Settings'),
            _('Customize the appearance, wallpaper, background effects, and toolbar panel of the NoobWrt LuCI theme.'));

        /* ============================================================
         * SECTION: Global – tabbed (Appearance / Wallpaper / Effects / Toolbar / About)
         * ============================================================ */
        s = m.section(form.NamedSection, 'global', 'global');
        s.addremove = false;
        s.anonymous = true;

        s.tab('appearance', _('Appearance'));
        s.tab('wallpaper',  _('Wallpaper'));
        s.tab('effects',    _('Background Effects'));
        s.tab('toolbar',    _('Toolbar Panel'));
        s.tab('about',      _('About'));

        /* ---- Appearance ---- */
        o = s.taboption('appearance', form.Flag, 'auto_dark_mode',
            _('Automatic Light / Dark Mode'),
            _('Automatically switch to Dark mode from 6 PM to 6 AM and Light mode from 6 AM to 6 PM. When enabled, the schedule overrides the manual toolbar toggle.'));
        o.default = '1';

        o = s.taboption('appearance', form.ListValue, 'mode',
            _('Default Theme Mode'),
            _('Theme applied on page load when Automatic mode is disabled. Users can also toggle it manually using the toolbar sun/moon button.'));
        o.value('normal', _('Light'));
        o.value('dark',   _('Dark'));

        o = s.taboption('appearance', form.Value, 'primary',
            _('Accent Color — Light Mode'),
            _('Primary accent color used throughout the light theme.'));
        o.placeholder = '#5e72e4';
        o.rmempty = false;
        o.renderWidget = function(section_id, option_index, cfgvalue) {
            var node = form.Value.prototype.renderWidget.apply(this, arguments);
            var input = node.querySelector('input');
            if (input) {
                input.style.cssText = 'width:140px;display:inline-block;vertical-align:middle;margin-right:6px';
                var picker = document.createElement('input');
                picker.type = 'color';
                picker.value = (cfgvalue && cfgvalue !== this.placeholder) ? cfgvalue : this.placeholder;
                picker.style.cssText = 'width:40px;height:32px;padding:2px;border:1px solid #ccc;border-radius:4px;cursor:pointer;vertical-align:middle';
                picker.addEventListener('input', function() { input.value = picker.value; input.dispatchEvent(new Event('input', { bubbles: true })); });
                input.addEventListener('input', function() { if (/^#[0-9a-fA-F]{6}$/.test(input.value)) picker.value = input.value; });
                node.appendChild(picker);
            }
            return node;
        };

        o = s.taboption('appearance', form.Value, 'dark_primary',
            _('Accent Color — Dark Mode'),
            _('Primary accent color used throughout the dark theme.'));
        o.placeholder = '#7c8ff5';
        o.rmempty = false;
        o.renderWidget = function(section_id, option_index, cfgvalue) {
            var node = form.Value.prototype.renderWidget.apply(this, arguments);
            var input = node.querySelector('input');
            if (input) {
                input.style.cssText = 'width:140px;display:inline-block;vertical-align:middle;margin-right:6px';
                var picker = document.createElement('input');
                picker.type = 'color';
                picker.value = (cfgvalue && cfgvalue !== this.placeholder) ? cfgvalue : this.placeholder;
                picker.style.cssText = 'width:40px;height:32px;padding:2px;border:1px solid #ccc;border-radius:4px;cursor:pointer;vertical-align:middle';
                picker.addEventListener('input', function() { input.value = picker.value; input.dispatchEvent(new Event('input', { bubbles: true })); });
                input.addEventListener('input', function() { if (/^#[0-9a-fA-F]{6}$/.test(input.value)) picker.value = input.value; });
                node.appendChild(picker);
            }
            return node;
        };

        /* ---- Wallpaper ---- */
        var BGURL = '/luci-static/noobwrt/background/custom.jpg';
        var BGTMP = '/tmp/noobwrt_wallpaper.tmp';

        o = s.taboption('wallpaper', form.ListValue, 'online_wallpaper',
            _('Online Wallpaper Source'),
            _('Automatically fetch a wallpaper from an online source for the login page background. Set to None to use a custom uploaded image or the built-in default.'));
        o.value('none',      _('None (use custom / default)'));
        o.value('bing',      _('Bing Daily Photo'));
        o.value('picsum',    _('Lorem Picsum (Random)'));
        o.value('wikimedia', _('Wikimedia Picture of the Day'));
        o.default = 'none';

        o = s.taboption('wallpaper', form.DummyValue, '_wallpaper_ui', '');
        o.rawhtml = true;
        o.default = [
            '<div style="max-width:520px">',
            '<p style="color:#888;font-size:13px;margin:0 0 12px">',
            _('Upload a custom image to use as the login page background. Supported formats: JPG, PNG, WebP (max 10 MB).'),  
            '</p>',
            '<div id="noobwrt-wp-preview" style="margin-bottom:12px;border-radius:10px;overflow:hidden;background:#f0f0f0;height:160px;display:flex;align-items:center;justify-content:center">',
            '<img id="noobwrt-wp-img" src="" style="width:100%;height:100%;object-fit:cover;display:none" />',
            '<span id="noobwrt-wp-placeholder" style="color:#aaa;font-size:13px">' + _('No custom wallpaper — using default') + '</span>',
            '</div>',
            '<p id="noobwrt-wp-status" style="font-size:12px;color:#888;min-height:18px;margin:0 0 12px"></p>',
            '<div style="display:flex;gap:10px">',
            '<button id="noobwrt-wp-upload" type="button" class="btn cbi-button cbi-button-action">' + _('Upload Wallpaper...') + '</button>',
            '<button id="noobwrt-wp-revert" type="button" class="btn cbi-button cbi-button-reset">' + _('Revert to Default') + '</button>',
            '</div>',
            '</div>'
        ].join('');


        /* ---- Background Effects ---- */
        o = s.taboption('effects', form.Value, 'blur',
            _('Blur Radius — Light Mode'),
            _('Login page background blur radius in pixels for light mode. Default: 10'));
        o.placeholder = '10';
        o.datatype = 'uinteger';

        o = s.taboption('effects', form.Value, 'blur_dark',
            _('Blur Radius — Dark Mode'),
            _('Login page background blur radius in pixels for dark mode. Default: 10'));
        o.placeholder = '10';
        o.datatype = 'uinteger';

        o = s.taboption('effects', form.Value, 'transparency',
            _('Background Opacity — Light Mode'),
            _('Overlay opacity on the login page background for light mode. Range: 0.0 (transparent) to 1.0 (opaque). Default: 0.8'));
        o.placeholder = '0.8';

        o = s.taboption('effects', form.Value, 'transparency_dark',
            _('Background Opacity — Dark Mode'),
            _('Overlay opacity on the login page background for dark mode. Default: 0.8'));
        o.placeholder = '0.8';

        /* ---- Toolbar tab – placeholder only, real table rendered below ---- */
        o = s.taboption('toolbar', form.DummyValue, '_toolbar_placeholder', '');
        o.rawhtml  = true;
        o.default  = '<div id="noobwrt-toolbar-tab-content"></div>';

        /* ---- About ---- */
        o = s.taboption('about', form.DummyValue, '_about', '');
        o.rawhtml = true;
        o.default = [
            '<div style="max-width:480px;background:var(--color-bg-1,#fff);border:1px solid var(--color-border,#e5e7eb);border-radius:12px;padding:20px 24px;box-shadow:0 2px 8px rgba(0,0,0,0.06)">',
            '  <h3 style="margin:0 0 6px;font-size:16px;font-weight:600">' + _('NoobWrt Theme') + '</h3>',
            '  <p style="margin:0 0 16px;color:#888;font-size:13px">' + _('A clean modern LuCI theme for OpenWrt routers.') + '</p>',
            '  <table style="width:100%;border-collapse:collapse;line-height:1.9;font-size:13px">',
            '    <tr><td style="width:130px;color:#888;padding:3px 0">' + _('Developer') + '</td>',
            '        <td><strong>NoobLk</strong></td></tr>',
            '    <tr><td style="color:#888;padding:3px 0">' + _('Repository') + '</td>',
            '        <td><a href="https://github.com/nooblk-98/luci-theme-noobwrt" target="_blank" rel="noopener" style="color:#5e72e4">github.com/nooblk-98/luci-theme-noobwrt</a></td></tr>',
            '    <tr><td style="color:#888;padding:3px 0">' + _('Contributors') + '</td>',
            '        <td><a href="https://github.com/nooblk-98/luci-theme-noobwrt/graphs/contributors" target="_blank" rel="noopener" style="color:#5e72e4">' + _('View on GitHub') + '</a></td></tr>',
            '    <tr><td style="color:#888;padding:3px 0">' + _('License') + '</td>',
            '        <td>MIT</td></tr>',
            '    <tr><td style="color:#888;padding:3px 0">' + _('Issues / Support') + '</td>',
            '        <td><a href="https://github.com/nooblk-98/luci-theme-noobwrt/issues" target="_blank" rel="noopener" style="color:#5e72e4">' + _('Open an issue') + '</a></td></tr>',
            '  </table>',
            '  <p style="margin:16px 0 0;color:#bbb;font-size:12px;text-align:center;border-top:1px solid var(--color-border,#e5e7eb);padding-top:12px">' + _('Made with \u2665 for the OpenWrt community') + '</p>',
            '</div>'
        ].join('\n');

        /* ============================================================
         * SECTION: Toolbar Panel Items (TableSection)
         * Rendered separately, then moved into the Toolbar tab via JS.
         * ============================================================ */
        var ts = m.section(form.TableSection, 'toolbar_item',
            _('Toolbar Panel Items'),
            _('Quick-access links displayed in the right-side toolbar panel on every page. Items are rendered in ascending Order number. Use the Add button below to create new entries.'));
        ts.addremove = true;
        ts.anonymous = true;
        ts.sortable  = false;
        ts.nodescriptions = true;

        o = ts.option(form.Flag, 'enabled', _('Enable'));
        o.default = '1';
        o.editable = true;

        o = ts.option(form.Value, 'title', _('Label'));
        o.placeholder = 'Home';
        o.rmempty = false;
        o.editable = true;

        o = ts.option(form.Value, 'url', _('URL / Path'));
        o.placeholder = '/cgi-bin/luci/admin/status/overview';
        o.rmempty = false;
        o.editable = true;

        o = ts.option(form.ListValue, 'icon', _('Icon'));
        [
            ['home.png',     _('Home')],
            ['signal.png',   _('Signal / Status')],
            ['cell.png',     _('Cell / Modem')],
            ['sms.png',      _('SMS')],
            ['network.png',  _('Network / Data Usage')],
            ['nas.png',      _('NAS / Storage')],
            ['wifi.png',     _('WiFi / Wireless')],
            ['firewall.png', _('Firewall')],
            ['settings.png', _('Settings / System')],
            ['terminal.png', _('Terminal')],
            ['vpn.png',      _('VPN')],
            ['files.png',    _('Files')],
            ['info.png',     _('Info / Log')]
        ].forEach(function (v) { o.value(v[0], v[1]); });
        o.editable = true;

        o = ts.option(form.Value, 'order',
            _('Order'),
            _('Lower numbers appear first in the toolbar.'));
        o.datatype = 'uinteger';
        o.placeholder = '10';
        o.editable = true;

        return m.render().then(function (node) {
            /* ---- Wire wallpaper buttons ---- */
            var uploadBtn = node.querySelector('#noobwrt-wp-upload');
            var revertBtn = node.querySelector('#noobwrt-wp-revert');
            var wpImg     = node.querySelector('#noobwrt-wp-img');
            var wpPh      = node.querySelector('#noobwrt-wp-placeholder');
            var wpSt      = node.querySelector('#noobwrt-wp-status');

            function setStatus(msg, ok) {
                wpSt.textContent = msg;
                wpSt.style.color = ok === true ? '#2dce89' : ok === false ? '#f5365c' : '#888';
            }

            fetch(BGURL, { method: 'HEAD' })
                .then(function (r) {
                    if (r.ok) { wpImg.src = BGURL + '?_=' + Date.now(); wpImg.style.display = ''; wpPh.style.display = 'none'; }
                }).catch(function () {});

            uploadBtn.addEventListener('click', function (ev) {
                ui.uploadFile(BGTMP, ev.target)
                    .then(function () { return callSetCustomWallpaper(); })
                    .then(function (result) {
                        if (result === 0) {
                            wpImg.src = BGURL + '?_=' + Date.now(); wpImg.style.display = ''; wpPh.style.display = 'none';
                            setStatus(_('Wallpaper uploaded! Refresh the login page to see it.'), true);
                        } else {
                            setStatus(_('Failed to save wallpaper.'), false);
                        }
                    })
                    .catch(function (e) { setStatus(_('Upload error: ') + e.message, false); });
            });

            revertBtn.addEventListener('click', function () {
                if (!window.confirm(_('Remove custom wallpaper and revert to default?'))) return;
                callRemoveCustomWallpaper()
                    .then(function () {
                        wpImg.src = ''; wpImg.style.display = 'none'; wpPh.style.display = '';
                        setStatus(_('Reverted to default wallpaper.'), true);
                    })
                    .catch(function (e) { setStatus(_('Could not remove: ') + e.message, false); });
            });

            /* ---- Move TableSection into Toolbar tab ---- */
            var tabContent = node.querySelector('#noobwrt-toolbar-tab-content');
            var sections   = node.querySelectorAll('.cbi-map > .cbi-section');
            var tsNode     = sections[sections.length - 1];

            if (tabContent && tsNode) {
                var heading = tsNode.querySelector('h3, .cbi-section-legend');
                if (heading) heading.style.display = 'none';
                tabContent.appendChild(tsNode);
            }

            return node;
        });
    }
});
