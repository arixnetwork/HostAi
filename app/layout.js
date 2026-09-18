import './globals.css';

export const metadata = {
  title: 'Rabby Host',
  description: 'Secure hosting control panel',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
