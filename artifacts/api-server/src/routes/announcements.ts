import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { announcementsTable } from "@workspace/db/schema";
import { eq } from "drizzle-orm";
import { CreateAnnouncementBody } from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/", async (_req, res) => {
  const announcements = await db
    .select()
    .from(announcementsTable)
    .orderBy(announcementsTable.id);
  res.json(announcements.reverse());
});

router.post("/", async (req, res) => {
  const body = CreateAnnouncementBody.parse(req.body);
  const createdAt = new Date().toISOString();
  const [announcement] = await db
    .insert(announcementsTable)
    .values({ ...body, createdAt })
    .returning();
  res.status(201).json(announcement);
});

router.delete("/:id", async (req, res) => {
  const id = parseInt(req.params.id);
  await db.delete(announcementsTable).where(eq(announcementsTable.id, id));
  res.status(204).end();
});

export default router;
