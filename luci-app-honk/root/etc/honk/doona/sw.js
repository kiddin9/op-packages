const PREFIX = `doona-shell:${self.registration.scope}:`;
// The page reads the same build from index.html, to tell whether this worker taking it over is a new build.
const BUILD = '99fcca42805aac47';
const CACHE = PREFIX + BUILD;
const PRECACHE = ["assets/AddCircle-D2cMd6zF.js","assets/AppearanceControls-E-VPhjIz.js","assets/AreaChart-Ci1Uh0tf.js","assets/AreaCurve-DQSHOSpG.js","assets/BackendText-Dtw6qhij.js","assets/CardView-N7n2PJ-s.js","assets/Checkbox-8Iqnc6T1.js","assets/CheckboxSet-CZH2lrzI.js","assets/CodeEditor-DCw5LkC0.js","assets/Config-DqTXXH6g.js","assets/Connections-6ME7y64q.js","assets/Copy-CO66tox2.js","assets/Coverage-BJRxyviT.js","assets/DaeCode-DEjXqvav.js","assets/Delete-D-jw0Qv4.js","assets/Dns-BoEQQlrw.js","assets/Dns-CsAXSf3H.css","assets/Donut-CaWe91EB.js","assets/Editors-DF8AauI-.js","assets/Editors-rPgk_VZK.css","assets/Events-C4f8u4ie.js","assets/FlagPicker-BI-GnHgk.js","assets/Flows-BekA1vQh.css","assets/Flows-sA9EQ0Nt.js","assets/GridList-CQPDUasC.js","assets/ItemText-CnEXu0-f.js","assets/LinkOut-B2JdPfjI.js","assets/Login-CQ8wv6QO.js","assets/Logs-BusGYLIA.js","assets/ManualFields-DHf-9v_o.js","assets/ModeReadOnlyHint-DXD7rshf.js","assets/NodePath-BtHMV14P.js","assets/Nodes-Dz09mbUJ.css","assets/Nodes-dSDkBdMR.js","assets/NumberField-C_bakFfF.js","assets/Overview-DS2qv84b.js","assets/Policies-BGgc6lxy.js","assets/Rules-Hq71-PZg.js","assets/SearchDialog-VfSZ0gQR.js","assets/SearchList-DMvmI1K7.js","assets/SearchSelect-Fy-2ASgN.js","assets/Select-BA0NS1_z.js","assets/Settings-B6Ds1-yl.js","assets/Settings-BVpmQMTB.css","assets/Sparkline-CGmJj9ao.js","assets/SubscriptionFields-CPXw0oPX.js","assets/Table-DX856nrS.js","assets/Tabs-DiTlqyjA.js","assets/Tag-4SaGY8GT.js","assets/TimeCell-N-r54xmV.js","assets/Trace-bE6wprsq.js","assets/TwemojiCountryFlags-Bymva2JV.woff2","assets/Virtualizer-UMC7L0o2.js","assets/WallpaperSettings-CrxyWVw_.js","assets/XhttpOptions-DeiAyCza.js","assets/_commonjsHelpers-CXUWDbkB.js","assets/activity-B3PmJo_X.js","assets/activity-CgcM8uHz.css","assets/array-C0VuvQyb.js","assets/auth-DucfFvIi.js","assets/auth-hmN4lsTM.js","assets/daeTokens-BVtuNnWZ.js","assets/duck-night-CbKHyiul.webp","assets/files-Dt8K7QfP.js","assets/flows-DS-lcTPn.js","assets/fonts-C5_wsAqZ.css","assets/geodata-CvcFemyc.js","assets/geodataUpdate-C1V3fVK8.js","assets/glass-D8tYX8mi.js","assets/glass-piYllnzE.css","assets/gorges-dark-FlgXSNn1.webp","assets/gorges-light-DCWkLX37.webp","assets/halloween-Dfny7j3b.js","assets/halloween-e3DfiasY.css","assets/impact-B8feJDtJ.css","assets/index-CUHkLMAp.js","assets/index-DUM-iwa2.js","assets/index-DhY2A0CV.css","assets/ipLookup-BYorpVJi.css","assets/ipLookup-CY9MTfz2.js","assets/labels-D8xxfRTQ.js","assets/lake-dark-B_VaUlAe.webp","assets/lake-light-oWll36-V.webp","assets/lens-BMneTJKP.js","assets/limitHint-nHl9AqvH.js","assets/logo-CKC46m8V.svg","assets/logo-obi05X1B.svg","assets/logs-C6Kb44nw.js","assets/match.worker-B2aIccpg.js","assets/nav-C94cbBA2.js","assets/nav-Dn-_mMqu.js","assets/nodes-BYMoo8M1.js","assets/outbounds-CUiHWeth.js","assets/paletteSheet-Vc0PGoNW.js","assets/probe-Cuvc4PWQ.js","assets/recorder-BHyqDNp5.js","assets/rule-D4-Og0AG.js","assets/square-dark-CG0rwsS1.webp","assets/square-light-OU6dsCf9.webp","assets/subscriptionEntries-JdG-Ijgl.js","assets/taishan-dark-BI3cd4fj.webp","assets/taishan-light-Dip0HmJZ.webp","assets/useGridSelectionCheckbox-CTBMGgmQ.js","assets/useQuickRule-Cd5z6aFL.js","assets/vendor-editor-50h2cCk6.js","assets/vendor-react-64fcanlc.js","assets/wall-dark-DCO0xUUO.webp","assets/wall-light-BYfte2Bi.webp","assets/wallpaper-CEC7gitM.js","index.html"];
// Each language's catalogue and stylesheets in this build, cached only for a language a reader uses. A partial
// language's list holds the reference language's files too, since it loads them.
const LANGUAGES = {"zh-TW":["assets/fonts-tc-D9rvq3k7.css","assets/locale-zh-TW-activity-CopnBuwF.js","assets/locale-zh-TW-core-DAYvUvJV.js","assets/locale-zh-TW-rest-DipSnd54.js"],"zh-CN":["assets/fonts-sc-Dyn9aW84.css","assets/locale-zh-CN-activity-CjG6S6CQ.js","assets/locale-zh-CN-core-CAxois-L.js","assets/locale-zh-CN-rest-B5XCKaN5.js"],"en":["assets/locale-en-activity-B6t-8m5i.js","assets/locale-en-core-B9JMncJj.js","assets/locale-en-rest-DYQhiAUt.js"]};
// The mock backend's chunk, cached only for a page that runs on it.
const MOCK = ["assets/index-CevJ0lw3.js"];
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
