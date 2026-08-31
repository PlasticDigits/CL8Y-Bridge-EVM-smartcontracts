/**
 * Playwright helpers: mock CL8Y Legal API so e2e does not depend on
 * api.terms.cl8y.com uptime (GL-134).
 *
 * Default is signed_latest=true so existing transfer specs stay green.
 */

import type { Page } from '@playwright/test'

export type LegalClickwrapMockMode = 'signed' | 'unsigned' | 'error'

export interface LegalClickwrapMockOptions {
  mode?: LegalClickwrapMockMode
}

const PROPERTY = 'bridge.cl8y.com'

const TERMS_LATEST = {
  property: PROPERTY,
  version_label: 'e2e-v1',
  effective_date: '2026-01-01',
  content_sha256: 'e2e',
  published_at: '2026-01-01T00:00:00Z',
  sign_urls: {
    telegram: 'https://terms.cl8y.com/sign/telegram?property=bridge.cl8y.com',
    evm: 'https://terms.cl8y.com/sign/evm?property=bridge.cl8y.com',
    terra_classic: 'https://terms.cl8y.com/sign/terra-classic?property=bridge.cl8y.com',
    solana: 'https://terms.cl8y.com/sign/solana?property=bridge.cl8y.com',
  },
}

export async function installLegalClickwrapMock(
  page: Page,
  opts: LegalClickwrapMockOptions = {},
): Promise<void> {
  const mode = opts.mode ?? 'signed'

  await page.route('https://api.terms.cl8y.com/**', async (route) => {
    const url = new URL(route.request().url())
    if (mode === 'error') {
      await route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'legal unavailable' }),
      })
      return
    }

    if (url.pathname.endsWith('/signatures/status')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          property: PROPERTY,
          latest_version: 'e2e-v1',
          signed_latest: mode === 'signed',
          signed_version: mode === 'signed' ? 'e2e-v1' : null,
          signed_at: mode === 'signed' ? '2026-01-01T00:00:00Z' : null,
        }),
      })
      return
    }

    if (url.pathname.endsWith('/terms/latest/content')) {
      await route.fulfill({
        status: 200,
        contentType: 'text/plain',
        body: 'E2E terms content',
      })
      return
    }

    if (url.pathname.endsWith('/terms/latest')) {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(TERMS_LATEST),
      })
      return
    }

    await route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: JSON.stringify({ error: 'not mocked' }),
    })
  })
}
