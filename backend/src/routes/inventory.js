import { Router } from 'express'
import { z } from 'zod'
import { supabaseAdmin } from '../supabase.js'
import { ok, fail, asyncHandler } from '../utils/http.js'

const router = Router()

// Schemas
const almacenSchema = z.object({
  nombre: z.string().min(1),
  direccion: z.string().optional(),
  tipo: z.enum(['materia_prima', 'producto_terminado'])
})

const ubicacionSchema = z.object({
  almacen_id: z.string().uuid(),
  codigo: z.string().min(1),
  descripcion: z.string().optional()
})

const loteSchema = z.object({
  variante_id: z.string().uuid(),
  tipo_lote: z.enum(['bobina', 'quimico', 'pieza']),
  codigo_lote: z.string().min(1),
  fecha_fabricacion: z.string().optional(), // YYYY-MM-DD
  atributos_json: z.record(z.any()).optional()
})

const movimientoSchema = z.object({
  tipo: z.enum(['ingreso','salida','ajuste','consumo_op','traslado']),
  referencia: z.string().optional(),
  cantidad: z.number().positive(),
  unidad: z.enum(['M2','ML','PZA','KG','LT']),
  lote_id: z.string().uuid(),
  ubicacion_origen_id: z.string().uuid().optional(),
  ubicacion_destino_id: z.string().uuid().optional()
})

// POST /api/inventario/almacenes
router.post('/almacenes', asyncHandler(async (req, res) => {
  const parsed = almacenSchema.safeParse(req.body)
  if (!parsed.success) return fail(res, parsed.error.issues, 400)
  const { data, error } = await supabaseAdmin.from('almacen').insert(parsed.data).select('*').single()
  if (error) return fail(res, error.message, 500)
  return ok(res, data, 201)
}))

// POST /api/inventario/ubicaciones
router.post('/ubicaciones', asyncHandler(async (req, res) => {
  const parsed = ubicacionSchema.safeParse(req.body)
  if (!parsed.success) return fail(res, parsed.error.issues, 400)
  const { data, error } = await supabaseAdmin.from('ubicacion').insert(parsed.data).select('*').single()
  if (error) return fail(res, error.message, 500)
  return ok(res, data, 201)
}))

// POST /api/inventario/lotes
router.post('/lotes', asyncHandler(async (req, res) => {
  const parsed = loteSchema.safeParse(req.body)
  if (!parsed.success) return fail(res, parsed.error.issues, 400)
  const { data, error } = await supabaseAdmin.from('lote').insert(parsed.data).select('*').single()
  if (error) return fail(res, error.message, 500)
  return ok(res, data, 201)
}))

// Helper para actualizar stock según movimiento
async function aplicarMovimiento(mov) {
  // Insertamos movimiento
  const { data: movIns, error: movErr } = await supabaseAdmin.from('movimiento_stk').insert({
    tipo: mov.tipo,
    referencia: mov.referencia ?? null,
    cantidad: mov.cantidad,
    unidad: mov.unidad,
    lote_id: mov.lote_id,
    ubicacion_origen_id: mov.ubicacion_origen_id ?? null,
    ubicacion_destino_id: mov.ubicacion_destino_id ?? null
  }).select('*').single()
  if (movErr) throw new Error(movErr.message)

  // Resolver delta por ubicaciones
  const deltas = []
  if (mov.tipo === 'ingreso') {
    deltas.push({ lote_id: mov.lote_id, ubicacion_id: mov.ubicacion_destino_id, delta: mov.cantidad })
  } else if (mov.tipo === 'salida' || mov.tipo === 'consumo_op') {
    deltas.push({ lote_id: mov.lote_id, ubicacion_id: mov.ubicacion_origen_id, delta: -mov.cantidad })
  } else if (mov.tipo === 'ajuste') {
    // ajuste aplica al destino como delta directo (positivo o negativo)
    deltas.push({ lote_id: mov.lote_id, ubicacion_id: mov.ubicacion_destino_id, delta: mov.cantidad })
  } else if (mov.tipo === 'traslado') {
    deltas.push({ lote_id: mov.lote_id, ubicacion_id: mov.ubicacion_origen_id, delta: -mov.cantidad })
    deltas.push({ lote_id: mov.lote_id, ubicacion_id: mov.ubicacion_destino_id, delta: mov.cantidad })
  }

  for (const d of deltas) {
    if (!d.ubicacion_id) throw new Error('Ubicación requerida para movimiento')
    // Buscar stock existente
    const { data: stockExist, error: stockErr } = await supabaseAdmin
      .from('stock')
      .select('*')
      .eq('lote_id', d.lote_id)
      .eq('ubicacion_id', d.ubicacion_id)
      .maybeSingle()
    if (stockErr) throw new Error(stockErr.message)

    if (stockExist) {
      const nueva = Number(stockExist.cantidad) + d.delta
      const { error: updErr } = await supabaseAdmin
        .from('stock')
        .update({ cantidad: nueva })
        .eq('id', stockExist.id)
      if (updErr) throw new Error(updErr.message)
    } else {
      const { error: insErr } = await supabaseAdmin
        .from('stock')
        .insert({ lote_id: d.lote_id, ubicacion_id: d.ubicacion_id, cantidad: d.delta, unidad: mov.unidad })
      if (insErr) throw new Error(insErr.message)
    }
  }
  return movIns
}

// POST /api/inventario/movimientos
router.post('/movimientos', asyncHandler(async (req, res) => {
  const parsed = movimientoSchema.safeParse(req.body)
  if (!parsed.success) return fail(res, parsed.error.issues, 400)
  try {
    const result = await aplicarMovimiento(parsed.data)
    return ok(res, result, 201)
  } catch (e) {
    return fail(res, e.message, 500)
  }
}))

// GET /api/inventario/kardex?lote_id=...
router.get('/kardex', asyncHandler(async (req, res) => {
  const { lote_id } = req.query
  if (!lote_id) return fail(res, 'lote_id requerido', 400)
  const { data, error } = await supabaseAdmin
    .from('movimiento_stk')
    .select('*')
    .eq('lote_id', lote_id)
    .order('fecha', { ascending: true })
  if (error) return fail(res, error.message, 500)
  return ok(res, data)
}))

export default router
