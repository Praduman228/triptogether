import { createFileRoute } from "@tanstack/react-router";
import { useEffect } from 'react';
import { useNavigate } from '@tanstack/react-router';
import { supabase } from '@/integrations/supabase/client';
import { AppShell } from '@/components/app-shell';
import { TripProvider } from '@/components/trip-provider';
import { Dashboard } from '@/components/dashboard';
import { pageHead } from '@/lib/meta';
export const Route = createFileRoute("/")({
  head:()=>pageHead('Your travel space','Plan shared trips and keep every expense, budget and balance together.'),
  component: Index,
});
function Index() {
  const navigate=useNavigate();
  useEffect(()=>{void supabase.auth.getUser().then(({data})=>{if(data.user)void navigate({to:'/dashboard',replace:true});});},[navigate]);
  return <TripProvider><AppShell guest><Dashboard guest/></AppShell></TripProvider>;
}
