/* SPDX-License-Identifier: Apache-2.0 */
(function() {
 'use strict';
 function init() {
  var menu = document.getElementById('topmenu'), content = document.getElementById('maincontent');
  if (!menu || !content || document.getElementById('rmm-menu-search')) return;
  var dictionaries = {
   ru: {'Menu search':'Поиск по меню','Search':'Поиск','Close':'Закрыть','Search available pages':'Поиск доступных страниц','No matching pages':'Нет подходящих страниц','Results':'Результаты','Use Up/Down to select, Enter to open, Escape to close.':'Выбор: вверх/вниз. Открыть: Enter. Закрыть: Escape.'},
   zh: {'Menu search':'菜单搜索','Search':'搜索','Close':'关闭','Search available pages':'搜索可用页面','No matching pages':'没有匹配页面','Results':'结果','Use Up/Down to select, Enter to open, Escape to close.':'使用上下键选择，Enter 打开，Escape 关闭。'}
  };
  function text(value) { var language = (document.documentElement.lang || '').split('-')[0];return dictionaries[language] && dictionaries[language][value] || value; }
  function node(tag, attributes, value) { var el=document.createElement(tag);Object.keys(attributes || {}).forEach(function(key) { el.setAttribute(key,attributes[key]); });if (value) el.textContent=value;return el; }
  var trigger=node('button',{type:'button','class':'btn',hidden:'','aria-haspopup':'dialog','aria-controls':'rmm-menu-search','aria-keyshortcuts':'Control+k Meta+k'},text('Search') + ' · Ctrl+K');
  var launch=node('div',{'class':'rmm-search-launcher'});launch.appendChild(trigger);content.prepend(launch);
  var dialog=node('dialog',{id:'rmm-menu-search','class':'rmm-menu-search','aria-labelledby':'rmm-search-title'});
  var title=node('h2',{id:'rmm-search-title'},text('Menu search'));
  var close=node('button',{type:'button','class':'btn'},text('Close'));
  var heading=node('div',{'class':'rmm-search-heading'});heading.append(title,close);
  var label=node('label',{for:'rmm-search-query'},text('Search available pages'));
  var input=node('input',{id:'rmm-search-query',type:'search',autocomplete:'off',maxlength:'128','aria-describedby':'rmm-search-help'});
  var help=node('p',{id:'rmm-search-help','class':'rmm-search-meta'},text('Use Up/Down to select, Enter to open, Escape to close.'));
  var status=node('p',{'class':'rmm-search-meta',role:'status','aria-live':'polite'});
  var results=node('ul',{'class':'rmm-search-results'});
  dialog.append(heading,label,input,help,status,results);document.body.appendChild(dialog);
  var entries=[],previousFocus=null,scheduled=false;
  function indexMenu() {
   var seen = new Set();entries=[];
   menu.querySelectorAll('a[href]').forEach(function(link) {
    if (link.closest('[hidden], [aria-hidden="true"], [aria-disabled="true"]') || link.hasAttribute('disabled')) return;
    var raw=link.getAttribute('href'),url;
    if (!raw || raw.charAt(0)==='#') return;
    try { url=new URL(raw,location.href); } catch (_) { return; }
    var marker=location.pathname.indexOf('/admin'), root=marker < 0 ? null : location.pathname.slice(0,marker+6);
    if (root && location.pathname.length > root.length && location.pathname.charAt(root.length)!=='/') root=null;
    if (!root || url.origin!==location.origin || !url.pathname.startsWith(root+'/') || url.pathname.split('/').includes('logout')) return;
    var label=(link.getAttribute('aria-label') || link.textContent).trim();
    if (!label || seen.has(url.href)) return;
    var parent=link.parentElement.parentElement.closest('li');
    var group=parent && parent.querySelector(':scope > a');
    var category=group && (group.getAttribute('aria-label') || group.textContent).trim();
    var name=category && category!==label ? category + ' / ' + label : label;
    var synonyms={'dashboard':'обзор дашборд панель сводка','wireless':'вайфай wi-fi wifi беспроводная ssid','network':'сеть lan wan интерфейсы','dhcp':'аренды адреса клиенты leases','dns':'днс резолвер имена','firewall':'файрвол фаервол правила защита','system':'система время часы timezone','flash':'прошивка резервная копия backup обновление','startup':'автозапуск службы сервисы','reboot':'перезагрузка рестарт','package-manager':'пакеты установка opkg apk','admin':'пароль ssh доступ'};
    var aliases=url.pathname.split('/').slice(4).map(function(part){return synonyms[part] || '';}).join(' ');
    entries.push({name:name,href:url.href,search:(name+' '+url.pathname+' '+aliases).toLowerCase()});seen.add(url.href);
   });
   trigger.hidden=!entries.length || typeof dialog.showModal!=='function';
   if (dialog.hasAttribute('open')) renderResults();
  }
  function renderResults() {
   var active=document.activeElement,oldHref=results.contains(active) ? active.getAttribute('href') : null;
   var terms=input.value.trim().toLowerCase().split(/[ ]+/).filter(Boolean);
   var matching=entries.filter(function(entry) { return terms.every(function(term) { return entry.search.includes(term); }); });
   results.replaceChildren();
   matching.slice(0,50).forEach(function(entry) { var li=node('li'),link=node('a',{href:entry.href},entry.name);li.appendChild(link);results.appendChild(li); });
   var message=matching.length ? text('Results') + ': ' + Math.min(50,matching.length) + ' / ' + matching.length : text('No matching pages');
   if (status.textContent!==message) status.textContent=message;
   if (oldHref) { var replacement=Array.from(results.querySelectorAll('a')).find(function(link) { return link.getAttribute('href')===oldHref; });(replacement || input).focus(); }
  }
  function open() {
   if (document.body.classList.contains('modal-overlay-active') || Array.from(document.querySelectorAll('dialog[open]')).some(function(other) { return other!==dialog; })) return;
   indexMenu();if (trigger.hidden) return;
   if (!dialog.hasAttribute('open')) { previousFocus=document.activeElement;dialog.showModal(); }
   input.value='';renderResults();input.focus();
  }
  trigger.addEventListener('click',open);close.addEventListener('click',function() { dialog.close(); });
  dialog.addEventListener('close',function() { if (previousFocus && previousFocus.isConnected) previousFocus.focus(); });
  input.addEventListener('input',renderResults);
  dialog.addEventListener('keydown',function(event) {
   var links=Array.from(results.querySelectorAll('a')),active=document.activeElement,index=links.indexOf(active);
   if (event.key==='ArrowDown' || event.key==='ArrowUp') {
    event.preventDefault();if (links.length) links[index < 0 ? event.key==='ArrowDown' ? 0 : links.length-1 : (index+(event.key==='ArrowDown'?1:-1)+links.length)%links.length].focus();
   }
   if (event.key==='Enter' && active===input && links.length) { event.preventDefault();links[0].click(); }
   if (event.key==='Escape') { event.preventDefault();dialog.close(); }
   if (event.key==='Tab') {
    var controls=[close,input].concat(links),first=controls[0],last=controls[controls.length-1];
    if (event.shiftKey && active===first) { event.preventDefault();last.focus(); }
    else if (!event.shiftKey && active===last) { event.preventDefault();first.focus(); }
   }
  });
  document.addEventListener('keydown',function(event) {
   if (!(event.ctrlKey || event.metaKey) || event.altKey || event.shiftKey || event.key.toLowerCase()!=='k') return;
   if (event.target && event.target.closest('input, textarea, select, [contenteditable]') && !dialog.contains(event.target)) return;
   if (trigger.hidden || document.body.classList.contains('modal-overlay-active') || Array.from(document.querySelectorAll('dialog[open]')).some(function(other) { return other!==dialog; })) return;event.preventDefault();open();
  });
  new MutationObserver(function() { if (!scheduled) { scheduled=true;Promise.resolve().then(function() { scheduled=false;indexMenu(); }); } }).observe(menu,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['href','hidden','aria-hidden','aria-disabled']});
  indexMenu();
 }
 if (document.readyState==='loading') document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
