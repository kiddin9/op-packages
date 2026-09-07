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

// 限定哪些 from 模块名当作 luci 模块（name = require name）
const luciModuleNames = new Set(
    ['view', 'fs', 'form', 'uci', 'ui', 'network', 'baseclass', 'rpc', 'poll']);

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
async function buildOne(entryPath) {
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
          export default ${moduleName};
        `;
                return {
                    contents: code,
                    loader: 'ts'
                };
            });
        }
    };

    // 计算输出文件名：views/demo.ts → dist/demo.js
    const rel = path.relative(VIEWS_DIR, entryPath); // demo.ts
    const baseName = rel.replace(/\.ts$/, '');       // demo
    const outFile = path.join(DIST_DIR, `${baseName}.js`);

    await build({
        entryPoints: [entryPath],
        bundle: true,
        platform: 'browser',
        format: 'iife',
        target: ['es2022'],
        outfile: outFile,
        sourcemap: false,
        minify: true,
        globalName: 'LuciView',
        plugins: [luciPlugin]
    });

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
}

bundleAll().catch(err => {
    console.error(err);
    process.exit(1);
});
