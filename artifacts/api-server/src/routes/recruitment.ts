import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import { jobsTable, applicationsTable, departmentsTable } from "@workspace/db/schema";
import { eq, sql } from "drizzle-orm";
import {
  CreateJobBody,
  CreateApplicationBody,
  UpdateApplicationBody,
} from "@workspace/api-zod";

const router: IRouter = Router();

// Jobs
router.get("/jobs", async (_req, res) => {
  const jobs = await db
    .select({
      id: jobsTable.id,
      title: jobsTable.title,
      departmentId: jobsTable.departmentId,
      departmentName: departmentsTable.name,
      location: jobsTable.location,
      type: jobsTable.type,
      description: jobsTable.description,
      requirements: jobsTable.requirements,
      salary: jobsTable.salary,
      status: jobsTable.status,
      postedAt: jobsTable.postedAt,
    })
    .from(jobsTable)
    .leftJoin(departmentsTable, eq(jobsTable.departmentId, departmentsTable.id));

  const counts = await db
    .select({ jobId: applicationsTable.jobId, count: sql<number>`count(*)::int` })
    .from(applicationsTable)
    .groupBy(applicationsTable.jobId);

  const countMap = Object.fromEntries(counts.map((c) => [c.jobId, c.count]));

  res.json(jobs.map((j) => ({ ...j, applicantCount: countMap[j.id] ?? 0 })));
});

router.post("/jobs", async (req, res) => {
  const body = CreateJobBody.parse(req.body);
  const postedAt = new Date().toISOString().split("T")[0];
  const [job] = await db.insert(jobsTable).values({ ...body, postedAt }).returning();
  res.status(201).json({ ...job, applicantCount: 0, departmentName: null });
});

router.delete("/jobs/:id", async (req, res) => {
  const id = parseInt(req.params.id);
  await db.delete(jobsTable).where(eq(jobsTable.id, id));
  res.status(204).end();
});

// Applications
router.get("/applications", async (req, res) => {
  const { jobId, status } = req.query as { jobId?: string; status?: string };

  const apps = await db
    .select({
      id: applicationsTable.id,
      jobId: applicationsTable.jobId,
      jobTitle: jobsTable.title,
      applicantName: applicationsTable.applicantName,
      email: applicationsTable.email,
      phone: applicationsTable.phone,
      resumeUrl: applicationsTable.resumeUrl,
      coverLetter: applicationsTable.coverLetter,
      status: applicationsTable.status,
      appliedAt: applicationsTable.appliedAt,
    })
    .from(applicationsTable)
    .leftJoin(jobsTable, eq(applicationsTable.jobId, jobsTable.id));

  let filtered = apps;
  if (jobId) filtered = filtered.filter((a) => a.jobId === parseInt(jobId));
  if (status) filtered = filtered.filter((a) => a.status === status);

  res.json(filtered);
});

router.post("/applications", async (req, res) => {
  const body = CreateApplicationBody.parse(req.body);
  const appliedAt = new Date().toISOString().split("T")[0];
  const [app] = await db.insert(applicationsTable).values({ ...body, appliedAt }).returning();

  let jobTitle = "Unknown";
  if (app.jobId) {
    const [job] = await db
      .select({ title: jobsTable.title })
      .from(jobsTable)
      .where(eq(jobsTable.id, app.jobId));
    jobTitle = job?.title ?? "Unknown";
  }

  res.status(201).json({ ...app, jobTitle });
});

router.put("/applications/:id", async (req, res): Promise<void> => {
  const id = parseInt(req.params.id);
  const body = UpdateApplicationBody.parse(req.body);
  const [app] = await db
    .update(applicationsTable)
    .set(body)
    .where(eq(applicationsTable.id, id))
    .returning();
  if (!app) { res.status(404).json({ error: "Not found" }); return; }

  let jobTitle = "Unknown";
  if (app.jobId) {
    const [job] = await db
      .select({ title: jobsTable.title })
      .from(jobsTable)
      .where(eq(jobsTable.id, app.jobId));
    jobTitle = job?.title ?? "Unknown";
  }

  res.json({ ...app, jobTitle });
});

export default router;
