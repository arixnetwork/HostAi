const initialSites = [
  { name: 'alpha.example.com', status: 'Healthy', php: '8.2', traffic: '2.4 GB' },
  { name: 'beta.example.com', status: 'Queued', php: '8.3', traffic: '1.1 GB' },
  { name: 'api.example.com', status: 'Healthy', php: '8.2', traffic: '4.7 GB' },
];

export default function HomePage() {
  return (
    <main style={{ padding: '2rem', fontFamily: 'sans-serif', background: '#0b1020', color: '#e5ecff', minHeight: '100vh' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto' }}>
        <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
          <div>
            <h1 style={{ margin: 0, fontSize: '2rem' }}>Rabby Host</h1>
            <p style={{ margin: '0.4rem 0 0', color: '#a9b8d8' }}>Admin shell + site creation API bridge</p>
          </div>
          <button style={{ background: '#3b82f6', color: '#fff', border: 'none', borderRadius: 8, padding: '0.8rem 1.2rem', fontWeight: 700 }}>
            + Create Site
          </button>
        </header>

        <section style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '1rem', marginBottom: '2rem' }}>
          {[
            { label: 'Sites', value: String(initialSites.length) },
            { label: 'Domains', value: '28' },
            { label: 'Backups', value: '7' },
            { label: 'Jobs', value: '3' },
          ].map((item) => (
            <div key={item.label} style={{ background: '#111827', border: '1px solid #24314d', borderRadius: 12, padding: '1.2rem' }}>
              <div style={{ color: '#8da0c7', fontSize: '0.85rem' }}>{item.label}</div>
              <div style={{ fontSize: '2rem', fontWeight: 700, marginTop: '0.6rem' }}>{item.value}</div>
            </div>
          ))}
        </section>

        <section style={{ display: 'grid', gridTemplateColumns: '1.1fr 0.9fr', gap: '1.5rem', marginBottom: '2rem' }}>
          <div style={{ background: '#111827', border: '1px solid #24314d', borderRadius: 12, padding: '1.25rem' }}>
            <h2 style={{ marginTop: 0 }}>Create site</h2>
            <form action="/api/sites" method="POST" style={{ display: 'grid', gap: '0.8rem' }}>
              <input name="site_name" placeholder="site_name" style={inputStyle} />
              <input name="domain" placeholder="example.com" style={inputStyle} />
              <input name="root_path" placeholder="/var/www/example.com" style={inputStyle} />
              <input name="php_version" placeholder="8.2" defaultValue="8.2" style={inputStyle} />
              <button type="submit" style={{ background: '#10b981', border: 'none', color: '#fff', padding: '0.8rem 1rem', borderRadius: 8, fontWeight: 700 }}>
                Submit site request
              </button>
            </form>
          </div>

          <div style={{ background: '#111827', border: '1px solid #24314d', borderRadius: 12, padding: '1.25rem' }}>
            <h2 style={{ marginTop: 0 }}>Admin login</h2>
            <form action="/api/admin/login" method="POST" style={{ display: 'grid', gap: '0.8rem' }}>
              <input name="email" placeholder="admin@localhost" style={inputStyle} />
              <input name="password" type="password" placeholder="password" style={inputStyle} />
              <button type="submit" style={{ background: '#f59e0b', border: 'none', color: '#fff', padding: '0.8rem 1rem', borderRadius: 8, fontWeight: 700 }}>
                Sign in
              </button>
            </form>
          </div>
        </section>

        <section style={{ background: '#111827', border: '1px solid #24314d', borderRadius: 12, overflow: 'hidden' }}>
          <div style={{ padding: '1rem 1.2rem', borderBottom: '1px solid #24314d', fontWeight: 700 }}>Sites</div>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ background: '#0f172a' }}>
                <th style={{ textAlign: 'left', padding: '0.9rem 1.2rem' }}>Domain</th>
                <th style={{ textAlign: 'left', padding: '0.9rem 1.2rem' }}>Status</th>
                <th style={{ textAlign: 'left', padding: '0.9rem 1.2rem' }}>PHP</th>
                <th style={{ textAlign: 'left', padding: '0.9rem 1.2rem' }}>Traffic</th>
              </tr>
            </thead>
            <tbody>
              {initialSites.map((site) => (
                <tr key={site.name} style={{ borderTop: '1px solid #24314d' }}>
                  <td style={{ padding: '0.9rem 1.2rem' }}>{site.name}</td>
                  <td style={{ padding: '0.9rem 1.2rem' }}>
                    <span style={{
                      background: site.status === 'Healthy' ? '#14532d' : '#78350f',
                      color: '#ecfeff',
                      borderRadius: 999,
                      padding: '0.3rem 0.7rem',
                      fontSize: '0.8rem',
                      fontWeight: 700,
                    }}>
                      {site.status}
                    </span>
                  </td>
                  <td style={{ padding: '0.9rem 1.2rem' }}>{site.php}</td>
                  <td style={{ padding: '0.9rem 1.2rem' }}>{site.traffic}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      </div>
    </main>
  );
}

const inputStyle = {
  width: '100%',
  background: '#0f172a',
  color: '#e5ecff',
  border: '1px solid #334155',
  borderRadius: 8,
  padding: '0.8rem 1rem',
  fontSize: '0.95rem',
};
