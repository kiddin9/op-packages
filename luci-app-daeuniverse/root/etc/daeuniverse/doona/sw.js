const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = 'aba7348c316651e5';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-qKwVDZ__.js","assets/AppearanceControls-I4PvP9Es.js","assets/AreaChart-m_wmxFIp.js","assets/AreaCurve-DQSHOSpG.js","assets/BackendText-CxshqKrW.js","assets/CardView-f0UIkdtH.js","assets/ChainFields-BAItfFQK.js","assets/Checkbox-CUoHrzuV.js","assets/CheckboxSet-BThgrv4U.js","assets/CodeEditor-Cb8XCLWG.js","assets/Config-BzyCN_Ax.js","assets/Connections-Dlv_78r1.js","assets/Copy-ftx4Gb2m.js","assets/Coverage-BhgtC9t6.js","assets/DaeCode-DEjXqvav.js","assets/Delete-D69JigFx.js","assets/Dns-CP7rSbYW.js","assets/Dns-CsAXSf3H.css","assets/Donut-DQU0_smr.js","assets/Editors-7UGtyi9X.js","assets/Editors-rPgk_VZK.css","assets/Events-Cz7XGkUG.js","assets/FlagPicker-DkMTBjLE.js","assets/Flows-CFNotQUH.css","assets/Flows-CWq91DGu.js","assets/GridList-Cq8h6RdG.js","assets/ItemText-B5OxI5lS.js","assets/LinkOut-DVAiBR_J.js","assets/Login-Dthlqd0l.js","assets/Logs-B21_MfGT.js","assets/ManualFields-CTj0sr4A.js","assets/ModeReadOnlyHint-D73z908a.js","assets/NodePath-CW8z1Niq.js","assets/Nodes-CM_U6MZ3.css","assets/Nodes-DIVmMRlP.js","assets/NumberField-BGS5AF_x.js","assets/Overview-BUdN7c7l.js","assets/Policies-DR22sMzN.js","assets/Rules-BMHWGCx6.js","assets/SearchDialog-CCF-sgtO.js","assets/SearchList-D75Ie4nx.js","assets/SearchSelect-CSXz7lhe.js","assets/Select-W-Xrx6y6.js","assets/Settings-BVpmQMTB.css","assets/Settings-KwPU8MKD.js","assets/Sparkline-IClrZGcQ.js","assets/SubscriptionFields-DhFfUi4P.js","assets/Table-DotwWze-.js","assets/Tabs-Kfe2CfSx.js","assets/Tag-DE8n6iTZ.js","assets/TimeCell-xtED_iww.js","assets/Trace-DY4zXTiF.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-tkoH0e4V.js","assets/WallpaperSettings-Dynl1X5E.js","assets/XhttpOptions-CFjPLQAZ.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-C22CeO5G.js","assets/activity-Dh87vlBh.css","assets/antd-BTVob2XE.css","assets/arco-DnDQV30N.css","assets/array-C0VuvQyb.js","assets/auth-BIagQEUo.js","assets/auth-BNrY15aC.js","assets/catppuccin-CFfx8ddQ.css","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-BfIUsgdd.js","assets/fonts-C5_wsAqZ.css","assets/geodata-CvcFemyc.js","assets/geodataUpdate-CK75960A.js","assets/glass-BcMm4w7K.js","assets/glass-piYllnzE.css","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/groupFilters-vTIJClEo.js","assets/halloween-Dfny7j3b.js","assets/halloween-e3DfiasY.css","assets/impact-B8feJDtJ.css","assets/index-C4UFgHia.js","assets/index-CQHYBvmE.css","assets/index-DUM-iwa2.js","assets/ipLookup-BYorpVJi.css","assets/ipLookup-Cl7psHhv.js","assets/kary-pGa0AxYi.css","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-DIncl1LE.js","assets/logo-CKC46m8V.svg","assets/logo-obi05X1B.svg","assets/logs-j0cmmcZI.js","assets/match.worker-B2aIccpg.js","assets/nav-DrWHp_dt.js","assets/nav-VzrSXoKO.js","assets/nodes-BXUOUiP2.js","assets/nord-BE7QITf9.css","assets/outbounds-CJznbPkH.js","assets/paletteSheet-Vc0PGoNW.js","assets/paletteSheets-Bf5fGVE_.js","assets/probe-CRm42H8E.js","assets/qiangguo-CTOUSOCk.css","assets/recorder-BHyqDNp5.js","assets/rule-ljMHmFs3.js","assets/semi-DGpddBEP.css","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/subscriptionEntries-CB_uX4nO.js","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-D0fV1e0v.js","assets/useQuickRule-D86TFC6s.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-B4FjBL_G.js","assets/locale-zh-TW-core-DUIVLsYf.js","assets/locale-zh-TW-rest-BCiiZaKK.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity--3M_cvyC.js","assets/locale-zh-CN-core-D8hHJVk2.js","assets/locale-zh-CN-rest-PXwz-ehW.js"],"en":["assets/locale-en-activity-DciTGa2i.js","assets/locale-en-core-B5pEqoG8.js","assets/locale-en-rest-DSXBo_3V.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-Didrg8zX.js"];
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
