import { callAgent } from '@/app/lib/agent-client';

const siteStore = [];

export async function GET() {
  return Response.json({ sites: siteStore });
}

export async function POST(request) {
  try {
    const payload = await request.json();
    const { site_name, domain, root_path, php_version = '8.2', owner = 'default' } = payload;

    if (!site_name || !domain || !root_path) {
      return Response.json({ error: 'site_name, domain, and root_path are required' }, { status: 400 });
    }

    const agentPayload = { site_name, domain, root_path, php_version, owner };
    const result = await callAgent('http://127.0.0.1:8417/agent/websites/create', agentPayload);

    const record = {
      id: result.task_id || `${site_name}-${Date.now()}`,
      site_name,
      domain,
      root_path,
      php_version,
      owner,
      status: result.status || 'accepted',
      task_id: result.task_id,
    };

    siteStore.push(record);

    return Response.json({ ok: true, record, agent: result }, { status: 201 });
  } catch (error) {
    return Response.json({ error: error.message || 'site creation failed' }, { status: 500 });
  }
}
