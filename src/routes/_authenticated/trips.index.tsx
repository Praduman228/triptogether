import { createFileRoute } from '@tanstack/react-router';
import { Dashboard } from '@/components/dashboard';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/_authenticated/trips/')({head:()=>pageHead('My trips','Find your current, upcoming and past shared trips.'),component:()=> <Dashboard tripsOnly/>});