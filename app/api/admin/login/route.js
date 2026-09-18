export async function POST(request) {
  try {
    const { email, password } = await request.json();
    const expectedEmail = process.env.ADMIN_EMAIL || 'admin@localhost';
    const expectedPassword = process.env.ADMIN_PASSWORD || 'adminpass123';

    if (!email || !password) {
      return Response.json({ error: 'email and password required' }, { status: 400 });
    }

    if (email !== expectedEmail || password !== expectedPassword) {
      return Response.json({ error: 'invalid credentials' }, { status: 401 });
    }

    return Response.json({
      token: 'dev-admin-token',
      user: { email, role: 'admin' },
    });
  } catch (error) {
    return Response.json({ error: 'invalid request body' }, { status: 400 });
  }
}
