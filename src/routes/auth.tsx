import { createFileRoute,useNavigate } from '@tanstack/react-router';
import { useEffect } from 'react';
import { AuthForm } from '@/components/auth-form';
import { supabase } from '@/integrations/supabase/client';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/auth')({head:()=>pageHead('Sign in','Sign in to TripTogether with Google or your email to access your shared trips.'),component:Auth});
function Auth(){
  const navigate=useNavigate();
  useEffect(()=>{
    const handleRedirect=()=>{
      const token=sessionStorage.getItem('trip-invite');
      if(token)void navigate({to:'/join',search:{token},replace:true});
      else void navigate({to:'/dashboard',replace:true});
    };
    void supabase.auth.getUser().then(({data})=>{if(data.user)handleRedirect();});
    const {data:{subscription}}=supabase.auth.onAuthStateChange((event,session)=>{
      if(session?.user&&(event==='SIGNED_IN'||event==='INITIAL_SESSION')){
        handleRedirect();
      }
    });
    return()=>subscription.unsubscribe();
  },[navigate]);
  return <AuthForm/>;
}