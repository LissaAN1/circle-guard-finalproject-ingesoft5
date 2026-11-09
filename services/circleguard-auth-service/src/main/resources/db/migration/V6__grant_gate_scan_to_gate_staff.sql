-- HU-07: gate-scanner UI needs the already-defined gate:scan permission.
-- Safe on databases where the mapping was added manually; never changes users or passwords.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'GATE_STAFF'
  AND p.name = 'gate:scan'
ON CONFLICT (role_id, permission_id) DO NOTHING;
