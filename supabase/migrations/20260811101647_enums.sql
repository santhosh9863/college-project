-- Phase 1.2 — Database Foundation
-- Migration 1: Enums

-- 1. user_role
create type user_role as enum (
  'student',
  'hod',
  'technician',
  'operations',
  'admin'
);

-- 2. report_type
create type report_type as enum (
  'community',
  'private'
);

-- 3. report_status
create type report_status as enum (
  'pending',
  'under_review',
  'in_progress',
  'resolved',
  'rejected',
  'closed'
);

-- 4. priority
create type priority as enum (
  'low',
  'medium',
  'high'
);
