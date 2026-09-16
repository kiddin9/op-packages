import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const source = readFileSync(
  resolve(import.meta.dirname, "../src/resource/menu-shadcn.js"),
  "utf8",
);

const E = (tagName, attributes, children) => ({
  tagName,
  attributes,
  children,
  addEventListener() {},
});

// The module's top level only defines constants and returns the extended
// object, so empty DOM/storage stubs keep the factory inert.
const loadMenuModule = (
  localStorage = {},
  { document = {}, ui = { menu: { getChildren: () => [] } } } = {},
) => {
  const baseclass = {
    extend(module) {
      return module;
    },
  };
  const L = {
    env: { dispatchpath: [], requestpath: [] },
    url: (...segments) => `/${segments.join("/")}`,
  };

  return new Function(
    "baseclass",
    "ui",
    "E",
    "L",
    "_",
    "document",
    "window",
    "localStorage",
    "sessionStorage",
    "navigator",
    source,
  )(
    baseclass,
    ui,
    E,
    L,
    (value) => value,
    document,
    {},
    localStorage,
    {},
    { platform: "" },
  );
};

const RECENTS_KEY = "shadcn.palette.recents";

const fakeStorage = (initial = {}) => {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, String(value)),
    map,
  };
};

const navPage = (path, title, group = "Group") => ({
  title,
  group,
  icon: "activity",
  path,
  href: `/${path}`,
  isLogout: false,
});

const paletteWith = (storage, index) => {
  const module = loadMenuModule(storage);
  module.palIndex = index;
  return module;
};

const browseIndex = () => [
  navPage("admin/status/overview", "概览", "状态"),
  navPage("admin/status/syslog", "系统日志", "状态"),
  navPage("admin/network/iface", "接口", "网络"),
  navPage("admin/network/firewall", "防火墙", "网络"),
  {
    title: "Logout",
    group: null,
    icon: "logout",
    path: "admin/logout",
    href: "/admin/logout",
    isLogout: true,
  },
];

const stored = (recents) => ({ [RECENTS_KEY]: JSON.stringify(recents) });

const paths = (pages) => pages.map((page) => page.path);

test("a recorded pick lands at the head of the stored recents", () => {
  const storage = fakeStorage();
  const palette = paletteWith(storage, browseIndex());

  palette._palRecordRecent("admin/status/syslog");
  palette._palRecordRecent("admin/network/iface");

  assert.deepEqual(JSON.parse(storage.map.get(RECENTS_KEY)), [
    "admin/network/iface",
    "admin/status/syslog",
  ]);
});

test("re-recording a path moves it up instead of duplicating it", () => {
  const storage = fakeStorage(
    stored(["admin/network/iface", "admin/status/syslog"]),
  );
  const palette = paletteWith(storage, browseIndex());

  palette._palRecordRecent("admin/status/syslog");

  assert.deepEqual(JSON.parse(storage.map.get(RECENTS_KEY)), [
    "admin/status/syslog",
    "admin/network/iface",
  ]);
});

test("corrupt or foreign stored values read as no history", () => {
  for (const value of ["not json", '"just a string"', "[1,2,3]", "{}"]) {
    const palette = paletteWith(
      fakeStorage({ [RECENTS_KEY]: value }),
      browseIndex(),
    );
    assert.deepEqual(palette._palReadRecents(), [], value);
  }
});

test("a throwing storage neither breaks reads nor records", () => {
  const hostile = {
    getItem: () => {
      throw new Error("privacy mode");
    },
    setItem: () => {
      throw new Error("quota");
    },
  };
  const palette = paletteWith(hostile, browseIndex());

  assert.deepEqual(palette._palReadRecents(), []);
  assert.doesNotThrow(() => palette._palRecordRecent("admin/status/overview"));
});

test("browsing floats visited pages in recency order, menu order behind", () => {
  const palette = paletteWith(
    fakeStorage(stored(["admin/network/iface", "admin/status/syslog"])),
    browseIndex(),
  );

  assert.deepEqual(paths(palette._palBrowsePages()), [
    "admin/network/iface",
    "admin/status/syslog",
    "admin/status/overview",
    "admin/network/firewall",
  ]);
});

test("vanished paths drop and the rest keep their order", () => {
  const palette = paletteWith(
    fakeStorage(stored(["admin/removed/page", "admin/network/firewall"])),
    browseIndex(),
  );

  assert.deepEqual(paths(palette._palBrowsePages()), [
    "admin/network/firewall",
    "admin/status/overview",
    "admin/status/syslog",
    "admin/network/iface",
  ]);
});

