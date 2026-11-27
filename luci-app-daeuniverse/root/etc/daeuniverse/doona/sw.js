const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = 'dad7c5281aa795a6';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-Btq0vXOQ.js","assets/AppearanceControls-DBwh-zC-.js","assets/AreaChart-BzuUSbSh.js","assets/AreaCurve-DQSHOSpG.js","assets/BackendText-DQ9qUdjJ.js","assets/CardView-Dn1jAvjW.js","assets/Checkbox-Dmt59vcH.js","assets/CheckboxSet-DxawyCCb.js","assets/CodeEditor-Bm8hPIpW.js","assets/Config-T24sUVt9.js","assets/Connections-BLE9iQwc.js","assets/Copy-DRjWRYp2.js","assets/Coverage-DUpycOrL.js","assets/DaeCode-DEjXqvav.js","assets/Delete-BILfQYDi.js","assets/Dns-BpPYqjjz.js","assets/Dns-CsAXSf3H.css","assets/Donut-DQ9K6naH.js","assets/Editors-Cgu6fYZK.js","assets/Editors-rPgk_VZK.css","assets/Events-Cyaex2-O.js","assets/FlagPicker-BUoWF_Fg.js","assets/Flows-CFNotQUH.css","assets/Flows-DmqnWkFP.js","assets/GridList-LKhrHaDu.js","assets/ItemText-BKQsIL9J.js","assets/LinkOut-B809ETV1.js","assets/Login-C_JEnRe7.js","assets/Logs-blXUjVhM.js","assets/ManualFields-CJBOILrb.js","assets/ModeReadOnlyHint-DcZsiUeq.js","assets/NodePath-Mbm3X8yC.js","assets/Nodes-CM_U6MZ3.css","assets/Nodes-Doi3Ljki.js","assets/NumberField-BKJB01jy.js","assets/Overview-iHSRVtRC.js","assets/Policies-1IIuQ3V9.js","assets/Rules-68w3pJWl.js","assets/SearchDialog-DCQKEiy_.js","assets/SearchList-DxYORQYX.js","assets/SearchSelect-C3Fe_yJs.js","assets/Select-DRH9r7vF.js","assets/Settings-BVpmQMTB.css","assets/Settings-BlCu877u.js","assets/Sparkline-C7opz8sl.js","assets/SubscriptionFields-BexMNHwS.js","assets/Table-DV0Oj4uh.js","assets/Tabs-CDT0zwMQ.js","assets/Tag-B9DAYYG_.js","assets/TimeCell-k-eFblZS.js","assets/Trace-BL9Ep3TH.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-hnw6vdfK.js","assets/WallpaperSettings-Ds_XLbqM.js","assets/XhttpOptions-B4JR0VVl.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-B7D0HvF_.js","assets/activity-Dh87vlBh.css","assets/antd-BTVob2XE.css","assets/arco-DnDQV30N.css","assets/array-C0VuvQyb.js","assets/auth-BJ0AQAgw.js","assets/auth-DFVs6nFP.js","assets/catppuccin-CFfx8ddQ.css","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-C2gUotC0.js","assets/fonts-C5_wsAqZ.css","assets/geodata-CvcFemyc.js","assets/geodataUpdate-CdVmWrsL.js","assets/glass-BcMm4w7K.js","assets/glass-piYllnzE.css","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/groupFilters-DgQHc307.js","assets/halloween-Dfny7j3b.js","assets/halloween-e3DfiasY.css","assets/impact-B8feJDtJ.css","assets/index-Bfx9IpuR.js","assets/index-DU395y_R.css","assets/index-DUM-iwa2.js","assets/ipLookup-BYorpVJi.css","assets/ipLookup-C6_WsRFw.js","assets/kary-pGa0AxYi.css","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-DTUX3nLM.js","assets/logo-CKC46m8V.svg","assets/logo-obi05X1B.svg","assets/logs-BocnSCS1.js","assets/match.worker-B2aIccpg.js","assets/nav-C8HtUxRz.js","assets/nav-DO6EyYn2.js","assets/nodes-DmwG6sng.js","assets/nord-BE7QITf9.css","assets/outbounds-BT-CxnPY.js","assets/paletteSheet-Vc0PGoNW.js","assets/paletteSheets-Bf5fGVE_.js","assets/probe-4Osvxh41.js","assets/qiangguo-CTOUSOCk.css","assets/recorder-BHyqDNp5.js","assets/rule-D3MNMhl0.js","assets/semi-DGpddBEP.css","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/subscriptionEntries-Cnm3ET_a.js","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-CE9YClHs.js","assets/useQuickRule-yAKiFJK-.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-fRKz10-p.js","assets/locale-zh-TW-core-CXhgGZht.js","assets/locale-zh-TW-rest-Nw0kR3k8.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity-BJWaMDih.js","assets/locale-zh-CN-core-Bee1WHW4.js","assets/locale-zh-CN-rest-6b40OSIu.js"],"en":["assets/locale-en-activity-EBNyCYzq.js","assets/locale-en-core-DaThY8z_.js","assets/locale-en-rest-7Y2RmrcJ.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-B846UBiM.js"];
const ROOT = new URL(self.registration.scope);

