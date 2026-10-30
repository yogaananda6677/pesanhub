-- 000011_add_branch_operational_hours.down.sql

ALTER TABLE branches
  DROP COLUMN is_open,
  DROP COLUMN open_days,
  DROP COLUMN close_time,
  DROP COLUMN open_time;
