import crypto from 'crypto';

export function signAgentRequest(payload, secret = process.env.AGENT_SECRET || 'dev-agent-secret-change-me') {
  const nonce = crypto.randomBytes(12).toString('hex');
  const timestamp = String(Math.floor(Date.now() / 1000));
  const rawBody = JSON.stringify(payload);
  const signature = crypto
    .createHmac('sha256', secret)
    .update(Buffer.from(rawBody + '|' + timestamp + '|' + nonce, 'utf8'))
    .digest('hex');

  return { nonce, timestamp, signature, rawBody };
}

export async function callAgent(endpoint, payload) {
  const { nonce, timestamp, signature, rawBody } = signAgentRequest(payload);

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-signature': signature,
      'x-timestamp': timestamp,
      'x-nonce': nonce,
    },
    body: rawBody,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.detail || 'Agent request failed');
  }
  return data;
}
