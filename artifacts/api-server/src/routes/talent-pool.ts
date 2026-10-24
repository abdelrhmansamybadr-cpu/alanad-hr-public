import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import {
  departmentsTable,
  jobsTable,
  applicationsTable,
  candidateDocumentsTable,
  employeesTable,
} from "@workspace/db/schema";
import { eq, sql, inArray, notInArray, and, isNotNull } from "drizzle-orm";
import multer from "multer";
import path from "path";
import fs from "fs";
import { sessions } from "./auth";

const router: IRouter = Router();

const UPLOADS_DIR = path.resolve(process.cwd(), "uploads/candidates");

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

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const appId = req.params.id as string;
    const appDir = path.join(UPLOADS_DIR, appId);
    if (!fs.existsSync(appDir)) {
      fs.mkdirSync(appDir, { recursive: true });
    }
    cb(null, appDir);
  },
  filename: (req, file, cb) => {
    const timestamp = Date.now();
    const originalName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, "_");
    cb(null, `${timestamp}_${originalName}`);
  },
});

const upload = multer({ storage });

interface DepartmentOverview {
  departmentId: number;
  departmentName: string;
  jobs: {
    jobId: number;
    jobTitle: string;
    counts: Record<string, number>;
  }[];
}

router.get("/overview", async (_req, res): Promise<void> => {
  try {
    const departments = await db.select().from(departmentsTable);
    const jobs = await db
      .select({
        id: jobsTable.id,
        title: jobsTable.title,
        departmentId: jobsTable.departmentId,
      })
      .from(jobsTable);

    const allStatuses = [
      "new",
      "screening",
      "interview",
      "offer",
      "hired",
      "rejected",
      "talent_pool",
    ];

    const statusCounts = await db
      .select({
        jobId: applicationsTable.jobId,
        status: applicationsTable.status,
        count: sql<number>`count(*)::int`,
      })
      .from(applicationsTable)
      .groupBy(applicationsTable.jobId, applicationsTable.status);

    const countMap: Record<string, Record<string, number>> = {};
    statusCounts.forEach((sc) => {
      if (sc.jobId === null) return;
      const key = sc.jobId.toString();
      if (!countMap[key]) countMap[key] = {};
      countMap[key][sc.status] = sc.count;
    });

    const jobsByDept: Record<
      number,
      { jobId: number; jobTitle: string; counts: Record<string, number> }[]
    > = {};
    jobs.forEach((j) => {
      if (!jobsByDept[j.departmentId]) jobsByDept[j.departmentId] = [];
      const jobCounts: Record<string, number> = {};
      allStatuses.forEach((s) => {
        jobCounts[s] = countMap[j.id.toString()]?.[s] ?? 0;
      });
      jobsByDept[j.departmentId].push({
        jobId: j.id,
        jobTitle: j.title,
        counts: jobCounts,
      });
    });

    const overview: DepartmentOverview[] = departments.map((dept) => ({
      departmentId: dept.id,
      departmentName: dept.name,
      jobs: jobsByDept[dept.id] ?? [],
    }));

    res.json(overview);
  } catch (err) {
    console.error("Error fetching talent pool overview:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

interface ListCandidatesParams {
  departmentId?: string;
  jobId?: string;
  status?: string;
  search?: string;
}

interface CandidateWithDetails {
  id: number;
  applicantName: string;
  email: string;
  phone: string | null;
  resumeUrl: string | null;
  coverLetter: string | null;
  notes: string | null;
  status: string;
  appliedAt: string;
  jobId: number | null;
  jobTitle: string;
  departmentId: number;
  departmentName: string;
  documents: {
    id: number;
    fileName: string;
    filePath: string;
    mimeType: string;
    uploadedAt: string;
  }[];
}

router.get("/candidates", async (req, res): Promise<void> => {
  try {
    const { departmentId, jobId, status, search } =
      req.query as ListCandidatesParams;

    const apps = await db
      .select({
        id: applicationsTable.id,
        jobId: applicationsTable.jobId,
        applicantName: applicationsTable.applicantName,
        email: applicationsTable.email,
        phone: applicationsTable.phone,
        resumeUrl: applicationsTable.resumeUrl,
        coverLetter: applicationsTable.coverLetter,
        status: applicationsTable.status,
        notes: applicationsTable.notes,
        appliedAt: applicationsTable.appliedAt,
        jobTitle: jobsTable.title,
        departmentId: jobsTable.departmentId,
        departmentName: departmentsTable.name,
      })
      .from(applicationsTable)
      .leftJoin(jobsTable, eq(applicationsTable.jobId, jobsTable.id))
      .leftJoin(
        departmentsTable,
        eq(jobsTable.departmentId, departmentsTable.id),
      );

    let filtered = apps;

    if (departmentId) {
      filtered = filtered.filter(
        (a) => a.departmentId === parseInt(departmentId),
      );
    }
    if (jobId) {
      filtered = filtered.filter((a) => a.jobId === parseInt(jobId));
    }
    if (status) {
      filtered = filtered.filter((a) => a.status === status);
    }
    if (search) {
      const searchLower = search.toLowerCase();
      filtered = filtered.filter(
        (a) =>
          a.applicantName.toLowerCase().includes(searchLower) ||
          a.email.toLowerCase().includes(searchLower),
      );
    }

    const docs = await db.select().from(candidateDocumentsTable);
    const docsByApp: Record<number, CandidateWithDetails["documents"]> = {};
    docs.forEach((d) => {
      if (!docsByApp[d.applicationId]) docsByApp[d.applicationId] = [];
      docsByApp[d.applicationId].push({
        id: d.id,
        fileName: d.fileName ?? "",
        filePath: d.filePath ?? "",
        mimeType: d.mimeType ?? "",
        uploadedAt: d.uploadedAt ?? "",
      });
    });

    const result: CandidateWithDetails[] = filtered.map((a) => ({
      id: a.id,
      applicantName: a.applicantName,
      email: a.email,
      phone: a.phone,
      resumeUrl: a.resumeUrl,
      coverLetter: a.coverLetter,
      notes: a.notes,
      status: a.status,
      appliedAt: a.appliedAt,
      jobId: a.jobId,
      jobTitle: a.jobTitle ?? "Unknown",
      departmentId: a.departmentId ?? 0,
      departmentName: a.departmentName ?? "Unknown",
      documents: docsByApp[a.id] ?? [],
    }));

    res.json(result);
  } catch (err) {
    console.error("Error fetching candidates:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

interface UpdateCandidateBody {
  status?: string;
  notes?: string;
}

router.put("/candidates/:id", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const id = parseInt(req.params.id);
    const { status, notes } = req.body as UpdateCandidateBody;

    const updates: Record<string, any> = {};
    if (status !== undefined) updates.status = status;
    if (notes !== undefined) updates.notes = notes;

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: "No fields to update" });
      return;
    }

    const [updated] = await db
      .update(applicationsTable)
      .set(updates)
      .where(eq(applicationsTable.id, id))
      .returning();

    if (!updated) {
      res.status(404).json({ error: "Candidate not found" });
      return;
    }

    let jobTitle = "Unknown";
    if (updated.jobId) {
      const [job] = await db
        .select({ title: jobsTable.title })
        .from(jobsTable)
        .where(eq(jobsTable.id, updated.jobId));
      jobTitle = job?.title ?? "Unknown";
    }

    res.json({ ...updated, jobTitle });
  } catch (err) {
    console.error("Error updating candidate:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post(
  "/candidates/:id/hire-as-employee",
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const id = parseInt(req.params.id);

      const [app] = await db
        .select({
          id: applicationsTable.id,
          applicantName: applicationsTable.applicantName,
          email: applicationsTable.email,
          phone: applicationsTable.phone,
          jobId: applicationsTable.jobId,
          directDepartmentId: applicationsTable.directDepartmentId,
          directJobTitle: applicationsTable.directJobTitle,
        })
        .from(applicationsTable)
        .where(eq(applicationsTable.id, id));

      if (!app) {
        res.status(404).json({ error: "Candidate not found" });
        return;
      }

      let position = app.directJobTitle || "Employee";
      let departmentId = app.directDepartmentId || 1;

      if (app.jobId) {
        const [job] = await db
          .select({
            title: jobsTable.title,
            departmentId: jobsTable.departmentId,
          })
          .from(jobsTable)
          .where(eq(jobsTable.id, app.jobId));
        if (job) {
          position = job.title;
          departmentId = job.departmentId;
        }
      }

      const nameParts = app.applicantName.trim().split(/\s+/);
      const firstName = nameParts[0] ?? app.applicantName;
      const lastName = nameParts.slice(1).join(" ") || "-";
      const startDate = new Date().toISOString().split("T")[0];

      const [employee] = await db
        .insert(employeesTable)
        .values({
          firstName,
          lastName,
          email: app.email,
          phone: app.phone ?? null,
          position,
          departmentId,
          status: "active",
          startDate,
        })
        .returning();

      await db
        .update(applicationsTable)
        .set({ status: "hired" })
        .where(eq(applicationsTable.id, id));

      res.status(201).json(employee);
    } catch (err) {
      console.error("Error hiring candidate as employee:", err);
      const message =
        err instanceof Error ? err.message : "Internal server error";
      res.status(500).json({ error: message });
    }
  },
);

router.delete("/candidates/:id", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const id = parseInt(req.params.id);

    const docs = await db
      .select()
      .from(candidateDocumentsTable)
      .where(eq(candidateDocumentsTable.applicationId, id));

    for (const doc of docs) {
      if (doc.filePath) {
        const filePath = path.join(UPLOADS_DIR, doc.filePath);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      }
      await db
        .delete(candidateDocumentsTable)
        .where(eq(candidateDocumentsTable.id, doc.id));
    }

    const appDir = path.join(UPLOADS_DIR, id.toString());
    if (fs.existsSync(appDir)) {
      fs.rmSync(appDir, { recursive: true, force: true });
    }

    await db.delete(applicationsTable).where(eq(applicationsTable.id, id));
    res.status(204).end();
  } catch (err) {
    console.error("Error deleting candidate:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post(
  "/candidates/:id/documents",
  upload.single("file"),
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const idParam = req.params.id;
      const id = Array.isArray(idParam)
        ? parseInt(idParam[0])
        : parseInt(idParam);
      const file = req.file;

      if (!file) {
        res.status(400).json({ error: "No file uploaded" });
        return;
      }

      const fileName = Array.isArray(file.originalname)
        ? file.originalname[0]
        : file.originalname;
      const fileNameStr = Array.isArray(file.filename)
        ? file.filename[0]
        : file.filename;

      const relativePath = path
        .join(id.toString(), fileNameStr)
        .replace(/\\/g, "/");

      const [newDoc] = await db
        .insert(candidateDocumentsTable)
        .values({
          applicationId: id,
          fileName: fileName,
          filePath: relativePath,
          mimeType: file.mimetype,
          uploadedAt: new Date().toISOString(),
        })
        .returning();

      res.status(201).json({
        id: newDoc.id,
        fileName: newDoc.fileName,
        filePath: newDoc.filePath,
        mimeType: newDoc.mimeType,
        uploadedAt: newDoc.uploadedAt,
      });
    } catch (err) {
      console.error("Error uploading document:", err);
      res.status(500).json({ error: "Internal server error" });
    }
  },
);

router.delete(
  "/candidates/:id/documents/:docId",
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const docId = parseInt(req.params.docId);

      const [doc] = await db
        .select()
        .from(candidateDocumentsTable)
        .where(eq(candidateDocumentsTable.id, docId));

      if (!doc) {
        res.status(404).json({ error: "Document not found" });
        return;
      }

      if (doc.filePath) {
        const filePath = path.join(UPLOADS_DIR, doc.filePath);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      }

      await db
        .delete(candidateDocumentsTable)
        .where(eq(candidateDocumentsTable.id, docId));

      res.status(204).end();
    } catch (err) {
      console.error("Error deleting document:", err);
      res.status(500).json({ error: "Internal server error" });
    }
  },
);

// ======================
// New Talent Bank APIs
// ======================

interface DepartmentWithCount {
  id: number;
  name: string;
  description: string | null;
  waitingCount: number;
  managerName: string | null;
  employeeCount: number;
}

// Get all departments with waiting candidate counts
router.get("/talent-bank/departments", async (_req, res): Promise<void> => {
  try {
    const departments = await db.select().from(departmentsTable);

    // Count candidates not in hired/rejected status per department
    // 1. Via job -> department mapping
    const talentPoolViaJob = await db
      .select({
        jobId: applicationsTable.jobId,
        count: sql<number>`count(*)::int`,
      })
      .from(applicationsTable)
      .where(notInArray(applicationsTable.status, ["hired", "rejected"]))
      .groupBy(applicationsTable.jobId);

    const jobs = await db
      .select({ id: jobsTable.id, departmentId: jobsTable.departmentId })
      .from(jobsTable);

    const jobDeptMap: Record<number, number> = {};
    jobs.forEach((j) => {
      jobDeptMap[j.id] = j.departmentId;
    });

    const deptCounts: Record<number, number> = {};
    talentPoolViaJob.forEach((sc) => {
      if (sc.jobId !== null) {
        const deptId = jobDeptMap[sc.jobId];
        if (deptId) deptCounts[deptId] = (deptCounts[deptId] || 0) + sc.count;
      }
    });

    // 2. Via direct_department_id (count all non-hired/rejected)
    const talentPoolDirect = await db
      .select({
        directDepartmentId: applicationsTable.directDepartmentId,
        count: sql<number>`count(*)::int`,
      })
      .from(applicationsTable)
      .where(
        and(
          notInArray(applicationsTable.status, ["hired", "rejected"]),
          isNotNull(applicationsTable.directDepartmentId),
        ),
      )
      .groupBy(applicationsTable.directDepartmentId);

    talentPoolDirect.forEach((sc) => {
      if (sc.directDepartmentId) {
        deptCounts[sc.directDepartmentId] =
          (deptCounts[sc.directDepartmentId] || 0) + sc.count;
      }
    });

    // Get employee count per department
    const employeeCounts = await db
      .select({
        departmentId: employeesTable.departmentId,
        count: sql<number>`count(*)::int`,
      })
      .from(employeesTable)
      .groupBy(employeesTable.departmentId);

    const empCountMap: Record<number, number> = {};
    employeeCounts.forEach((ec) => {
      empCountMap[ec.departmentId] = ec.count;
    });

    const result: DepartmentWithCount[] = departments.map((dept) => ({
      id: dept.id,
      name: dept.name,
      description: dept.description,
      waitingCount: deptCounts[dept.id] || 0,
      managerName: null,
      employeeCount: empCountMap[dept.id] || 0,
    }));

    res.json(result);
  } catch (err) {
    console.error("Error fetching talent bank departments:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get candidates for a specific department
router.get("/talent-bank/department/:id", async (req, res): Promise<void> => {
  try {
    const deptId = parseInt(req.params.id);
    if (isNaN(deptId)) {
      res.status(400).json({ error: "Invalid department ID" });
      return;
    }

    // Get jobs for this department
    const deptJobs = await db
      .select({ id: jobsTable.id, title: jobsTable.title })
      .from(jobsTable)
      .where(eq(jobsTable.departmentId, deptId));

    const jobIds = deptJobs.map((j) => j.id);
    const jobTitles: Record<number, string> = {};
    deptJobs.forEach((j) => {
      jobTitles[j.id] = j.title;
    });

    // Get department name
    const [dept] = await db
      .select({ name: departmentsTable.name })
      .from(departmentsTable)
      .where(eq(departmentsTable.id, deptId));

    const deptName = dept?.name || "Unknown";

    // Fetch candidates: via job OR via direct_department_id
    let candidates: {
      id: number;
      applicantName: string;
      email: string;
      phone: string | null;
      resumeUrl: string | null;
      coverLetter: string | null;
      notes: string | null;
      status: string;
      appliedAt: string;
      jobId: number | null;
      directDepartmentId: number | null;
      directJobTitle: string | null;
    }[] = [];

    if (jobIds.length > 0) {
      const viaJob = await db
        .select({
          id: applicationsTable.id,
          applicantName: applicationsTable.applicantName,
          email: applicationsTable.email,
          phone: applicationsTable.phone,
          resumeUrl: applicationsTable.resumeUrl,
          coverLetter: applicationsTable.coverLetter,
          notes: applicationsTable.notes,
          status: applicationsTable.status,
          appliedAt: applicationsTable.appliedAt,
          jobId: applicationsTable.jobId,
          directDepartmentId: applicationsTable.directDepartmentId,
          directJobTitle: applicationsTable.directJobTitle,
        })
        .from(applicationsTable)
        .where(
          and(
            inArray(applicationsTable.jobId, jobIds),
            notInArray(applicationsTable.status, ["hired", "rejected"]),
          ),
        );
      candidates.push(...viaJob);
    }

    // Direct candidates (no job, directly added to department)
    const directCandidates = await db
      .select({
        id: applicationsTable.id,
        applicantName: applicationsTable.applicantName,
        email: applicationsTable.email,
        phone: applicationsTable.phone,
        resumeUrl: applicationsTable.resumeUrl,
        coverLetter: applicationsTable.coverLetter,
        notes: applicationsTable.notes,
        status: applicationsTable.status,
        appliedAt: applicationsTable.appliedAt,
        jobId: applicationsTable.jobId,
        directDepartmentId: applicationsTable.directDepartmentId,
        directJobTitle: applicationsTable.directJobTitle,
      })
      .from(applicationsTable)
      .where(
        and(
          eq(applicationsTable.directDepartmentId, deptId),
          notInArray(applicationsTable.status, ["hired", "rejected"]),
        ),
      );
    candidates.push(...directCandidates);

    // Deduplicate by id
    const seen = new Set<number>();
    candidates = candidates.filter((c) => {
      if (seen.has(c.id)) return false;
      seen.add(c.id);
      return true;
    });

    // Get documents
    const candidateIds = candidates.map((c) => c.id);
    let docs: (typeof candidateDocumentsTable.$inferSelect)[] = [];
    if (candidateIds.length > 0) {
      docs = await db
        .select()
        .from(candidateDocumentsTable)
        .where(inArray(candidateDocumentsTable.applicationId, candidateIds));
    }

    const docsByApp: Record<number, typeof docs> = {};
    docs.forEach((d) => {
      if (!docsByApp[d.applicationId]) docsByApp[d.applicationId] = [];
      docsByApp[d.applicationId].push(d);
    });

    const result = candidates.map((c) => ({
      id: c.id,
      applicantName: c.applicantName,
      email: c.email,
      phone: c.phone,
      resumeUrl: c.resumeUrl,
      coverLetter: c.coverLetter,
      notes: c.notes,
      status: c.status,
      appliedAt: c.appliedAt,
      jobId: c.jobId,
      jobTitle: c.jobId
        ? jobTitles[c.jobId] || "Unknown"
        : c.directJobTitle || "",
      departmentId: deptId,
      departmentName: deptName,
      documents: (docsByApp[c.id] || []).map((d) => ({
        id: d.id,
        fileName: d.fileName || "",
        filePath: d.filePath || "",
        mimeType: d.mimeType || "",
        uploadedAt: d.uploadedAt || "",
      })),
    }));

    res.json(result);
  } catch (err) {
    console.error("Error fetching department candidates:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Create a new candidate (for Talent Bank)
interface CreateCandidateBody {
  applicantName: string;
  email: string;
  phone?: string;
  departmentId: number;
  jobTitle?: string;
  notes?: string;
  coverLetter?: string;
}

router.post("/talent-bank/candidates", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const {
      applicantName,
      email,
      phone,
      departmentId,
      jobTitle,
      notes,
      coverLetter,
    } = req.body as CreateCandidateBody;

    if (!applicantName || !email || !departmentId) {
      res.status(400).json({ error: "Missing required fields" });
      return;
    }

    const [dept] = await db
      .select({ name: departmentsTable.name })
      .from(departmentsTable)
      .where(eq(departmentsTable.id, departmentId));

    if (!dept) {
      res.status(400).json({ error: "Department not found" });
      return;
    }

    const [newCandidate] = await db
      .insert(applicationsTable)
      .values({
        jobId: null,
        applicantName,
        email,
        phone: phone || null,
        coverLetter: coverLetter || null,
        notes: notes || null,
        status: "talent_pool",
        appliedAt: new Date().toISOString(),
        directDepartmentId: departmentId,
        directJobTitle: jobTitle || null,
      })
      .returning();

    res.status(201).json({
      ...newCandidate,
      jobTitle: jobTitle || "",
      departmentId,
      departmentName: dept.name,
      documents: [],
    });
  } catch (err) {
    console.error("Error creating candidate:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Update a candidate
interface UpdateCandidateBody {
  status?: string;
  notes?: string;
}

router.put("/talent-bank/candidates/:id", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const id = parseInt(req.params.id);
    const { status, notes } = req.body as UpdateCandidateBody;

    const updates: Record<string, any> = {};
    if (status !== undefined) updates.status = status;
    if (notes !== undefined) updates.notes = notes;

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: "No fields to update" });
      return;
    }

    const [updated] = await db
      .update(applicationsTable)
      .set(updates)
      .where(eq(applicationsTable.id, id))
      .returning();

    if (!updated) {
      res.status(404).json({ error: "Candidate not found" });
      return;
    }

    let jobTitle = updated.directJobTitle || "";
    let departmentId = updated.directDepartmentId || 0;
    let departmentName = "Unknown";

    if (updated.jobId) {
      const [job] = await db
        .select({
          title: jobsTable.title,
          departmentId: jobsTable.departmentId,
        })
        .from(jobsTable)
        .where(eq(jobsTable.id, updated.jobId));
      if (job) {
        jobTitle = job.title;
        departmentId = job.departmentId;
      }
    }

    if (departmentId) {
      const [dept] = await db
        .select({ name: departmentsTable.name })
        .from(departmentsTable)
        .where(eq(departmentsTable.id, departmentId));
      if (dept) departmentName = dept.name;
    }

    res.json({
      ...updated,
      jobTitle,
      departmentId,
      departmentName,
    });
  } catch (err) {
    console.error("Error updating candidate:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Delete a candidate
router.delete(
  "/talent-bank/candidates/:id",
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const id = parseInt(req.params.id);

      // Delete documents first
      const docs = await db
        .select()
        .from(candidateDocumentsTable)
        .where(eq(candidateDocumentsTable.applicationId, id));

      for (const doc of docs) {
        if (doc.filePath) {
          const filePath = path.join(UPLOADS_DIR, doc.filePath);
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
          }
        }
        await db
          .delete(candidateDocumentsTable)
          .where(eq(candidateDocumentsTable.id, doc.id));
      }

      // Delete candidate
      await db.delete(applicationsTable).where(eq(applicationsTable.id, id));

      res.status(204).end();
    } catch (err) {
      console.error("Error deleting candidate:", err);
      res.status(500).json({ error: "Internal server error" });
    }
  },
);

export default router;
