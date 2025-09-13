CREATE TABLE IF NOT EXISTS widgets (
  id   INT PRIMARY KEY,
  name TEXT NOT NULL
);

INSERT INTO widgets (id, name) VALUES
  (1, 'alpha'), (2, 'beta'), (3, 'gamma')
ON CONFLICT (id) DO NOTHING;
