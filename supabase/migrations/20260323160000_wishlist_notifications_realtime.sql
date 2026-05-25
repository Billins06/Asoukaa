-- Migration: Wishlist table + notification subscriptions
-- Timestamp: 20260323160000

-- ── Wishlists table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wishlists (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  product_id    UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  added_price   NUMERIC(12,2),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

-- Enable RLS
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

-- Users can only see and manage their own wishlist
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wishlists' AND policyname = 'wishlist_select_own'
  ) THEN
    CREATE POLICY wishlist_select_own ON public.wishlists
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wishlists' AND policyname = 'wishlist_insert_own'
  ) THEN
    CREATE POLICY wishlist_insert_own ON public.wishlists
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wishlists' AND policyname = 'wishlist_delete_own'
  ) THEN
    CREATE POLICY wishlist_delete_own ON public.wishlists
      FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- ── Enable realtime on wishlists and products ──────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'wishlists'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wishlists;
  END IF;
END $$;

-- Ensure products table is in realtime publication for price change alerts
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  END IF;
END $$;

-- Ensure notifications table is in realtime publication
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;
