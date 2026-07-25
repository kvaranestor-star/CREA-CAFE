// =====================================================================
//  api/monobank.js — заглушка QR-оплати через Monobank Acquiring.
//  ESM (Vercel serverless). Викликається фронтом POST /api/monobank
//  з body { amount, reference }. Повертає { invoiceId, pageUrl }.
//
//  ⚠️ ЩОБ ПРАЦЮВАЛО:
//   1. У Vercel → Project → Settings → Environment Variables додай:
//        MONO_TOKEN  = <X-Token мерчанта з Monobank Acquiring>
//   2. Розкоментуй справжній виклик нижче (зараз повертає demo-відповідь,
//      щоб UI не падав, поки токена немає).
//   Документація: https://api.monobank.ua/docs/acquiring.html
// =====================================================================
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }
  const { amount = 0, reference = '' } = req.body || {};
  const token = process.env.MONO_TOKEN;

  // --- DEMO-режим (без токена): не ходимо в банк, повертаємо заглушку ---
  if (!token) {
    res.status(200).json({
      demo: true,
      invoiceId: 'demo-' + Date.now(),
      pageUrl: '',
      note: 'MONO_TOKEN не заданий — це демо-відповідь. Додай токен у Vercel env.',
    });
    return;
  }

  // --- Реальний виклик Monobank Acquiring ---
  try {
    const r = await fetch('https://api.monobank.ua/api/merchant/invoice/create', {
      method: 'POST',
      headers: { 'X-Token': token, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(Number(amount) * 100), // копійки
        ccy: 980,                                  // UAH
        merchantPaymInfo: { reference: String(reference).slice(0, 60) },
        // redirectUrl / webHookUrl — за потреби
      }),
    });
    const data = await r.json();
    if (!r.ok) {
      res.status(502).json({ error: 'monobank', detail: data });
      return;
    }
    res.status(200).json({ invoiceId: data.invoiceId, pageUrl: data.pageUrl });
  } catch (e) {
    res.status(500).json({ error: String(e && e.message || e) });
  }
}
