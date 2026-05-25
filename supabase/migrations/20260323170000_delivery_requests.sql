-- ─────────────────────────────────────────────────────────────
-- Delivery Requests (Courses sans commande produit)
-- ─────────────────────────────────────────────────────────────

-- 1. ENUM types
DROP TYPE IF EXISTS public.delivery_request_status CASCADE;
CREATE TYPE public.delivery_request_status AS ENUM (
  'pending',
  'accepted',
  'in_progress',
  'completed',
  'cancelled'
);

DROP TYPE IF EXISTS public.delivery_urgency CASCADE;
CREATE TYPE public.delivery_urgency AS ENUM (
  'normal',
  'urgent',
  'express'
);

-- 2. Table
CREATE TABLE IF NOT EXISTS public.delivery_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  deliverer_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  pickup_address TEXT NOT NULL,
  dropoff_address TEXT NOT NULL,
  package_description TEXT NOT NULL,
  urgency public.delivery_urgency DEFAULT 'normal'::public.delivery_urgency,
  proposed_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  status public.delivery_request_status DEFAULT 'pending'::public.delivery_request_status,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  accepted_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_delivery_requests_requester ON public.delivery_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_deliverer ON public.delivery_requests(deliverer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_status ON public.delivery_requests(status);
CREATE INDEX IF NOT EXISTS idx_delivery_requests_created ON public.delivery_requests(created_at DESC);

-- 4. Updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_delivery_request_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

-- 5. Enable RLS
ALTER TABLE public.delivery_requests ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies
DROP POLICY IF EXISTS "requesters_manage_own_delivery_requests" ON public.delivery_requests;
CREATE POLICY "requesters_manage_own_delivery_requests"
ON public.delivery_requests
FOR ALL
TO authenticated
USING (requester_id = auth.uid())
WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS "deliverers_view_pending_requests" ON public.delivery_requests;
CREATE POLICY "deliverers_view_pending_requests"
ON public.delivery_requests
FOR SELECT
TO authenticated
USING (status = 'pending'::public.delivery_request_status OR deliverer_id = auth.uid());

DROP POLICY IF EXISTS "deliverers_update_accepted_requests" ON public.delivery_requests;
CREATE POLICY "deliverers_update_accepted_requests"
ON public.delivery_requests
FOR UPDATE
TO authenticated
USING (deliverer_id = auth.uid() OR (status = 'pending'::public.delivery_request_status AND deliverer_id IS NULL))
WITH CHECK (deliverer_id = auth.uid() OR (status = 'pending'::public.delivery_request_status));

-- 7. Trigger
DROP TRIGGER IF EXISTS delivery_requests_updated_at ON public.delivery_requests;
CREATE TRIGGER delivery_requests_updated_at
  BEFORE UPDATE ON public.delivery_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_delivery_request_updated_at();
