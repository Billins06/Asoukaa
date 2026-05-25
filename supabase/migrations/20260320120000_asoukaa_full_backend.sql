-- ============================================================
-- ASOUKAA FULL BACKEND MIGRATION
-- ============================================================

-- ── 1. ENUM TYPES ─────────────────────────────────────────────────────────

DROP TYPE IF EXISTS public.user_role CASCADE;
CREATE TYPE public.user_role AS ENUM ('acheteur', 'vendeur', 'livreur');

DROP TYPE IF EXISTS public.order_status CASCADE;
CREATE TYPE public.order_status AS ENUM ('en_attente', 'confirme', 'en_preparation', 'expedie', 'en_livraison', 'livre', 'annule', 'rembourse');

DROP TYPE IF EXISTS public.mission_status CASCADE;
CREATE TYPE public.mission_status AS ENUM ('disponible', 'accepte', 'en_cours', 'livre', 'annule');

DROP TYPE IF EXISTS public.message_type CASCADE;
CREATE TYPE public.message_type AS ENUM ('text', 'product_attachment', 'system');

DROP TYPE IF EXISTS public.notification_type CASCADE;
CREATE TYPE public.notification_type AS ENUM ('commande', 'message', 'promo', 'livraison', 'systeme');

-- ── 2. CORE TABLES ────────────────────────────────────────────────────────

-- User profiles (linked to auth.users via trigger)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL DEFAULT '',
    phone TEXT DEFAULT '',
    avatar_url TEXT DEFAULT '',
    role public.user_role NOT NULL DEFAULT 'acheteur',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Shops (for sellers)
CREATE TABLE IF NOT EXISTS public.shops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    category TEXT DEFAULT '',
    logo_url TEXT DEFAULT '',
    banner_url TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    address TEXT DEFAULT '',
    city TEXT DEFAULT '',
    country TEXT DEFAULT 'Sénégal',
    ninea TEXT DEFAULT '',
    is_verified BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    rating NUMERIC(3,2) DEFAULT 0,
    total_sales INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Products
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    category TEXT DEFAULT '',
    price NUMERIC(12,2) NOT NULL DEFAULT 0,
    original_price NUMERIC(12,2) DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'FCFA',
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    images JSONB DEFAULT '[]'::jsonb,
    videos JSONB DEFAULT '[]'::jsonb,
    price_tiers JSONB DEFAULT '[]'::jsonb,
    tags JSONB DEFAULT '[]'::jsonb,
    weight NUMERIC(8,3) DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    rating NUMERIC(3,2) DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES public.shops(id) ON DELETE SET NULL,
    order_number TEXT NOT NULL UNIQUE,
    status public.order_status NOT NULL DEFAULT 'en_attente',
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
    delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
    discount NUMERIC(12,2) NOT NULL DEFAULT 0,
    total NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'FCFA',
    payment_method TEXT DEFAULT '',
    payment_status TEXT DEFAULT 'en_attente',
    delivery_address JSONB DEFAULT '{}'::jsonb,
    notes TEXT DEFAULT '',
    estimated_delivery TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cart items
CREATE TABLE IF NOT EXISTS public.cart_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Favorites
CREATE TABLE IF NOT EXISTS public.favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Conversations (chat)
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    last_message TEXT DEFAULT '',
    last_message_at TIMESTAMPTZ DEFAULT now(),
    buyer_unread INTEGER NOT NULL DEFAULT 0,
    seller_unread INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Messages
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL DEFAULT '',
    message_type public.message_type NOT NULL DEFAULT 'text',
    product_data JSONB DEFAULT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    notification_type public.notification_type NOT NULL DEFAULT 'systeme',
    is_read BOOLEAN NOT NULL DEFAULT false,
    data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Deliverer missions
CREATE TABLE IF NOT EXISTS public.deliverer_missions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deliverer_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    status public.mission_status NOT NULL DEFAULT 'disponible',
    pickup_address JSONB DEFAULT '{}'::jsonb,
    delivery_address JSONB DEFAULT '{}'::jsonb,
    distance_km NUMERIC(8,2) DEFAULT 0,
    earnings NUMERIC(12,2) DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'FCFA',
    proof_photo_url TEXT DEFAULT '',
    proof_signature TEXT DEFAULT '',
    notes TEXT DEFAULT '',
    accepted_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Product reviews
