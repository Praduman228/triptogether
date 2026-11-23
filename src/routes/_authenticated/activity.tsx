import { createFileRoute } from '@tanstack/react-router';
import { ActivityPage } from '@/components/dashboard';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/_authenticated/activity')({head:()=>pageHead('Activity','Review your recorded travel expenses and settlement history.'),component:ActivityPage});