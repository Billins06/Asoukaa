-- Migration: Add sold_count, visitor_count, is_blocked, withdrawals_blocked columns
-- and seed products from asoukaa.com

-- Add sold_count to products if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'sold_count'
  ) THEN
    ALTER TABLE public.products ADD COLUMN sold_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Add is_blocked to user_profiles if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'is_blocked'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN is_blocked BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Add withdrawals_blocked to user_profiles if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'withdrawals_blocked'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN withdrawals_blocked BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Add last_seen to user_profiles if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'last_seen'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN last_seen TIMESTAMPTZ DEFAULT NOW();
  END IF;
END $$;

-- Add visitor_count to shops if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shops' AND column_name = 'visitor_count'
  ) THEN
    ALTER TABLE public.shops ADD COLUMN visitor_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Add is_delivered to messages if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'is_delivered'
  ) THEN
    ALTER TABLE public.messages ADD COLUMN is_delivered BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Add created_by_admin to orders if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'created_by_admin'
  ) THEN
    ALTER TABLE public.orders ADD COLUMN created_by_admin BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Seed products from asoukaa.com (selection of products with rewritten descriptions)
-- Only insert if no products exist yet
DO $$
DECLARE
  shop_id UUID;
  seller_id UUID;
BEGIN
  -- Get first available shop
  SELECT id, owner_id INTO shop_id, seller_id FROM public.shops LIMIT 1;
  
  IF shop_id IS NOT NULL THEN
    -- Insert products only if fewer than 5 exist
    IF (SELECT COUNT(*) FROM public.products) < 5 THEN
      
      INSERT INTO public.products (name, description, price, original_price, category, images, stock_quantity, is_active, is_featured, rating, sold_count, shop_id, seller_id)
      VALUES
      (
        'Tissu Wax Ankara Premium 6 Yards',
        'Plongez dans l''authenticité africaine avec ce tissu Wax Ankara 100% coton de qualité supérieure. Ses motifs géométriques exclusifs aux couleurs vives et résistantes sublimeront vos tenues traditionnelles et modernes. Idéal pour confectionner boubous, robes, pagnes ou accessoires. Chaque mètre est un chef-d''œuvre artisanal qui raconte l''histoire de l''Afrique.',
        18500,
        32000,
        'Mode',
        ARRAY['https://img.rocket.new/generatedImages/rocket_gen_img_1c0579dd1-1773189871928.png'],
        50,
        TRUE,
        TRUE,
        4.8,
        127,
        shop_id,
        seller_id
      ),
      (
        'Smartphone Infinix Hot 40 Pro 256Go',
        'Libérez votre potentiel avec l''Infinix Hot 40 Pro — le smartphone qui allie performance et élégance à prix accessible. Son processeur octa-core, son écran AMOLED 6.78" et sa batterie 5000mAh vous accompagnent toute la journée. La caméra 108MP capture chaque moment avec une précision époustouflante. Idéal pour les professionnels et les créateurs de contenu.',
        89000,
        115000,
        'Électronique',
        ARRAY['https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=600'],
        15,
        TRUE,
        TRUE,
        4.6,
        43,
        shop_id,
        seller_id
      ),
      (
        'Huile de Karité Pure Bio 500ml',
        'Découvrez le secret de beauté des femmes africaines : notre huile de karité 100% pure et naturelle, extraite à froid selon les méthodes traditionnelles du Bénin. Hydratante, nourrissante et réparatrice, elle transforme votre peau, vos cheveux et vos ongles en quelques applications. Sans additifs, sans conservateurs — juste la nature à l''état pur.',
        7500,
        12000,
        'Beauté',
        ARRAY['https://images.unsplash.com/photo-1608248543803-ba4f8c70ae0b?w=600'],
        200,
        TRUE,
        FALSE,
        4.9,
        312,
        shop_id,
        seller_id
      ),
      (
        'Sac à Main Cuir Artisanal Femme',
        'Affirmez votre style avec ce sac à main en cuir véritable, confectionné à la main par nos artisans béninois. Sa structure robuste, ses finitions soignées et sa capacité généreuse en font le compagnon idéal pour le bureau, les sorties et les voyages. Disponible en marron, noir et camel — un investissement mode qui dure des années.',
        25000,
        40000,
        'Mode',
        ARRAY['https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=600'],
        30,
        TRUE,
        FALSE,
        4.7,
        89,
        shop_id,
        seller_id
      ),
      (
        'Ventilateur Colonne 45W Silencieux',
        'Combattez la chaleur béninoise avec ce ventilateur colonne ultra-silencieux 45W. Ses 3 vitesses réglables, son oscillation automatique 90° et sa minuterie programmable jusqu''à 8h en font l''allié parfait de vos nuits et journées. Design élégant, faible consommation électrique et télécommande incluse. Livraison rapide à Cotonou et environs.',
        35000,
        48000,
        'Maison',
        ARRAY['https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=600'],
        25,
        TRUE,
        FALSE,
        4.5,
        67,
        shop_id,
        seller_id
      ),
      (
        'Ensemble Boubou Brodé Homme',
        'Élégance et tradition réunies dans cet ensemble boubou brodé pour homme. Confectionné en bazin riche de qualité supérieure, il est orné de broderies dorées réalisées à la main par nos maîtres artisans. Parfait pour les cérémonies, mariages et occasions spéciales. Disponible en blanc, bleu royal et vert émeraude. Tailles S à XXL.',
        45000,
        65000,
        'Mode',
        ARRAY['https://img.rocket.new/generatedImages/rocket_gen_img_16499f8fc-1768476848602.png'],
        20,
        TRUE,
        TRUE,
        4.8,
        156,
        shop_id,
        seller_id
      ),
      (
        'Casque Bluetooth JBL Tune 520BT',
        'Immergez-vous dans votre musique avec le JBL Tune 520BT. Son son JBL Pure Bass, ses 57h d''autonomie et sa connexion Bluetooth 5.3 stable vous offrent une expérience audio sans compromis. Léger, pliable et confortable pour des heures d''écoute. Compatible iOS et Android. Le choix des mélomanes exigeants à Cotonou.',
        42000,
        58000,
        'Électronique',
        ARRAY['https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600'],
        18,
        TRUE,
        FALSE,
        4.7,
        78,
        shop_id,
        seller_id
      ),
      (
        'Savon Noir Africain Naturel 200g',
        'Le savon noir africain, trésor ancestral de beauté, est enfin disponible en version premium. Enrichi en huile de palme, karité et cendres végétales, il nettoie en profondeur, exfolie doucement et illumine le teint. Convient à tous types de peau, même les plus sensibles. Fabriqué artisanalement au Bénin selon une recette transmise de génération en génération.',
        3500,
        5500,
        'Beauté',
        ARRAY['https://images.unsplash.com/photo-1607006344380-b6775a0824a7?w=600'],
        500,
        TRUE,
        FALSE,
        4.8,
        445,
        shop_id,
        seller_id
      ),
      (
        'Chaussures Cuir Oxford Homme',
        'Marchez avec assurance dans ces chaussures Oxford en cuir véritable, fabriquées à la main par nos cordonniers béninois. Leur semelle antidérapante, leur doublure respirante et leur coupe classique en font le choix parfait pour le bureau et les occasions formelles. Disponibles du 40 au 46. Un savoir-faire local qui rivalise avec les grandes marques.',
        28000,
        42000,
        'Mode',
        ARRAY['https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=600'],
        35,
        TRUE,
        FALSE,
        4.6,
        92,
        shop_id,
        seller_id
      ),
      (
        'Mixeur Blender Multifonction 1000W',
        'Préparez smoothies, sauces, soupes et jus en quelques secondes avec ce blender professionnel 1000W. Ses 6 lames en acier inoxydable, son bol en verre borosilicate 1.5L et ses 5 vitesses réglables s''adaptent à toutes vos recettes. Moteur silencieux, facile à nettoyer et garantie 2 ans. Le must-have de votre cuisine béninoise.',
        32000,
        45000,
        'Maison',
        ARRAY['https://images.unsplash.com/photo-1570222094114-d054a817e56b?w=600'],
        40,
        TRUE,
        FALSE,
        4.5,
        134,
        shop_id,
        seller_id
      )
      ON CONFLICT DO NOTHING;
      
    END IF;
  END IF;
END $$;
