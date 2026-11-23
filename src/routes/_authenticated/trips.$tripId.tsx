import { createFileRoute } from '@tanstack/react-router';
import { TripDetail } from '@/components/trip-detail';
import { pageHead } from '@/lib/meta';
export const Route=createFileRoute('/_authenticated/trips/$tripId')({head:()=>pageHead('Trip finances','View a private trip budget, shared ledger, friends and settlements.'),component:Trip});
function Trip(){const {tripId}=Route.useParams();return <TripDetail tripId={tripId}/>;}