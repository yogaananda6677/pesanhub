INSERT IGNORE INTO menu_categories(id,name,sort_order,is_active,version) VALUES
  ('10000000-0000-4000-8000-000000000001','Sosis / Jamur',10,true,1),
  ('10000000-0000-4000-8000-000000000002','Daging Ayam',20,true,1),
  ('10000000-0000-4000-8000-000000000003','Daging Sapi',30,true,1),
  ('10000000-0000-4000-8000-000000000004','Martel Mozarella',40,true,1);

INSERT INTO menus(id,category_id,sku,name,description,price_amount,hpp_amount,is_available,version,sort_order)
SELECT seed.id,c.id,seed.sku,seed.menu_name,NULL,seed.price,NULL,true,1,seed.sort_order
FROM (
  SELECT '20000000-0000-4000-8000-000000000001' id,'Sosis / Jamur' category_name,'MT-SJ-BIASA' sku,'Biasa' menu_name,20000 price,10 sort_order
  UNION ALL SELECT '20000000-0000-4000-8000-000000000002','Sosis / Jamur','MT-SJ-SPESIAL','Spesial',30000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000003','Sosis / Jamur','MT-SJ-ISTIMEWA','Istimewa',40000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000004','Daging Ayam','MT-AYAM-BIASA','Biasa',25000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000005','Daging Ayam','MT-AYAM-SPESIAL','Spesial',35000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000006','Daging Ayam','MT-AYAM-ISTIMEWA','Istimewa',45000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000007','Daging Sapi','MT-SAPI-BIASA','Biasa',30000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000008','Daging Sapi','MT-SAPI-SPESIAL','Spesial',40000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000009','Daging Sapi','MT-SAPI-ISTIMEWA','Istimewa',50000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000010','Martel Mozarella','MT-MOZA-1','1 Isian + Moza',50000,10
  UNION ALL SELECT '20000000-0000-4000-8000-000000000011','Martel Mozarella','MT-MOZA-MIX2','Mix 2 + Moza',55000,20
  UNION ALL SELECT '20000000-0000-4000-8000-000000000012','Martel Mozarella','MT-MOZA-MIX3','Mix 3 + Moza',60000,30
  UNION ALL SELECT '20000000-0000-4000-8000-000000000013','Martel Mozarella','MT-MOZA-MIX4','Mix 4 + Moza',65000,40
) seed
JOIN menu_categories c ON c.name=seed.category_name
ON DUPLICATE KEY UPDATE
  category_id=VALUES(category_id),sku=VALUES(sku),name=VALUES(name),
  price_amount=VALUES(price_amount),sort_order=VALUES(sort_order);

INSERT INTO menu_channel_prices(menu_id,channel,amount)
SELECT id,'OFFLINE',price_amount FROM menus
WHERE id LIKE '20000000-0000-4000-8000-0000000000%'
ON DUPLICATE KEY UPDATE amount=VALUES(amount);

INSERT INTO modifier_groups(id,menu_id,code,name,min_select,max_select,is_active,sort_order)
SELECT UUID(),m.id,'extra_isian','Extra Isian',0,6,true,100
FROM menus m
WHERE m.id LIKE '20000000-0000-4000-8000-0000000000%'
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
WHERE m.id LIKE '20000000-0000-4000-8000-0000000000%'
  AND g.code='extra_isian'
  AND NOT EXISTS (SELECT 1 FROM modifier_options o WHERE o.group_id=g.id AND o.code=extra.code);
