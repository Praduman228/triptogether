import { createFileRoute } from '@tanstack/react-router';
import { ProfilePage } from '@/components/profile-page';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/_authenticated/profile')({head:()=>pageHead('Profile','Manage your traveller profile and view personal spending across trips.'),component:ProfilePage});