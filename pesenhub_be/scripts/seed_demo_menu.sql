-- scripts/seed_demo_menu.sql
-- Complete seeder for Martabak Telur & Terang Bulan Manis menus from official flyers.
-- Execute with:
--   mysql -h 127.0.0.1 -P 3306 -u pesenhub -ppesenhub123 pesenhub < scripts/seed_demo_menu.sql

-- 1. Categories
INSERT INTO menu_categories(id,name,sort_order,is_active,version) VALUES
  ('10000000-0000-4000-8000-000000000001','Sosis / Jamur',10,true,1),
  ('10000000-0000-4000-8000-000000000002','Daging Ayam',20,true,1),
  ('10000000-0000-4000-8000-000000000003','Daging Sapi',30,true,1),
  ('10000000-0000-4000-8000-000000000004','Martel Mozarella',40,true,1),
  ('10000000-0000-4000-8000-000000000005','Terang Bulan Manis',50,true,1)
ON DUPLICATE KEY UPDATE name=VALUES(name), sort_order=VALUES(sort_order), is_active=true;

-- 2. Martabak Telur Menus
INSERT INTO menus(id,category_id,sku,name,description,product_type,price_amount,hpp_amount,is_available,version,sort_order)
SELECT seed.id,c.id,seed.sku,seed.menu_name,seed.description,'MARTABAK_TELUR',seed.price,NULL,true,1,seed.sort_order
FROM (
  SELECT '20000000-0000-4000-8000-000000000001' id,'Sosis / Jamur' category_name,'MT-SJ-BIASA' sku,'Biasa' menu_name,'Martabak Telur isian Sosis/Jamur porsi biasa dengan sambal uleg dan acar segar' description,20000 price,10 sort_order
  UNION ALL SELECT '20000000-0000-4000-8000-000000000002','Sosis / Jamur','MT-SJ-SPESIAL','Spesial','Martabak Telur isian Sosis/Jamur porsi spesial dengan telur ekstra dan acar segar',30000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000003','Sosis / Jamur','MT-SJ-ISTIMEWA','Istimewa','Martabak Telur isian Sosis/Jamur porsi istimewa paling tebal dan mantap',40000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000004','Daging Ayam','MT-AYAM-BIASA','Biasa','Martabak Telur daging ayam cincang gurih porsi biasa',25000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000005','Daging Ayam','MT-AYAM-SPESIAL','Spesial','Martabak Telur daging ayam cincang gurih porsi spesial',35000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000006','Daging Ayam','MT-AYAM-ISTIMEWA','Istimewa','Martabak Telur daging ayam cincang melimpah porsi istimewa',45000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000007','Daging Sapi','MT-SAPI-BIASA','Biasa','Martabak Telur daging sapi olahan rempah pilihan porsi biasa',30000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000008','Daging Sapi','MT-SAPI-SPESIAL','Spesial','Martabak Telur daging sapi olahan rempah pilihan porsi spesial',40000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000009','Daging Sapi','MT-SAPI-ISTIMEWA','Istimewa','Martabak Telur daging sapi olahan rempah pilihan porsi istimewa',50000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000010','Martel Mozarella','MT-MOZA-1','1 Isian + Moza','Sensasi tarik menarik Keju Mozarella lumer dengan 1 pilihan isian daging/sosis',50000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000011','Martel Mozarella','MT-MOZA-MIX2','Mix 2 + Moza','Sensasi tarik menarik Keju Mozarella lumer dengan mix 2 isian gurih',55000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000012','Martel Mozarella','MT-MOZA-MIX3','Mix 3 + Moza','Sensasi tarik menarik Keju Mozarella lumer dengan mix 3 isian lezat',60000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000013','Martel Mozarella','MT-MOZA-MIX4','Mix 4 + Moza','Sensasi tarik menarik Keju Mozarella lumer komplit dengan mix 4 isian',65000,40
) seed
JOIN menu_categories c ON c.name=seed.category_name
ON DUPLICATE KEY UPDATE
  category_id=VALUES(category_id),sku=VALUES(sku),name=VALUES(name),description=VALUES(description),
  price_amount=VALUES(price_amount),sort_order=VALUES(sort_order),is_available=true;

