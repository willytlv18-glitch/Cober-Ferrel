export function ok(res, data = {}, status = 200) {
  res.status(status).json({ ok: true, data })
}

export function fail(res, message = 'Error', status = 500, meta = {}) {
  res.status(status).json({ ok: false, error: message, meta })
}

export const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next)
}
