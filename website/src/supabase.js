import { createClient } from '@supabase/supabase-js';

// Config comes from Vite env (VITE_ prefixed vars are exposed to the
// client). The anon key is meant to be public; row-level security is what
// protects the data (see supabase/schema.sql).
const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const configured = Boolean(url && anonKey);

export const supabase = configured ? createClient(url, anonKey) : null;
