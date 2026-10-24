import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { attendanceRulesTable } from "@workspace/db/schema";
import { eq, sql } from "drizzle-orm";

const router: IRouter = Router();

// GET /api/attendance-rules - list all rules
router.get("/", async (req, res) => {
  const rules = await db.select().from(attendanceRulesTable);
  res.json(rules.map(r => ({
    ...r,
    locationLat: r.locationLat ? parseFloat(r.locationLat) : null,
    locationLng: r.locationLng ? parseFloat(r.locationLng) : null,
    locationRadiusKm: r.locationRadiusKm ? parseFloat(r.locationRadiusKm) : null,
  })));
});

// GET /api/attendance-rules/active - get first active rule
router.get("/active", async (req, res) => {
  const [rule] = await db
    .select()
    .from(attendanceRulesTable)
    .where(eq(attendanceRulesTable.isActive, true))
    .limit(1);

  if (!rule) {
    res.json(null);
    return;
  }

  res.json({
    ...rule,
    locationLat: rule.locationLat ? parseFloat(rule.locationLat) : null,
    locationLng: rule.locationLng ? parseFloat(rule.locationLng) : null,
    locationRadiusKm: rule.locationRadiusKm ? parseFloat(rule.locationRadiusKm) : null,
  });
});

// POST /api/attendance-rules - create rule
router.post("/", async (req, res): Promise<void> => {
  try {
    const { name, locationEnabled, locationLat, locationLng, locationRadiusKm, wifiEnabled, wifiSsid, isActive } = req.body ?? {};

    if (!name) {
      res.status(400).json({ error: "Name required" });
      return;
    }

    const [rule] = await db
      .insert(attendanceRulesTable)
      .values({
        name,
        locationEnabled: locationEnabled ?? false,
        locationLat: locationLat ? String(locationLat) : null,
        locationLng: locationLng ? String(locationLng) : null,
        locationRadiusKm: locationRadiusKm ? String(locationRadiusKm) : null,
        wifiEnabled: wifiEnabled ?? false,
        wifiSsid: wifiSsid ?? null,
        isActive: isActive ?? true,
        createdAt: new Date().toISOString(),
      })
      .returning();

    res.status(201).json({
      ...rule,
      locationLat: rule.locationLat ? parseFloat(rule.locationLat) : null,
      locationLng: rule.locationLng ? parseFloat(rule.locationLng) : null,
      locationRadiusKm: rule.locationRadiusKm ? parseFloat(rule.locationRadiusKm) : null,
    });
  } catch (err) {
    console.error("Create attendance rule error:", err);
    res.status(500).json({ error: "Failed to create rule" });
  }
});

// PUT /api/attendance-rules/:id - update rule
router.put("/:id", async (req, res): Promise<void> => {
  try {
    const id = parseInt(req.params.id);
    const { name, locationEnabled, locationLat, locationLng, locationRadiusKm, wifiEnabled, wifiSsid, isActive } = req.body ?? {};

    const updates: Record<string, any> = {};
    if (name !== undefined) updates.name = name;
    if (locationEnabled !== undefined) updates.locationEnabled = locationEnabled;
    if (locationLat !== undefined) updates.locationLat = locationLat ? String(locationLat) : null;
    if (locationLng !== undefined) updates.locationLng = locationLng ? String(locationLng) : null;
    if (locationRadiusKm !== undefined) updates.locationRadiusKm = locationRadiusKm ? String(locationRadiusKm) : null;
    if (wifiEnabled !== undefined) updates.wifiEnabled = wifiEnabled;
    if (wifiSsid !== undefined) updates.wifiSsid = wifiSsid;
    if (isActive !== undefined) updates.isActive = isActive;

    const [rule] = await db
      .update(attendanceRulesTable)
      .set(updates)
      .where(eq(attendanceRulesTable.id, id))
      .returning();

    if (!rule) {
      res.status(404).json({ error: "Rule not found" });
      return;
    }

    res.json({
      ...rule,
      locationLat: rule.locationLat ? parseFloat(rule.locationLat) : null,
      locationLng: rule.locationLng ? parseFloat(rule.locationLng) : null,
      locationRadiusKm: rule.locationRadiusKm ? parseFloat(rule.locationRadiusKm) : null,
    });
  } catch (err) {
    console.error("Update attendance rule error:", err);
    res.status(500).json({ error: "Failed to update rule" });
  }
});

// DELETE /api/attendance-rules/:id - delete rule
router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params.id);
  await db.delete(attendanceRulesTable).where(eq(attendanceRulesTable.id, id));
  res.status(204).end();
});

export default router;
