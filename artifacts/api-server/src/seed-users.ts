import crypto from "crypto";
import { pgClient } from "@workspace/db";

function hashPassword(password: string): string {
  return crypto.createHash("sha256").update(password).digest("hex");
}

/**
 * Ensures the default admin user exists with correct credentials.
 * Uses UPSERT so it fixes the hash even if the record already existed.
 */
export async function seedAdminUser(): Promise<void> {
  const hash = hashPassword("123456");
  // Insert only if email doesn't exist yet
  await pgClient.query(
    `INSERT INTO users (name, email, password_hash, role, status, title, created_at)
     SELECT $1, $2, $3, $4, $5, $6, $7
     WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = $2)`,
    [
      "Abdelrhman Samy",
      "admin@example.com",
      hash,
      "hr_manager",
      "active",
      "HR Director",
      "2024-01-01",
    ],
  );
  // Always update the hash and role to ensure it's correct
  await pgClient.query(
    `UPDATE users SET password_hash = $1, role = 'hr_manager', status = 'active' WHERE email = $2`,
    [hash, "admin@example.com"],
  );
}
