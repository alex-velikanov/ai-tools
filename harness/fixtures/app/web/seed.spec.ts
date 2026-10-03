import { test, expect } from '@playwright/test';

test.describe('invoices/new', () => {
  test('creating an invoice with no billing address on file', async ({ page }) => {
    await page.goto('/invoices/new');

    await page.getByLabel('Customer name').fill('Legacy Customer');
    await page.getByLabel('Customer has a billing address on file').uncheck();
    await page.getByLabel('Unit price').fill('80');
    await page.getByLabel('Quantity').fill('1');
    await page.getByRole('button', { name: 'Create invoice' }).click();

    await expect(page.getByRole('heading', { name: 'Invoice created' })).toBeVisible();
    await expect(page.getByText('no billing address on file')).toBeVisible();
  });

  test('rejects submission with required fields empty', async ({ page }) => {
    await page.goto('/invoices/new');
    await page.getByRole('button', { name: 'Create invoice' }).click();

    await expect(page.getByText('Customer name is required.')).toBeVisible();
    await expect(page.getByText('Unit price must be a positive number.')).toBeVisible();
  });
});