-- 3. Terang Bulan Menus
INSERT INTO menus(id,category_id,sku,name,description,product_type,price_amount,hpp_amount,is_available,version,sort_order)
SELECT seed.id,c.id,seed.sku,seed.menu_name,seed.description,'TERANG_BULAN',seed.price,NULL,true,1,seed.sort_order
FROM (
  SELECT '20000000-0000-4000-8000-000000000014' id,'Terang Bulan Manis' category_name,'TB-1TOPING-BIASA' sku,'1 Toping - Biasa' menu_name,'Manis susu kenyal sampai pagi dengan 1 pilihan toping porsi biasa' description,18000 price,10 sort_order
  UNION ALL SELECT '20000000-0000-4000-8000-000000000015','Terang Bulan Manis','TB-1TOPING-BESAR','1 Toping - Besar','Manis susu kenyal sampai pagi dengan 1 pilihan toping porsi besar mantap' description,25000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000016','Terang Bulan Manis','TB-2TOPING-BIASA','2 Toping - Biasa','Kombinasi 2 pilihan toping lezat ukuran biasa' description,23000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000017','Terang Bulan Manis','TB-2TOPING-BESAR','2 Toping - Besar','Kombinasi 2 pilihan toping lezat ukuran besar' description,30000,40
  UNION ALL SELECT '20000000-0000-4000-8000-000000000018','Terang Bulan Manis','TB-3TOPING-BIASA','3 Toping - Biasa','Perpaduan 3 toping melimpah porsi biasa' description,28000,50
  UNION ALL SELECT '20000000-0000-4000-8000-000000000019','Terang Bulan Manis','TB-3TOPING-BESAR','3 Toping - Besar','Perpaduan 3 toping melimpah porsi besar' description,35000,60
  UNION ALL SELECT '20000000-0000-4000-8000-000000000020','Terang Bulan Manis','TB-PIZZA-ALLINONE','Cut Pizza All In One','Terang Bulan Pizza potong 8 dengan kombinasi toping aneka rasa serba ada' description,45000,70
) seed
JOIN menu_categories c ON c.name=seed.category_name
ON DUPLICATE KEY UPDATE
  category_id=VALUES(category_id),sku=VALUES(sku),name=VALUES(name),description=VALUES(description),
  price_amount=VALUES(price_amount),sort_order=VALUES(sort_order),is_available=true;

-- 4. Channel Prices
INSERT INTO menu_channel_prices(menu_id,channel,amount)
SELECT id,'OFFLINE',price_amount FROM menus
WHERE id LIKE '20000000-0000-4000-8000-0000000000%'
ON DUPLICATE KEY UPDATE amount=VALUES(amount);

-- 5. Branch Availability for all active branches
INSERT INTO branch_menu_availability(branch_id,menu_id,is_available,version)
SELECT b.id, m.id, true, 1
FROM branches b
CROSS JOIN menus m
WHERE m.id LIKE '20000000-0000-4000-8000-0000000000%'
ON DUPLICATE KEY UPDATE is_available = true;

-- 6. Modifier groups for Martabak Telur (Extra Isian & Level Pedas)
-- Extra Isian
INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order)
SELECT UUID(),m.id,'extra_isian','Extra Isian',0,6,true,10
FROM menus m
WHERE m.product_type='MARTABAK_TELUR'
  AND NOT EXISTS (SELECT 1 FROM modifier_groups g WHERE g.menu_id=m.id AND g.code='extra_isian');

INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order)
SELECT UUID(),g.id,extra.code,extra.option_name,extra.amount,true,extra.sort_order
FROM modifier_groups g
JOIN menus m ON m.id=g.menu_id
CROSS JOIN (
  SELECT 'sapi' code,'Sapi' option_name,7000 amount,10 sort_order
  UNION ALL SELECT 'ayam','Ayam',5000,20
  UNION ALL SELECT 'jamur','Jamur',5000,30
  UNION ALL SELECT 'sosis','Sosis',5000,40
  UNION ALL SELECT 'sambal_uleg','Sambal Uleg',4000,50
  UNION ALL SELECT 'keju_mozzarella','Keju Mozzarella',20000,60
) extra
WHERE m.product_type='MARTABAK_TELUR'
  AND g.code='extra_isian'
  AND NOT EXISTS (SELECT 1 FROM modifier_options o WHERE o.group_id=g.id AND o.code=extra.code);

