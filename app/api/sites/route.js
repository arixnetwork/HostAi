import { callAgent } from '../../lib/agent-client';
import { buildSiteProvisionPlan } from '../../lib/provisioner';
import { enqueueJob } from '../../lib/job-store';

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

    const provisionPlan = buildSiteProvisionPlan({ site_name, domain, root_path, php_version });
    const agentPayload = {
      site_name: provisionPlan.site_name,
      domain: provisionPlan.domain,
      root_path: provisionPlan.root_path,
      php_version: provisionPlan.php_version,
      owner,
    };

    const result = await callAgent('http://127.0.0.1:8417/agent/websites/create', agentPayload);
    const job = enqueueJob({
      type: 'site-create',
      status: 'queued',
      owner,
      payload: provisionPlan,
    });

    const record = {
      id: result.task_id || `${site_name}-${Date.now()}`,
      site_name: provisionPlan.site_name,
      domain: provisionPlan.domain,
      root_path: provisionPlan.root_path,
      php_version: provisionPlan.php_version,
      owner,
      status: result.status || 'accepted',
      task_id: result.task_id,
      job_id: job.id,
      nginx_vhost: provisionPlan.nginx_vhost,
      php_pool: provisionPlan.php_pool,
    };

    siteStore.push(record);

    return Response.json({ ok: true, record, agent: result, job }, { status: 201 });
  } catch (error) {
    return Response.json({ error: error.message || 'site creation failed' }, { status: 500 });
  }
}
