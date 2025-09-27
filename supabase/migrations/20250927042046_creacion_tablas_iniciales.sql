-- Migración inicial: esquema base + RLS mínimas
-- Fecha: 2025-09-27
-- ARCHIVO CORREGIDO Y REORDENADO LÓGICAMENTE

-- =============================================================
-- 1. SETUP INICIAL (EXTENSIONES Y TIPOS)
-- =============================================================
create extension if not exists "pgcrypto" with schema pg_catalog;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'rol_app') then
    create type rol_app as enum ('admin','ventas','almacen','produccion','contabilidad');
  end if;
  if not exists (select 1 from pg_type where typname = 'udm') then
    create type udm as enum ('M2','ML','PZA','KG','LT');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_cot') then
    create type estado_cot as enum ('borrador','enviado','aceptado','vencido');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_pedido') then
    create type estado_pedido as enum ('abierto','en_produccion','parcial','cerrado');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_op') then
    create type estado_op as enum ('planificada','en_proceso','terminada');
  end if;
  if not exists (select 1 from pg_type where typname = 'segmento_cliente') then
    create type segmento_cliente as enum ('publico','revendedor','proyecto');
  end if;
end$$;

-- =============================================================
-- 2. CREACIÓN DE TODAS LAS TABLAS
-- =============================================================

