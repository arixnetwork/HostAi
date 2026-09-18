const summary = [
  { label: 'Sites', value: '12' },
  { label: 'Domains', value: '28' },
  { label: 'Backups', value: '7' },
  { label: 'Jobs', value: '3' },
];

const siteRows = [
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
            <p style={{ margin: '0.4rem 0 0', color: '#a9b8d8' }}>Secure panel shell</p>
          </div>
          <button style={{ background: '#3b82f6', color: '#fff', border: 'none', borderRadius: 8, padding: '0.8rem 1.2rem', fontWeight: 700 }}>
            + Create Site
          </button>
        </header>

        <section style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '1rem', marginBottom: '2rem' }}>
          {summary.map((item) => (
            <div key={item.label} style={{ background: '#111827', border: '1px solid #24314d', borderRadius: 12, padding: '1.2rem' }}>
              <div style={{ color: '#8da0c7', fontSize: '0.85rem' }}>{item.label}</div>
              <div style={{ fontSize: '2rem', fontWeight: 700, marginTop: '0.6rem' }}>{item.value}</div>
            </div>
          ))}
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
              {siteRows.map((site) => (
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
