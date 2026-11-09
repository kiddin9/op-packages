const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = 'e85fc6a59ad04821';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-6b-rL1eo.js","assets/AppearanceControls-CEVO9-aR.js","assets/AreaChart-B0HmHYXx.js","assets/AreaCurve-DQSHOSpG.js","assets/BackendText-DK5RWFKi.js","assets/CardView-jh7SJ_si.js","assets/Checkbox-CsFZSc5N.js","assets/CheckboxSet-C1rY3UKa.js","assets/CodeEditor-9GVA7w36.js","assets/Config-DPN1ciCe.js","assets/Connections-BPMOPt05.js","assets/Copy-Dw2ag2LB.js","assets/Coverage-CsDZglAg.js","assets/DaeCode-DEjXqvav.js","assets/Delete-DqJAS65M.js","assets/Dns-CsAXSf3H.css","assets/Dns-fSskIZZh.js","assets/Donut-D4QPrxiw.js","assets/Editors-BlMhsZNx.js","assets/Editors-rPgk_VZK.css","assets/Events-DwM4OJI7.js","assets/FlagPicker-9QJIrYuT.js","assets/Flows-BekA1vQh.css","assets/Flows-CN4scPGP.js","assets/GridList-Dgo5IXUg.js","assets/ItemText-D6SGBgOi.js","assets/LinkOut-BYZWxkzu.js","assets/Login-Df-pKhHQ.js","assets/Logs-B5y3FE3n.js","assets/ManualFields-CmbVQgLM.js","assets/ModeReadOnlyHint-D3IWP6gj.js","assets/NodePath-DbG_-_A4.js","assets/Nodes-CM_U6MZ3.css","assets/Nodes-oYqjPYEh.js","assets/NumberField-C8qnuOCX.js","assets/Overview-Cj-FUrIA.js","assets/Policies-CXlyfzr3.js","assets/Rules-DAeSUjlv.js","assets/SearchDialog-B9DM3vJ5.js","assets/SearchList-LS4kpJXT.js","assets/SearchSelect-q5tbOYXk.js","assets/Select-hQ95uOjm.js","assets/Settings-BVpmQMTB.css","assets/Settings-zm4J70HT.js","assets/Sparkline-Bn_AHmiF.js","assets/SubscriptionFields-DfTLDtXc.js","assets/Table-Cc5T3jJO.js","assets/Tabs-PDr10lJU.js","assets/Tag-D4suq1U_.js","assets/TimeCell-DSeESBN3.js","assets/Trace-DBPbFVPm.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-9R4wsZhf.js","assets/WallpaperSettings-UQGzwYIT.js","assets/XhttpOptions-j6QnBUMz.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-BoXvjA12.js","assets/activity-CgcM8uHz.css","assets/antd-BTVob2XE.css","assets/arco-DnDQV30N.css","assets/array-C0VuvQyb.js","assets/auth-6JyCJBV2.js","assets/auth-DQ-HlQv0.js","assets/catppuccin-CFfx8ddQ.css","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-C0jcpIhs.js","assets/fonts-C5_wsAqZ.css","assets/geodata-CvcFemyc.js","assets/geodataUpdate-BQgn8VND.js","assets/glass-BcMm4w7K.js","assets/glass-piYllnzE.css","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/groupFilters-D2DpD7-F.js","assets/halloween-Dfny7j3b.js","assets/halloween-e3DfiasY.css","assets/impact-B8feJDtJ.css","assets/index-C06va4Yw.js","assets/index-DUM-iwa2.js","assets/index-DdIDwpAM.css","assets/ipLookup-BYorpVJi.css","assets/ipLookup-CdclczzV.js","assets/kary-pGa0AxYi.css","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-Cb7NYoro.js","assets/logo-CKC46m8V.svg","assets/logo-obi05X1B.svg","assets/logs-BtAlqVqe.js","assets/match.worker-B2aIccpg.js","assets/nav-BEjkpsy8.js","assets/nav-BvgMebTJ.js","assets/nodes-oXccX15o.js","assets/nord-BE7QITf9.css","assets/outbounds-ynHeqeCa.js","assets/paletteSheet-Vc0PGoNW.js","assets/paletteSheets-Bf5fGVE_.js","assets/probe-y8tWllpS.js","assets/qiangguo-CTOUSOCk.css","assets/recorder-BHyqDNp5.js","assets/rule-C_M_c6EN.js","assets/semi-DGpddBEP.css","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/subscriptionEntries-BusVyEOj.js","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-inhSeUkV.js","assets/useQuickRule-CCpuINzQ.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-OwlmpZI1.js","assets/locale-zh-TW-core-CXhgGZht.js","assets/locale-zh-TW-rest-CQx8azuQ.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity-oeOXoHOS.js","assets/locale-zh-CN-core-Bee1WHW4.js","assets/locale-zh-CN-rest-yHdYfxj5.js"],"en":["assets/locale-en-activity-8ELc1Zfz.js","assets/locale-en-core-DaThY8z_.js","assets/locale-en-rest-BiF8xsQr.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-r_PqDIOh.js"];
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
