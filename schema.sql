-- =====================================================================
--  CREA — облікова / касова система для кофейні
--  Supabase (Postgres) стартова схема. ІДЕМПОТЕНТНА (можна ганяти повторно).
--  ⚠️  ЗРОБИ БЕКАП БД перед запуском на робочому проєкті.
--  Правило: тільки ДОДАВАТИ (CREATE ... IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
--  Нічого не перейменовувати й не видаляти. SQL запускати ДО деплою коду.
--  Усі гроші — numeric(10,2). branch_id скрізь. created_at timestamptz default now().
-- =====================================================================

create extension if not exists pgcrypto;   -- для gen_random_uuid()

-- ---------- ФІЛІЇ ----------
create table if not exists branches (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  address    text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- ПЕРСОНАЛ ----------
create table if not exists users (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  login      text,                          -- телефон або email
  role       text not null default 'barista',  -- owner / admin / barista
  pin        text,                          -- короткий пін для входу на касі
  branch_id  uuid references branches(id),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists users_login_uniq on users(login) where login is not null;

-- ---------- СКЛАД: ІНГРЕДІЄНТИ (сировина) ----------
create table if not exists ingredients (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  unit       text not null default 'g',     -- g / ml / pcs / kg / l
  stock      numeric(12,3) not null default 0,
  cost       numeric(10,2) not null default 0,   -- собівартість за 1 одиницю
  min_stock  numeric(12,3) not null default 0,
  category   text,
  emoji      text,
  branch_id  uuid references branches(id),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists ingredients_name_branch_uniq
  on ingredients(name, branch_id);

-- ---------- МЕНЮ: КАТЕГОРІЇ ----------
create table if not exists menu_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  sort       int  not null default 0,
  emoji      text,
  branch_id  uuid references branches(id),
  created_at timestamptz not null default now()
);
create unique index if not exists menu_categories_name_branch_uniq
  on menu_categories(name, branch_id);

-- ---------- МЕНЮ: ПОЗИЦІЇ ----------
create table if not exists menu_items (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  category_id uuid references menu_categories(id),
  price       numeric(10,2) not null default 0,   -- базова ціна (якщо без варіантів)
  photo_url   text,
  emoji       text,
  sort        int not null default 0,
  is_active   boolean not null default true,
  branch_id   uuid references branches(id),
  created_at  timestamptz not null default now()
);
create unique index if not exists menu_items_name_branch_uniq
  on menu_items(name, branch_id);

-- ---------- МЕНЮ: ВАРІАНТИ (розміри S/M/L) ----------
create table if not exists menu_variants (
  id           uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references menu_items(id) on delete cascade,
  name         text not null,                 -- S / M / L / 0.3 / 0.4 ...
  price        numeric(10,2) not null default 0,
  sort         int not null default 0
);

-- ---------- МЕНЮ: МОДИФІКАТОРИ (доп. молоко, сироп...) ----------
create table if not exists modifiers (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  price        numeric(10,2) not null default 0,
  ingredient_id uuid references ingredients(id),  -- що списувати зі складу (опц.)
  qty          numeric(12,3) not null default 0,  -- скільки одиниць інгредієнта
  branch_id    uuid references branches(id),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

-- звʼязок «яка позиція які модифікатори дозволяє»
create table if not exists menu_item_modifiers (
  menu_item_id uuid not null references menu_items(id) on delete cascade,
  modifier_id  uuid not null references modifiers(id) on delete cascade,
  primary key (menu_item_id, modifier_id)
);

-- ---------- ТЕХКАРТИ (рецепти) ----------
-- qty у одиниці інгредієнта. variant_id null = базовий рецепт (для всіх розмірів,
-- якщо для конкретного розміру немає власних рядків).
create table if not exists recipe_items (
  id            uuid primary key default gen_random_uuid(),
  menu_item_id  uuid not null references menu_items(id) on delete cascade,
  variant_id    uuid references menu_variants(id) on delete cascade,
  ingredient_id uuid not null references ingredients(id),
  qty           numeric(12,3) not null default 0
);

-- ---------- ЗМІНИ (SHIFT) ----------
create table if not exists shifts (
  id          uuid primary key default gen_random_uuid(),
  branch_id   uuid references branches(id),
  opened_by   uuid references users(id),
  opened_at   timestamptz not null default now(),
  closed_by   uuid references users(id),
  closed_at   timestamptz,
  cash_start  numeric(10,2) not null default 0,
  cash_end    numeric(10,2),
  status      text not null default 'open',   -- open / closed
  note        text
);

-- ---------- ПРОДАЖІ (шапка чека / рух грошей) ----------
create table if not exists sales (
  id             uuid primary key default gen_random_uuid(),
  branch_id      uuid references branches(id),
  shift_id       uuid references shifts(id),
  type           text not null default 'sale', -- sale/income/outcome/return/writeoff
  total          numeric(10,2) not null default 0,
  cost_total     numeric(10,2) not null default 0,   -- собівартість чека
  payment_method text,                          -- cash / card / qr
  item_name      text,                          -- як у CREAGYM (короткий опис)
  customer_id    uuid,                          -- лояльність (опц.)
  created_by     uuid references users(id),
  created_at     timestamptz not null default now()
);

-- ---------- ПОЗИЦІЇ ЧЕКА ----------
create table if not exists sale_items (
  id           uuid primary key default gen_random_uuid(),
  sale_id      uuid not null references sales(id) on delete cascade,
  menu_item_id uuid references menu_items(id),
  variant_id   uuid references menu_variants(id),
  name         text,
  qty          numeric(12,3) not null default 1,
  price        numeric(10,2) not null default 0,   -- ціна за 1 (з модифікаторами)
  cost         numeric(10,2) not null default 0,   -- собівартість за 1
  mods         jsonb                               -- обрані модифікатори
);

-- ---------- РУХ СКЛАДУ ----------
create table if not exists stock_moves (
  id            uuid primary key default gen_random_uuid(),
  branch_id     uuid references branches(id),
  ingredient_id uuid references ingredients(id),
  delta         numeric(12,3) not null default 0,   -- +прихід / -списання
  reason        text,                               -- sale/income/writeoff/inventory/return
  ref_id        uuid,
  created_at    timestamptz not null default now()
);

-- ---------- ПОСТАЧАЛЬНИКИ ----------
create table if not exists suppliers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  phone      text,
  note       text,
  branch_id  uuid references branches(id),
  created_at timestamptz not null default now()
);

-- ---------- ПРИХІД (накладна) ----------
create table if not exists deliveries (
  id          uuid primary key default gen_random_uuid(),
  branch_id   uuid references branches(id),
  supplier_id uuid references suppliers(id),
  total       numeric(10,2) not null default 0,
  note        text,
  created_by  uuid references users(id),
  created_at  timestamptz not null default now()
);
create table if not exists delivery_items (
  id            uuid primary key default gen_random_uuid(),
  delivery_id   uuid not null references deliveries(id) on delete cascade,
  ingredient_id uuid references ingredients(id),
  qty           numeric(12,3) not null default 0,
  unit_cost     numeric(10,2) not null default 0
);

-- ---------- СПИСАННЯ ----------
create table if not exists writeoffs (
  id            uuid primary key default gen_random_uuid(),
  branch_id     uuid references branches(id),
  ingredient_id uuid references ingredients(id),
  qty           numeric(12,3) not null default 0,
  cost          numeric(10,2) not null default 0,
  reason        text,                            -- бій/псування/дегустація/службове
  created_by    uuid references users(id),
  created_at    timestamptz not null default now()
);

-- ---------- КАСОВІ ОПЕРАЦІЇ (внесення/винесення) ----------
create table if not exists cash_ops (
  id         uuid primary key default gen_random_uuid(),
  branch_id  uuid references branches(id),
  shift_id   uuid references shifts(id),
  type       text not null,                    -- in / out
  category   text,                             -- Здача/Оренда/Зарплата/Інкасація...
  amount     numeric(10,2) not null default 0,
  note       text,
  created_by uuid references users(id),
  created_at timestamptz not null default now()
);

-- ---------- ЛОЯЛЬНІСТЬ ----------
create table if not exists customers (
  id         uuid primary key default gen_random_uuid(),
  phone      text,
  name       text,
  bonus      numeric(10,2) not null default 0,
  stamps     int not null default 0,
  branch_id  uuid references branches(id),
  created_at timestamptz not null default now()
);
create unique index if not exists customers_phone_branch_uniq
  on customers(phone, branch_id) where phone is not null;

-- =====================================================================
--  СТАРТОВІ ДАНІ (idempotent seed) — 1 філія + власник Нестор
-- =====================================================================
insert into branches (name, address)
select 'CREA', ''
where not exists (select 1 from branches);

insert into users (name, login, role, pin, branch_id)
select 'Нестор', 'owner', 'owner', '0000', (select id from branches order by created_at limit 1)
where not exists (select 1 from users where role = 'owner');

-- =====================================================================
--  RLS: для anon-ключа лишаємо доступ (як у CREAGYM). За потреби —
--  увімкнути RLS і політики окремо. Тут просто вимикаємо RLS-блокування.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'branches','users','ingredients','menu_categories','menu_items','menu_variants',
    'modifiers','menu_item_modifiers','recipe_items','shifts','sales','sale_items',
    'stock_moves','suppliers','deliveries','delivery_items','writeoffs','cash_ops','customers'
  ] loop
    execute format('alter table %I disable row level security', t);
  end loop;
end $$;
