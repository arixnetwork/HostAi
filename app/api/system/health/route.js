export async function GET() {
  return Response.json({
    status: 'ok',
    system: 'panel',
    api: 'v1',
    checks: {
      database: 'not-configured',
      agent: 'localhost:8417',
      nginx: 'not-configured',
    },
  });
}
