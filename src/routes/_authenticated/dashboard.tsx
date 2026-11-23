import { createFileRoute } from '@tanstack/react-router';
import { Dashboard } from '@/components/dashboard';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/_authenticated/dashboard')({head:()=>pageHead('Home','Your personal trip budget and shared-expense overview.'),component:()=> <Dashboard/>});