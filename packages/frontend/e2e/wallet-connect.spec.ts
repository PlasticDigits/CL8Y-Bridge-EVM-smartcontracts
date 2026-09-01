/**
 * E2E Tests: Wallet Connection
 *
 * Tests connecting and disconnecting EVM and Terra dev wallets.
 *
 * Note: NavBar renders wallet buttons 3x for responsive breakpoints.
 * At 1280px viewport, only the desktop instance is visible.
 * Accessible name for Terra is `Connect Terra Wallet` (aria-label on
 * `data-testid="connect-terra-wallet"`). The transfer form CTA is only
 * `Connect` — always target the header banner instance (GL-137).
 */

import { test, expect, headerTerraConnect } from './fixtures/base'

test.describe('Wallet Connection', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    await page.waitForLoadState('networkidle')
  })

  test('should show connect buttons when disconnected', async ({ page }) => {
    await expect(page.getByRole('button', { name: 'CONNECT EVM' })).toBeVisible()
    await expect(headerTerraConnect(page)).toBeVisible()
    await expect(headerTerraConnect(page)).toBeEnabled()
    await expect(headerTerraConnect(page)).toHaveAttribute('aria-label', 'Connect Terra Wallet')
  })

  test('should connect EVM dev wallet', async ({ page }) => {
    await page.getByRole('button', { name: 'CONNECT EVM' }).click()
    await page.locator('button', { hasText: 'Simulated EVM Wallet' }).last().click()
    // .last() = desktop navbar instance (visible at 1280px)
    await expect(page.locator('text=0xf39F').last()).toBeVisible({ timeout: 10_000 })
  })

  test('should connect Terra dev wallet', async ({ page }) => {
    await headerTerraConnect(page).click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    await expect(page.locator('text=terra1').last()).toBeVisible({ timeout: 10_000 })
  })

  test('should connect both wallets', async ({ page }) => {
    await page.getByRole('button', { name: 'CONNECT EVM' }).click()
    await page.locator('button', { hasText: 'Simulated EVM Wallet' }).last().click()
    await expect(page.locator('text=0xf39F').last()).toBeVisible({ timeout: 10_000 })

    await headerTerraConnect(page).click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    await expect(page.locator('text=terra1').last()).toBeVisible({ timeout: 10_000 })
  })

  test('should disconnect EVM wallet', async ({ page }) => {
    await page.getByRole('button', { name: 'CONNECT EVM' }).click()
    await page.locator('button', { hasText: 'Simulated EVM Wallet' }).last().click()
    await expect(page.locator('text=0xf39F').last()).toBeVisible({ timeout: 10_000 })

    await page.locator('text=0xf39F').last().click()
    await page.getByRole('button', { name: 'Disconnect' }).click()
    await expect(page.getByRole('button', { name: 'CONNECT EVM' })).toBeVisible({ timeout: 5_000 })
  })

  test('connected Terra dropdown backdrop does not survive History navigation', async ({ page }) => {
    await headerTerraConnect(page).click()
    await page.locator('button', { hasText: 'Simulated Terra Wallet' }).last().click()
    const connected = page.getByRole('button', { name: 'Connected Terra wallet' }).filter({ visible: true })
    await expect(connected).toBeVisible({ timeout: 10_000 })
    await connected.click()
    await expect(page.getByTestId('wallet-menu-backdrop').filter({ visible: true })).toBeVisible()
    await page.locator('nav').getByRole('link', { name: 'History' }).click()
    await expect(page).toHaveURL(/\/history/)
    await expect(page.getByTestId('wallet-menu-backdrop')).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Connected Terra wallet' }).filter({ visible: true })).toBeVisible()
  })
})

test.describe('mobile viewport Terra connect (GL-137)', () => {
  test.use({
    viewport: { width: 390, height: 844 },
    userAgent:
      'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
  })

  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    await page.waitForLoadState('networkidle')
  })

  test('header CTA is enabled and opens TerraWalletModal on first tap', async ({ page }) => {
    const cta = headerTerraConnect(page)
    await expect(cta).toBeVisible()
    await expect(cta).toBeEnabled()
    await expect(cta).toHaveAttribute('aria-label', 'Connect Terra Wallet')
    await cta.click()
    await expect(page.getByRole('dialog', { name: 'Connect Wallet' })).toBeVisible()
    await expect(page.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
    await expect(page.getByTestId('wallet-option-galaxy-station')).toBeEnabled()
    await expect(page.getByTestId('wallet-option-keplr')).toBeEnabled()
    await expect(page.getByTestId('wallet-option-keplr')).toContainText(/WalletConnect/i)
  })

  test('simulated Terra wallet still connects at mobile width', async ({ page }) => {
    await headerTerraConnect(page).click()
    await page.getByTestId('wallet-option-simulated-terra-wallet').click()
    await expect(page.getByRole('button', { name: 'Connected Terra wallet' }).filter({ visible: true })).toBeVisible({
      timeout: 10_000,
    })
  })
})

test.describe('in-app browser Terra connect hint (GL-137)', () => {
  test.use({
    viewport: { width: 390, height: 844 },
    userAgent: 'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 KeplrMobile',
  })

  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    await page.waitForLoadState('networkidle')
  })

  test('shows the in-app browser banner before wallet rows', async ({ page }) => {
    await headerTerraConnect(page).click()
    await expect(page.getByRole('dialog', { name: 'Connect Wallet' })).toBeVisible()
    const banner = page.getByTestId('wallet-modal-in-app-banner')
    await expect(banner).toBeVisible()
    await expect(banner).toContainText('Keplr')
    await expect(page.getByTestId('wallet-option-lunc-dash')).toBeEnabled()
    await expect(page.getByTestId('wallet-modal-mobile-hint')).toHaveCount(0)
  })
})
