const { test, expect } = require('@playwright/test');
test('loads the canonical site and working documents without missing local assets', async ({ page }) => {
  const errors = [], missing = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('response', response => { if (response.url().startsWith('http://127.0.0.1:18546/') && response.status() >= 400) missing.push(response.url()); });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /Earn Your Reputation/ })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.getByRole('link', { name: 'Read the White Paper' }).click();
  await expect(page.getByRole('heading', { name: 'Status and scope' })).toBeVisible();
  await page.getByRole('link', { name: 'Business model', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Unit economics', exact: true })).toBeVisible();
  expect(errors).toEqual([]); expect(missing).toEqual([]);
});
test('shows no false success while Supabase is unconfigured; preserves the email for retry', async ({ page }) => {
  await page.goto('/#waitlist');
  await page.locator('[name=email]').fill('waitlist-test@example.invalid');
  await page.locator('[name=consent]').check();
  await page.getByRole('button', { name: 'Join Waitlist' }).click();
  await expect(page.locator('#waitlist-note')).toContainText('temporarily unavailable');
  await expect(page.locator('[name=email]')).toHaveValue('waitlist-test@example.invalid');
});
test('shows success only after confirmed storage', async ({ page }) => {
  await page.route('**/api/waitlist', async route => {
    expect(route.request().postDataJSON().consent).toBe(true);
    await route.fulfill({ status: 202, contentType: 'application/json', body: '{"ok":true}' });
  });
  await page.goto('/#waitlist'); await page.locator('[name=email]').fill('waitlist-test@example.invalid');
  await page.locator('[name=consent]').check(); await page.getByRole('button', { name: 'Join Waitlist' }).click();
  await expect(page.locator('#waitlist-note')).toContainText('interest is registered');
  await expect(page.locator('[name=email]')).toHaveValue('');
});
