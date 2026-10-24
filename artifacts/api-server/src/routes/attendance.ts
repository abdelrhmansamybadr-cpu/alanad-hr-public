import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { attendanceTable, employeesTable } from "@workspace/db/schema";
import { eq } from "drizzle-orm";
import { CreateAttendanceBody } from "@workspace/api-zod";

const router: IRouter = Router();

function calcHours(checkIn?: string | null, checkOut?: string | null): string | null {
  if (!checkIn || !checkOut) return null;
  const inn = new Date(`2000-01-01T${checkIn}`);
  const out = new Date(`2000-01-01T${checkOut}`);
  const diff = (out.getTime() - inn.getTime()) / (1000 * 60 * 60);
  return diff > 0 ? diff.toFixed(2) : null;
}

async function enrichRecord(a: typeof attendanceTable.$inferSelect) {
  const [emp] = await db
    .select({ firstName: employeesTable.firstName, lastName: employeesTable.lastName })
    .from(employeesTable)
    .where(eq(employeesTable.id, a.employeeId));
  return {
    ...a,
    employeeName: emp ? `${emp.firstName} ${emp.lastName}` : "Unknown",
    hoursWorked: a.hoursWorked ? parseFloat(a.hoursWorked) : null,
  };
}

router.get("/", async (req, res) => {
  const { employeeId, date } = req.query as { employeeId?: string; date?: string };
  const records = await db.select().from(attendanceTable);
  const enriched = await Promise.all(records.map(enrichRecord));

  let filtered = enriched;
  if (employeeId) filtered = filtered.filter((a) => a.employeeId === parseInt(employeeId));
  if (date) filtered = filtered.filter((a) => a.date === date);

  res.json(filtered);
});

router.post("/", async (req, res) => {
  const body = CreateAttendanceBody.parse(req.body);
  const hoursWorked = calcHours(body.checkIn, body.checkOut);
  const [record] = await db
    .insert(attendanceTable)
    .values({ ...body, hoursWorked })
    .returning();
  res.status(201).json(await enrichRecord(record));
});

router.put("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) { res.status(400).json({ error: "Invalid id" }); return; }

  const { status, checkIn, checkOut } = req.body as {
    status?: string;
    checkIn?: string | null;
    checkOut?: string | null;
  };

  const updateData: Partial<typeof attendanceTable.$inferInsert> = {};
  if (status !== undefined) updateData.status = status;
  if (checkIn !== undefined) updateData.checkIn = checkIn;
  if (checkOut !== undefined) updateData.checkOut = checkOut;
  if (checkIn !== undefined || checkOut !== undefined) {
    const existing = await db.select().from(attendanceTable).where(eq(attendanceTable.id, id));
    const rec = existing[0];
    const newIn = checkIn !== undefined ? checkIn : rec?.checkIn;
    const newOut = checkOut !== undefined ? checkOut : rec?.checkOut;
    updateData.hoursWorked = calcHours(newIn, newOut);
  }

  const [updated] = await db
    .update(attendanceTable)
    .set(updateData)
    .where(eq(attendanceTable.id, id))
    .returning();

  if (!updated) { res.status(404).json({ error: "Not found" }); return; }
  res.json(await enrichRecord(updated));
});

router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params["id"] ?? "");
  if (isNaN(id)) { res.status(400).json({ error: "Invalid id" }); return; }
  const [deleted] = await db.delete(attendanceTable).where(eq(attendanceTable.id, id)).returning();
  if (!deleted) { res.status(404).json({ error: "Not found" }); return; }
  res.json({ success: true });
});

export default router;
