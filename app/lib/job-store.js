export const jobStore = [];

export function enqueueJob({ type, status = 'queued', owner = 'system', payload = {} }) {
  const job = {
    id: `job-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    type,
    status,
    owner,
    payload,
    created_at: new Date().toISOString(),
  };
  jobStore.push(job);
  return job;
}

export function listJobs() {
  return [...jobStore];
}
