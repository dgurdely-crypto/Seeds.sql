INSERT INTO entity_type (code, domain, parent_types, child_types, id_pattern) VALUES
  ('FARM','SPATIAL','{}','{PROPERTY}','^FARM-'),
  ('GREENHOUSE','SPATIAL','{PROPERTY}','{ZONE,BENCH}','^GH-\d{2}$'),
  ('BENCH','SPATIAL','{GREENHOUSE}','{TRAY}','^B-\d{2}$'),
  ('TRAY','PRODUCTION','{BENCH}','{}','^T-\d{3}$'),
  ('PUMP','ASSET','{PROPERTY}','{}','^PUMP-\d{2}$'),
  ('WORKER','OPERATION','{FARM}','{DEVICE}','^W-'),
  ('DEVICE','ASSET','{WORKER,PROPERTY}','{}','^DEV-'),
  ('ANIMAL','BIOLOGICAL','{}','{}','^A-'),
  ('WORK_ITEM','OPERATION','{}','{}','^WO-\d{5}$'),
  ('SERVICE_CASE','OPERATION','{}','{}','^SC-'),
  ('PLAN','OPERATION','{}','{}','^PLAN-');
