-- ============================================================
-- ASOUKAA STORAGE BUCKETS MIGRATION
-- ============================================================

-- Product images bucket (public)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-images',
    'product-images',
    true,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
) ON CONFLICT (id) DO NOTHING;

-- Shop logos bucket (public)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'shop-logos',
    'shop-logos',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
) ON CONFLICT (id) DO NOTHING;

-- Delivery proofs bucket (public)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'delivery-proofs',
    'delivery-proofs',
    true,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
) ON CONFLICT (id) DO NOTHING;

-- ── RLS Policies: product-images ──────────────────────────────────────────

CREATE POLICY "public_read_product_images" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'product-images');

CREATE POLICY "authenticated_upload_product_images" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'product-images');

CREATE POLICY "owners_delete_product_images" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'product-images' AND owner = auth.uid());

-- ── RLS Policies: shop-logos ──────────────────────────────────────────────

CREATE POLICY "public_read_shop_logos" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'shop-logos');

CREATE POLICY "authenticated_upload_shop_logos" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'shop-logos');

CREATE POLICY "owners_delete_shop_logos" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'shop-logos' AND owner = auth.uid());

-- ── RLS Policies: delivery-proofs ─────────────────────────────────────────

CREATE POLICY "public_read_delivery_proofs" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'delivery-proofs');

CREATE POLICY "authenticated_upload_delivery_proofs" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'delivery-proofs');

CREATE POLICY "owners_delete_delivery_proofs" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'delivery-proofs' AND owner = auth.uid());
