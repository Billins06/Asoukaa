-- GPS Tracking & Delivery Ratings Migration
-- Adds: deliverer_positions (real-time GPS), delivery_ratings tables
-- Enables realtime on orders table for live status subscriptions

-- ══════════════════════════════════════════════════════════════════════════
-- 1. DELIVERER GPS POSITIONS TABLE
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.deliverer_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deliverer_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  mission_id UUID REFERENCES public.deliverer_missions(id) ON DELETE SET NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deliverer_positions_deliverer_id ON public.deliverer_positions(deliverer_id);
CREATE INDEX IF NOT EXISTS idx_deliverer_positions_mission_id ON public.deliverer_positions(mission_id);
CREATE INDEX IF NOT EXISTS idx_deliverer_positions_created_at ON public.deliverer_positions(created_at DESC);

-- ══════════════════════════════════════════════════════════════════════════
-- 2. DELIVERY RATINGS TABLE
-- ══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.delivery_ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  deliverer_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT DEFAULT '',
  photo_url TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_ratings_order_buyer ON public.delivery_ratings(order_id, buyer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_ratings_order_id ON public.delivery_ratings(order_id);
CREATE INDEX IF NOT EXISTS idx_delivery_ratings_deliverer_id ON public.delivery_ratings(deliverer_id);

-- ══════════════════════════════════════════════════════════════════════════
-- 3. ADD DELIVERY_NOTES COLUMN TO deliverer_missions (if not exists)
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.deliverer_missions
  ADD COLUMN IF NOT EXISTS delivery_notes TEXT DEFAULT '';

-- ══════════════════════════════════════════════════════════════════════════
-- 4. ENABLE RLS
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.deliverer_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_ratings ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════════════════════════════════════
-- 5. RLS POLICIES - deliverer_positions
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "deliverers_manage_own_positions" ON public.deliverer_positions;
CREATE POLICY "deliverers_manage_own_positions"
ON public.deliverer_positions
FOR ALL
TO authenticated
USING (deliverer_id = auth.uid())
WITH CHECK (deliverer_id = auth.uid());

DROP POLICY IF EXISTS "authenticated_read_positions" ON public.deliverer_positions;
CREATE POLICY "authenticated_read_positions"
ON public.deliverer_positions
FOR SELECT
TO authenticated
USING (true);

-- ══════════════════════════════════════════════════════════════════════════
-- 6. RLS POLICIES - delivery_ratings
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "buyers_manage_own_ratings" ON public.delivery_ratings;
CREATE POLICY "buyers_manage_own_ratings"
ON public.delivery_ratings
FOR ALL
TO authenticated
USING (buyer_id = auth.uid())
WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "authenticated_read_ratings" ON public.delivery_ratings;
CREATE POLICY "authenticated_read_ratings"
ON public.delivery_ratings
FOR SELECT
TO authenticated
USING (true);

-- ══════════════════════════════════════════════════════════════════════════
-- 7. ENABLE REALTIME ON ORDERS & POSITIONS
-- ══════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  -- Enable realtime publication for orders (status changes)
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;

  -- Enable realtime publication for deliverer_positions (GPS updates)
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'deliverer_positions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.deliverer_positions;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Realtime publication update: %', SQLERRM;
END $$;