test("the logout leaf stays out of the browse list, stored or not", () => {
  const palette = paletteWith(
    fakeStorage(stored(["admin/logout", "admin/status/syslog"])),
    browseIndex(),
  );

  assert.deepEqual(paths(palette._palBrowsePages()), [
    "admin/status/syslog",
    "admin/status/overview",
    "admin/network/iface",
    "admin/network/firewall",
  ]);
});

// ---- Tabs: third-level menu nodes ----

// ui.menu.getChildren() as luci-base ships it, down to handing out alias
// nodes with their target's children (none, for a tab target).
const menuUi = {
  menu: {
    getChildren: (node) =>
      Object.entries(node?.children ?? {})
        .filter(([, child]) => child.satisfied && "title" in child)
        .map(([name, child]) =>
          child.action?.type === "alias"
            ? { ...child, name, children: undefined }
            : Object.assign(child, { name }),
        )
        .sort((a, b) => (a.order ?? 1000) - (b.order ?? 1000)),
  },
};

const node = (title, order, action, children) => ({
  satisfied: true,
  title,
  order,
  action,
  children,
});
const view = { type: "view" };

const menuBranch = () =>
  node(
    "Administration",
    1,
    { type: "firstchild" },
    {
      status: node("Status", 1, view, {
        overview: node("Overview", 1, view),
        logs: node(
          "System Log",
          2,
          { type: "alias", path: "admin/status/logs/syslog" },
          {
            dmesg: node("Kernel Log", 2, view),
            syslog: node("System Log", 1, view),
          },
        ),
      }),
      system: node("System", 2, view, {
        admin: node(
          "Administration",
          1,
          { type: "firstchild" },
          {
            dropbear: node("SSH Access", 2, view),
            hidden: { satisfied: true, order: 0, action: view },
            password: node("Router Password", 1, view),
          },
        ),
        bmx: node("BMX", 2, view, { nodes: node("Nodes", 1, view) }),
      }),
    },
  );

const initTabbedPalette = (storage = fakeStorage()) => {
  const trigger = {
    querySelector: () => null,
    setAttribute() {},
    addEventListener() {},
  };
  const document = {
    getElementById: (id) => (id === "cmdk-trigger" ? trigger : null),
    addEventListener() {},
  };
  const palette = loadMenuModule(storage, { document, ui: menuUi });
  palette.initPalette(menuBranch(), "admin");
  return palette;
};

test("tabs join the index; a redirecting parent gives way to them", () => {
  const index = initTabbedPalette().palIndex;

  assert.deepEqual(
    index.map((page) => [page.path, page.parent ?? null]),
    [
      ["admin/status/overview", null],
      ["admin/status/logs/syslog", "System Log"],
      ["admin/status/logs/dmesg", "System Log"],
      ["admin/system/admin/password", "Administration"],
      ["admin/system/admin/dropbear", "Administration"],
      ["admin/system/bmx", null],
      ["admin/system/bmx/nodes", "BMX"],
    ],
  );
  assert.equal(index[2].href, "/admin/status/logs/dmesg");
  assert.equal(index[2].group, "Status");
  assert.equal(index[2].icon, "status");
});

test("redirecting parents map to the tab they open", () => {
  assert.deepEqual(initTabbedPalette().palAliases, {
    "admin/status/logs": "admin/status/logs/syslog",
    "admin/system/admin": "admin/system/admin/password",
  });
});

test("a stored parent path reads as its tab, deduplicated", () => {
  const palette = initTabbedPalette(
    fakeStorage(
      stored([
        "admin/system/admin",
        "admin/system/admin/password",
        "admin/status/logs",
      ]),
    ),
  );

  assert.deepEqual(palette._palReadRecents(), [
    "admin/system/admin/password",
    "admin/status/logs/syslog",
  ]);
  assert.deepEqual(paths(palette._palBrowsePages()).slice(0, 3), [
    "admin/system/admin/password",
    "admin/status/logs/syslog",
    "admin/status/overview",
  ]);
});

const menu = loadMenuModule();
const sliced = (text, ranges) =>
  ranges.map(([from, to]) => text.slice(from, to));

test("a parent-only query ties the tabs and ranks them under title hits", () => {
  const title = menu._palScore(
    "firewall",
    "Firewall",
    "admin/status/nftables",
    "Status",
  );
  const zones = menu._palScore(
    "firewall",
    "General Settings",
    "admin/network/firewall/zones",
    "Network",
    "Firewall",
  );
  const forwards = menu._palScore(
    "firewall",
    "Port Forwards",
    "admin/network/firewall/forwards",
    "Network",
    "Firewall",
  );

  assert.equal(zones.score, forwards.score);
  assert.ok(title.score > zones.score);
  assert.equal(zones.ranges, null);
  assert.deepEqual(sliced("Firewall", zones.parentRanges), ["Firewall"]);
});

