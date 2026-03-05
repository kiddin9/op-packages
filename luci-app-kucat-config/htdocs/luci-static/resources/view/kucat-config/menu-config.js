/*
 *  luci-app-kucat-config
 *  Copyright (C) 2021-2026 The Sirpdboy <herboy2008@gmail.com> 
 *
 *  Licensed to the public under the Apache License 2.0
 */

'use strict';
'require baseclass';
'require view';
'require ui';
'require rpc';
'require fs';

// 继承 View 基类
return view.extend({
    callMenuConfig: rpc.declare({
        object: 'luci',
        method: 'getMenuConfig',
        params: ['']
    }),

    callSetMenuConfig: rpc.declare({
        object: 'luci',
        method: 'setMenuConfig',
        params: ['config']
    }),

    title: _('KuCat Menu Configuration'),

    load: function() {
        var self = this;
        
        // 先加载菜单配置
        return this.loadBasicMenus().then(function(basicSet) {
            // 等待菜单渲染完成后再获取所有菜单
            return new Promise(function(resolve) {
                // 延迟一段时间，等待菜单渲染完成
                setTimeout(function() {
                    self.loadAllMenus().then(function(allMenus) {
                        resolve([allMenus, basicSet]);
                    });
                }, 500);
            });
        });
    },

    /**
     * 获取所有菜单 - 从已渲染的DOM中获取
     */
    loadAllMenus: function() {
        var self = this;
        return new Promise(function(resolve) {
            var menus = [];
            var menuSet = new Set();
            
            try {
                // 从页面中获取所有菜单链接
                var menuLinks = document.querySelectorAll('#mainmenu a, .slide-menu a, .nav a, [data-title]');
                
                //console.log('Found menu links:', menuLinks.length);
                
                menuLinks.forEach(function(link) {
                    var href = link.getAttribute('href');
                    var text = link.textContent.trim() || link.getAttribute('data-title');
                    
                    if (href && href.indexOf('/admin/') !== -1) {
                        // 提取路径，移除 /admin/ 前缀
                        var path = href.replace(/.*\/admin\//, '');
                        path = path.replace(/\/$/, ''); // 移除末尾的斜杠
                        
                        // 确保路径有效
                        if (path && path !== '#' && !menuSet.has(path) && text && text !== '') {
                            menuSet.add(path);
                            menus.push({
                                path: path,
                                title: text
                            });
                            
                            //console.log('Added menu:', path, text);
                        }
                    }
                });
                
                // 如果通过链接获取不到，尝试从 data-title 属性获取
                if (menus.length === 0) {
                    var menuItems = document.querySelectorAll('[data-title]');
                    menuItems.forEach(function(item) {
                        var title = item.getAttribute('data-title');
                        var href = item.getAttribute('href');
                        
                        if (href && href.indexOf('/admin/') !== -1) {
                            var path = href.replace(/.*\/admin\//, '').replace(/\/$/, '');
                            if (path && !menuSet.has(path) && title) {
                                menuSet.add(path);
                                menus.push({
                                    path: path,
                                    title: title
                                });
                            }
                        }
                    });
                }
                
                // 如果还是获取不到，使用主题的默认菜单
                if (menus.length === 0) {
                    //console.log('No menus found from DOM, using fallback');
                    menus = self.getFallbackMenus();
                }
                
            } catch (e) {
                console.debug('Error loading menus:', e);
                menus = self.getFallbackMenus();
            }
            
            // 去重并排序
            var uniqueMenus = self.deduplicateMenus(menus);
            //console.log('Final menus count:', uniqueMenus.length);
            resolve(uniqueMenus);
        });
    },

    deduplicateMenus: function(menus) {
        var uniqueMenus = [];
        var seen = new Set();
        
        menus.forEach(function(menu) {
            if (menu && menu.path && !seen.has(menu.path)) {
                seen.add(menu.path);
                uniqueMenus.push(menu);
            }
        });
        
        // 按主分类和路径排序
        uniqueMenus.sort(function(a, b) {
            var catA = (a.path || '').split('/')[0];
            var catB = (b.path || '').split('/')[0];
            
            if (catA !== catB) {
                return catA.localeCompare(catB);
            }
            return (a.path || '').localeCompare(b.path || '');
        });
        
        return uniqueMenus;
    },

    getFallbackMenus: function() {
        // 从主题的 getDefaultBasicMenus 中获取默认菜单
        return [
            { path: 'status/overview', title: 'Overview' },
            { path: 'status/processes', title: 'Processes' },
            { path: 'status/realtime', title: 'Realtime Graphs' },
            { path: 'status/iptables', title: 'Firewall Status' },
            { path: 'system/system', title: 'System' },
            { path: 'system/administration', title: 'Administration' },
            { path: 'system/startup', title: 'Startup' },
            { path: 'system/crontab', title: 'Scheduled Tasks' },
            { path: 'system/flash', title: 'Backup/Flash Firmware' },
            { path: 'system/ttyd', title: 'Terminal' },
            { path: 'system/advancedplus', title: 'Advanced Plus' },
            { path: 'system/ota', title: 'OTA Update' },
            { path: 'system/kucat-config', title: 'KuCat Config' },
            { path: 'system/partexp', title: 'Partition Exp' },
            { path: 'services/services', title: 'Services' },
            { path: 'services/AdGuardHome', title: 'AdGuard Home' },
            { path: 'network/interfaces', title: 'Interfaces' },
            { path: 'network/dhcp', title: 'DHCP and DNS' },
            { path: 'network/hostnames', title: 'Hostnames' },
            { path: 'network/routes', title: 'Static Routes' },
            { path: 'network/firewall', title: 'Firewall' },
            { path: 'network/diagnostics', title: 'Diagnostics' },
            { path: 'network/netspeedtest', title: 'Net Speed Test' },
            { path: 'control/eqosplus', title: 'EQoS Plus' },
            { path: 'control/timecontrol', title: 'Time Control' },
            { path: 'control/watchdog', title: 'Watchdog' },
            { path: 'control/taskplan', title: 'Task Plan' },
            { path: 'netwizard', title: 'Network Wizard' }
        ];
    },

    loadBasicMenus: function() {
        var self = this;
        
        // 先尝试通过RPC获取
        return this.callMenuConfig().then(function(result) {
            var basicSet = new Set();
            if (result && result.basic && Array.isArray(result.basic)) {
                result.basic.forEach(function(path) {
                    if (path) basicSet.add(path);
                });
            }
            
            // 如果RPC返回了数据，直接返回
            if (basicSet.size > 0) {
                return basicSet;
            }
            
            // 否则从文件读取
            return self.loadBasicMenusFromFile();
            
        }).catch(function() {
            // RPC失败，从文件读取
            return self.loadBasicMenusFromFile();
        });
    },

    loadBasicMenusFromFile: function() {
        return fs.read('/etc/config/kucat').then(function(content) {
            var basicSet = new Set();
            var lines = content.split('\n');
            var inBasicSection = false;
            
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim();
                
                // 检查是否进入basic配置段
                if (line === 'config basic' || line === 'config basic \'settings\'') {
                    inBasicSection = true;
                    continue;
                }
                
                // 如果遇到其他config行，退出basic段
                if (inBasicSection && line.match(/^config /)) {
                    inBasicSection = false;
                }
                
                // 如果在basic段中，收集list item
                if (inBasicSection) {
                    var match = line.match(/list item ['"](.+)['"]/);
                    if (match && match[1]) {
                        basicSet.add(match[1]);
                    }
                }
            }
            
            return basicSet;
        }).catch(function() {
            // 文件不存在或读取失败，返回默认basic菜单
            return new Set([
                'status/overview',
                'status/realtime',
                'netwizard',
                'system/system',
                'system/admin',
                'system/ttyd',
                'system/advancedplus',
                'system/ota',
                'system/kucat-config',
                'services/AdGuardHome',
                'control/eqosplus',
                'control/timecontrol',
                'control/watchdog',
                'control/taskplan',
                'network/firewall',
                'network/netspeedtest',
                'system/partexp'
            ]);
        });
    },

    render: function(data) {
        var allMenus = data[0];
        var basicSet = data[1];
        
        // 分离basic和非basic菜单
        var basicMenus = [];
        var allmenuMenus = [];
        
        allMenus.forEach(function(menu) {
            if (basicSet.has(menu.path)) {
                basicMenus.push(menu);
            } else {
                allmenuMenus.push(menu);
            }
        });
        
        return E('div', { 'class': 'cbi-map', 'id': 'kucat-menu-config' }, [
            E('style', {}, [this.getStyles()]),
            E('h2', { 'class': 'cbi-page-title' }, [_('KuCat Menu Configuration')]),
            E('div', { 'class': 'cbi-section' }, [
                E('div', { 'class': 'cbi-section-descr' }, [
                    _('Configure the menu displayed in custom mode. Select items and use the buttons to switch between lists.')
                ]),
                
                E('div', { 'class': 'cbi-section-node' }, [
                    this.renderDualList(basicMenus, allmenuMenus)
                ])
            ])
        ]);
    },

    getStyles: function() {
        return '' +
            '#kucat-menu-config .dual-list-container {' +
            '    display: flex;' +
            '    gap: 20px;' +
            '    margin: 20px 0;' +
            '    min-height: 500px;' +
            '}' +
            '#kucat-menu-config .list-box {' +
            '    flex: 1;' +
            '    border: 1px solid #ccc;' +
            '    border: 1px solid var(--input-boxcolor);' +
            '    border-radius: 4px;' +
            '    display: flex;' +
            '    flex-direction: column;' +
            '}' +
            '#kucat-menu-config .list-header {' +
            '    padding: 0 15px;' +
            '    border-bottom: 1px solid #ccc;' +
            '    border-bottom: 1px solid var(--input-boxcolor);' +
            '    display: flex;' +
            '    justify-content: space-between;' +
            '    align-items: center;' +
            '}' +
            '#kucat-menu-config .list-header h3 {' +
            '    margin: 0;' +
            '    font-size: 16px;' +
            '    font-weight: 600;' +
            '}' +
            '#kucat-menu-config .list-count {' +
            '    font-size: 13px;' +
            '    color: #666;' +
            '    background: #e0e0e0;' +
            '    padding: 3px 8px;' +
            '    border-radius: 12px;' +
            '}' +
            '#kucat-menu-config .selected-count {' +
            '    margin-left: auto;' +
            '    font-size: 12px;' +
            '    color: #666;' +
            '    background: #e0e0e0;' +
            '    padding: 2px 8px;' +
            '    margin: 0px 8px;' +
            '    border-radius: 12px;' +
            '}' +
            '#kucat-menu-config .list-content {' +
            '    flex: 1;' +
            '    padding: 1px;' +
            '    overflow-y: auto;' +
            '    min-height: 400px;' +
            '    max-height: 600px;' +
            '}' +
            '#kucat-menu-config .list-footer {' +
            '    padding: 12px 15px;' +
            '    border-top: 1px solid #ccc;' +
            '    border-top: 1px solid var(--input-boxcolor);' +
            '    border-radius: 0 0 4px 4px;' +
            '    text-align: center;' +
            '}' +
            '#kucat-menu-config .list-controls {' +
            '    display: flex;' +
            '    flex-direction: column;' +
            '    justify-content: center;' +
            '    align-items: center;' +
            '}' +
            '#kucat-menu-config .list-controls .cbi-button {' +
            '    width: 110px;' +
            '    margin: 5px 0;' +
            '}' +
            '#kucat-menu-config .menu-list-item {' +
            '    margin: 2px 0;' +
            '    transition: background 0.2s ease;' +
            '}' +
            '#kucat-menu-config .menu-list-item:hover {' +
            '    background: rgba(50,50,50,0.15);' +
            '}' +
            '#kucat-menu-config .menu-item-label {' +
            '    display: flex;' +
            '    align-items: center;' +
            '    padding: 4px 8px;' +
            '    cursor: pointer;' +
            '    width: 100%;' +
            '}' +
            '#kucat-menu-config .menu-item-label .menu-title {' +
            '    font-size: 14px;' +
            '    font-weight: 500;' +
            '    flex: 1;' +
            '}' +
            '#kucat-menu-config .menu-item-label .menu-path {' +
            '    margin-left: 10px;' +
            '    font-family: monospace;' +
            '}' +
            '#kucat-menu-config .button-group {' +
            '    display: flex;' +
            '    justify-content: center;' +
            '    align-items: center;' +
            '    gap: 10px;' +
            '}' +
            '#kucat-menu-config .cbi-button-add {' +
            '    background: #4CAF50;' +
            '    color: white;' +
            '}' +
            '#kucat-menu-config .cbi-button-add:hover:not(:disabled) {' +
            '    background: #45a049;' +
            '}' +
            '#kucat-menu-config .cbi-button-remove {' +
            '    background: #f44336;' +
            '    color: white;' +
            '}' +
            '#kucat-menu-config .cbi-button-remove:hover:not(:disabled) {' +
            '    background: #da190b;' +
            '}' +
            '#kucat-menu-config .cbi-button:disabled {' +
            '    opacity: 0.5;' +
            '    cursor: not-allowed;' +
            '}' +
            '@media screen and (max-width: 920px) {' +
            '    #kucat-menu-config .dual-list-container {' +
            '        flex-direction: column;' +
            '    }' +
            '    #kucat-menu-config .list-controls {' +
            '        width: 100%;' +
            '        flex-direction: row;' +
            '        justify-content: center;' +
            '    }' +
            '    #kucat-menu-config .list-controls .cbi-button {' +
            '        width: auto;' +
            '        margin: 0 10px;' +
            '    }' +
            '}';
    },

    renderDualList: function(basicMenus, allmenuMenus) {
        var self = this;
        
        var basicListContent = E('div', { 'class': 'list-content', 'id': 'basic-list-content' });
        var allmenuListContent = E('div', { 'class': 'list-content', 'id': 'allmenu-list-content' });
        
        // 渲染basic菜单列表
        basicMenus.forEach(function(menu, index) {
            basicListContent.appendChild(self.renderMenuItem(menu, 'basic', index));
        });
        
        // 渲染allmenu菜单列表
        allmenuMenus.forEach(function(menu, index) {
            allmenuListContent.appendChild(self.renderMenuItem(menu, 'allmenu', index));
        });
        
        return E('div', { 'class': 'dual-list-container' }, [
            // 左侧 Basic 菜单列表
            E('div', { 'class': 'list-box basic-list' }, [
                E('div', { 'class': 'list-header' }, [
                    E('h3', {}, [_('Custom Menu')]),
                    E('span', { 'class': 'list-count' }, [basicMenus.length + ' ' + _('items')])
                ]),
                basicListContent,
                E('div', { 'class': 'list-footer' }, [
                    E('div', { 'class': 'button-group' }, [
                        E('button', {
                            'class': 'cbi-button cbi-button-apply cbi-button-select',
                            'click': ui.createHandlerFn(self, 'handleSelectAllBasic'),
                            'disabled': basicMenus.length === 0 ? 'disabled' : null
                        }, [_('Select All')]),
                        E('button', {
                            'class': 'cbi-button cbi-button-reset cbi-button-select',
                            'click': ui.createHandlerFn(self, 'handleDeselectAllBasic'),
                            'disabled': basicMenus.length === 0 ? 'disabled' : null
                        }, [_('Select None')]),
                        E('span', { 'class': 'selected-count' }, ['0/' + basicMenus.length])
                    ])
                ])
            ]),
            
            // 中间移动按钮
            E('div', { 'class': 'list-controls' }, [
                E('button', {
                    'class': 'cbi-button cbi-button-add',
                    'click': ui.createHandlerFn(self, 'handleAddSelected'),
                    'disabled': allmenuMenus.length === 0 ? 'disabled' : null
                }, ['← ' + _('Add')]),
                E('button', {
                    'class': 'cbi-button cbi-button-remove',
                    'click': ui.createHandlerFn(self, 'handleRemoveSelected'),
                    'disabled': basicMenus.length === 0 ? 'disabled' : null,
                    'style': 'margin-top: 10px;'
                }, [_('Remove') + ' →'])
            ]),
            
            // 右侧 allmenu 菜单列表
            E('div', { 'class': 'list-box allmenu-list' }, [
                E('div', { 'class': 'list-header' }, [
                    E('h3', {}, [_('Full Menus')]),
                    E('span', { 'class': 'list-count' }, [allmenuMenus.length + ' ' + _('items')])
                ]),
                allmenuListContent,
                E('div', { 'class': 'list-footer' }, [
                        E('button', {
                        'class': 'cbi-button cbi-button-save cbi-button-select',
                        'click': ui.createHandlerFn(self, 'handleRecommendBasic'),
                        'title': _('Select recommended basic menu items')
                        }, [_('Commonly Used')]),
                        E('button', {
                            'class': 'cbi-button cbi-button-apply cbi-button-select',
                            'click': ui.createHandlerFn(self, 'handleSelectAllallmenu'),
                            'disabled': allmenuMenus.length === 0 ? 'disabled' : null
                        }, [_('Select All')]),
                        E('button', {
                            'class': 'cbi-button cbi-button-reset cbi-button-select',
                            'click': ui.createHandlerFn(self, 'handleDeselectAllallmenu'),
                            'disabled': allmenuMenus.length === 0 ? 'disabled' : null
                        }, [_('Select None')]),
                        E('span', { 'class': 'selected-count' }, ['0/' + allmenuMenus.length])
                ])
            ])
        ]);
    },

    renderMenuItem: function(menu, type, index) {
        var self = this;
        var checkbox = E('input', {
            'type': 'checkbox',
            'class': 'menu-checkbox',
            'data-path': menu.path,
            'data-title': menu.title,
            'data-list': type,
            'value': menu.path,
            'id': 'menu-' + type + '-' + index
        });
        
        checkbox.addEventListener('change', function() {
            self.handleCheckboxChange();
        });
        
        var label = E('label', {
            'class': 'menu-item-label',
            'for': 'menu-' + type + '-' + index
        }, [
            checkbox,
            E('span', { 'class': 'menu-title' }, [menu.title]),
            E('span', { 'class': 'menu-path' }, ['(' + menu.path + ')'])
        ]);
        
        return E('div', { 'class': 'menu-list-item' }, [label]);
    },

    getSelectedItems: function(listId) {
        var container = document.getElementById(listId);
        if (!container) return [];
        
        var checkboxes = container.querySelectorAll('.menu-checkbox:checked');
        var selected = [];
        
        checkboxes.forEach(function(cb) {
            selected.push({
                path: cb.getAttribute('data-path'),
                title: cb.getAttribute('data-title')
            });
        });
        
        return selected;
    },

    handleAddSelected: function() {
        var self = this;
        var selected = this.getSelectedItems('allmenu-list-content');
        
        if (selected.length === 0) {
            ui.addNotification({
                title: _('Information'),
                message: _('No items selected'),
                type: 'info',
                timeout: 3000
            });
            return;
        }
        
        var basicContainer = document.getElementById('basic-list-content');
        var allmenuContainer = document.getElementById('allmenu-list-content');
        
        if (!basicContainer || !allmenuContainer) return;
        
        // 获取当前所有菜单
        var basicItems = [];
        var allmenuItems = [];
        
        basicContainer.querySelectorAll('.menu-checkbox').forEach(function(cb) {
            basicItems.push({
                path: cb.getAttribute('data-path'),
                title: cb.getAttribute('data-title')
            });
        });
        
        allmenuContainer.querySelectorAll('.menu-checkbox').forEach(function(cb) {
            var path = cb.getAttribute('data-path');
            var isSelected = selected.some(function(item) {
                return item.path === path;
            });
            if (!isSelected) {
                allmenuItems.push({
                    path: path,
                    title: cb.getAttribute('data-title')
                });
            }
        });
        
        // 添加选中的到basic
        selected.forEach(function(item) {
            basicItems.push(item);
        });
        
        // 按主分类排序
        basicItems.sort(self.sortByMainCategory.bind(self));
        allmenuItems.sort(self.sortByMainCategory.bind(self));
        
        // 重新渲染
        basicContainer.innerHTML = '';
        allmenuContainer.innerHTML = '';
        
        basicItems.forEach(function(menu, index) {
            basicContainer.appendChild(self.renderMenuItem(menu, 'basic', index));
        });
        
        allmenuItems.forEach(function(menu, index) {
            allmenuContainer.appendChild(self.renderMenuItem(menu, 'allmenu', index));
        });
        
        this.updateCounts();
        
        ui.addNotification({
            title: _('Success'),
            message: selected.length + ' ' + _('items moved to Custom Menu'),
            type: 'info',
            timeout: 3000
        });
    },

    handleRemoveSelected: function() {
        var self = this;
        var selected = this.getSelectedItems('basic-list-content');
        
        if (selected.length === 0) {
            ui.addNotification({
                title: _('Information'),
                message: _('No items selected'),
                type: 'info',
                timeout: 3000
            });
            return;
        }
        
        var basicContainer = document.getElementById('basic-list-content');
        var allmenuContainer = document.getElementById('allmenu-list-content');
        
        if (!basicContainer || !allmenuContainer) return;
        
        // 获取当前所有菜单
        var basicItems = [];
        var allmenuItems = [];
        
        allmenuContainer.querySelectorAll('.menu-checkbox').forEach(function(cb) {
            allmenuItems.push({
                path: cb.getAttribute('data-path'),
                title: cb.getAttribute('data-title')
            });
        });
        
        basicContainer.querySelectorAll('.menu-checkbox').forEach(function(cb) {
            var path = cb.getAttribute('data-path');
            var isSelected = selected.some(function(item) {
                return item.path === path;
            });
            if (!isSelected) {
                basicItems.push({
                    path: path,
                    title: cb.getAttribute('data-title')
                });
            }
        });
        
        // 添加选中的到allmenu
        selected.forEach(function(item) {
            allmenuItems.push(item);
        });
        
        // 按主分类排序
        basicItems.sort(self.sortByMainCategory.bind(self));
        allmenuItems.sort(self.sortByMainCategory.bind(self));
        
        // 重新渲染
        basicContainer.innerHTML = '';
        allmenuContainer.innerHTML = '';
        
        basicItems.forEach(function(menu, index) {
            basicContainer.appendChild(self.renderMenuItem(menu, 'basic', index));
        });
        
        allmenuItems.forEach(function(menu, index) {
            allmenuContainer.appendChild(self.renderMenuItem(menu, 'allmenu', index));
        });
        
        this.updateCounts();
        
        ui.addNotification({
            title: _('Success'),
            message: selected.length + ' ' + _('items removed from Custom Menu'),
            type: 'info',
            timeout: 3000
        });
    },

    /**
     * 全选Basic列表
     */
    handleSelectAllBasic: function() {
        var basicContainer = document.getElementById('basic-list-content');
        if (!basicContainer) return;
        
        var checkboxes = basicContainer.querySelectorAll('.menu-checkbox');
        checkboxes.forEach(function(cb) {
            cb.checked = true;
        });
        
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    /**
     * 取消全选Basic列表
     */
    handleDeselectAllBasic: function() {
        var basicContainer = document.getElementById('basic-list-content');
        if (!basicContainer) return;
        
        var checkboxes = basicContainer.querySelectorAll('.menu-checkbox');
        checkboxes.forEach(function(cb) {
            cb.checked = false;
        });
        
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    /**
     * 全选allmenu列表
     */
    handleSelectAllallmenu: function() {
        var allmenuContainer = document.getElementById('allmenu-list-content');
        if (!allmenuContainer) return;
        
        var checkboxes = allmenuContainer.querySelectorAll('.menu-checkbox');
        checkboxes.forEach(function(cb) {
            cb.checked = true;
        });
        
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    /**
     * 取消全选allmenu列表
     */
    handleDeselectAllallmenu: function() {
        var allmenuContainer = document.getElementById('allmenu-list-content');
        if (!allmenuContainer) return;
        
        var checkboxes = allmenuContainer.querySelectorAll('.menu-checkbox');
        checkboxes.forEach(function(cb) {
            cb.checked = false;
        });
        
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    /**
     * 推荐基本菜单集
     */
    handleRecommendBasic: function() {
        var recommendedPaths = [
            'status/overview',
            'status/realtime',
            'netwizard',
            'system/system',
            'system/administration',
            'system/ttyd',
            'system/advancedplus',
            'system/ota',
            'system/kucat-config',
            'services/AdGuardHome',
            'control/eqosplus',
            'control/timecontrol',
            'control/watchdog',
            'control/taskplan',
            'network/firewall',
            'network/netspeedtest',
            'system/partexp'
        ];
        
        this.selectRecommended(recommendedPaths);
    },

    /**
     * 选择推荐的菜单项
     */
    selectRecommended: function(recommendedPaths) {
        var allmenuContainer = document.getElementById('allmenu-list-content');
        if (!allmenuContainer) return;
        
        // 先取消所有选中
        var allCheckboxes = allmenuContainer.querySelectorAll('.menu-checkbox');
        allCheckboxes.forEach(function(cb) {
            cb.checked = false;
        });
        
        // 选中推荐的菜单
        allCheckboxes.forEach(function(cb) {
            var path = cb.getAttribute('data-path');
            if (recommendedPaths.includes(path)) {
                cb.checked = true;
            }
        });
        
        // 更新按钮状态和选中计数
        this.updateButtonStates();
        this.updateSelectedCount();
        
        // 显示提示信息
        var selectedCount = allmenuContainer.querySelectorAll('.menu-checkbox:checked').length;
        ui.addNotification({
            title: _('Recommendation Applied'),
            message: _('Selected ') + selectedCount + _(' recommended menu items'),
            type: 'info',
            timeout: 3000
        });
    },

    sortByMainCategory: function(a, b) {
        var catA = (a.path || '').split('/')[0];
        var catB = (b.path || '').split('/')[0];
        
        if (catA !== catB) {
            return catA.localeCompare(catB);
        }
        return (a.path || '').localeCompare(b.path || '');
    },

    updateCounts: function() {
        var basicContainer = document.getElementById('basic-list-content');
        var allmenuContainer = document.getElementById('allmenu-list-content');
        
        if (basicContainer) {
            var basicCount = basicContainer.querySelectorAll('.menu-checkbox').length;
            var basicHeader = document.querySelector('.basic-list .list-count');
            if (basicHeader) {
                basicHeader.textContent = basicCount + ' ' + _('items');
            }
        }
        
        if (allmenuContainer) {
            var allmenuCount = allmenuContainer.querySelectorAll('.menu-checkbox').length;
            var allmenuHeader = document.querySelector('.allmenu-list .list-count');
            if (allmenuHeader) {
                allmenuHeader.textContent = allmenuCount + ' ' + _('items');
            }
        }
        
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    /**
     * 更新选中数量显示
     */
    updateSelectedCount: function() {
        var basicContainer = document.getElementById('basic-list-content');
        var allmenuContainer = document.getElementById('allmenu-list-content');
        
        if (basicContainer) {
            var basicSelected = basicContainer.querySelectorAll('.menu-checkbox:checked').length;
            var basicTotal = basicContainer.querySelectorAll('.menu-checkbox').length;
            var basicCountEl = document.querySelector('.basic-list .selected-count');
            
            if (basicCountEl) {
                basicCountEl.textContent = basicSelected + '/' + basicTotal;
            }
        }
        
        if (allmenuContainer) {
            var allmenuSelected = allmenuContainer.querySelectorAll('.menu-checkbox:checked').length;
            var allmenuTotal = allmenuContainer.querySelectorAll('.menu-checkbox').length;
            var allmenuCountEl = document.querySelector('.allmenu-list .selected-count');
            
            if (allmenuCountEl) {
                allmenuCountEl.textContent = allmenuSelected + '/' + allmenuTotal;
            }
        }
    },

    handleSave: function() {
        var self = this;
        var basicContainer = document.getElementById('basic-list-content');
        if (!basicContainer) return;
        
        var basicCheckboxes = basicContainer.querySelectorAll('.menu-checkbox');
        var selected = [];
        
        basicCheckboxes.forEach(function(cb) {
            var path = cb.getAttribute('data-path');
            if (path) {
                selected.push(path);
            }
        });
        
        // console.log('Saving basic menus:', selected);
        
        // 先读取现有配置文件
        fs.read('/etc/config/kucat').then(function(content) {
            var lines = content.split('\n');
            var newContent = [];
            var inBasicSection = false;
            var basicSectionUpdated = false;
            
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i];
                var trimmedLine = line.trim();
                
                // 检查是否进入basic配置段
                if (trimmedLine === 'config basic' || trimmedLine === 'config basic \'settings\'') {
                    inBasicSection = true;
                    newContent.push(line);
                    basicSectionUpdated = true;
                    continue;
                }
                
                // 如果遇到其他config行，退出basic段
                if (inBasicSection && trimmedLine.match(/^config /)) {
                    inBasicSection = false;
                }
                
                // 如果在basic段中，跳过原有的list item行
                if (inBasicSection && trimmedLine.match(/^list item/)) {
                    continue;
                }
                
                // 添加其他行
                newContent.push(line);
            }
            
            // 如果找到了basic段，在段内添加新的list items
            if (basicSectionUpdated) {
                var result = [];
                for (var i = 0; i < newContent.length; i++) {
                    result.push(newContent[i]);
                    // 如果是basic段的开始行，在后面添加list items
                    if (newContent[i].trim() === 'config basic' || newContent[i].trim() === 'config basic \'settings\'') {
                        selected.forEach(function(path) {
                            result.push('    list item \'' + path + '\'');
                        });
                    }
                }
                newContent = result;
            } else {
                // 如果文件中没有basic配置段，添加一个
                newContent.push('');
                newContent.push('config basic \'settings\'');
                selected.forEach(function(path) {
                    newContent.push('    list item \'' + path + '\'');
                });
            }
            
            // 写入更新后的配置
            return fs.write('/etc/config/kucat', newContent.join('\n'));
            
        }).then(function() {
            ui.addNotification({
                title: _('Success'),
                message: _('Configuration saved successfully'),
                type: 'info',
                timeout: 3000
            });
            // 重新加载页面以显示更新后的列表
            setTimeout(function() {
                window.location.reload();
            }, 1000);
        }).catch(function(err) {
            // console.error('Save error:', err);
            ui.addNotification({
                title: _('Error'),
                message: _('Failed to save configuration: ' + (err.message || 'Unknown error')),
                type: 'error',
                timeout: 5000
            });
        });
    },

    handleReset: function() {
        window.location.reload();
    },

    handleCheckboxChange: function() {
        this.updateButtonStates();
        this.updateSelectedCount();
    },

    updateButtonStates: function() {
        var basicContainer = document.getElementById('basic-list-content');
        var allmenuContainer = document.getElementById('allmenu-list-content');
        
        if (!basicContainer || !allmenuContainer) return;
        
        var basicCheckboxes = basicContainer.querySelectorAll('.menu-checkbox');
        var allmenuCheckboxes = allmenuContainer.querySelectorAll('.menu-checkbox');
        
        var hasBasicSelected = Array.from(basicCheckboxes).some(function(cb) {
            return cb.checked;
        });
        var hasallmenuSelected = Array.from(allmenuCheckboxes).some(function(cb) {
            return cb.checked;
        });
        
        var removeButtons = document.querySelectorAll('#kucat-menu-config .cbi-button-remove');
        removeButtons.forEach(function(btn) {
            btn.disabled = !hasBasicSelected;
        });
        
        var addButtons = document.querySelectorAll('#kucat-menu-config .cbi-button-add');
        addButtons.forEach(function(btn) {
            btn.disabled = !hasallmenuSelected;
        });
        
        // 更新选中计数
        this.updateSelectedCount();
    }
});