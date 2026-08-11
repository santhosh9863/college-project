-- Phase 1.2 — Database Foundation
-- Migration 12: ai_classification_log
-- classification:    { "category": "...", "confidence": 0.0, "reasoning": "..." }
-- priority_prediction: { "priority": "...", "confidence": 0.0 }
-- duplicate_check:   { "is_duplicate": false, "similar_report_id": null, "similarity_score": 0.0 }

create table public.ai_classification_log (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  raw_input text not null,
  classification jsonb not null,
  priority_prediction jsonb not null,
  duplicate_check jsonb not null,
  model_version text not null,
  created_at timestamptz not null default now()
);
