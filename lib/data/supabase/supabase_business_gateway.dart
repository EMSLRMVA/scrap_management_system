import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBusinessGateway {
  SupabaseBusinessGateway({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;

  final SupabaseClient client;

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const schemaSql = '''
create extension if not exists pgcrypto;

create table users (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mobile text unique,
  role text not null check (role in ('owner','supervisor','manager','accountant','admin','developer')),
  pin_hash text,
  is_blocked boolean not null default false,
  privacy_consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into users (name, mobile, role)
values ('Radha Rajput', '+919566092123', 'owner')
on conflict (mobile) do update set name = excluded.name, role = excluded.role;

create table supervisors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete set null,
  name text not null,
  mobile text,
  area text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table sellers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mobile text not null,
  area text,
  pending_amount numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mobile text not null,
  area text,
  pending_amount numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table inventory (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'General',
  available_kg numeric not null default 0 check (available_kg >= 0),
  current_buying_rate numeric not null default 0 check (current_buying_rate >= 0),
  current_selling_rate numeric not null default 0 check (current_selling_rate >= 0),
  min_rate numeric not null default 0 check (min_rate >= 0),
  max_rate numeric not null default 0 check (max_rate >= 0),
  is_active boolean not null default true,
  is_deleted boolean not null default false,
  created_by uuid references users(id) on delete set null,
  updated_by uuid references users(id) on delete set null,
  deleted_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz
);

create table purchases (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  seller_id uuid references sellers(id),
  material_id uuid references inventory(id),
  supervisor_id uuid references supervisors(id) on delete set null,
  weight_kg numeric not null check (weight_kg > 0),
  rate numeric not null check (rate > 0),
  paid_amount numeric not null default 0 check (paid_amount >= 0),
  remarks text,
  is_deleted boolean not null default false,
  created_by uuid references users(id) on delete set null,
  updated_by uuid references users(id) on delete set null,
  deleted_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz
);

create table sales (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  customer_id uuid references customers(id),
  material_id uuid references inventory(id),
  weight_kg numeric not null check (weight_kg > 0),
  rate numeric not null check (rate > 0),
  received_amount numeric not null default 0 check (received_amount >= 0),
  remarks text,
  is_deleted boolean not null default false,
  created_by uuid references users(id) on delete set null,
  updated_by uuid references users(id) on delete set null,
  deleted_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz
);

create table cash_allocations (
  id uuid primary key default gen_random_uuid(),
  allocation_date date not null,
  supervisor_id uuid references supervisors(id) on delete restrict,
  supervisor_name text not null,
  amount numeric not null check (amount > 0),
  payment_mode text not null check (payment_mode in ('Cash','UPI','Bank','Other')),
  remarks text,
  added_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null,
  supervisor_id uuid references supervisors(id) on delete set null,
  category text not null check (category in ('Scrap Purchase','Other Purchase','Transport Expense','Loading Expense','Miscellaneous Expense','Inventory Purchase','Inventory Adjustment')),
  amount numeric not null check (amount > 0),
  vendor_name text,
  remarks text,
  bill_upload_path text,
  photo_upload_path text,
  is_approved boolean not null default false,
  is_deleted boolean not null default false,
  added_by uuid references users(id) on delete set null,
  updated_by uuid references users(id) on delete set null,
  deleted_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz
);

create table inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  inventory_id uuid not null references inventory(id) on delete cascade,
  adjustment_date date not null,
  previous_kg numeric not null,
  new_kg numeric not null check (new_kg >= 0),
  reason text not null,
  created_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete set null,
  user_name text not null,
  action text not null,
  record_type text not null,
  record_id text not null,
  previous_value jsonb,
  new_value jsonb,
  device_name text,
  created_at timestamptz not null default now()
);

create table login_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete set null,
  mobile text,
  device_name text,
  app_version text,
  login_time timestamptz not null default now(),
  logout_time timestamptz,
  last_active_time timestamptz,
  success boolean not null default true,
  failure_reason text
);

create table device_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  device_name text not null,
  device_id text,
  app_version text,
  is_blocked boolean not null default false,
  first_seen_at timestamptz not null default now(),
  last_active_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  role text,
  title text not null,
  body text not null,
  type text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace view balance_summary as
select
  s.id as supervisor_id,
  s.name as supervisor_name,
  coalesce(sum(distinct ca.amount), 0) as total_cash_allocated,
  coalesce(sum(e.amount) filter (where e.is_deleted = false), 0) as total_expense,
  coalesce(sum(e.amount) filter (where e.category = 'Scrap Purchase' and e.is_deleted = false), 0) as total_scrap_purchase,
  coalesce(sum(e.amount) filter (where e.category = 'Other Purchase' and e.is_deleted = false), 0) as total_other_purchase,
  coalesce(sum(p.weight_kg * p.rate) filter (where p.is_deleted = false), 0) as total_inventory_purchase,
  coalesce(sum(e.amount) filter (where e.category = 'Inventory Adjustment' and e.is_deleted = false), 0) as total_adjustment,
  coalesce(sum(distinct ca.amount), 0)
    - coalesce(sum(e.amount) filter (where e.is_deleted = false), 0)
    - coalesce(sum(p.weight_kg * p.rate) filter (where p.is_deleted = false), 0)
    - coalesce(sum(e.amount) filter (where e.category = 'Inventory Adjustment' and e.is_deleted = false), 0) as remaining_balance
from supervisors s
left join cash_allocations ca on ca.supervisor_id = s.id
left join expenses e on e.supervisor_id = s.id
left join purchases p on p.supervisor_id = s.id
group by s.id, s.name;

create index idx_cash_allocations_supervisor_date on cash_allocations(supervisor_id, allocation_date);
create index idx_expenses_supervisor_date on expenses(supervisor_id, expense_date) where is_deleted = false;
create index idx_inventory_active on inventory(is_active, is_deleted);
create index idx_purchases_supervisor_date on purchases(supervisor_id, created_at) where is_deleted = false;
create index idx_audit_logs_record on audit_logs(record_type, record_id, created_at desc);
create index idx_login_history_mobile on login_history(mobile, login_time desc);
create index idx_notifications_user_read on notifications(user_id, is_read, created_at desc);
''';
}
