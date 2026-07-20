import { ImageResponse } from 'next/og'

export const alt = 'OpenSourcingOS — Procurement Value Tracker'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(135deg, #0f172a 0%, #1e1b4b 50%, #312e81 100%)',
          fontFamily: 'system-ui, -apple-system, sans-serif',
        }}
      >
        {/* Logo */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '16px',
            marginBottom: '48px',
          }}
        >
          <span
            style={{
              fontSize: '80px',
              fontWeight: 700,
              color: '#f8fafc',
              letterSpacing: '-2px',
            }}
          >
            OpenSourcing
          </span>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '72px',
              height: '72px',
              borderRadius: '14px',
              backgroundColor: '#4f46e5',
              fontSize: '36px',
              fontWeight: 700,
              color: '#ffffff',
            }}
          >
            OS
          </div>
        </div>

        {/* Tagline */}
        <div
          style={{
            fontSize: '36px',
            color: '#a5b4fc',
            marginBottom: '20px',
            fontWeight: 500,
          }}
        >
          Procurement Value Tracker
        </div>

        {/* Feature list */}
        <div
          style={{
            fontSize: '26px',
            color: '#94a3b8',
            display: 'flex',
            gap: '24px',
          }}
        >
          <span>Sourcing</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Baselines</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Offers</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Savings</span>
          <span style={{ color: '#4f46e5' }}>•</span>
          <span>Realization</span>
        </div>
      </div>
    ),
    { ...size }
  )
}
