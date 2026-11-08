-- Use an immutable random OPAQUE identifier instead of the mutable login email.
-- V2 test accounts created before this migration must be re-enrolled because
-- their registration records were bound to the previous email identifier.
ALTER TABLE user_opaque_credential
  ADD COLUMN opaque_user_identifier VARCHAR(64) NULL AFTER user_id;
UPDATE user_opaque_credential
  SET opaque_user_identifier=LOWER(REPLACE(UUID(),'-',''))
  WHERE opaque_user_identifier IS NULL;
ALTER TABLE user_opaque_credential
  MODIFY opaque_user_identifier VARCHAR(64) NOT NULL;
CREATE UNIQUE INDEX uk_opaque_user_identifier
  ON user_opaque_credential(opaque_user_identifier);

ALTER TABLE opaque_registration_challenge
  ADD COLUMN opaque_user_identifier VARCHAR(64) NULL AFTER email;
UPDATE opaque_registration_challenge
  SET opaque_user_identifier=LOWER(REPLACE(UUID(),'-',''))
  WHERE opaque_user_identifier IS NULL;
ALTER TABLE opaque_registration_challenge
  MODIFY opaque_user_identifier VARCHAR(64) NOT NULL;
