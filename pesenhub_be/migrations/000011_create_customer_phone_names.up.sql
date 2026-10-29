-- 000011_create_customer_phone_names.up.sql
CREATE TABLE IF NOT EXISTS customer_phone_names (
  phone_e164 varchar(20) PRIMARY KEY,
  customer_name varchar(120) NOT NULL,
  notes text NULL,
  created_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;
