import react from '@vitejs/plugin-react'
import { execSync } from 'child_process'
import { fileURLToPath } from 'node:url'
import { defineConfig, type Plugin } from 'vite'

function bufferBootstrapEntry(): Plugin {
  const bootstrapSrc = fileURLToPath(new URL('./src/buffer-bootstrap.ts', import.meta.url))
  let base = '/'
  return {
    name: 'buffer-bootstrap-entry',
    configResolved(config) {
      base = config.base.endsWith('/') ? config.base : `${config.base}/`
    },
    transformIndexHtml(html, ctx) {
      if (html.includes('buffer-bootstrap')) return html
      let bootstrapHref: string
      if (ctx.bundle) {
        const chunk = Object.values(ctx.bundle).find(
          (f) =>
            f.type === 'chunk' &&
            typeof f.facadeModuleId === 'string' &&
            (f.facadeModuleId === bootstrapSrc || f.facadeModuleId.endsWith('/buffer-bootstrap.ts')),
        )
        if (!chunk) return html
        bootstrapHref = `${base}${chunk.fileName}`.replace(/([^:]\/)\/+/g, '$1')
      } else {
        bootstrapHref = `${base}src/buffer-bootstrap.ts`.replace(/([^:]\/)\/+/g, '$1')
      }
      const cross = ctx.bundle ? ' crossorigin' : ''
      // Dev: /src/main.tsx — build: /assets/main-*.js
      const replaced = html.replace(
        /(\n\s*)(<script type="module"[^>]*src="[^"]*main(\.tsx|-[^"]+\.js)"[^>]*><\/script>)/,
        `$1<script type="module"${cross} src="${bootstrapHref}"></script>$1$2`,
      )
      if (replaced !== html) return replaced
      return html.replace(
        /(\n\s*)(<script type="module")/,
        `$1<script type="module"${cross} src="${bootstrapHref}"></script>$1$2`,
      )
    },
  }
}

const GITHUB_REPO = 'PlasticDigits/cl8y-bridge-monorepo'
const VERSION_OFFSET = 190

function shell(command: string, fallback = ''): string {
  try {
    return execSync(command, {
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 10000,
    }).toString().trim()
  } catch {
    return fallback
  }
}

function getGitSha(): string {
  return (
    process.env.VITE_GIT_SHA ||
    process.env.SOURCE_COMMIT ||
    process.env.COOLIFY_GIT_COMMIT ||
    shell('git rev-parse --short HEAD', 'unknown')
  )
}

function getCommitCount(): number {
  const localCount = parseInt(shell('git rev-list --count HEAD', '0'), 10)
  if (Number.isFinite(localCount) && localCount > 1) {
    return localCount
  }

  try {
    const linkHeader = execSync(
      `node -e "fetch('https://api.github.com/repos/${GITHUB_REPO}/commits?per_page=1&sha=main',{headers:{'User-Agent':'cl8y-build'}}).then(r=>console.log(r.headers.get('link')||'')).catch(()=>console.log(''))"`,
      {
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 10000,
      },
    ).toString().trim()

    const match = linkHeader.match(/page=(\d+)>;\s*rel="last"/)
    if (match) {
      return parseInt(match[1], 10)
    }
  } catch {
    // Build continues with fallback version.
  }

  return VERSION_OFFSET
}

const gitSha = getGitSha()
const commitCount = getCommitCount()
const appVersion = `v0.1.${Math.max(0, commitCount - VERSION_OFFSET)}`

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), bufferBootstrapEntry()],
  server: {
    port: 3000,
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    // Optimize for smaller initial load (Raspberry Pi on WiFi)
    target: 'es2020',
    minify: 'esbuild',
    rollupOptions: {
      input: {
        main: fileURLToPath(new URL('./index.html', import.meta.url)),
        'buffer-bootstrap': fileURLToPath(new URL('./src/buffer-bootstrap.ts', import.meta.url)),
      },
      output: {
        // Split chunks for better caching and smaller initial load
        manualChunks: (id) => {
          // Keep npm `buffer` out of shared vendor chunks so the bootstrap entry stays tiny and safe to run first.
          if (id.includes('node_modules/buffer/') || id.endsWith('node_modules/buffer')) {
            return 'buffer-polyfill'
          }

          // Vendor chunk for React core
          if (id.includes('node_modules/react') || 
              id.includes('node_modules/react-dom') ||
              id.includes('node_modules/scheduler')) {
            return 'vendor-react'
          }
          
          // Terra wallet libraries (heavy, lazy-loadable)
          if (id.includes('@goblinhunt/cosmes') ||
              id.includes('cosmjs') ||
              id.includes('cosmrs') ||
              id.includes('bip39') ||
              id.includes('bip32')) {
            return 'wallet-terra'
          }
          
          // EVM wallet libraries (includes WalletConnect/Reown to avoid circular chunks)
          if (id.includes('wagmi') ||
              id.includes('viem') ||
              id.includes('@wagmi') ||
              id.includes('@walletconnect') ||
              id.includes('@reown') ||
              id.includes('walletconnect')) {
            return 'wallet-evm'
          }
          
          // Query and state management
          if (id.includes('@tanstack') ||
              id.includes('zustand')) {
            return 'vendor-state'
          }
          
          // Crypto utilities
          if (id.includes('secp256k1') ||
              id.includes('noble') ||
              id.includes('scure') ||
              id.includes('elliptic')) {
            return 'crypto'
          }
        },
        // Optimize chunk file names for caching
        chunkFileNames: 'assets/[name]-[hash].js',
        entryFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
    // Terra wallet libs are large but lazy-loaded, suppress warning
    chunkSizeWarningLimit: 6000,
  },
  define: {
    // Required for some wallet libraries
    'process.env': {},
    global: 'globalThis',
    __GIT_SHA__: JSON.stringify(gitSha),
    __APP_VERSION__: JSON.stringify(appVersion),
  },
  resolve: {
    alias: {
      buffer: 'buffer/',
    },
  },
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      'zustand',
      '@tanstack/react-query',
      'buffer',
    ],
    exclude: [],
  },
})
