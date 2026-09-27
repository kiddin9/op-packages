import { fileURLToPath, URL } from 'node:url';

import preact from '@preact/preset-vite';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig, loadEnv } from 'vite';

const frontendDirectory = fileURLToPath(new URL('./', import.meta.url));
const outputDirectory = fileURLToPath(
  new URL('../root/www/luci-static/smartsafehub/', import.meta.url),
);

function routerProxyTarget(value: string): string {
  let target: URL;

  try {
    target = new URL(value);
  } catch {
    throw new Error(
      'SMARTSAFEHUB_DEV_ROUTER must be an absolute http(s) URL, for example http://192.168.1.1',
    );
  }

  if (target.protocol !== 'http:' && target.protocol !== 'https:') {
    throw new Error('SMARTSAFEHUB_DEV_ROUTER must use http:// or https://');
  }

  return target.origin;
}

function resolveDevRouterTarget(mode: string): string {
  const fileEnv = loadEnv(mode, frontendDirectory, 'SMARTSAFEHUB_');
  const configuredRouter = (
    process.env.SMARTSAFEHUB_DEV_ROUTER ?? fileEnv.SMARTSAFEHUB_DEV_ROUTER
  )?.trim();

  if (!configuredRouter) {
    throw new Error(
      'SMARTSAFEHUB_DEV_ROUTER is required for local development. Run SMARTSAFEHUB_DEV_ROUTER=http://192.168.1.1 npm run dev or set it in frontend/.env.local.',
    );
  }

  return routerProxyTarget(configuredRouter);
}

export default defineConfig(({ command, mode }) => {
  const isDevServer = command === 'serve';
  const devRouterTarget = isDevServer ? resolveDevRouterTarget(mode) : undefined;

  return {
    base: isDevServer ? '/' : '/luci-static/smartsafehub/',
    publicDir: 'public',
    plugins: [preact(), tailwindcss()],
    ...(devRouterTarget
      ? {
          server: {
            proxy: {
              '/cgi-bin': {
                target: devRouterTarget,
                changeOrigin: true,
                secure: false,
                cookieDomainRewrite: '',
              },
            },
          },
        }
      : {}),
    build: {
      target: 'es2020',
      outDir: outputDirectory,
      emptyOutDir: true,
      sourcemap: false,
      cssCodeSplit: false,
      reportCompressedSize: true,
      rollupOptions: {
        input: fileURLToPath(new URL('./src/main.tsx', import.meta.url)),
        output: {
          entryFileNames: 'app.js',
          chunkFileNames: 'chunks/[name]-[hash].js',
          assetFileNames: (assetInfo) =>
            assetInfo.name?.endsWith('.css')
              ? 'app.css'
              : 'assets/[name]-[hash][extname]',
        },
      },
    },
  };
});