-- Tablas de seguridad / usuarios de aplicación
create table if not exists app_user (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique,
  rol rol_app not null default 'ventas',
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- Catálogos principales
create table if not exists cliente (
  id uuid primary key default gen_random_uuid(),
  ruc varchar(11),
  razon_social text not null,
  segmento segmento_cliente not null default 'publico',
  direccion_fiscal text,
  telefono text,
  email text,
  created_at timestamptz not null default now()
);

create table if not exists contacto (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references cliente(id) on delete cascade,
  nombre text not null,
  cargo text,
  telefono text,
  email text
);

create table if not exists producto (
  id uuid primary key default gen_random_uuid(),
  tipo text not null, -- muro, techo, cobertura, accesorio, insumo
  nombre text not null,
  codigo_sku text not null unique,
  unidad_base udm not null,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists variante (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references producto(id) on delete cascade,
  espesor_mm numeric(6,2),
  ancho_util_mm numeric(8,2),
  color text,
  material_base text,
  densidad text, -- PUR/EPS/etc
  codigo_variante text not null unique
);

create table if not exists lista_precio (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  segmento segmento_cliente not null,
  moneda text not null default 'USD',
  vigente_desde date not null default current_date,
  vigente_hasta date
);

create table if not exists lista_precio_item (
  id uuid primary key default gen_random_uuid(),
  lista_precio_id uuid not null references lista_precio(id) on delete cascade,
  variante_id uuid not null references variante(id) on delete restrict,
  regla_dimension jsonb, -- rangos de ml/m2/espesor
  precio_unitario numeric(14,4) not null,
  unidad_precio udm not null
);

-- Inventario
create table if not exists almacen (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  direccion text,
  tipo text not null -- materia_prima, producto_terminado
);

create table if not exists ubicacion (
  id uuid primary key default gen_random_uuid(),
  almacen_id uuid not null references almacen(id) on delete cascade,
  codigo text not null,
  descripcion text,
  unique(almacen_id, codigo)
);

create table if not exists lote (
  id uuid primary key default gen_random_uuid(),
  variante_id uuid not null references variante(id) on delete restrict,
  tipo_lote text not null, -- bobina, quimico, pieza
  codigo_lote text not null,
  fecha_fabricacion date,
  atributos_json jsonb,
  unique (codigo_lote)
);

create table if not exists stock (
  id uuid primary key default gen_random_uuid(),
  lote_id uuid not null references lote(id) on delete cascade,
  ubicacion_id uuid not null references ubicacion(id) on delete restrict,
  cantidad numeric(18,6) not null default 0,
  unidad udm not null
);

create table if not exists movimiento_stk (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  tipo text not null, -- ingreso, salida, ajuste, consumo_op
  referencia text,
  cantidad numeric(18,6) not null,
  unidad udm not null,
  lote_id uuid references lote(id),
  ubicacion_origen_id uuid references ubicacion(id),
  ubicacion_destino_id uuid references ubicacion(id)
);

-- Comercial: Cotizaciones y Pedidos
create table if not exists cotizacion (
  id uuid primary key default gen_random_uuid(),
  nro text unique,
  cliente_id uuid not null references cliente(id),
  fecha date not null default current_date,
  estado estado_cot not null default 'borrador',
  moneda text not null default 'USD',
  validez_dias int default 7
);

create table if not exists cotizacion_item (
  id uuid primary key default gen_random_uuid(),
  cotizacion_id uuid not null references cotizacion(id) on delete cascade,
  variante_id uuid not null references variante(id),
  ancho_util_m numeric(8,3),
  largo_m numeric(8,3),
  cantidad_piezas int,
  unidad_comercial udm not null,
  m2_total numeric(14,4),
  precio_unitario numeric(14,4) not null,
  descuento_pct numeric(6,2) default 0,
  subtotal numeric(14,4) not null,
  descripcion_snapshot text
);

create table if not exists pedido (
  id uuid primary key default gen_random_uuid(),
  nro text unique,
  cliente_id uuid not null references cliente(id),
  fecha date not null default current_date,
  fecha_compromiso date,
  estado estado_pedido not null default 'abierto'
);

create table if not exists pedido_item (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references pedido(id) on delete cascade,
  cotizacion_item_id uuid references cotizacion_item(id),
  variante_id uuid not null references variante(id),
  dimensiones_json jsonb,
  cantidades_json jsonb,
  reglas_precio_snapshot jsonb,
  subtotal numeric(14,4) not null
);

-- Producción
create table if not exists orden_produccion (
  id uuid primary key default gen_random_uuid(),
  nro text unique,
  pedido_id uuid not null references pedido(id),
  fecha_inicio_plan date,
  fecha_fin_plan date,
  linea text, -- manual/automatica
  estado estado_op not null default 'planificada'
);

create table if not exists op_operacion (
  id uuid primary key default gen_random_uuid(),
  orden_produccion_id uuid not null references orden_produccion(id) on delete cascade,
  secuencia int not null,
  recurso_id uuid,
  tiempo_std_min numeric(10,2),
  capacidad_ud_hora numeric(10,2),
  parametros_json jsonb
);

-- Documentos: Guía de Remisión (estructura mínima)
create table if not exists guia_remision (
  id uuid primary key default gen_random_uuid(),
  serie text not null,
  numero text not null,
  fecha_emision date not null default current_date,
  motivo_traslado text,
  punto_partida text,
  punto_llegada text,
  placa text,
  conductor text,
  unique(serie, numero)
);

create table if not exists guia_item (
  id uuid primary key default gen_random_uuid(),
  guia_id uuid not null references guia_remision(id) on delete cascade,
  variante_id uuid references variante(id),
  descripcion text,
  unidad udm not null,
  cantidad numeric(14,4) not null,
  ancho_util_m numeric(8,3),
  largo_m numeric(8,3),
  lote_id uuid references lote(id)
);


-- =============================================================
-- 3. FUNCIONES AUXILIARES PARA RLS
-- =============================================================
create or replace function app_has_role(role_name text)
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from app_user u
    where u.auth_user_id = auth.uid()
      and u.activo = true
      and u.rol::text = role_name
  );
$$;

create or replace function app_is_auth()
returns boolean language sql stable as $$ select auth.uid() is not null $$;


-- =============================================================
-- 4. ACTIVACIÓN DE RLS Y CREACIÓN DE POLÍTICAS
-- =============================================================

-- Habilitar RLS en todas las tablas primero
alter table app_user enable row level security;
alter table cliente enable row level security;
alter table contacto enable row level security;
alter table producto enable row level security;
alter table variante enable row level security;
alter table lista_precio enable row level security;
alter table lista_precio_item enable row level security;
alter table almacen enable row level security;
alter table ubicacion enable row level security;
alter table lote enable row level security;
alter table stock enable row level security;
alter table movimiento_stk enable row level security;
alter table cotizacion enable row level security;
alter table cotizacion_item enable row level security;
alter table pedido enable row level security;
alter table pedido_item enable row level security;
alter table orden_produccion enable row level security;
alter table op_operacion enable row level security;
alter table guia_remision enable row level security;
alter table guia_item enable row level security;

-- Crear políticas para cada tabla

-- app_user
drop policy if exists app_user_sel on app_user;
create policy app_user_sel on app_user for select using (auth.uid() = auth_user_id or app_has_role('admin'));
drop policy if exists app_user_ins on app_user;
create policy app_user_ins on app_user for insert with check (app_has_role('admin'));
drop policy if exists app_user_upd on app_user;
create policy app_user_upd on app_user for update using (app_has_role('admin')) with check (app_has_role('admin'));

-- Cliente
drop policy if exists cliente_sel on cliente;
create policy cliente_sel on cliente for select using (app_is_auth());
drop policy if exists cliente_mut on cliente;
create policy cliente_mut on cliente for all using (app_has_role('admin')) with check (app_has_role('admin'));

-- Contacto
drop policy if exists contacto_sel on contacto;
create policy contacto_sel on contacto for select using (app_is_auth());
drop policy if exists contacto_mut on contacto;
create policy contacto_mut on contacto for all using (app_has_role('admin')) with check (app_has_role('admin'));

-- Producto / Variante
drop policy if exists producto_sel on producto;
create policy producto_sel on producto for select using (app_is_auth());
drop policy if exists producto_mut on producto;
create policy producto_mut on producto for all using (app_has_role('admin')) with check (app_has_role('admin'));
drop policy if exists variante_sel on variante;
create policy variante_sel on variante for select using (app_is_auth());
drop policy if exists variante_mut on variante;
create policy variante_mut on variante for all using (app_has_role('admin')) with check (app_has_role('admin'));

-- Listas de precios
drop policy if exists lp_sel on lista_precio;
create policy lp_sel on lista_precio for select using (app_is_auth());
drop policy if exists lp_mut on lista_precio;
create policy lp_mut on lista_precio for all using (app_has_role('admin')) with check (app_has_role('admin'));
drop policy if exists lpi_sel on lista_precio_item;
create policy lpi_sel on lista_precio_item for select using (app_is_auth());
drop policy if exists lpi_mut on lista_precio_item;
create policy lpi_mut on lista_precio_item for all using (app_has_role('admin')) with check (app_has_role('admin'));

-- Inventario
drop policy if exists alm_sel on almacen;
create policy alm_sel on almacen for select using (app_is_auth());
drop policy if exists alm_mut on almacen;
create policy alm_mut on almacen for all using (app_has_role('admin')) with check (app_has_role('admin'));
drop policy if exists ubi_sel on ubicacion;
create policy ubi_sel on ubicacion for select using (app_is_auth());
drop policy if exists ubi_mut on ubicacion;
create policy ubi_mut on ubicacion for all using (app_has_role('admin')) with check (app_has_role('admin'));
drop policy if exists lote_sel on lote;
create policy lote_sel on lote for select using (app_is_auth());
drop policy if exists lote_mut on lote;
create policy lote_mut on lote for all using (app_has_role('almacen') or app_has_role('admin')) with check (app_has_role('almacen') or app_has_role('admin'));
drop policy if exists stock_sel on stock;
create policy stock_sel on stock for select using (app_is_auth());
drop policy if exists stock_mut on stock;
create policy stock_mut on stock for all using (app_has_role('almacen') or app_has_role('admin')) with check (app_has_role('almacen') or app_has_role('admin'));
drop policy if exists mov_sel on movimiento_stk;
create policy mov_sel on movimiento_stk for select using (app_is_auth());
drop policy if exists mov_mut on movimiento_stk;
create policy mov_mut on movimiento_stk for all using (app_has_role('almacen') or app_has_role('produccion') or app_has_role('admin')) with check (app_has_role('almacen') or app_has_role('produccion') or app_has_role('admin'));

-- Comercial
drop policy if exists cot_sel on cotizacion;
create policy cot_sel on cotizacion for select using (app_is_auth());
drop policy if exists cot_mut on cotizacion;
create policy cot_mut on cotizacion for all using (app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('ventas') or app_has_role('admin'));
drop policy if exists coti_sel on cotizacion_item;
create policy coti_sel on cotizacion_item for select using (app_is_auth());
drop policy if exists coti_mut on cotizacion_item;
create policy coti_mut on cotizacion_item for all using (app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('ventas') or app_has_role('admin'));
drop policy if exists ped_sel on pedido;
create policy ped_sel on pedido for select using (app_is_auth());
drop policy if exists ped_mut on pedido;
create policy ped_mut on pedido for all using (app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('ventas') or app_has_role('admin'));
drop policy if exists pedi_sel on pedido_item;
create policy pedi_sel on pedido_item for select using (app_is_auth());
drop policy if exists pedi_mut on pedido_item;
create policy pedi_mut on pedido_item for all using (app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('ventas') or app_has_role('admin'));

-- Producción
drop policy if exists op_sel on orden_produccion;
create policy op_sel on orden_produccion for select using (app_is_auth());
drop policy if exists op_mut on orden_produccion;
create policy op_mut on orden_produccion for all using (app_has_role('produccion') or app_has_role('admin')) with check (app_has_role('produccion') or app_has_role('admin'));
drop policy if exists opo_sel on op_operacion;
create policy opo_sel on op_operacion for select using (app_is_auth());
drop policy if exists opo_mut on op_operacion;
create policy opo_mut on op_operacion for all using (app_has_role('produccion') or app_has_role('admin')) with check (app_has_role('produccion') or app_has_role('admin'));

-- Guías
drop policy if exists guia_sel on guia_remision;
create policy guia_sel on guia_remision for select using (app_is_auth());
drop policy if exists guia_mut on guia_remision;
create policy guia_mut on guia_remision for all using (app_has_role('almacen') or app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('almacen') or app_has_role('ventas') or app_has_role('admin'));
drop policy if exists guiai_sel on guia_item;
create policy guiai_sel on guia_item for select using (app_is_auth());
drop policy if exists guiai_mut on guia_item;
create policy guiai_mut on guia_item for all using (app_has_role('almacen') or app_has_role('ventas') or app_has_role('admin')) with check (app_has_role('almacen') or app_has_role('ventas') or app_has_role('admin'));


-- =============================================================
-- 5. ÍNDICES ÚTILES
-- =============================================================
create index if not exists idx_variante_producto on variante(producto_id);
create index if not exists idx_lote_variante on lote(variante_id);
create index if not exists idx_stock_lote on stock(lote_id);
create index if not exists idx_mov_fecha on movimiento_stk(fecha);
create index if not exists idx_cot_cliente on cotizacion(cliente_id);
create index if not exists idx_ped_cliente on pedido(cliente_id);
create index if not exists idx_op_pedido on orden_produccion(pedido_id);