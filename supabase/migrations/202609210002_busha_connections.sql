create table if not exists public.busha_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  secret_cipher text not null,
  secret_iv text not null,
  updated_at timestamptz not null default now()
);

alter table public.busha_connections enable row level security;

drop policy if exists "Users can manage their own Busha connection" on public.busha_connections;
create policy "Users can manage their own Busha connection"
on public.busha_connections for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop table if exists public.bybit_connections;