CREATE TABLE IF NOT EXISTS public.reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 3. INDEXES ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_user_profiles_role ON public.user_profiles(role);
CREATE INDEX IF NOT EXISTS idx_shops_owner_id ON public.shops(owner_id);
CREATE INDEX IF NOT EXISTS idx_shops_category ON public.shops(category);
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON public.products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_seller_id ON public.products(seller_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON public.products(is_active);
CREATE INDEX IF NOT EXISTS idx_orders_buyer_id ON public.orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_orders_shop_id ON public.orders(shop_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_favorites_user_id ON public.favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_buyer_id ON public.conversations(buyer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_seller_id ON public.conversations(seller_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_deliverer_missions_deliverer_id ON public.deliverer_missions(deliverer_id);
CREATE INDEX IF NOT EXISTS idx_deliverer_missions_status ON public.deliverer_missions(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cart_items_unique ON public.cart_items(user_id, product_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_unique ON public.favorites(user_id, product_id);

-- ── 4. FUNCTIONS ──────────────────────────────────────────────────────────

-- Auto-create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_profiles (id, email, full_name, phone, avatar_url, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'phone', ''),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
        COALESCE(NEW.raw_user_meta_data->>'role', 'acheteur')::public.user_role
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Auto-create shop when seller registers
CREATE OR REPLACE FUNCTION public.handle_new_seller()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.role = 'vendeur' AND OLD.role IS DISTINCT FROM 'vendeur' THEN
        INSERT INTO public.shops (owner_id, name, description, category)
        VALUES (
            NEW.id,
            COALESCE(NEW.full_name || '''s Shop', 'Ma Boutique'),
            '',
            'Autres'
        )
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

-- Update conversation last message
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.conversations
    SET
        last_message = NEW.content,
        last_message_at = NEW.created_at,
        buyer_unread = CASE
            WHEN (SELECT seller_id FROM public.conversations WHERE id = NEW.conversation_id) = NEW.sender_id
            THEN buyer_unread + 1
            ELSE buyer_unread
        END,
        seller_unread = CASE
            WHEN (SELECT buyer_id FROM public.conversations WHERE id = NEW.conversation_id) = NEW.sender_id
            THEN seller_unread + 1
            ELSE seller_unread
        END
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$;

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Role helper (reads from auth metadata to avoid recursion)
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT COALESCE(raw_user_meta_data->>'role', 'acheteur')
    FROM auth.users
    WHERE id = auth.uid();
$$;

-- ── 5. ENABLE RLS ─────────────────────────────────────────────────────────

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliverer_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- ── 6. RLS POLICIES ───────────────────────────────────────────────────────

-- user_profiles
DROP POLICY IF EXISTS "users_manage_own_profile" ON public.user_profiles;
CREATE POLICY "users_manage_own_profile"
ON public.user_profiles FOR ALL TO authenticated
USING (id = auth.uid()) WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "users_view_any_profile" ON public.user_profiles;
CREATE POLICY "users_view_any_profile"
ON public.user_profiles FOR SELECT TO authenticated
USING (true);

-- shops
DROP POLICY IF EXISTS "public_read_shops" ON public.shops;
CREATE POLICY "public_read_shops"
ON public.shops FOR SELECT TO public
USING (is_active = true);

DROP POLICY IF EXISTS "sellers_manage_own_shop" ON public.shops;
CREATE POLICY "sellers_manage_own_shop"
ON public.shops FOR ALL TO authenticated
USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

-- products
DROP POLICY IF EXISTS "public_read_products" ON public.products;
CREATE POLICY "public_read_products"
ON public.products FOR SELECT TO public
USING (is_active = true);

DROP POLICY IF EXISTS "sellers_manage_own_products" ON public.products;
CREATE POLICY "sellers_manage_own_products"
ON public.products FOR ALL TO authenticated
USING (seller_id = auth.uid()) WITH CHECK (seller_id = auth.uid());

-- orders
DROP POLICY IF EXISTS "buyers_manage_own_orders" ON public.orders;
CREATE POLICY "buyers_manage_own_orders"
ON public.orders FOR ALL TO authenticated
USING (buyer_id = auth.uid()) WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "sellers_view_shop_orders" ON public.orders;
CREATE POLICY "sellers_view_shop_orders"
ON public.orders FOR SELECT TO authenticated
USING (
    shop_id IN (
        SELECT id FROM public.shops WHERE owner_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "deliverers_view_missions_orders" ON public.orders;
CREATE POLICY "deliverers_view_missions_orders"
ON public.orders FOR SELECT TO authenticated
USING (
    id IN (
        SELECT order_id FROM public.deliverer_missions WHERE deliverer_id = auth.uid()
    )
);

-- cart_items
DROP POLICY IF EXISTS "users_manage_own_cart" ON public.cart_items;
CREATE POLICY "users_manage_own_cart"
ON public.cart_items FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- favorites
DROP POLICY IF EXISTS "users_manage_own_favorites" ON public.favorites;
CREATE POLICY "users_manage_own_favorites"
ON public.favorites FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- conversations
DROP POLICY IF EXISTS "participants_access_conversations" ON public.conversations;
CREATE POLICY "participants_access_conversations"
ON public.conversations FOR ALL TO authenticated
USING (buyer_id = auth.uid() OR seller_id = auth.uid())
WITH CHECK (buyer_id = auth.uid() OR seller_id = auth.uid());

-- messages
DROP POLICY IF EXISTS "participants_access_messages" ON public.messages;
CREATE POLICY "participants_access_messages"
ON public.messages FOR SELECT TO authenticated
USING (
    conversation_id IN (
        SELECT id FROM public.conversations
        WHERE buyer_id = auth.uid() OR seller_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "sender_insert_messages" ON public.messages;
CREATE POLICY "sender_insert_messages"
ON public.messages FOR INSERT TO authenticated
WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "sender_update_messages" ON public.messages;
CREATE POLICY "sender_update_messages"
ON public.messages FOR UPDATE TO authenticated
USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid());

-- notifications
DROP POLICY IF EXISTS "users_manage_own_notifications" ON public.notifications;
CREATE POLICY "users_manage_own_notifications"
ON public.notifications FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- deliverer_missions
DROP POLICY IF EXISTS "public_view_available_missions" ON public.deliverer_missions;
CREATE POLICY "public_view_available_missions"
ON public.deliverer_missions FOR SELECT TO authenticated
USING (status = 'disponible' OR deliverer_id = auth.uid());

DROP POLICY IF EXISTS "deliverers_manage_own_missions" ON public.deliverer_missions;
CREATE POLICY "deliverers_manage_own_missions"
ON public.deliverer_missions FOR UPDATE TO authenticated
USING (deliverer_id = auth.uid() OR deliverer_id IS NULL)
WITH CHECK (deliverer_id = auth.uid());

-- reviews
DROP POLICY IF EXISTS "public_read_reviews" ON public.reviews;
CREATE POLICY "public_read_reviews"
ON public.reviews FOR SELECT TO public
USING (true);

DROP POLICY IF EXISTS "buyers_manage_own_reviews" ON public.reviews;
CREATE POLICY "buyers_manage_own_reviews"
ON public.reviews FOR ALL TO authenticated
USING (reviewer_id = auth.uid()) WITH CHECK (reviewer_id = auth.uid());

-- ── 7. TRIGGERS ───────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS on_seller_role_set ON public.user_profiles;
CREATE TRIGGER on_seller_role_set
    AFTER UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_seller();

DROP TRIGGER IF EXISTS on_message_inserted ON public.messages;
CREATE TRIGGER on_message_inserted
    AFTER INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.update_conversation_on_message();

DROP TRIGGER IF EXISTS set_updated_at_user_profiles ON public.user_profiles;
CREATE TRIGGER set_updated_at_user_profiles
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_shops ON public.shops;
CREATE TRIGGER set_updated_at_shops
    BEFORE UPDATE ON public.shops
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_products ON public.products;
CREATE TRIGGER set_updated_at_products
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_orders ON public.orders;
CREATE TRIGGER set_updated_at_orders
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 8. MOCK DATA ──────────────────────────────────────────────────────────

DO $$
DECLARE
    buyer_uuid UUID := gen_random_uuid();
    seller_uuid UUID := gen_random_uuid();
    deliverer_uuid UUID := gen_random_uuid();
    shop_uuid UUID := gen_random_uuid();
    product1_uuid UUID := gen_random_uuid();
    product2_uuid UUID := gen_random_uuid();
    product3_uuid UUID := gen_random_uuid();
    order1_uuid UUID := gen_random_uuid();
    conv_uuid UUID := gen_random_uuid();
BEGIN
    -- Create demo auth users (trigger creates user_profiles automatically)
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
        is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
        recovery_token, recovery_sent_at, email_change_token_new, email_change,
        email_change_sent_at, email_change_token_current, email_change_confirm_status,
        reauthentication_token, reauthentication_sent_at, phone, phone_change,
        phone_change_token, phone_change_sent_at
    ) VALUES
        (buyer_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'acheteur@asoukaa.com', crypt('Demo1234!', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('full_name', 'Aminata Konaté', 'role', 'acheteur', 'phone', '+221 77 123 4567'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (seller_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'vendeur@asoukaa.com', crypt('Demo1234!', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('full_name', 'Moussa Diallo', 'role', 'vendeur', 'phone', '+221 76 987 6543'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (deliverer_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'livreur@asoukaa.com', crypt('Demo1234!', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('full_name', 'Ibrahim Sow', 'role', 'livreur', 'phone', '+221 78 555 0000'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null)
    ON CONFLICT (id) DO NOTHING;

    -- Create shop for seller
    INSERT INTO public.shops (id, owner_id, name, description, category, is_verified, rating, total_sales)
    VALUES (
        shop_uuid, seller_uuid,
        'Maison Diallo Tissus',
        'Spécialiste des tissus africains wax, bazin et bogolan depuis 2010',
        'Mode & Vêtements',
        true, 4.7, 342
    )
    ON CONFLICT (id) DO NOTHING;

    -- Create products
    INSERT INTO public.products (id, shop_id, seller_id, name, description, category, price, original_price, stock_quantity, images, is_featured, rating, review_count)
    VALUES
        (product1_uuid, shop_uuid, seller_uuid,
         'Tissu Wax Hollandais 6 yards',
         'Tissu wax hollandais authentique, motifs géométriques colorés, idéal pour confection boubou et robe',
         'Mode & Vêtements', 18500, 32000, 45,
         jsonb_build_array('https://images.pexels.com/photos/6311392/pexels-photo-6311392.jpeg?auto=compress&cs=tinysrgb&w=400'),
         true, 4.8, 127),
        (product2_uuid, shop_uuid, seller_uuid,
         'Boubou Brodé Homme Taille L',
         'Boubou traditionnel en bazin riche, broderies artisanales dorées, taille L',
         'Mode & Vêtements', 45000, 45000, 12,
         jsonb_build_array('https://images.pexels.com/photos/1464625/pexels-photo-1464625.jpeg?auto=compress&cs=tinysrgb&w=400'),
         false, 4.6, 43),
        (product3_uuid, shop_uuid, seller_uuid,
         'Sac en Cuir Tressé Artisanal',
         'Sac à main artisanal en cuir véritable tressé à la main, finitions soignées',
         'Maroquinerie', 28000, 35000, 8,
         jsonb_build_array('https://images.pexels.com/photos/1152077/pexels-photo-1152077.jpeg?auto=compress&cs=tinysrgb&w=400'),
         true, 4.9, 89)
    ON CONFLICT (id) DO NOTHING;

    -- Create a sample order
    INSERT INTO public.orders (id, buyer_id, shop_id, order_number, status, items, subtotal, delivery_fee, total, payment_method, payment_status, delivery_address)
    VALUES (
        order1_uuid, buyer_uuid, shop_uuid,
        'ASK-2026-0001',
        'en_livraison',
        jsonb_build_array(
            jsonb_build_object('product_id', product1_uuid, 'name', 'Tissu Wax Hollandais 6 yards', 'price', 18500, 'quantity', 2, 'image_url', 'https://images.pexels.com/photos/6311392/pexels-photo-6311392.jpeg?auto=compress&cs=tinysrgb&w=400')
        ),
        37000, 2500, 39500,
        'orange_money', 'paye',
        jsonb_build_object('street', 'Rue 42, Badalabougou', 'city', 'Bamako', 'country', 'Mali', 'phone', '+221 77 123 4567')
    )
    ON CONFLICT (id) DO NOTHING;

    -- Create a deliverer mission for the order
    INSERT INTO public.deliverer_missions (order_id, deliverer_id, status, pickup_address, delivery_address, distance_km, earnings)
    VALUES (
        order1_uuid, deliverer_uuid,
        'en_cours',
        jsonb_build_object('street', 'Marché Sandaga', 'city', 'Dakar'),
        jsonb_build_object('street', 'Rue 42, Badalabougou', 'city', 'Bamako'),
        3.2, 1500
    )
    ON CONFLICT DO NOTHING;

    -- Create a conversation between buyer and seller
    INSERT INTO public.conversations (id, buyer_id, seller_id, product_id, last_message, last_message_at, seller_unread)
    VALUES (
        conv_uuid, buyer_uuid, seller_uuid, product1_uuid,
        'Bonjour ! Je suis intéressé par votre tissu wax.',
        now() - interval '5 minutes',
        1
    )
    ON CONFLICT (id) DO NOTHING;

    -- Create messages in the conversation
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, is_read)
    VALUES
        (conv_uuid, buyer_uuid, 'Bonjour ! Je suis intéressé par votre tissu wax.', 'text', true),
        (conv_uuid, seller_uuid, 'Bonjour ! Oui, il est encore disponible. Livraison sous 48h à Dakar.', 'text', true),
        (conv_uuid, buyer_uuid, 'Parfait, je vais commander. Merci !', 'text', false)
    ON CONFLICT DO NOTHING;

    -- Create notifications for buyer
    INSERT INTO public.notifications (user_id, title, body, notification_type, is_read)
    VALUES
        (buyer_uuid, 'Commande expédiée', 'Votre commande ASK-2026-0001 est en cours de livraison', 'livraison', false),
        (buyer_uuid, 'Nouveau message', 'Moussa Diallo vous a répondu', 'message', false),
        (buyer_uuid, 'Offre spéciale', 'Profitez de -20% sur les tissus wax ce weekend !', 'promo', true)
    ON CONFLICT DO NOTHING;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Mock data insertion failed: %', SQLERRM;
END $$;
