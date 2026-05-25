-- Migration: Add account approval, identity verification, and product approval columns
-- Safe to run multiple times (idempotent)

-- Add account_status to user_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'account_status'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN account_status TEXT DEFAULT 'pending';
  END IF;
END $$;

-- Add rejection_reason to user_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'rejection_reason'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN rejection_reason TEXT;
  END IF;
END $$;

-- Add verification_status to user_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'verification_status'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN verification_status TEXT DEFAULT 'pending';
  END IF;
END $$;

-- Add is_verified to user_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- Add id_card_url to user_profiles (for identity verification)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'id_card_url'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN id_card_url TEXT;
  END IF;
END $$;

-- Add business_reg_url to user_profiles (registre de commerce)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'business_reg_url'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN business_reg_url TEXT;
  END IF;
END $$;

-- Add verification_rejection_reason to user_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'verification_rejection_reason'
  ) THEN
    ALTER TABLE public.user_profiles ADD COLUMN verification_rejection_reason TEXT;
  END IF;
END $$;

-- Add approval_status to products
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'approval_status'
  ) THEN
    ALTER TABLE public.products ADD COLUMN approval_status TEXT DEFAULT 'pending';
  END IF;
END $$;

-- Add rejection_reason to products
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'rejection_reason'
  ) THEN
    ALTER TABLE public.products ADD COLUMN rejection_reason TEXT;
  END IF;
END $$;

-- Set existing active products as approved
UPDATE public.products SET approval_status = 'approved' WHERE is_active = TRUE AND approval_status = 'pending';
