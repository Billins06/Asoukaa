-- ─── Analytics Events Table ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.analytics_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type    text NOT NULL,          -- product_view | cart_add | purchase | chat_open
  product_id    text,
  product_name  text,
  shop_id       text,
  order_id      text,
  amount        numeric,
  metadata      jsonb DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- Anyone (including anon) can insert events
CREATE POLICY "insert_analytics" ON public.analytics_events
  FOR INSERT WITH CHECK (true);

-- Users can read their own events
CREATE POLICY "select_own_analytics" ON public.analytics_events
  FOR SELECT USING (auth.uid() = user_id OR user_id IS NULL);

-- ─── Import Assisté Requests Table ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.import_requests (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  product_url           text,
  description           text NOT NULL,
  quantity              integer NOT NULL DEFAULT 1,
  category              text NOT NULL,
  origin                text NOT NULL,
  budget                text NOT NULL,
  needs_customs         boolean NOT NULL DEFAULT true,
  needs_quality_check   boolean NOT NULL DEFAULT true,
  status                text NOT NULL DEFAULT 'pending',  -- pending | processing | quoted | completed
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.import_requests ENABLE ROW LEVEL SECURITY;

-- Authenticated users can insert their own requests
CREATE POLICY "insert_import_request" ON public.import_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Users can read their own requests
CREATE POLICY "select_own_import_requests" ON public.import_requests
  FOR SELECT USING (auth.uid() = user_id OR user_id IS NULL);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'import_requests_updated_at'
  ) THEN
    CREATE TRIGGER import_requests_updated_at
      BEFORE UPDATE ON public.import_requests
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END;
$$;
