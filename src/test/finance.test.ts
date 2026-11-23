import { describe,it,expect } from 'vitest';
import { balances,equalSplit,parseMoney,transfers,validateShares,type Expense } from '@/lib/finance';
function expense(amount:number,paid:Record<string,number>,spent:Record<string,number>):Expense{return {id:'e',trip_id:'t',title:'Test',amount,category:'Food & drinks',occurred_at:'2026-11-16T00:00:00Z',description:'',created_by:'A',reversal_of:null,receipt_path:null,expense_contributions:Object.entries(paid).map(([user_id,amount])=>({user_id,amount})),expense_splits:Object.entries(spent).map(([user_id,amount])=>({user_id,amount}))};}
describe('Integer-paise financial rules',()=>{
 it('personal ₹500 only increases A spending',()=>expect(balances(['A','B'],[expense(50000,{A:50000},{A:50000})],[])).toEqual({A:{paid:50000,spent:50000,net:0},B:{paid:0,spent:0,net:0}}));
 it('₹3000 shared by three yields ₹1000 owed by B and C',()=>{const b=balances(['A','B','C'],[expense(300000,{A:300000},{A:100000,B:100000,C:100000})],[]);expect([b['A']?.net,b['B']?.net,b['C']?.net]).toEqual([200000,-100000,-100000]);});
 it('₹1500 on behalf of B is owed to A',()=>{const b=balances(['A','B'],[expense(150000,{A:150000},{B:150000})],[]);expect([b['A']?.net,b['B']?.net]).toEqual([150000,-150000]);});
 it('custom ₹5000 split accepts ₹2000, ₹1000, ₹2000',()=>expect(()=>validateShares(500000,[{user_id:'A',amount:500000}],[{user_id:'A',amount:200000},{user_id:'B',amount:100000},{user_id:'C',amount:200000}])).not.toThrow());
 it('rejects custom shares not equaling total',()=>expect(()=>validateShares(500000,[{user_id:'A',amount:500000}],[{user_id:'A',amount:499999}])).toThrow());
 it('multiple contributors preserve paid and consumed independently',()=>{const b=balances(['A','B','C'],[expense(300000,{A:200000,B:100000},{A:100000,B:100000,C:100000})],[]);expect([b['A']?.net,b['B']?.net,b['C']?.net]).toEqual([100000,0,-100000]);});
 it('deterministically distributes paise without loss',()=>expect(equalSplit(100,['C','B','A'])).toEqual([{user_id:'A',amount:34},{user_id:'B',amount:33},{user_id:'C',amount:33}]));
 it('partial ₹500 settlement reduces ₹1500 debt to ₹1000',()=>{const b=balances(['A','B'],[expense(150000,{A:150000},{B:150000})],[{id:'s',trip_id:'t',sender_id:'B',recipient_id:'A',amount:50000,note:'',occurred_at:''}]);expect([b['A']?.net,b['B']?.net]).toEqual([100000,-100000]);expect(Object.values(b).reduce((s,r)=>s+r.net,0)).toBe(0);});
 it('reversal cancels but preserves original expense',()=>{const e=expense(150000,{A:150000},{B:150000});expect(balances(['A','B'],[e,{...e,id:'r',reversal_of:'e'}],[])['A']?.net).toBe(0);});
 it('suggested transfers settle zero-sum balances',()=>expect(transfers({A:{net:200000},B:{net:-100000},C:{net:-100000}})).toEqual([{sender_id:'B',recipient_id:'A',amount:100000},{sender_id:'C',recipient_id:'A',amount:100000}]));
 it('parses ₹0.29 without floating point loss',()=>expect(parseMoney('0.29')).toBe(29));
});