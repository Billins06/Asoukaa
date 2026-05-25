-- Add 'admin' to user_role enum if not already present
-- Must be outside a DO block to commit before being used in policies
ALTER TYPE public.user_role ADD VALUE IF NOT EXISTS 'admin';

-- Add commission tracking to orders and deliverer_missions
-- Commission rate: 10% on sales and deliveries

-- Add commission columns to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5,2) DEFAULT 10.00;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS commission_amount DECIMAL(12,2) GENERATED ALWAYS AS (total * commission_rate / 100) STORED;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS seller_net_amount DECIMAL(12,2) GENERATED ALWAYS AS (total * (100 - commission_rate) / 100) STORED;

-- Add commission columns to deliverer_missions
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5,2) DEFAULT 10.00;
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS commission_amount DECIMAL(12,2);
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS deliverer_net_amount DECIMAL(12,2);

-- Create commissions table for tracking
CREATE TABLE IF NOT EXISTS commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "type" TEXT NOT NULL CHECK (type IN ('sale', 'delivery')),
  reference_id UUID NOT NULL,
  seller_id UUID REFERENCES user_profiles(id),
  deliverer_id UUID REFERENCES user_profiles(id),
  gross_amount DECIMAL(12,2) NOT NULL,
  commission_rate DECIMAL(5,2) NOT NULL DEFAULT 10.00,
  commission_amount DECIMAL(12,2) NOT NULL,
  net_amount DECIMAL(12,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create commission_settings table for admin to modify rate
CREATE TABLE IF NOT EXISTS commission_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "type" TEXT NOT NULL UNIQUE CHECK (type IN ('sale', 'delivery', 'import')),
  rate DECIMAL(5,2) NOT NULL DEFAULT 10.00,
  updated_by UUID REFERENCES user_profiles(id),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default commission settings
INSERT INTO commission_settings (type, rate) VALUES
  ('sale', 10.00),
  ('delivery', 10.00),
  ('import', 5.00)
ON CONFLICT (type) DO NOTHING;

-- Add delivery expiration and priority fields to deliverer_missions
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS priority_score INTEGER DEFAULT 0;
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS reassignment_count INTEGER DEFAULT 0;
ALTER TABLE deliverer_missions ADD COLUMN IF NOT EXISTS buyer_phone_shared BOOLEAN DEFAULT FALSE;

-- Add import_assiste_products table for admin curated products
CREATE TABLE IF NOT EXISTS import_assiste_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  origin TEXT DEFAULT 'Chine',
  price INTEGER NOT NULL,
  original_price INTEGER,
  image_url TEXT,
  delivery_days TEXT DEFAULT '12-18 jours',
  min_order INTEGER DEFAULT 1,
  stock INTEGER DEFAULT 0,
  badge TEXT,
  badge_color TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  week_of DATE,
  created_by UUID REFERENCES user_profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add deposit tracking to import_requests
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS deposit_amount INTEGER DEFAULT 10000;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS deposit_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS deposit_paid_at TIMESTAMPTZ;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS final_amount INTEGER;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS final_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS devis_amount INTEGER;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS devis_note TEXT;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS devis_sent_at TIMESTAMPTZ;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS admin_notes TEXT;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS product_url TEXT;
ALTER TABLE import_requests ADD COLUMN IF NOT EXISTS product_image_url TEXT;

-- RLS policies for commissions
ALTER TABLE commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE commission_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_assiste_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin can manage commissions" ON commissions;
CREATE POLICY "Admin can manage commissions" ON commissions
  FOR ALL USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'admin'::public.user_role)
  );

DROP POLICY IF EXISTS "Sellers can view own commissions" ON commissions;
CREATE POLICY "Sellers can view own commissions" ON commissions
  FOR SELECT USING (seller_id = auth.uid());

DROP POLICY IF EXISTS "Deliverers can view own commissions" ON commissions;
CREATE POLICY "Deliverers can view own commissions" ON commissions
  FOR SELECT USING (deliverer_id = auth.uid());

DROP POLICY IF EXISTS "Anyone can view commission settings" ON commission_settings;
CREATE POLICY "Anyone can view commission settings" ON commission_settings
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Admin can manage commission settings" ON commission_settings;
CREATE POLICY "Admin can manage commission settings" ON commission_settings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'admin'::public.user_role)
  );

DROP POLICY IF EXISTS "Anyone can view active import products" ON import_assiste_products;
CREATE POLICY "Anyone can view active import products" ON import_assiste_products
  FOR SELECT USING (is_active = TRUE);

DROP POLICY IF EXISTS "Admin can manage import products" ON import_assiste_products;
CREATE POLICY "Admin can manage import products" ON import_assiste_products
  FOR ALL USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'admin'::public.user_role)
  );
