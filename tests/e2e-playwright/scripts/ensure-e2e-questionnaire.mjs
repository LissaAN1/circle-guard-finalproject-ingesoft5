const baseUrl = process.env.E2E_BASE_URL;

if (!baseUrl) {
  throw new Error('E2E_BASE_URL is required');
}

const base = `${baseUrl.replace(/\/$/, '')}/form/api/v1/questionnaires`;

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, {
    ...options,
    signal: AbortSignal.timeout(15000),
  });

  const body = await response.text();
  let data = null;

  if (body) {
    try {
      data = JSON.parse(body);
    } catch {
      // The activation endpoint may return an empty body.
    }
  }

  if (response.status >= 400 && response.status !== 404) {
    throw new Error(
      `Questionnaire request failed: HTTP ${response.status} (${path})`
    );
  }

  return { status: response.status, data };
}

function validate(questionnaire) {
  if (
    !questionnaire ||
    !Array.isArray(questionnaire.questions) ||
    !questionnaire.questions.some(q => q.type === 'YES_NO')
  ) {
    throw new Error('Active questionnaire has no YES_NO question');
  }
}

async function main() {
  console.log('Checking active E2E questionnaire...');

  const active = await request('/active');

  if (active.status === 200) {
    validate(active.data);
    console.log('Existing active questionnaire reused');
    return;
  }

  if (active.status !== 404) {
    throw new Error(`Unexpected active questionnaire status: ${active.status}`);
  }

  console.log('Creating DEV E2E questionnaire...');

  const payload = {
    title: 'CircleGuard DEV E2E questionnaire',
    description: 'Automated DEV E2E fixture',
    version: 1,
    isActive: false,
    questions: [
      { text: 'Do you have a fever?', type: 'YES_NO', orderIndex: 1 },
      { text: 'Do you have a cough?', type: 'YES_NO', orderIndex: 2 },
      {
        text: 'Have you been in contact with a confirmed case?',
        type: 'YES_NO',
        orderIndex: 3,
      },
    ],
  };

  const created = await request('', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (![200, 201].includes(created.status) || !created.data?.id) {
    throw new Error(`Questionnaire creation failed: HTTP ${created.status}`);
  }

  console.log('Activating questionnaire...');

  const activated = await request(`/${created.data.id}/activate`, {
    method: 'POST',
  });

  if (![200, 204].includes(activated.status)) {
    throw new Error(`Activation failed: HTTP ${activated.status}`);
  }

  const verified = await request('/active');

  if (verified.status !== 200) {
    throw new Error(`Verification failed: HTTP ${verified.status}`);
  }

  validate(verified.data);
  console.log('E2E questionnaire fixture ready');
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
