/**
 * Playwright base fixture: mock Legal clickwrap API as signed-by-default (GL-134).
 */

import { test as base, expect } from '@playwright/test'
import { installLegalClickwrapMock } from './legal-clickwrap'

export const test = base.extend<{ legalClickwrap: void }>({
  legalClickwrap: [
    async ({ page }, use) => {
      await installLegalClickwrapMock(page, { mode: 'signed' })
      await use()
    },
    { auto: true },
  ],
})

export { expect }
