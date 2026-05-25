-- Migration: Additional tables for commissions, banners, refunds, withdrawals, admin logs
-- Safe to run multiple times (idempotent)

-- ── Commission Settings ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.commission_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rate numeric(5,2) NOT NULL DEFAULT 10.0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Insert default 10% commission if not exists
INSERT INTO public.commission_settings (rate, is_active)
SELECT 10.0, true
WHERE NOT EXISTS (SELECT 1 FROM public.commission_settings WHERE is_active = true);

-- ── Commissions (Sales) ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  seller_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  order_amount numeric(12,2) NOT NULL DEFAULT 0,
  commission_rate numeric(5,2) NOT NULL DEFAULT 10.0,
  commission_amount numeric(12,2) NOT NULL DEFAULT 0,
  seller_net_amount numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id)
);

-- ── Delivery Commissions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.delivery_commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid REFERENCES public.deliverer_missions(id) ON DELETE CASCADE,
  deliverer_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  delivery_fee numeric(12,2) NOT NULL DEFAULT 0,
  commission_rate numeric(5,2) NOT NULL DEFAULT 10.0,
  commission_amount numeric(12,2) NOT NULL DEFAULT 0,
  deliverer_net_amount numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(mission_id)
);

-- ── Deliverer Earnings ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.deliverer_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deliverer_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL DEFAULT 0,
  delivery_count integer NOT NULL DEFAULT 0,
  period_start timestamptz,
  period_end timestamptz,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid')),
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ── Banners ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.banners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL DEFAULT '',
  subtitle text DEFAULT '',
  image_url text NOT NULL DEFAULT '',
  link_url text DEFAULT '',
  link_type text DEFAULT 'product' CHECK (link_type IN ('product', 'category', 'shop', 'url', 'none')),
  link_id text DEFAULT '',
  is_active boolean NOT NULL DEFAULT true,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── Refund Requests ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.refund_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  buyer_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  reason text NOT NULL DEFAULT '',
  amount numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'processed')),
  admin_note text DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── Withdrawals ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.withdrawals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  amount numeric(12,2) NOT NULL DEFAULT 0,
  payment_method text NOT NULL DEFAULT 'mobile_money',
  payment_details jsonb DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
  admin_note text DEFAULT '',
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── Admin Logs ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  action text NOT NULL DEFAULT '',
  target_type text NOT NULL DEFAULT '',
  target_id text DEFAULT '',
  details jsonb DEFAULT '{}',
  ip_address text DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ── Import Assisté Products ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.import_assiste_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL DEFAULT '',
  description text DEFAULT '',
  origin text NOT NULL DEFAULT 'Chine',
  price integer NOT NULL DEFAULT 0,
  original_price integer DEFAULT 0,
  image_url text DEFAULT '',
  min_order integer NOT NULL DEFAULT 1,
  stock integer NOT NULL DEFAULT 0,
  badge text DEFAULT '',
  delivery_days text DEFAULT '12-18 jours',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── RLS Policies ──────────────────────────────────────────────────────────

-- Commission settings: public read
ALTER TABLE public.commission_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "commission_settings_read" ON public.commission_settings;
CREATE POLICY "commission_settings_read" ON public.commission_settings FOR SELECT USING (true);

-- Commissions: seller can read own, admin can read all
ALTER TABLE public.commissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "commissions_seller_read" ON public.commissions;
CREATE POLICY "commissions_seller_read" ON public.commissions FOR SELECT
  USING (auth.uid() = seller_id);

-- Delivery commissions: deliverer can read own
ALTER TABLE public.delivery_commissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "delivery_commissions_deliverer_read" ON public.delivery_commissions;
CREATE POLICY "delivery_commissions_deliverer_read" ON public.delivery_commissions FOR SELECT
  USING (auth.uid() = deliverer_id);

-- Deliverer earnings: deliverer can read own
ALTER TABLE public.deliverer_earnings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "deliverer_earnings_read" ON public.deliverer_earnings;
CREATE POLICY "deliverer_earnings_read" ON public.deliverer_earnings FOR SELECT
  USING (auth.uid() = deliverer_id);

-- Banners: public read
ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "banners_public_read" ON public.banners;
CREATE POLICY "banners_public_read" ON public.banners FOR SELECT USING (true);

-- Refund requests: buyer can read own, insert own
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "refund_requests_buyer_read" ON public.refund_requests;
CREATE POLICY "refund_requests_buyer_read" ON public.refund_requests FOR SELECT
  USING (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "refund_requests_buyer_insert" ON public.refund_requests;
CREATE POLICY "refund_requests_buyer_insert" ON public.refund_requests FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);

-- Withdrawals: seller can read own, insert own
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "withdrawals_seller_read" ON public.withdrawals;
CREATE POLICY "withdrawals_seller_read" ON public.withdrawals FOR SELECT
  USING (auth.uid() = seller_id);
DROP POLICY IF EXISTS "withdrawals_seller_insert" ON public.withdrawals;
CREATE POLICY "withdrawals_seller_insert" ON public.withdrawals FOR INSERT
  WITH CHECK (auth.uid() = seller_id);

-- Admin logs: authenticated users can insert
ALTER TABLE public.admin_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_logs_insert" ON public.admin_logs;
CREATE POLICY "admin_logs_insert" ON public.admin_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- Import assisté products: public read
ALTER TABLE public.import_assiste_products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "import_assiste_products_read" ON public.import_assiste_products;
CREATE POLICY "import_assiste_products_read" ON public.import_assiste_products FOR SELECT
  USING (true);
