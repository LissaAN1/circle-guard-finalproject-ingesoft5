import { test, expect, type Page } from '@playwright/test';

type Question = { id: string; text: string; type: string; options?: string | null };

async function signIn(page: Page, account: 'survey' | 'gate' = 'survey') {
  const username = process.env[account === 'gate' ? 'E2E_GATE_USERNAME' : 'E2E_USERNAME'];
  const password = process.env[account === 'gate' ? 'E2E_GATE_PASSWORD' : 'E2E_PASSWORD'];
  if (!username || !password) throw new Error(`E2E ${account} credentials missing`);

  await page.goto('/login');
  await page.getByPlaceholder('Username').fill(username);
  await page.getByPlaceholder('Password').fill(password);
  await page.getByText('SIGN IN', { exact: true }).click();
  await expect(page).not.toHaveURL(/\/login(?:\?|$)/);
  await expect(page.getByText('REPORT', { exact: true })).toBeVisible();
  await expect(page.getByText('LOGOUT', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => Boolean(localStorage.getItem('circleguard_token')))).toBe(true);
}

test('HU-07 / 1: user signs in through auth-service and reaches home', async ({ page }) => {
  await signIn(page);
});

test('HU-07 / 2: form-service receives user-selected questionnaire answers', async ({ page }) => {
  await signIn(page);
  const active = await page.request.get('/form/api/v1/questionnaires/active');
  expect(active.ok(), 'An active DEV questionnaire is mandatory').toBe(true);
  const questionnaire = await active.json() as { questions: Question[] };
  const question = questionnaire.questions.find(q => q.type === 'YES_NO');
  expect(question, 'DEV questionnaire must contain a YES_NO question').toBeTruthy();

  await page.goto('/questionnaire');
  const label = page.getByText(question!.text, { exact: true });
  await expect(label).toBeVisible();
  await label.locator('..').getByText('NO', { exact: true }).click();
  const submitted = page.waitForResponse(r =>
    r.url().includes('/api/v1/surveys') && r.request().method() === 'POST'
  );
  await page.getByText('SUBMIT REPORT', { exact: true }).click();
  const response = await submitted;
  expect(response.ok(), `Survey returned HTTP ${response.status()}`).toBe(true);
  const payload = response.request().postDataJSON() as { responses: Record<string, unknown> };
  expect(payload.responses[question!.id]).toBe('NO');
});

test('HU-07 / 3: CONFIRMED gate account is denied by real gateway', async ({ page }) => {
  await signIn(page, 'gate');
  const jwt = await page.evaluate(() => localStorage.getItem('circleguard_token'));
  expect(jwt).toBeTruthy();
  const qr = await page.request.get('/auth/api/v1/auth/qr/generate', {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  expect(qr.ok(), 'auth-service must issue a signed short-lived QR').toBe(true);
  const { qrToken } = await qr.json() as { qrToken: string };
  expect(qrToken).toBeTruthy();

  await page.goto('/gate-validation');
  await expect(page.getByText('Gate validation')).toBeVisible();
  await page.getByLabel('QR token').fill(qrToken);
  const validated = page.waitForResponse(r =>
    r.url().includes('/api/v1/gate/validate') && r.request().method() === 'POST'
  );
  await page.getByRole('button', { name: 'Validate access' }).click();
  const response = await validated;
  expect(response.ok()).toBe(true); // HTTP 200 carries the DENIED business decision.
  const decision = await response.json() as { valid: boolean; status: string };
  expect(decision.valid).toBe(false);
  expect(decision.status).toBe('RED');
  await expect(page.getByText('ACCESS DENIED', { exact: true })).toBeVisible();
});
