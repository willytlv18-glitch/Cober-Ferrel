# Supabase — Migraciones y RLS

## Requisitos
- Instala Supabase CLI: https://supabase.com/docs/guides/cli
- Inicia sesión: `supabase login`
- Enlaza tu proyecto: `supabase link --project-ref <REF>`
  - El `<REF>` es el ID del proyecto (ej. `ujmqikbvocnmftfskhhx`).

## Aplicar migraciones
- Desde la raíz de este repo:
```
supabase db push
```
Esto creará el esquema inicial, tipos ENUM, funciones auxiliares y habilitará RLS con políticas básicas.

## Crear usuario de app (roles)
1) Autentícate en tu app para obtener tu `auth.users.id` (UUID)
2) Inserta tu usuario como admin:
```
insert into app_user (auth_user_id, rol, activo)
values ('<TU_AUTH_UID>', 'admin', true);
```

## Verificar RLS
- Con una sesión autenticada no admin deberías poder leer catálogos (producto, variante) pero no insertarlos.
- Con admin podrás realizar mutaciones.

## Seeds opcionales
Puedes crear archivos en `supabase/seed/` y ejecutarlos con:
```
supabase db reset --seed
```
Advertencia: `reset` recrea la base (destructivo) en ambientes locales. No usar en producción.
