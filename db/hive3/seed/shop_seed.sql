-- shop 库测试数据 (Hive 3.1.3, MR local mode, 容器时区 UTC)
--
-- 用法:
--   docker cp db/hive3/seed/shop_seed.sql hiveserver3:/tmp/shop_seed.sql
--   docker exec hiveserver3 beeline --silent -u jdbc:hive2://localhost:10000/shop \
--       -n hive -p hive123 -f /tmp/shop_seed.sql
--
-- 日期窗口: 2026-09-16 ~ 2026-10-16 (31 天)
-- 规模: dim_date 31 / product_catalog 1200 / users 300 / inventory 3600 /
--       events 20000 / orders 10000 / order_details ~20000
-- 一致性: orders/order_details 共用同一确定性公式(见下方 recipe 注释),
--         orders.user_id / events.user_id 均落在 users 的 user_id 区间内
--
-- 注意: Hive 3.1 无 sequence()/element()/array_slice(),
--       用 posexplode(split(space(N),' ')) 生成数列, arr[i] 取下标
-- 幂等: 全部用 INSERT OVERWRITE (表为 EXTERNAL, 不支持 TRUNCATE),
--       分区表按生成的分区集合整体覆盖

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

-- 1) dim_date (31 行, 2026-09-16 ~ 2026-10-16)
INSERT OVERWRITE TABLE dim_date
SELECT
  from_unixtime(e, 'yyyy-MM-dd')                              AS date_key,
  cast(from_unixtime(e, 'yyyy') as int)                       AS year,
  cast(from_unixtime(e, 'MM') as int)                         AS month,
  cast(from_unixtime(e, 'dd') as int)                         AS day,
  cast((cast(from_unixtime(e, 'MM') as int) - 1) / 3 + 1 as int) AS quarter,
  weekofyear(cast(from_unixtime(e) as timestamp))             AS week_of_year,
  dayofweek(cast(from_unixtime(e) as timestamp)) in (1, 7)    AS is_weekend,
  from_unixtime(e, 'yyyy-MM-dd') between '2026-10-01' and '2026-10-07' AS is_holiday
FROM (
  SELECT 1789516800 + pos * 86400 AS e
  FROM (SELECT 1) seed
  LATERAL VIEW posexplode(split(space(30), ' ')) v AS pos, val
) t;

-- 2) product_catalog (1200 商品, 12 分类 x 100)
INSERT OVERWRITE TABLE product_catalog
SELECT
  cast(pc / 100 as int) + 1                                    AS category_id,
  cats[cast(pc / 100 as int)]                                  AS category_name,
  100000 + pc                                                  AS product_id,
  concat(cats[cast(pc / 100 as int)], '-', lpad(cast(pc + 1 as string), 4, '0')) AS product_name,
  cast(round(5 + rand() * 4995, 2) as decimal(10,2))           AS price,
  cast(floor(rand() * 1000) as int)                            AS stock
FROM (
  SELECT
    pc,
    array('手机数码','电脑办公','家用电器','服装内衣','美妆个护','食品生鲜',
          '家居家装','运动户外','母婴玩具','图书音像','鞋靴箱包','医药保健') AS cats
  FROM (SELECT 1) seed
  LATERAL VIEW posexplode(split(space(1199), ' ')) v AS pc, val
) t;

-- 3) users (300 人, 按 last_active 的 year/month 分区)
INSERT OVERWRITE TABLE users PARTITION (year, month)
SELECT
  900001 + uid                                                 AS user_id,
  concat(s[cast(floor(rand() * 10) as int)], g[cast(floor(rand() * 10) as int)]) AS name,
  concat('user', cast(uid as string), '@example.com')          AS email,
  concat('138', lpad(cast(10000000 + floor(rand() * 89999999) as string), 8, '0')) AS phone,
  named_struct(
    'province', pv[cast(floor(rand() * 8) as int)],
    'city', concat('市', lpad(cast(1 + floor(rand() * 20) as string), 2, '0')),
    'district', concat('区', lpad(cast(1 + floor(rand() * 10) as string), 2, '0')),
    'detail', concat(cast(1 + floor(rand() * 999) as string), '号路', cast(1 + floor(rand() * 200) as string), '号')
  )                                                            AS address,
  array(tg[cast(floor(rand() * 5) as int)], tg[cast(floor(rand() * 5) as int)]) AS tags,
  map('theme', th[cast(floor(rand() * 2) as int)],
      'language', 'zh-CN',
      'push', cast(floor(rand() * 2) as string))               AS preferences,
  cast(from_unixtime(created) as timestamp)                    AS created_at,
  cast(from_unixtime(latest) as timestamp)                     AS last_active,
  substring(cast(from_unixtime(latest) as string), 1, 4)       AS year,
  substring(cast(from_unixtime(latest) as string), 6, 2)       AS month
FROM (
  SELECT
    uid,
    1717200000 + floor(rand() * 72230400) AS created,  -- 2024-06-01 起
    1789516800 + floor(rand() * 2678400)  AS latest,   -- 窗口内 31 天
    array('张','王','李','赵','刘','陈','杨','黄','周','吴')          AS s,
    array('伟','芳','娜','敏','静','磊','军','洋','勇','艳')          AS g,
    array('北京市','上海市','广东省','浙江省','江苏省','四川省','湖北省','陕西省') AS pv,
    array('新客','老客','高价值','促销敏感','会员')                    AS tg,
    array('dark','light')                                            AS th
  FROM (SELECT 1) seed
  LATERAL VIEW posexplode(split(space(299), ' ')) v AS uid, val
) t;

