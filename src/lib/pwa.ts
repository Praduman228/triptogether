export async function registerOfflineApp() {
  if(!('serviceWorker' in navigator))return;
  const h=window.location.hostname.toLowerCase();
  const platform=['lovable.app','gpt-eng.com','gptengineer.run'].some(s=>h.endsWith('.'+s));
  const label=h.split('.')[0]??'';
  const preview=platform && (/^(?:id-preview|preview)(?:-[a-z0-9]+)?--.+$/.test(label) || label==='project--bf26302b-f237-4a82-b501-071ca092c08e-dev');
  const refused=!import.meta.env.PROD || window.self!==window.top || preview || ['lovableproject.com','lovableproject-dev.com','beta.lovable.dev'].some(s=>h===s||h.endsWith('.'+s)) || new URLSearchParams(location.search).get('sw')==='off';
  if(refused){for(const r of await navigator.serviceWorker.getRegistrations())if([r.active,r.waiting,r.installing].some(w=>w&&new URL(w.scriptURL).pathname==='/sw.js'))await r.unregister();return;}
  const {registerSW}=await import('virtual:pwa-register');registerSW({immediate:true});
}