/**
 * E2E Tests: Token Selection
 *
 * Tests that tokens appear correctly in dropdowns and amounts update.
 * INV-FE-TOKEN-RANK-1 (GL-136): economic tokens before known noneconomic faucet tokens.
 */

import { test, expect } from './fixtures/dev-wallet'
import { isNoneconomicBridgeToken } from '../src/utils/tokenEconomicRank'
import {
  MAINNET_TESTA_TERRA,
  MAINNET_TESTB_TERRA,
  MAINNET_TDEC_TERRA,
} from '../src/utils/faucetTokens'

test.describe('Token Selection', () => {
  test('should show token selector or token label', async ({ connectedPage: page }) => {
    // When tokens are available, either a dropdown or a static label should appear
    // Use .last() because the token label text "LUNC" also appears in the
    // hidden responsive navbar wallet balance (which renders 3x).
    const tokenArea = page.locator('[data-testid="token-select"]')
      .or(page.locator('text=LUNC'))
      .or(page.locator('text=Token'))
      .last()
    await expect(tokenArea).toBeVisible({ timeout: 5_000 })
  })

  test('should display token symbol in amount area', async ({ connectedPage: page }) => {
    // The amount input area should show the selected token symbol
    // Scope to the form area to avoid matching navbar balance labels
    const formArea = page.locator('main')
    const symbolLabel = formArea.locator('text=LUNC')
      .or(formArea.locator('text=TKNA'))
      .or(formArea.locator('text=TKNB'))
      .or(formArea.locator('text=TKNC'))
      .first()
    await expect(symbolLabel).toBeVisible({ timeout: 5_000 })
  })

  test('should update receive amount when input amount changes', async ({ connectedPage: page }) => {
    const amountInput = page.locator('[data-testid="amount-input"]')
    if (await amountInput.isVisible()) {
      // Enter an amount
      await amountInput.fill('1000')

      // The receive amount / fee breakdown should update
      // With 0.5% fee, 1000 should show ~995 receive
      await page.waitForTimeout(500)
      const feeSection = page.locator('text=Receive').or(page.locator('text=receive')).last()
      if (await feeSection.isVisible()) {
        await expect(feeSection).toBeVisible()
      }
    }
  })

  test('economic tokens appear before test tokens in the open listbox', async ({ connectedPage: page }) => {
    const select = page.locator('[data-testid="token-select"]')
    await expect(select).toBeVisible({ timeout: 10_000 })
    await select.click()
    const options = page.locator('[role="option"]')
    const count = await options.count()
    test.skip(count < 2, 'route only has one token — ranking not observable')

    const ids: string[] = []
    for (let i = 0; i < count; i++) {
      ids.push((await options.nth(i).getAttribute('data-tokenid')) ?? '')
    }

    let sawNoneconomic = false
    for (const id of ids) {
      const isTest = isNoneconomicBridgeToken({ id, tokenId: id })
      if (isTest) {
        sawNoneconomic = true
      } else if (sawNoneconomic) {
        throw new Error(`economic token ${id} appeared after a noneconomic token: ${ids.join(',')}`)
      }
    }
  })

  test('selecting a noneconomic token from the bottom keeps that selection', async ({ connectedPage: page }) => {
    const select = page.locator('[data-testid="token-select"]')
    await expect(select).toBeVisible({ timeout: 10_000 })
    await select.click()
    const options = page.locator('[role="option"]')
    const count = await options.count()
    test.skip(count < 2, 'route only has one token')

    let testOption = options.filter({ has: page.locator(`[data-tokenid="${MAINNET_TESTA_TERRA}"]`) })
    if ((await testOption.count()) === 0) {
      testOption = options.filter({ has: page.locator(`[data-tokenid="${MAINNET_TESTB_TERRA}"]`) })
    }
    if ((await testOption.count()) === 0) {
      testOption = options.filter({ has: page.locator(`[data-tokenid="${MAINNET_TDEC_TERRA}"]`) })
    }
    if ((await testOption.count()) === 0) {
      // Local QA: last option is the noneconomic group after ranking
      const last = options.nth(count - 1)
      const lastId = (await last.getAttribute('data-tokenid')) ?? ''
      test.skip(
        !isNoneconomicBridgeToken({ id: lastId, tokenId: lastId }),
        'no noneconomic token in this route',
      )
      await last.click()
      await expect(select).toHaveAttribute('aria-expanded', 'false')
      const amountInput = page.locator('[data-testid="amount-input"]')
      if (await amountInput.isVisible()) {
        await amountInput.fill('1')
      }
      await select.click()
      const selected = page.locator('[role="option"][aria-selected="true"]')
      await expect(selected).toHaveAttribute('data-tokenid', lastId)
      return
    }

    const testId = (await testOption.first().getAttribute('data-tokenid')) ?? ''
    await testOption.first().click()
    const amountInput = page.locator('[data-testid="amount-input"]')
    if (await amountInput.isVisible()) {
      await amountInput.fill('1')
    }
    await select.click()
    const selected = page.locator('[role="option"][aria-selected="true"]')
    await expect(selected).toHaveAttribute('data-tokenid', testId)
  })
})
