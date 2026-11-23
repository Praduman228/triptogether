import { createFileRoute,redirect,Outlet } from '@tanstack/react-router';
import { supabase } from '@/integrations/supabase/client';
import { TripProvider } from '@/components/trip-provider';
import { AppShell } from '@/components/app-shell';
export const Route=createFileRoute('/_authenticated')({ssr:false,beforeLoad:async()=>{const {data,error}=await supabase.auth.getUser();if(!data.user||error){if(!navigator.onLine){const {data:s}=await supabase.auth.getSession();if(s.session?.user)return;}throw redirect({to:'/auth'});}},component:()=> <TripProvider><AppShell><Outlet/></AppShell></TripProvider>});