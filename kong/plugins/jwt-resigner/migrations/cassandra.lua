local migrations = {
  {
    name = "2018-08-20-180000_jwt_resigner",
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_resigner_jwks (
        id          UUID       PRIMARY KEY,
        name        TEXT,
        keys        TEXT,
        previous    TEXT,
        created_at  TIMESTAMP,
        updated_at  TIMESTAMP,
      );

      CREATE INDEX IF NOT EXISTS jwt_resigner_jwks_name_idx ON jwt_resigner_jwks(name);
    ]],
    down = [[
      DROP TABLE jwt_resigner_jwks;
    ]]
  },
}

return migrations
