import { Router } from 'express'
import { supabaseAdmin } from '../supabase.js'
import { ok, fail, asyncHandler } from '../utils/http.js'

const router = Router()

// GET /api/catalog/productos
router.get('/productos', asyncHandler(async (_req, res) => {
  const { data, error } = await supabaseAdmin
    .from('producto')
    .select('*')
    .order('nombre', { ascending: true })
  if (error) return fail(res, error.message, 500)
  return ok(res, data)
}))

// GET /api/catalog/variantes?producto_id=...
router.get('/variantes', asyncHandler(async (req, res) => {
  const { producto_id } = req.query
  let query = supabaseAdmin.from('variante').select('*')
  if (producto_id) query = query.eq('producto_id', producto_id)
  const { data, error } = await query.order('codigo_variante', { ascending: true })
  if (error) return fail(res, error.message, 500)
  return ok(res, data)
}))

export default router