// A new build takes over on the next online load, including open dashboard tabs.
// Each build records when it was installed, so activation can tell the build it replaces from older ones.
const STAMP = new URL('__installed__', ROOT);
// index.html keeps its name across builds, so it is fetched past the HTTP cache: a caching proxy cannot hand the new
// build an old shell. A file under assets/ is named after its content hash, so the copy the page already loaded through
// the HTTP cache is the same file and is not downloaded again.
const precacheRequest = url => (url.startsWith('assets/') ? url : new Request(url, {cache: 'reload'}));
self.addEventListener('install', event => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then(cache => Promise.all([cache.addAll(PRECACHE.map(precacheRequest)), cache.put(STAMP, new Response(String(Date.now())))]))
      .then(() => self.skipWaiting())
  );
});
// A page loads its catalogue and backend before this worker controls it, so it reports the language it shows and
// whether it runs on the mock, to have them cached.
self.addEventListener('message', event => {
  if (event.data?.build === true) {
    event.ports[0]?.postMessage(BUILD);
    return;
  }
  const lang = event.data?.language;
  const files = [...(typeof lang === 'string' && Object.hasOwn(LANGUAGES, lang) ? LANGUAGES[lang] : []), ...(event.data?.mock === true ? MOCK : [])];
  if (!files.length) return;
  event.waitUntil(caches.open(CACHE).then(cache => Promise.all(files.map(async url => (await cache.match(url, {ignoreVary: true})) ?? cache.add(url)))));
});
// The build just replaced stays: tabs still showing it load their remaining chunks from it until reloaded.
self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      const older = [];
      for (const key of await caches.keys()) {
        if (!key.startsWith(PREFIX) || key === CACHE) continue;
        const stamp = await (await caches.open(key)).match(STAMP);
        older.push({key, installed: stamp ? Number(await stamp.text()) : 0});
      }
      older.sort((a, b) => b.installed - a.installed);
      await Promise.all(older.slice(1).map(({key}) => caches.delete(key)));
      await self.clients.claim();
    })()
  );
});

function hit(response) {
  if (!response) return Response.error();
  const headers = new Headers(response.headers);
  headers.set('x-doona-sw', 'hit');
  return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
}

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== ROOT.origin || /\/api(?:\/|$)/.test(url.pathname) || !url.pathname.startsWith(ROOT.pathname)) return;
  if (url.pathname.startsWith(new URL('lite/', ROOT).pathname)) return;
  const navigation = request.mode === 'navigate';
  if (!navigation && !/^(assets|fonts|icons)\//.test(url.pathname.slice(ROOT.pathname.length))) return;
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      if (navigation) {
        try {
          return await fetch(request);
        } catch {
          return hit(await cache.match(new URL('index.html', ROOT)));
        }
      }
      // A build file is the same for every requester, so a server's Vary: Origin must not turn a cached copy into a miss.
      const response = (await cache.match(request, {ignoreVary: true})) ?? (await caches.match(request, {ignoreVary: true}));
      if (response) return hit(response);
      const fresh = await fetch(request);
      // A host may answer a missing file with the page; caching that would keep the file missing once it is installed.
      if (fresh.ok && fresh.type === 'basic' && !fresh.redirected && !fresh.headers.get('content-type')?.includes('html'))
        await cache.put(request, fresh.clone());
      return fresh;
    })()
  );
});
