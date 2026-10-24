import { Router, type IRouter } from "express";
import {
  db,
  usersTable,
  webauthnCredentialsTable,
  userPermissionsTable,
  employeesTable,
} from "@workspace/db";
import { eq, and } from "drizzle-orm";
import crypto from "crypto";
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} from "@simplewebauthn/server";

const router: IRouter = Router();

// In-memory sessions: token -> userId
export const sessions = new Map<string, number>();

// In-memory password reset tokens: token -> { userId, expiresAt }
const resetTokens = new Map<string, { userId: number; expiresAt: Date }>();

// In-memory WebAuthn challenges (short-lived)
const regChallenges = new Map<number, string>(); // userId -> challenge
const authChallenges = new Map<string, string>(); // email -> challenge

const RP_NAME = "Al Anad HR HR Portal";

function hashPassword(password: string): string {
  return crypto.createHash("sha256").update(password).digest("hex");
}

async function buildUserPayload(userId: number) {
  const [user] = await db.select().from(usersTable).where(eq(usersTable.id, userId));
  if (!user) return null;
  const permissions = await db
    .select({ module: userPermissionsTable.module, enabled: userPermissionsTable.enabled })
    .from(userPermissionsTable)
    .where(eq(userPermissionsTable.userId, userId));
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    avatar: user.avatar,
    title: user.title,
    phone: user.phone,
    status: user.status,
    permissions: permissions.map((p) => ({ module: p.module, enabled: p.enabled })),
  };
}

function getToken(req: any): string | null {
  const auth = req.headers.authorization as string | undefined;
  if (!auth?.startsWith("Bearer ")) return null;
  return auth.slice(7);
}

async function requireAuth(req: any, res: any): Promise<number | null> {
  const token = getToken(req);
  if (!token) {
    res.status(401).json({ error: "Unauthorized" });
    return null;
  }
  const userId = sessions.get(token);
  if (!userId) {
    res.status(401).json({ error: "Invalid or expired session" });
    return null;
  }

  // Check user status
  const [user] = await db
    .select({ status: usersTable.status, role: usersTable.role })
    .from(usersTable)
    .where(eq(usersTable.id, userId));

  if (user && user.status !== "active") {
    sessions.delete(token);
    res.status(403).json({
      error:
        user.status === "pending"
          ? "Account is pending approval"
          : user.status === "suspended"
            ? "Account has been suspended"
            : "Account has been disabled",
    });
    return null;
  }

  return userId;
}

function getRpId(req: any): string {
  try {
    const origin = (req.headers.origin as string) || "http://localhost:5173";
    return new URL(origin).hostname;
  } catch {
    return "localhost";
  }
}

function getOrigin(req: any): string {
  return (req.headers.origin as string) || "http://localhost:5173";
}

// ─────────────────────────────────────────────
// Password auth
// ─────────────────────────────────────────────

router.post("/login", async (req, res): Promise<void> => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      res.status(400).json({ error: "Email and password required" });
      return;
    }

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, email.toLowerCase().trim()));
    if (!user || user.passwordHash !== hashPassword(password)) {
      res.status(401).json({ error: "Invalid email or password" });
      return;
    }

    // Check user status before issuing token
    if (user.status !== "active") {
      if (user.status === "pending") {
        res.status(403).json({
          error: "Account is pending approval. Please contact your manager.",
        });
      } else if (user.status === "suspended") {
        res.status(403).json({
          error: "Account has been suspended. Please contact your manager.",
        });
      } else {
        res.status(403).json({
          error: "Account has been disabled. Please contact your manager.",
        });
      }
      return;
    }

    const token = crypto.randomUUID();
    sessions.set(token, user.id);
    const userPayload = await buildUserPayload(user.id);
    res.json({ token, user: userPayload });
  } catch (err) {
    console.error("Login error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/register", async (req, res): Promise<void> => {
  try {
    const { name, email, password } = req.body ?? {};
    if (!name || !email || !password) {
      res.status(400).json({ error: "Name, email and password are required" });
      return;
    }
    if (password.length < 6) {
      res.status(400).json({ error: "Password must be at least 6 characters" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();
    const [existing] = await db
      .select({ id: usersTable.id })
      .from(usersTable)
      .where(eq(usersTable.email, normalizedEmail));
    if (existing) {
      res
        .status(409)
        .json({ error: "An account with this email already exists" });
      return;
    }

    const [user] = await db
      .insert(usersTable)
      .values({
        name: name.trim(),
        email: normalizedEmail,
        passwordHash: hashPassword(password),
        role: "hr_manager",
        status: "active",
        createdAt: new Date().toISOString(),
      })
      .returning();

    const token = crypto.randomUUID();
    sessions.set(token, user.id);
    const userPayload = await buildUserPayload(user.id);
    res.status(201).json({ token, user: userPayload });
  } catch (err) {
    console.error("Register error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.get("/me", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;
    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, userId));
    if (!user) {
      res.status(404).json({ error: "User not found" });
      return;
    }

    // Get permissions for this user
    const permissions = await db
      .select({
        module: userPermissionsTable.module,
        enabled: userPermissionsTable.enabled,
      })
      .from(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, userId));

    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      avatar: user.avatar,
      title: user.title,
      phone: user.phone,
      status: user.status,
      permissions: permissions.map((p) => ({
        module: p.module,
        enabled: p.enabled,
      })),
    });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/logout", (req, res): void => {
  const token = getToken(req);
  if (token) sessions.delete(token);
  res.json({ ok: true });
});

router.put("/profile", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;
    const { name, title, phone, avatar } = req.body ?? {};
    const updates: Record<string, string> = {};
    if (name !== undefined) updates.name = name.trim();
    if (title !== undefined) updates.title = title;
    if (phone !== undefined) updates.phone = phone;
    if (avatar !== undefined) updates.avatar = avatar;
    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: "No fields to update" });
      return;
    }
    const [user] = await db
      .update(usersTable)
      .set(updates)
      .where(eq(usersTable.id, userId))
      .returning();
    res.json({
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      avatar: user.avatar,
      title: user.title,
      phone: user.phone,
    });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

