import { listJobs } from '../../lib/job-store';

export async function GET() {
  return Response.json({ jobs: listJobs() });
}

export async function POST(request) {
  try {
    const json = await request.json();
    const { type = 'manual', status = 'queued', owner = 'system', payload = {} } = json;

    const { enqueueJob } = await import('../../lib/job-store');
    const job = enqueueJob({ type, status, owner, payload });

    return Response.json({ ok: true, job }, { status: 201 });
  } catch (error) {
    return Response.json({ error: error.message || 'job creation failed' }, { status: 500 });
  }
}
