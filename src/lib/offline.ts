import { openDB } from 'idb';
import type { Overview, ExpenseInput } from './trips.functions';
type Operation = {id:string;userId:string;data:ExpenseInput;status:'pending'|'failed';error?:string};
const db = () => openDB('triptogether-v1',1,{upgrade(d){d.createObjectStore('snapshots');d.createObjectStore('queue',{keyPath:'id'});}});
export async function cacheOverview(userId:string,value:Overview){await (await db()).put('snapshots',value,userId);}
export async function cachedOverview(userId:string):Promise<Overview|undefined>{return (await db()).get('snapshots',userId);}
export async function enqueue(userId:string,data:ExpenseInput){await (await db()).put('queue',{id:data.id,userId,data,status:'pending'} satisfies Operation);}
export async function queued(userId:string):Promise<Operation[]>{return ((await (await db()).getAll('queue')) as Operation[]).filter(o=>o.userId===userId);}
export async function synchronize(userId:string,send:(data:ExpenseInput)=>Promise<unknown>){for(const op of await queued(userId)){try{await send(op.data);await (await db()).delete('queue',op.id);}catch(error){await (await db()).put('queue',{...op,status:'failed',error:error instanceof Error?error.message:'Synchronization failed'});}}}
export async function clearSnapshot(userId:string){await (await db()).delete('snapshots',userId);}