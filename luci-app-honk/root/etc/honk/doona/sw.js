const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = '33deb150aebd50e3';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-V0Kluz-m.js","assets/AppearanceControls-Bpq6OQjk.js","assets/AreaChart-BxyW1lgi.js","assets/AreaCurve-DQSHOSpG.js","assets/CardView-CwlxcqMf.js","assets/Checkbox-xU-Ds7Hn.js","assets/CheckboxSet-CRYfymLL.js","assets/CodeEditor-DW62W8R0.js","assets/Config-DdQPDBRG.js","assets/Connections-E-DQbY3S.js","assets/Copy-DRn0jPgo.js","assets/Coverage-BRhvKmi_.js","assets/DaeCode-DEjXqvav.js","assets/Delete-DIaM96Pb.js","assets/Dns-CsAXSf3H.css","assets/Dns-Ct51pA2s.js","assets/Donut-Cogv0HSG.js","assets/Editors-CMGR9TtS.js","assets/Editors-rPgk_VZK.css","assets/Events-BNRsSpN9.js","assets/FlagPicker-DZPvPF1E.js","assets/Flows-BekA1vQh.css","assets/Flows-DfgvM-Ta.js","assets/GridList-BuXKU7Uk.js","assets/ItemText-u3CUc_6I.js","assets/LinkOut-B50sd8cz.js","assets/Login-DaBUo9Xb.js","assets/Logs-C9CHXk6c.js","assets/ModeReadOnlyHint-DDRE5yga.js","assets/NodePath-DCKKYRsk.js","assets/Nodes-BP4CnthX.js","assets/Nodes-Dz09mbUJ.css","assets/NumberField-kCp6sey7.js","assets/Overview-CgY0TDEB.js","assets/Policies-SR8BE_dk.js","assets/ProbeOptionsDialog-BDgL7_BI.js","assets/Rules-Bt5JZQKX.js","assets/SearchDialog-CznCqNH0.js","assets/SearchList-C88Y6c53.js","assets/SearchSelect-CsXd0DEh.js","assets/Select-BFkb6iie.js","assets/Settings-BVpmQMTB.css","assets/Settings-IzcnYfjs.js","assets/Sparkline-DULE2gkm.js","assets/SubscriptionFields-CWqR97pB.js","assets/Table-6xnX6eUx.js","assets/Tabs-HxpCyCLR.js","assets/Tag-BZqiYh1Z.js","assets/TimeCell-CRwMWdtu.js","assets/Trace-CDFraj3q.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-BH6NJSXn.js","assets/WallpaperSettings-Bkh54SrZ.js","assets/XhttpOptions-BHPc7rZI.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-CKk6X7wg.css","assets/activity-pUN0wcVd.js","assets/array-C0VuvQyb.js","assets/auth-Br_GGGEt.js","assets/auth-rPpvn4ox.js","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-Cd1KbGP2.js","assets/fonts-C5_wsAqZ.css","assets/geodata-CvcFemyc.js","assets/geodataUpdate-BANPx3Of.js","assets/glass-BaA-OKzR.css","assets/glass-D0JDY1or.js","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/halloween-Dfny7j3b.js","assets/halloween-e3DfiasY.css","assets/impact-B8feJDtJ.css","assets/index-BnzLYrTn.css","assets/index-DFPUSiWe.js","assets/index-DUM-iwa2.js","assets/ipLookup-47nEpvjK.js","assets/ipLookup-BYorpVJi.css","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-drqGf1xh.js","assets/logo-CKC46m8V.svg","assets/logo-obi05X1B.svg","assets/logs-lI5kXcWp.js","assets/match.worker-B2aIccpg.js","assets/nav-BLmatpph.js","assets/nav-BO8viH9G.js","assets/nav-Bw7F3lhF.js","assets/nav-C6jMmQ4d.js","assets/nav-CISoRdvs.js","assets/nav-CfbmlNWr.js","assets/nav-lSzYOU50.js","assets/nodes-HzIJdCpg.js","assets/outbounds-BMHzxQr8.js","assets/paletteSheet-Vc0PGoNW.js","assets/probe-Db_cbYvO.js","assets/recorder-BHyqDNp5.js","assets/rule-D1hMywhM.js","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-wMhI-U-R.js","assets/useQuickRule-BGNvNXBX.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-C7Vz2kIV.js","assets/locale-zh-TW-core-C7Ay33Lr.js","assets/locale-zh-TW-rest-UNIj0wey.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity-B_7_QXPJ.js","assets/locale-zh-CN-core-BfCAILG5.js","assets/locale-zh-CN-rest-BcxkEWKL.js"],"en":["assets/locale-en-activity-D3WqzCdU.js","assets/locale-en-core-BYFqSMNd.js","assets/locale-en-rest-CE5BtEfD.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-D2MLmo5c.js"];
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
