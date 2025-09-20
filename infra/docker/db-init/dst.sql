CREATE TABLE IF NOT EXISTS widgets (
  id   INT PRIMARY KEY,
  name TEXT NOT NULL
);



INSERT INTO widgets (id, name) VALUES
  (1, 'alpha1'), (2, 'beta2'), (3, 'gamma3')
ON CONFLICT (id) DO NOTHING;
