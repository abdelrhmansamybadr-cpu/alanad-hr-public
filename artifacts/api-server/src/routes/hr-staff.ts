import { Router, type IRouter } from "express";
import { db, usersTable, userPermissionsTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import crypto from "crypto";
import { sessions } from "./auth";

const router: IRouter = Router();

function hashPassword(password: string): string {
  return crypto.createHash("sha256").update(password).digest("hex");
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
  return userId;
}

async function requireManager(req: any, res: any): Promise<number | null> {
  const userId = await requireAuth(req, res);
  if (!userId) return null;

  const [user] = await db
    .select({ role: usersTable.role })
    .from(usersTable)
    .where(eq(usersTable.id, userId));

  if (!user || user.role !== "hr_manager") {
    res.status(403).json({ error: "Access denied. Manager role required." });
    return null;
  }

  return userId;
}

// Get all HR staff created by the current manager
router.get("/", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staff = await db
      .select({
        id: usersTable.id,
        name: usersTable.name,
        email: usersTable.email,
        role: usersTable.role,
        avatar: usersTable.avatar,
        title: usersTable.title,
        phone: usersTable.phone,
        status: usersTable.status,
        createdAt: usersTable.createdAt,
      })
      .from(usersTable)
      .where(eq(usersTable.createdBy, managerId));

    // Get permissions for each staff member
    const staffWithPermissions = await Promise.all(
      staff.map(async (member) => {
        const perms = await db
          .select({
            module: userPermissionsTable.module,
            enabled: userPermissionsTable.enabled,
          })
          .from(userPermissionsTable)
          .where(eq(userPermissionsTable.userId, member.id));

        return {
          ...member,
          permissions: perms.map((p) => ({
            module: p.module,
            enabled: p.enabled,
          })),
        };
      }),
    );

    res.json(staffWithPermissions);
  } catch (err) {
    console.error("Error fetching HR staff:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Create new HR staff member
router.post("/", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const { name, email, password, title, phone } = req.body ?? {};

    if (!name || !email || !password) {
      res.status(400).json({ error: "Name, email and password are required" });
      return;
    }

    if (password.length < 6) {
      res.status(400).json({ error: "Password must be at least 6 characters" });
      return;
    }

    const normalizedEmail = email.toLowerCase().trim();

    // Check email uniqueness
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

    const [newStaff] = await db
      .insert(usersTable)
      .values({
        name: name.trim(),
        email: normalizedEmail,
        passwordHash: hashPassword(password),
        role: "hr_employee",
        status: "pending",
        title: title || null,
        phone: phone || null,
        createdBy: managerId,
        createdAt: new Date().toISOString(),
      })
      .returning({
        id: usersTable.id,
        name: usersTable.name,
        email: usersTable.email,
        role: usersTable.role,
        status: usersTable.status,
        title: usersTable.title,
        phone: usersTable.phone,
        createdAt: usersTable.createdAt,
      });

    res.status(201).json({
      ...newStaff,
      permissions: [],
    });
  } catch (err) {
    console.error("Error creating HR staff:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Update HR staff member
router.put("/:id", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    const { name, title, phone } = req.body ?? {};
    const updates: Record<string, string | null> = {};
    if (name !== undefined) updates.name = name.trim();
    if (title !== undefined) updates.title = title;
    if (phone !== undefined) updates.phone = phone;

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: "No fields to update" });
      return;
    }

    const [updated] = await db
      .update(usersTable)
      .set(updates)
      .where(eq(usersTable.id, staffId))
      .returning({
        id: usersTable.id,
        name: usersTable.name,
        email: usersTable.email,
        role: usersTable.role,
        status: usersTable.status,
        title: usersTable.title,
        phone: usersTable.phone,
        createdAt: usersTable.createdAt,
      });

    // Get permissions
    const perms = await db
      .select({
        module: userPermissionsTable.module,
        enabled: userPermissionsTable.enabled,
      })
      .from(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, staffId));

    res.json({
      ...updated,
      permissions: perms.map((p) => ({
        module: p.module,
        enabled: p.enabled,
      })),
    });
  } catch (err) {
    console.error("Error updating HR staff:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Update HR staff status
router.patch("/:id/status", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    const { status } = req.body ?? {};
    const validStatuses = ["active", "pending", "suspended", "disabled"];
    if (!status || !validStatuses.includes(status)) {
      res
        .status(400)
        .json({
          error:
            "Invalid status. Must be: active, pending, suspended, or disabled",
        });
      return;
    }

    const [updated] = await db
      .update(usersTable)
      .set({ status })
      .where(eq(usersTable.id, staffId))
      .returning({
        id: usersTable.id,
        name: usersTable.name,
        email: usersTable.email,
        role: usersTable.role,
        status: usersTable.status,
        title: usersTable.title,
        phone: usersTable.phone,
        createdAt: usersTable.createdAt,
      });

    // If suspending/disabling, invalidate all sessions for this user
    if (status === "suspended" || status === "disabled") {
      for (const [token, userId] of sessions.entries()) {
        if (userId === staffId) {
          sessions.delete(token);
        }
      }
    }

    // Get permissions
    const perms = await db
      .select({
        module: userPermissionsTable.module,
        enabled: userPermissionsTable.enabled,
      })
      .from(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, staffId));

    res.json({
      ...updated,
      permissions: perms.map((p) => ({
        module: p.module,
        enabled: p.enabled,
      })),
    });
  } catch (err) {
    console.error("Error updating HR staff status:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Reset HR staff password
router.patch("/:id/password", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    const { password } = req.body ?? {};
    if (!password || password.length < 6) {
      res.status(400).json({ error: "Password must be at least 6 characters" });
      return;
    }

    await db
      .update(usersTable)
      .set({ passwordHash: hashPassword(password) })
      .where(eq(usersTable.id, staffId));

    res.json({ success: true });
  } catch (err) {
    console.error("Error resetting HR staff password:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get staff permissions
router.get("/:id/permissions", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    const perms = await db
      .select({
        module: userPermissionsTable.module,
        enabled: userPermissionsTable.enabled,
      })
      .from(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, staffId));

    res.json(
      perms.map((p) => ({
        module: p.module,
        enabled: p.enabled,
      })),
    );
  } catch (err) {
    console.error("Error fetching staff permissions:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Update staff permissions
router.put("/:id/permissions", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    const { permissions } = req.body ?? {};
    if (!Array.isArray(permissions)) {
      res.status(400).json({ error: "Permissions array required" });
      return;
    }

    // Upsert each permission
    for (const perm of permissions) {
      await db
        .insert(userPermissionsTable)
        .values({
          userId: staffId,
          module: perm.module,
          enabled: perm.enabled ?? true,
        })
        .onConflictDoUpdate({
          target: [userPermissionsTable.userId, userPermissionsTable.module],
          set: { enabled: perm.enabled ?? true },
        });
    }

    // Return updated permissions
    const updatedPerms = await db
      .select({
        module: userPermissionsTable.module,
        enabled: userPermissionsTable.enabled,
      })
      .from(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, staffId));

    res.json(
      updatedPerms.map((p) => ({
        module: p.module,
        enabled: p.enabled,
      })),
    );
  } catch (err) {
    console.error("Error updating staff permissions:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Delete HR staff member
router.delete("/:id", async (req, res): Promise<void> => {
  try {
    const managerId = await requireManager(req, res);
    if (!managerId) return;

    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      res.status(400).json({ error: "Invalid staff ID" });
      return;
    }

    // Verify ownership
    const [staff] = await db
      .select()
      .from(usersTable)
      .where(eq(usersTable.id, staffId));

    if (!staff || staff.createdBy !== managerId) {
      res.status(403).json({ error: "You can only manage your own staff" });
      return;
    }

    // Delete permissions first
    await db
      .delete(userPermissionsTable)
      .where(eq(userPermissionsTable.userId, staffId));

    // Invalidate any sessions
    for (const [token, userId] of sessions.entries()) {
      if (userId === staffId) {
        sessions.delete(token);
      }
    }

    // Delete user
    await db.delete(usersTable).where(eq(usersTable.id, staffId));

    res.status(204).end();
  } catch (err) {
    console.error("Error deleting HR staff:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
