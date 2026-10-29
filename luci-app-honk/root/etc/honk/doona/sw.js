const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = '04129d38270446c3';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-DSnjUOi9.js","assets/AppearanceControls-D6ckn4zJ.js","assets/AreaChart-XcehmkGa.js","assets/AreaCurve-DQSHOSpG.js","assets/CardView-DB4CLM1X.js","assets/CodeEditor-Do6bv1iP.js","assets/ConditionRow-DDRkT9im.js","assets/Config-CsnBebfl.js","assets/Connections-CE8HVTjG.js","assets/Copy-8L85FkPb.js","assets/Coverage-D0M5eSx-.js","assets/DaeCode-DEjXqvav.js","assets/Delete-XRP-Yofb.js","assets/Dns-CRdlxhiM.js","assets/Dns-CsAXSf3H.css","assets/Donut-Dvqn45hE.js","assets/Editors-D7yNFTJ4.js","assets/Editors-rPgk_VZK.css","assets/Events-BVGNm2JO.js","assets/FlagPicker-DWPk_M3h.js","assets/Flows-BekA1vQh.css","assets/Flows-MzAGewk3.js","assets/GridList-2xKNlEZe.js","assets/ItemText-EZM3RrYN.js","assets/LinkOut-XZA33RqA.js","assets/Login-D2rVRyYl.js","assets/Logs-B7JeD6qF.js","assets/ModeReadOnlyHint-CuxYuSNG.js","assets/NodePath-C2It1vc3.js","assets/Nodes-CPgu8m3i.js","assets/Nodes-Dz09mbUJ.css","assets/NumberField-DT8-IUla.js","assets/Overview-B0bkmRdH.js","assets/Policies-DtNJCYoo.js","assets/ProbeOptionsDialog-CVvbW9SQ.js","assets/Rules-DC4HCNUS.js","assets/SearchDialog-B8FB1rqR.js","assets/SearchList-D3Aknep5.js","assets/SearchSelect-OEHKvvM7.js","assets/Select-DO5D4JEL.js","assets/Settings-BVpmQMTB.css","assets/Settings-Dvp8atFy.js","assets/Sparkline-C94-T74x.js","assets/SubscriptionFields-DlobjG05.js","assets/Table-CNIdPyPm.js","assets/Tabs-DWzcwxse.js","assets/Tag-D7lhqmBG.js","assets/TimeCell-CIxTaFhT.js","assets/Trace-CqI1I44o.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-Bm8y6eIs.js","assets/WallpaperSettings-72ZDPOH1.js","assets/XhttpOptions-DCivIoC6.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-CKk6X7wg.css","assets/activity-St9WlHNk.js","assets/array-C0VuvQyb.js","assets/auth-BbaGVG7g.js","assets/auth-CnQmki5R.js","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-GETlXTEg.js","assets/fonts-C5_wsAqZ.css","assets/geodata-X0pHz03D.js","assets/geodataUpdate-C5Lm7JjR.js","assets/glass-Cqyc7cvc.js","assets/glass-D3s0PXdk.css","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/impact-B8feJDtJ.css","assets/index-DUM-iwa2.js","assets/index-kgf32cc4.css","assets/index-tt2n9Zk_.js","assets/ipLookup-BYorpVJi.css","assets/ipLookup-D4aKj_sQ.js","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-Da336AR0.js","assets/logo-obi05X1B.svg","assets/logs-DlBF9FTI.js","assets/match.worker-B2aIccpg.js","assets/nav-BBKOedXV.js","assets/nav-BO8viH9G.js","assets/nav-BcPQklmW.js","assets/nav-CMiyhHuu.js","assets/nav-DL8Z2h52.js","assets/nav-c-qn5XzG.js","assets/nav-xLy0j69-.js","assets/nodes-CWX2Nx2b.js","assets/outbounds-DLdbuVA3.js","assets/probe-Bc_Ehmu3.js","assets/recorder-BHyqDNp5.js","assets/rule-C_tGvS3P.js","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-EoqO9l1F.js","assets/useQuickRule-DGnvKUbx.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-DL2nvzYA.js","assets/locale-zh-TW-core-c3IhMc6J.js","assets/locale-zh-TW-rest-B5Rh6v-j.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity-DiYfaPsz.js","assets/locale-zh-CN-core-CSyLpr37.js","assets/locale-zh-CN-rest-D0uTV6mK.js"],"en":["assets/locale-en-activity-Bz2CvEVi.js","assets/locale-en-core-cKs0VyvX.js","assets/locale-en-rest-CV-MTGy4.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-CG7Q_Xp4.js"];
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
