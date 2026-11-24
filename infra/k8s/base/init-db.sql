-- Initialize required microservice databases

SELECT 'CREATE DATABASE circleguard_auth' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'circleguard_auth')\gexec

SELECT 'CREATE DATABASE circleguard_identity' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'circleguard_identity')\gexec

SELECT 'CREATE DATABASE circleguard_promotion' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'circleguard_promotion')\gexec

SELECT 'CREATE DATABASE circleguard_dashboard' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'circleguard_dashboard')\gexec

SELECT 'CREATE DATABASE circleguard_form' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'circleguard_form')\gexec

-- bcrypt hashing for the dedicated E2E accounts of DEV (tests/e2e-playwright/scripts/ensure-e2e-users.sh).
-- This file only runs when the data directory is created; an existing environment needs it once by hand.
\connect circleguard_auth
CREATE EXTENSION IF NOT EXISTS pgcrypto;