test("a parent hit outranks a section-label hit", () => {
  const parent = menu._palScore(
    "sys",
    "Kernel Log",
    "admin/status/logs/dmesg",
    "Status",
    "System Log",
  );
  const group = menu._palScore(
    "sys",
    "Startup",
    "admin/system/startup",
    "System",
  );

  assert.ok(parent.score > group.score);
});

test("a spaced query pairs parent words with title words", () => {
  const hit = menu._palScore(
    "firewall  port",
    "Port Forwards",
    "admin/network/firewall/forwards",
    "Network",
    "Firewall",
  );

  assert.ok(hit);
  assert.deepEqual(sliced("Port Forwards", hit.ranges), ["Port"]);
  assert.deepEqual(sliced("Firewall", hit.parentRanges), ["Firewall"]);
  assert.equal(
    menu._palScore(
      "firewall port",
      "Traffic Rules",
      "admin/network/firewall/rules",
      "Network",
      "Firewall",
    ),
    null,
  );
});

test("a query no longer scatters across path segments", () => {
  assert.equal(
    menu._palScore(
      "ssh",
      "Other Settings",
      "admin/services/passwall2/other",
      "Services",
      "PassWall 2",
    ),
    null,
  );
  assert.ok(
    menu._palScore(
      "sshkeys",
      "SSH 密钥",
      "admin/system/admin/sshkeys",
      "系统",
      "管理权",
    ),
  );
});

test("path words land in segments in order, never scattered", () => {
  const score = (q, path, parent) =>
    menu._palScore(q, "无线", path, "网络", parent);

  assert.ok(score("network wireless", "admin/network/wireless"));
  assert.ok(score("status/overview", "admin/status/overview"));
  assert.ok(
    menu._palScore(
      "network firewall",
      "端口转发",
      "admin/network/firewall/forwards",
      "网络",
      "防火墙",
    ),
  );
  assert.equal(score("wireless network", "admin/network/wireless"), null);
  assert.equal(score("netwire", "admin/network/wireless"), null);
  assert.equal(score("/", "admin/network/wireless"), null);
});

test("a parent keeps its row unless it redirects to one of its own tabs", () => {
  const trigger = {
    querySelector: () => null,
    setAttribute() {},
    addEventListener() {},
  };
  const document = {
    getElementById: (id) => (id === "cmdk-trigger" ? trigger : null),
    addEventListener() {},
  };
  const palette = loadMenuModule(fakeStorage(), { document, ui: menuUi });
  const branch = node(
    "Administration",
    1,
    { type: "firstchild" },
    {
      services: node("Services", 1, view, {
        // Redirects to an untitled page, so no tab stands in for it.
        foo: node(
          "Foo",
          1,
          { type: "alias", path: "admin/services/foo/main" },
          {
            main: { satisfied: true, order: 1, action: view },
            log: node("Log", 2, view),
          },
        ),
        bar: node(
          "Bar",
          2,
          { type: "firstchild" },
          { only: { ...node("Only", 1, view), firstchild_ineligible: true } },
        ),
      }),
    },
  );

  palette.initPalette(branch, "admin");

  assert.deepEqual(paths(palette.palIndex), [
    "admin/services/foo",
    "admin/services/foo/log",
    "admin/services/bar",
    "admin/services/bar/only",
  ]);
  assert.deepEqual(palette.palAliases, {});
});

test("recording after a legacy read writes the mapped paths back", () => {
  const storage = fakeStorage(
    stored(["admin/status/logs", "admin/status/overview"]),
  );
  const palette = initTabbedPalette(storage);

  palette._palRecordRecent("admin/system/admin/dropbear");

  assert.deepEqual(JSON.parse(storage.map.get(RECENTS_KEY)), [
    "admin/system/admin/dropbear",
    "admin/status/logs/syslog",
    "admin/status/overview",
  ]);
});

test("a tab row renders its parent before the title unless they share a name", () => {
  const palette = loadMenuModule();
  palette._sectionIcon = () => "";
  const tabPage = (title) => ({
    title,
    parent: "Firewall",
    group: "Network",
    icon: "network",
    path: "admin/network/firewall/x",
    href: "/x",
    isLogout: false,
  });
  const marked = (parts) => parts.some((part) => part.tagName === "mark");

  const forwards = palette._palPageRow(tabPage("Port Forwards"), null, null, [
    [0, 4],
  ]).children[1].children;
  assert.deepEqual(
    forwards.map((part) => part.attributes.class),
    ["cmdk-parent", "cmdk-label"],
  );
  assert.ok(marked(forwards[0].children));
  assert.deepEqual(forwards[1].children, ["Port Forwards"]);

  const same = palette._palPageRow(tabPage("Firewall"), [[0, 4]]).children[1]
    .children;
  assert.ok(marked(same));
  assert.ok(!same.some((part) => part.attributes?.class === "cmdk-parent"));
});
