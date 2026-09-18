export async function GET() {
  return Response.json({
    status: 'ok',
    service: 'rabby-host-panel',
    version: '0.1.0',
  });
}