-- 4) inventory (1200 商品 x 3 仓 = 3600 行, reserved <= quantity)
INSERT OVERWRITE TABLE inventory
SELECT
  t.product_id,
  t.warehouse_id,
  t.quantity,
  cast(t.quantity * rand() as int)             AS reserved_qty,
  cast(from_unixtime(1789516800 + floor(rand() * 2678400)) as timestamp) AS updated_at
FROM (
  SELECT
    p.product_id,
    w                                          AS warehouse_id,
    cast(floor(rand() * 500) as int)           AS quantity
  FROM product_catalog p
  LATERAL VIEW explode(array(1, 2, 3)) wv AS w
) t;

-- 5) events (20000 行, 按 dt 分区)
INSERT OVERWRITE TABLE events PARTITION (dt)
SELECT
  concat('evt-', cast(ev as string))                       AS event_id,
  900001 + cast(floor(rand() * 300) as bigint)             AS user_id,
  et[cast(floor(rand() * 4) as int)]                       AS event_type,
  urls[cast(floor(rand() * 6) as int)]                     AS page_url,
  ts * 1000                                                AS event_time,
  map('source', src[cast(floor(rand() * 3) as int)],
      'campaign', cmp[cast(floor(rand() * 4) as int)])     AS metadata,
  from_unixtime(ts, 'yyyy-MM-dd')                          AS dt
FROM (
  SELECT
    ev,
    1789516800 + floor(rand() * 2678400) AS ts,
    array('login','pageview','click','purchase')                    AS et,
    array('/', '/product/100001', '/cart', '/order/confirm',
          '/search?q=手机', '/user/profile')                         AS urls,
    array('web','app','mini')                                        AS src,
    array('日常','国庆大促','秋促','会员日')                           AS cmp
  FROM (SELECT 1) seed
  LATERAL VIEW posexplode(split(space(19999), ' ')) v AS ev, val
) t;

-- 6) orders (10000 单, 按 dt 分区, 每单 1~3 个商品)
--    recipe (order_details 必须保持一致):
--      每单商品数 k = 1 + pmod(i, 3)   (pos = 0..k-1)
--      product_id = 100000 + pmod(i * 7 + pos * 13, 1200)
--      qty        = 1 + pmod(i + pos, 3)
INSERT OVERWRITE TABLE orders PARTITION (dt)
SELECT
  o.order_id,
  o.user_id,
  cast(round(sum(p.price * o.qty), 2) as decimal(10,2)) AS total_amount,
  o.status,
  collect_list(named_struct('product_id', o.product_id, 'name', p.product_name,
                            'price', p.price, 'qty', o.qty))  AS items,
  map('method', array('alipay','wechat','unionpay','card')[cast(floor(rand() * 4) as int)],
      'transaction_id', concat('TXN', cast(o.order_id as string)),
      'channel', array('app','h5','pos')[cast(floor(rand() * 3) as int)]) AS payment_info,
  o.dt
FROM (
  SELECT
    500000001 + i                                      AS order_id,
    900001 + cast(pmod(i * 13 + 7, 300) as bigint)     AS user_id,
    CASE WHEN r1 < 0.55 THEN 'paid'
         WHEN r1 < 0.80 THEN 'shipped'
         WHEN r1 < 0.92 THEN 'pending'
         ELSE 'cancelled' END                           AS status,
    from_unixtime(1789516800 + cast(i * 31 / 10000 as bigint) * 86400, 'yyyy-MM-dd') AS dt,
    100000 + cast(pmod(i * 7 + pos * 13, 1200) as bigint) AS product_id,
    1 + cast(pmod(i + pos, 3) as int)                   AS qty
  FROM (
    -- r1 每单取一次, 保证 status/user_id 在同一订单内一致
    SELECT i, pos, r1
    FROM (
      SELECT i, rand() AS r1
      FROM (SELECT 1) seed
      LATERAL VIEW posexplode(split(space(9999), ' ')) oi AS i, iv
    ) io
    LATERAL VIEW posexplode(split(space(2), ' ')) op AS pos, pv
    WHERE pos <= pmod(i, 3)
  ) g
) o
JOIN product_catalog p ON p.product_id = o.product_id
GROUP BY o.order_id, o.user_id, o.status, o.dt;

-- 7) order_details (与 orders.items 同一 recipe, 保证 JOIN 一致)
INSERT OVERWRITE TABLE order_details
SELECT
  500000001 + i                                         AS `order`,
  100000 + cast(pmod(i * 7 + pos * 13, 1200) as bigint) AS product,
  1 + cast(pmod(i + pos, 3) as int)                     AS quantity,
  p.price
FROM (
  SELECT i, pos
  FROM (SELECT 1) seed
  LATERAL VIEW posexplode(split(space(9999), ' ')) oi AS i, iv
  LATERAL VIEW posexplode(split(space(2), ' ')) op AS pos, pv
  WHERE pos <= pmod(i, 3)
) g
JOIN product_catalog p ON p.product_id = 100000 + cast(pmod(g.i * 7 + g.pos * 13, 1200) as bigint);
