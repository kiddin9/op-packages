// build.mjs
import {build} from 'esbuild';
import fs from 'fs';
import path from 'path';
import {fileURLToPath} from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 源码目录（你问的“入口目录”）
const VIEWS_DIR = path.join(__dirname, 'views');
// 输出目录
const DIST_DIR = path.join(__dirname, '../htdocs/luci-static/resources/view/hijpass');
const runtimePackages = new Set();

// 限定哪些 from 模块名当作 luci 模块（name = require name）
const luciModuleNames = new Set(
    ['view', 'fs', 'form', 'uci', 'ui', 'network', 'baseclass', 'rpc', 'poll', 'hijpass.editor', 'hijpass.drafts', 'request', 'session']);

/**
 * 扫描 views 目录下的所有 .ts 文件，返回绝对路径列表
 */
function scanEntryFiles(dir) {
    const files = fs.readdirSync(dir, {withFileTypes: true});
    const entries = [];

    for (const file of files) {
        if (file.isDirectory()) {
            // 若你需要递归子目录，这里可以继续深入
            const subDir = path.join(dir, file.name);
            entries.push(...scanEntryFiles(subDir));
        } else if (file.isFile() && file.name.endsWith('.ts')) {
            entries.push(path.join(dir, file.name));
        }
    }

    return entries;
}

/**
 * 为单个入口文件构建（entryPath 为绝对路径）
 */
async function buildOne(entryPath, outFile = path.join(DIST_DIR, path.relative(VIEWS_DIR, entryPath).replace(/\.ts$/, '.js'))) {
    // 本次构建中用到的 luci 模块名
    const usedModules = new Set();

    const luciPlugin = {
        name: 'luci-from-plugin',
        setup(pluginBuild) {
            pluginBuild.onResolve({filter: /.*/}, args => {
                if (luciModuleNames.has(args.path)) {
                    usedModules.add(args.path);
                    return {
                        path: args.path,
                        namespace: 'luci-virtual'
                    };
                }
            });

            pluginBuild.onLoad({filter: /.*/, namespace: 'luci-virtual'}, args => {
                const moduleName = args.path;
                const code = `
          // Virtual luci module: ${moduleName}
          export default ${moduleName.replace(/[^a-zA-Z0-9_]/g, '_')};
        `;
                return {
                    contents: code,
                    loader: 'ts'
                };
            });
        }
    };

    const result = await build({
        entryPoints: [entryPath],
        bundle: true,
        platform: 'browser',
        format: 'iife',
        target: ['es2022'],
        outfile: outFile,
        sourcemap: false,
        metafile: true,
        minify: true,
        globalName: 'LuciView',
        plugins: [luciPlugin]
    });

    // 仅收集实际打入浏览器的依赖，安装包同时携带它们的许可证。
    for (const input of Object.keys(result.metafile.inputs)) {
        const name = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/)?.[1];
        if (name) runtimePackages.add(name);
    }
    const bundled = fs.readFileSync(outFile, 'utf-8');
    const requireLines = Array.from(usedModules)
        .sort()
        .map(name => `'require ${name}';`)
        .join('\n');

    const snippet = `
'use strict';
${requireLines}

${bundled}

return LuciView.default;
`;

    fs.mkdirSync(path.dirname(outFile), {recursive: true});
    fs.writeFileSync(outFile, snippet, 'utf-8');
    console.log(`Build luci snippet: ${path.relative(__dirname, outFile)}`);
}

/**
 * 主流程：扫描 views 目录并构建所有 .ts
 */
async function bundleAll() {
    await buildOne(path.join(__dirname, 'modules/editor.ts'), path.join(DIST_DIR, '../../hijpass/editor.js'));
    await buildOne(path.join(__dirname, 'modules/drafts.ts'), path.join(DIST_DIR, '../../hijpass/drafts.js'));
    const entries = scanEntryFiles(VIEWS_DIR);
    if (entries.length === 0) {
        console.warn('No .ts files found in views/ directory');
        return;
    }

    for (const entry of entries) {
        // 按顺序构建每个入口；如需并行可用 Promise.all
        // 但串行 log 更清晰，出错也好排查
        await buildOne(entry);
    }
    const licenses = [...runtimePackages].sort().map(name => {
        const directory = path.join(__dirname, 'node_modules', name);
        const license = ['LICENSE', 'LICENSE.txt', 'LICENSE.md'].find(file => fs.existsSync(path.join(directory, file)));
        if (!license) throw new Error('Missing runtime dependency license: ' + name);
        return name + '\n' + fs.readFileSync(path.join(directory, license), 'utf8');
    });
    fs.writeFileSync(path.join(DIST_DIR, 'editor.LICENSES.txt'), licenses.join('\n\n'));
}

bundleAll().catch(err => {
    console.error(err);
    process.exit(1);
});
