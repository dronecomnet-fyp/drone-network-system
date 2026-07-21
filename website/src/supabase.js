import { createClient } from '@supabase/supabase-js';

// Public client config for the DroneComNet Supabase project. The anon key
// is meant to be public (it ships in every client bundle); row-level
// security is the real access control (see supabase/schema.sql). These
// committed defaults let the built site work on any static host without
// wiring build-time secrets; a local .env.local (VITE_SUPABASE_*) overrides
// them for development against a different project.
const FALLBACK_URL = 'https://ysxnvsyyngkkngltwqfk.supabase.co';
const FALLBACK_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzeG52c3l5bmdra25nbHR3cWZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2NDk2NTUsImV4cCI6MjEwMDIyNTY1NX0.x-5B_agAms_9QIew6klSkSvIOQKwSKZX4_zf2DBXrFU';

const url = import.meta.env.VITE_SUPABASE_URL || FALLBACK_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || FALLBACK_ANON_KEY;

export const configured = Boolean(url && anonKey);

export const supabase = configured ? createClient(url, anonKey) : null;