router.put("/password", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;
    const { currentPassword, newPassword } = req.body ?? {};
    if (!currentPassword || !newPassword) {
      res.status(400).json({ error: "Current and new password required" });
      return;
    }
    if (newPassword.length < 6) {
      res
        .status(400)
        .json({ error: "New password must be at least 6 characters" });
      return;
    }

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, userId));
    if (!user || user.passwordHash !== hashPassword(currentPassword)) {
      res.status(401).json({ error: "Current password is incorrect" });
      return;
    }

    await db
      .update(usersTable)
      .set({ passwordHash: hashPassword(newPassword) })
      .where(eq(usersTable.id, userId));
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// Employee auth endpoints
// ─────────────────────────────────────────────

// POST /api/auth/employee/check-email
router.post("/employee/check-email", async (req, res): Promise<void> => {
  try {
    const { email } = req.body ?? {};
    if (!email) {
      res.status(400).json({ error: "Email required" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();
    const [employee] = await db
      .select()
      .from(employeesTable)
      .where(eq(employeesTable.email, normalizedEmail));

    if (!employee) {
      res.json({ status: "not_found" });
      return;
    }

    // Check if an employee-role user already exists for this email
    const [existingUser] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, normalizedEmail));

    if (existingUser && existingUser.role === "employee") {
      res.json({ status: "active", employeeId: employee.id });
    } else {
      res.json({ status: "needs_activation", employeeId: employee.id });
    }
  } catch (err) {
    console.error("Check email error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/employee/activate
router.post("/employee/activate", async (req, res): Promise<void> => {
  try {
    const { email, password, confirmPassword } = req.body ?? {};
    if (!email || !password || !confirmPassword) {
      res.status(400).json({ error: "Email and passwords required" });
      return;
    }
    if (password !== confirmPassword) {
      res.status(400).json({ error: "Passwords do not match" });
      return;
    }
    if (password.length < 8) {
      res.status(400).json({ error: "Password must be at least 8 characters" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();
    const [employee] = await db
      .select()
      .from(employeesTable)
      .where(eq(employeesTable.email, normalizedEmail));

    if (!employee) {
      res.status(404).json({ error: "Employee not found" });
      return;
    }

    // Check if an employee account already exists for this email
    const [existingUser] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, normalizedEmail));

    if (existingUser && existingUser.role === "employee") {
      res.status(409).json({ error: "Account already activated" });
      return;
    }

    // Create employee user account
    const [user] = await db
      .insert(usersTable)
      .values({
        name: `${employee.firstName} ${employee.lastName}`,
        email: normalizedEmail,
        passwordHash: hashPassword(password),
        role: "employee",
        status: "active",
        employeeId: employee.id,
        createdAt: new Date().toISOString(),
      })
      .returning();

    const token = crypto.randomUUID();
    sessions.set(token, user.id);
    res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        employeeId: employee.id,
      },
    });
  } catch (err) {
    console.error("Activate error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/employee/login
router.post("/employee/login", async (req, res): Promise<void> => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      res.status(400).json({ error: "Email and password required" });
      return;
    }

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, email.toLowerCase().trim()));

    if (!user || user.role !== "employee") {
      res.status(401).json({ error: "Invalid email or password" });
      return;
    }

    if (user.passwordHash !== hashPassword(password)) {
      res.status(401).json({ error: "Invalid email or password" });
      return;
    }

    if (user.status !== "active") {
      res.status(403).json({ error: "Account is not active" });
      return;
    }

    const token = crypto.randomUUID();
    sessions.set(token, user.id);
    res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        employeeId: user.employeeId,
      },
    });
  } catch (err) {
    console.error("Employee login error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/employee/forgot-password
router.post("/employee/forgot-password", async (req, res): Promise<void> => {
  try {
    const { email } = req.body ?? {};
    if (!email) {
      res.status(400).json({ error: "Email required" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();
    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, normalizedEmail));

    if (!user || user.role !== "employee") {
      // Don't reveal if user exists for security
      res.json({ ok: true, message: "If the email exists, a reset link will be sent" });
      return;
    }

    // Generate reset token
    const resetToken = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes
    resetTokens.set(resetToken, { userId: user.id, expiresAt });

    // In production, send email with reset link
    // For dev mode, return token in response
    res.json({ ok: true, resetToken });
  } catch (err) {
    console.error("Forgot password error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/employee/reset-password
router.post("/employee/reset-password", async (req, res): Promise<void> => {
  try {
    const { resetToken, newPassword, confirmPassword } = req.body ?? {};
    if (!resetToken || !newPassword || !confirmPassword) {
      res.status(400).json({ error: "All fields required" });
      return;
    }
    if (newPassword !== confirmPassword) {
      res.status(400).json({ error: "Passwords do not match" });
      return;
    }
    if (newPassword.length < 8) {
      res.status(400).json({ error: "Password must be at least 8 characters" });
      return;
    }

    const tokenData = resetTokens.get(resetToken);
    if (!tokenData) {
      res.status(400).json({ error: "Invalid or expired reset token" });
      return;
    }
    if (tokenData.expiresAt < new Date()) {
      resetTokens.delete(resetToken);
      res.status(400).json({ error: "Reset token has expired" });
      return;
    }

    // Update password
    await db
      .update(usersTable)
      .set({ passwordHash: hashPassword(newPassword) })
      .where(eq(usersTable.id, tokenData.userId));

    resetTokens.delete(resetToken);
    res.json({ ok: true });
  } catch (err) {
    console.error("Reset password error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// WebAuthn — Windows Hello support
// ─────────────────────────────────────────────

// GET /api/auth/webauthn/status — check if user has passkey registered
router.get("/webauthn/status", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;
    const creds = await db
      .select({
        id: webauthnCredentialsTable.id,
        createdAt: webauthnCredentialsTable.createdAt,
      })
      .from(webauthnCredentialsTable)
      .where(eq(webauthnCredentialsTable.userId, userId));
    res.json({
      registered: creds.length > 0,
      count: creds.length,
      registeredAt: creds[0]?.createdAt ?? null,
    });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/webauthn/register-options
router.post("/webauthn/register-options", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, userId));
    if (!user) {
      res.status(404).json({ error: "User not found" });
      return;
    }

    const rpID = getRpId(req);

    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID,
      userName: user.email,
      userDisplayName: user.name,
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        userVerification: "required",
        residentKey: "preferred",
      },
      attestationType: "none",
      excludeCredentials: (
        await db
          .select({ credentialId: webauthnCredentialsTable.credentialId })
          .from(webauthnCredentialsTable)
          .where(eq(webauthnCredentialsTable.userId, userId))
      ).map((c) => ({ id: c.credentialId })),
    });

    regChallenges.set(userId, options.challenge);
    res.json(options);
  } catch (err) {
    console.error("WebAuthn register-options error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/webauthn/register-verify
router.post("/webauthn/register-verify", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const expectedChallenge = regChallenges.get(userId);
    if (!expectedChallenge) {
      res.status(400).json({ error: "No pending challenge" });
      return;
    }

    const verification = await verifyRegistrationResponse({
      response: req.body,
      expectedChallenge,
      expectedOrigin: getOrigin(req),
      expectedRPID: getRpId(req),
    });

    if (!verification.verified || !verification.registrationInfo) {
      res.status(400).json({ error: "Verification failed" });
      return;
    }

    const { credential } = verification.registrationInfo;
    const credentialId =
      typeof credential.id === "string"
        ? credential.id
        : Buffer.from(credential.id as Uint8Array).toString("base64url");
    const publicKey = Buffer.from(credential.publicKey as Uint8Array).toString(
      "base64url",
    );

    // Remove existing passkeys for this user (one device at a time for simplicity)
    await db
      .delete(webauthnCredentialsTable)
      .where(eq(webauthnCredentialsTable.userId, userId));

    const inserted = await db
      .insert(webauthnCredentialsTable)
      .values({
        userId,
        credentialId,
        publicKey,
        counter: credential.counter,
        createdAt: new Date().toISOString().split("T")[0],
      })
      .returning({ id: webauthnCredentialsTable.id });

    if (!inserted || inserted.length === 0) {
      res.status(500).json({ error: "Failed to save passkey to database" });
      return;
    }

    regChallenges.delete(userId);
    res.json({ verified: true });
  } catch (err) {
    console.error("WebAuthn register-verify error:", err);
    res.status(500).json({ error: "Verification failed" });
  }
});

// DELETE /api/auth/webauthn — remove passkey
router.delete("/webauthn", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;
    await db
      .delete(webauthnCredentialsTable)
      .where(eq(webauthnCredentialsTable.userId, userId));
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/webauthn/login-options — pass email in body
router.post("/webauthn/login-options", async (req, res): Promise<void> => {
  try {
    const { email } = req.body ?? {};
    if (!email) {
      res.status(400).json({ error: "Email required" });
      return;
    }

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, email.toLowerCase().trim()));
    if (!user) {
      res.status(404).json({ error: "No account found with that email" });
      return;
    }

    const userCreds = await db
      .select()
      .from(webauthnCredentialsTable)
      .where(eq(webauthnCredentialsTable.userId, user.id));
    if (userCreds.length === 0) {
      res.status(404).json({ error: "No passkey registered for this account" });
      return;
    }

    const rpID = getRpId(req);

    const options = await generateAuthenticationOptions({
      rpID,
      allowCredentials: userCreds.map((c) => ({ id: c.credentialId })),
      userVerification: "required",
    });

    authChallenges.set(email.toLowerCase().trim(), options.challenge);
    res.json(options);
  } catch (err) {
    console.error("WebAuthn login-options error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /api/auth/webauthn/login-verify
router.post("/webauthn/login-verify", async (req, res): Promise<void> => {
  try {
    const { email, assertionResponse } = req.body ?? {};
    if (!email || !assertionResponse) {
      res.status(400).json({ error: "Missing fields" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();
    const expectedChallenge = authChallenges.get(normalizedEmail);
    if (!expectedChallenge) {
      res.status(400).json({ error: "No pending challenge" });
      return;
    }

    const [user] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.email, normalizedEmail));
    if (!user) {
      res.status(404).json({ error: "User not found" });
      return;
    }

    // Check user status before issuing token
    if (user.status !== "active") {
      if (user.status === "pending") {
        res
          .status(403)
          .json({
            error: "Account is pending approval. Please contact your manager.",
          });
      } else if (user.status === "suspended") {
        res
          .status(403)
          .json({
            error: "Account has been suspended. Please contact your manager.",
          });
      } else {
        res
          .status(403)
          .json({
            error: "Account has been disabled. Please contact your manager.",
          });
      }
      return;
    }

    const userCreds = await db
      .select()
      .from(webauthnCredentialsTable)
      .where(eq(webauthnCredentialsTable.userId, user.id));

    // Find the matching credential
    const assertedCredId = assertionResponse.id || assertionResponse.rawId;
    const storedCred =
      userCreds.find((c) => c.credentialId === assertedCredId) ?? userCreds[0];
    if (!storedCred) {
      res.status(400).json({ error: "Credential not found" });
      return;
    }

    const verification = await verifyAuthenticationResponse({
      response: assertionResponse,
      expectedChallenge,
      expectedOrigin: getOrigin(req),
      expectedRPID: getRpId(req),
      credential: {
        id: storedCred.credentialId,
        publicKey: Buffer.from(storedCred.publicKey, "base64url"),
        counter: storedCred.counter,
      },
    });

    if (!verification.verified) {
      res.status(401).json({ error: "Authentication failed" });
      return;
    }

    // Update counter
    await db
      .update(webauthnCredentialsTable)
      .set({ counter: verification.authenticationInfo.newCounter })
      .where(eq(webauthnCredentialsTable.id, storedCred.id));

    authChallenges.delete(normalizedEmail);

    const token = crypto.randomUUID();
    sessions.set(token, user.id);
    const userPayload = await buildUserPayload(user.id);
    res.json({ token, user: userPayload });
  } catch (err) {
    console.error("WebAuthn login-verify error:", err);
    res.status(500).json({ error: "Authentication failed" });
  }
});

export default router;
