/**
 * E2E: Legal clickwrap gate (GL-134).
 *
 * Intercepts api.terms.cl8y.com. Default CI specs mock signed_latest=true;
 * this file covers unsigned and error paths.
 *
 * Default transfer source is Terra Classic, so Terra connect is the
 * reliable path to mount BridgeTermsGate on the deposit CTA. Also covers
 * unsigned EVM source (swap to Anvil). Dest auto-submit / Solana execute
 * need an on-chain deposited/approved transfer (verification project).
 */

import { test, expect } from './fixtures/base'
import { installLegalClickwrapMock } from './fixtures/legal-clickwrap'

test.describe('Legal clickwrap gate', () => {
  test('disconnected users can still open wallet connect (no Accept overlay)', async ({
    page,
  }) => {
    await page.goto('/')
    await expect(page.getByRole('button', { name: 'CONNECT EVM' }).last()).toBeVisible({
      timeout: 15_000,
    })
    await expect(page.getByRole('button', { name: 'CONNECT TC' }).last()).toBeVisible()
    await expect(page.getByRole('button', { name: 'Accept Terms' })).toHaveCount(0)
  })

  test('unsigned Terra source hides deposit CTA and shows Accept Terms', async ({
    page,
  }) => {
    await installLegalClickwrapMock(page, { mode: 'unsigned' })
    await page.goto('/')

    await page.getByRole('button', { name: 'CONNECT TC' }).last().click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    await expect(page.locator('text=terra1').last()).toBeVisible({ timeout: 10_000 })

    await expect(page.getByRole('button', { name: 'Accept Terms' })).toBeVisible({
      timeout: 15_000,
    })
    await expect(page.getByTestId('submit-transfer')).toHaveCount(0)
  })

  test('Legal API failure fails closed (no deposit CTA)', async ({ page }) => {
    await installLegalClickwrapMock(page, { mode: 'error' })
    await page.goto('/')

    await page.getByRole('button', { name: 'CONNECT TC' }).last().click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    await expect(page.locator('text=terra1').last()).toBeVisible({ timeout: 10_000 })

    await expect(page.getByRole('alert')).toBeVisible({ timeout: 15_000 })
    await expect(page.getByTestId('submit-transfer')).toHaveCount(0)
  })

  test('signed_latest true keeps deposit CTA (default mock)', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('button', { name: 'CONNECT TC' }).last().click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    await expect(page.locator('text=terra1').last()).toBeVisible({ timeout: 10_000 })

    await expect(page.getByTestId('submit-transfer')).toBeVisible({ timeout: 15_000 })
    await expect(page.getByRole('button', { name: 'Accept Terms' })).toHaveCount(0)
  })

  test('unsigned EVM source hides deposit CTA and shows Accept Terms', async ({
    page,
  }) => {
    await installLegalClickwrapMock(page, { mode: 'unsigned' })
    await page.goto('/')

    await page.getByRole('button', { name: 'CONNECT EVM' }).last().click()
    await page.locator('button', { hasText: 'Simulated EVM Wallet' }).last().click()
    await expect(page.locator('text=0xf39F').last()).toBeVisible({ timeout: 10_000 })
    await page.keyboard.press('Escape')

    // Default local route is Terra → Anvil; swap so the source wallet is EVM.
    await page.getByTestId('swap-direction').click()

    await expect(page.getByRole('button', { name: 'Accept Terms' })).toBeVisible({
      timeout: 15_000,
    })
    await expect(page.getByTestId('submit-transfer')).toHaveCount(0)
  })
})
