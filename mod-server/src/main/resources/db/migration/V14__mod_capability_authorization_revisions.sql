-- Monotonic revisions prevent a previously issued proof from becoming valid again
-- after a revoke -> re-grant / reject -> re-approve / disable -> re-enable cycle.
ALTER TABLE mod_capability_approval
  ADD COLUMN authorization_revision BIGINT NOT NULL DEFAULT 1;

ALTER TABLE user_mod_capability_grant
  ADD COLUMN authorization_revision BIGINT NOT NULL DEFAULT 1;

ALTER TABLE mod_packages
  ADD COLUMN authorization_revision BIGINT NOT NULL DEFAULT 1;
