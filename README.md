# Sistema Fábrica de Paneles — Monorepo

Estructura inicial con `frontend/` (React + Vite) y `backend/` (Node + Express). Base de datos: PostgreSQL (Supabase).

## Comandos
- `npm install` (en la raíz) — instala dependencias de los workspaces.
- `npm run dev:backend` — levanta API en http://localhost:4000
- `npm run dev:frontend` — levanta UI en http://localhost:5173
- `npm run dev` — levanta ambos en paralelo.

## Variables de entorno
Crea `frontend/.env` y `backend/.env` a partir de los archivos `.env.example` correspondientes.

Supabase (proyecto):
- URL: https://ujmqikbvocnmftfskhhx.supabase.co
- ANON KEY: (colocar desde el panel de Supabase)
- SERVICE ROLE KEY (solo backend): (desde el panel, no exponer en frontend)

## Notas
- No compartas claves en commits o repos públicos.
- El backend usa `supabase-js` para tareas server-side.
