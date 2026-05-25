-- ============================================================
-- ASOUKAA SUPPORT TICKETS UPDATE - Add category and admin_response columns
-- ============================================================

-- Add category column if not exists
ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'Autre';

-- Add admin_response as alias (the existing column is admin_reply, add admin_response too)
ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS admin_response TEXT DEFAULT NULL;

-- Sync existing admin_reply data to admin_response
UPDATE public.support_tickets
SET admin_response = admin_reply
WHERE admin_reply IS NOT NULL AND admin_response IS NULL;

-- Add updated_at column if not exists
ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
