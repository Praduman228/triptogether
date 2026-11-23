export type Share = { user_id: string; amount: number };
export type Expense = { id: string; trip_id: string; title: string; amount: number; category: string; occurred_at: string; description: string; created_by: string; reversal_of: string | null; receipt_path: string | null; expense_contributions: Share[]; expense_splits: Share[] };
export type Settlement = { id: string; trip_id: string; created_by?: string; sender_id: string; recipient_id: string; amount: number; note: string; occurred_at: string };
export function parseMoney(value: string) {
  if (!/^\d+(\.\d{1,2})?$/.test(value.trim())) throw new Error('Enter an amount with up to two decimal places.');
  const [whole, fraction = ''] = value.trim().split('.');
  const amount = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  if (!Number.isSafeInteger(amount) || amount > 9000000000000) throw new Error('Amount is too large.');
  return amount;
}
export function equalSplit(amount: number, ids: string[]): Share[] {
  if (!Number.isSafeInteger(amount) || amount <= 0 || !ids.length || new Set(ids).size !== ids.length) throw new Error('Select beneficiaries and a valid amount.');
  const sorted = [...ids].sort();
  return sorted.map((user_id, index) => ({ user_id, amount: Math.floor(amount / sorted.length) + (index < amount % sorted.length ? 1 : 0) }));
}
export function validateShares(amount: number, contributions: Share[], splits: Share[]) {
  for (const [rows, allowZero] of [[contributions, false], [splits, true]] as const) {
    if (!rows.length || new Set(rows.map(r => r.user_id)).size !== rows.length || rows.some(r => !Number.isSafeInteger(r.amount) || r.amount < (allowZero ? 0 : 1)) || rows.reduce((s, r) => s + r.amount, 0) !== amount) throw new Error('Contributions and shares must each equal the total.');
  }
}
export function balances(ids: string[], expenses: Expense[], settlements: Settlement[]) {
  const result = Object.fromEntries(ids.map(id => [id, { paid: 0, spent: 0, net: 0 }]));
  for (const e of expenses) {
    const sign = e.reversal_of ? -1 : 1;
    for (const r of e.expense_contributions) { const member=result[r.user_id]; if (member) { member.paid += sign * r.amount; member.net += sign * r.amount; } }
    for (const r of e.expense_splits) { const member=result[r.user_id]; if (member) { member.spent += sign * r.amount; member.net -= sign * r.amount; } }
  }
  for (const s of settlements) { const sender=result[s.sender_id];const recipient=result[s.recipient_id];if(sender)sender.net+=s.amount;if(recipient)recipient.net-=s.amount; }
  return result;
}
export function transfers(net: Record<string, { net: number }>) {
  const creditors = Object.entries(net).filter(([, r]) => r.net > 0).map(([id, r]) => ({ id, amount: r.net })).sort((a,b) => b.amount-a.amount || a.id.localeCompare(b.id));
  const debtors = Object.entries(net).filter(([, r]) => r.net < 0).map(([id, r]) => ({ id, amount: -r.net })).sort((a,b) => b.amount-a.amount || a.id.localeCompare(b.id));
  const rows: { sender_id: string; recipient_id: string; amount: number }[] = [];
  for (const d of debtors) for (const c of creditors) { const amount = Math.min(d.amount,c.amount); if (amount) { rows.push({ sender_id:d.id,recipient_id:c.id,amount }); d.amount -= amount; c.amount -= amount; } }
  return rows;
}
export function money(amount: number, currency = 'INR') { return new Intl.NumberFormat('en-IN', { style:'currency', currency, maximumFractionDigits: amount % 100 ? 2 : 0 }).format(amount / 100); }
export const categories = ['Accommodation','Food & drinks','Transportation','Fuel','Shopping','Activities','Entertainment','Miscellaneous'] as const;