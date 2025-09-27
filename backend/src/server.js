import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import { createClient } from '@supabase/supabase-js';
import catalogRouter from './routes/catalog.js';
import inventoryRouter from './routes/inventory.js';

const app = express();
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

const PORT = process.env.PORT || 4000;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Cliente de supabase (server-side). Usa service role para tareas que requieran bypass de RLS.
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

app.get('/health', async (_req, res) => {
  try {
    // Sonda simple: obtener hora del servidor DB (si existe una RPC futura) o responder OK
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// Ruta de ejemplo para validar conexión a Supabase (lista tablas públicas si se define una tabla de prueba)
app.get('/api/ping-supabase', async (_req, res) => {
  try {
    // Este es un ping lógico; se puede cambiar por una consulta real cuando existan tablas.
    const urlOk = Boolean(SUPABASE_URL);
    res.json({ ok: urlOk });
  } catch (err) {
    res.status(500).json({ ok: false, message: err.message });
  }
});

// Montar rutas de API
app.use('/api/catalog', catalogRouter);
app.use('/api/inventario', inventoryRouter);

app.listen(PORT, () => {
  console.log(`[backend] listening on http://localhost:${PORT}`);
});
