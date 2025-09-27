import React, { useEffect, useState } from 'react'
import { supabase } from './services/supabaseClient'

export default function App() {
  const [apiStatus, setApiStatus] = useState('loading')

  useEffect(() => {
    fetch(import.meta.env.VITE_API_BASE + '/health')
      .then(r => r.json())
      .then(() => setApiStatus('ok'))
      .catch(() => setApiStatus('error'))
  }, [])

  return (
    <div style={{ fontFamily: 'system-ui, Arial', padding: 24 }}>
      <h1>TransformaSysAI — Sistema Fábrica de Paneles</h1>
      <p>Estado API Backend: <strong>{apiStatus}</strong></p>
      <hr />
      <section>
        <h2>Conexión a Supabase (cliente)</h2>
        <p>URL: {supabase?.storage ? 'configurada' : 'no configurada'}</p>
      </section>
    </div>
  )
}
