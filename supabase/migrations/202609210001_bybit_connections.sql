create table if not exists public.bybit_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  api_key text not null,
  secret_cipher text not null,
  secret_iv text not null,
  updated_at timestamptz not null default now()
);
alter table public.bybit_connections enable row level security;
create policy "Users can manage their own Bybit connection"
on public.bybit_connections for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);