-- Level Pedas Martel (Gratis)
INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order)
SELECT UUID(),m.id,'level_pedas','Pilihan Pedas',0,1,true,20
FROM menus m
WHERE m.product_type='MARTABAK_TELUR'
  AND NOT EXISTS (SELECT 1 FROM modifier_groups g WHERE g.menu_id=m.id AND g.code='level_pedas');

INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order)
SELECT UUID(),g.id,pedas.code,pedas.option_name,pedas.amount,true,pedas.sort_order
FROM modifier_groups g
JOIN menus m ON m.id=g.menu_id
CROSS JOIN (
  SELECT 'pedas' code,'Pedas (Sambal Uleg & Cabe Rawit)' option_name,0 amount,10 sort_order
  UNION ALL SELECT 'normal','Normal / Tidak Pedas',0,20
) pedas
WHERE m.product_type='MARTABAK_TELUR'
  AND g.code='level_pedas'
  AND NOT EXISTS (SELECT 1 FROM modifier_options o WHERE o.group_id=g.id AND o.code=pedas.code);

-- 7. Modifier groups for Terang Bulan Manis (Pilihan Toping & Base Cake)
-- Pilihan Toping (Pilihan bebas sesuai jumlah toping)
INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order)
SELECT UUID(),m.id,'toping_terang_bulan','Pilihan Toping',1,8,true,10
FROM menus m
WHERE m.product_type='TERANG_BULAN'
  AND NOT EXISTS (SELECT 1 FROM modifier_groups g WHERE g.menu_id=m.id AND g.code='toping_terang_bulan');

INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order)
SELECT UUID(),g.id,top.code,top.option_name,top.amount,true,top.sort_order
FROM modifier_groups g
JOIN menus m ON m.id=g.menu_id
CROSS JOIN (
  SELECT 'coklat' code,'Coklat' option_name,0 amount,10 sort_order
  UNION ALL SELECT 'pisang','Pisang',0,20
  UNION ALL SELECT 'keju','Keju',0,30
  UNION ALL SELECT 'oreo','Oreo',0,40
  UNION ALL SELECT 'kacang','Kacang',0,50
  UNION ALL SELECT 'selai_strawberry','Selai Strawberry',0,60
  UNION ALL SELECT 'selai_blueberry','Selai Blueberry',0,70
  UNION ALL SELECT 'goldenfill','Goldenfill',0,80
) top
WHERE m.product_type='TERANG_BULAN'
  AND g.code='toping_terang_bulan'
  AND NOT EXISTS (SELECT 1 FROM modifier_options o WHERE o.group_id=g.id AND o.code=top.code);

-- Base Cake & Extra Base Cake
INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order)
SELECT UUID(),m.id,'base_cake','Pilihan Base Cake',1,1,true,20
FROM menus m
WHERE m.product_type='TERANG_BULAN'
  AND NOT EXISTS (SELECT 1 FROM modifier_groups g WHERE g.menu_id=m.id AND g.code='base_cake');

INSERT INTO modifier_options(id,group_id,code,name,price_delta_amount,is_available,sort_order)
SELECT UUID(),g.id,base.code,base.option_name,base.amount,true,base.sort_order
FROM modifier_groups g
JOIN menus m ON m.id=g.menu_id
CROSS JOIN (
  SELECT 'original' code,'Original' option_name,0 amount,10 sort_order
  UNION ALL SELECT 'red_velvet','Red Velvet',2000,20
  UNION ALL SELECT 'pandan','Pandan',2000,30
  UNION ALL SELECT 'black_forest','Black Forest',2000,40
  UNION ALL SELECT 'taro','Taro',2000,50
  UNION ALL SELECT 'mocca','Mocca',2000,60
  UNION ALL SELECT 'green_tea','Green Tea',2000,70
) base
WHERE m.product_type='TERANG_BULAN'
  AND g.code='base_cake'
  AND NOT EXISTS (SELECT 1 FROM modifier_options o WHERE o.group_id=g.id AND o.code=base.code);
