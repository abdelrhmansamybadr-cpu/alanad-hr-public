import { Router, type IRouter } from "express";
import { db } from "@workspace/db";
import {
  requiredDocumentTypesTable,
  employeeDocumentsTable,
} from "@workspace/db/schema";
import { eq, asc } from "drizzle-orm";
import multer from "multer";
import path from "path";
import fs from "fs";
import { sessions } from "./auth";

const router: IRouter = Router();

const UPLOADS_DIR = path.resolve(process.cwd(), "uploads");

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
    const employeeId = req.params.employeeId as string;
    const employeeDir = path.join(UPLOADS_DIR, employeeId);
    if (!fs.existsSync(employeeDir)) {
      fs.mkdirSync(employeeDir, { recursive: true });
    }
    cb(null, employeeDir);
  },
  filename: (req, file, cb) => {
    const typeId = req.params.typeId as string;
    const timestamp = Date.now();
    const originalName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, "_");
    cb(null, `${typeId}_${timestamp}_${originalName}`);
  },
});

const upload = multer({ storage });

router.get("/types", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const types = await db
      .select({
        id: requiredDocumentTypesTable.id,
        label: requiredDocumentTypesTable.label,
        order: requiredDocumentTypesTable.order,
        createdAt: requiredDocumentTypesTable.createdAt,
      })
      .from(requiredDocumentTypesTable)
      .orderBy(asc(requiredDocumentTypesTable.order));
    res.json(types);
  } catch (err) {
    console.error("Error fetching document types:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/types", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const { label, order } = req.body ?? {};
    if (!label) {
      res.status(400).json({ error: "Label is required" });
      return;
    }

    const newOrder = order ?? 0;

    const [newType] = await db
      .insert(requiredDocumentTypesTable)
      .values({
        label,
        order: newOrder,
        createdAt: new Date().toISOString(),
      })
      .returning();

    res.status(201).json(newType);
  } catch (err) {
    console.error("Error creating document type:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.put("/types/:id", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const id = parseInt(req.params.id as string);
    const { label, order } = req.body ?? {};

    const updates: Record<string, any> = {};
    if (label !== undefined) updates.label = label;
    if (order !== undefined) updates.order = order;

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: "No fields to update" });
      return;
    }

    const [updated] = await db
      .update(requiredDocumentTypesTable)
      .set(updates)
      .where(eq(requiredDocumentTypesTable.id, id))
      .returning();
    if (!updated) {
      res.status(404).json({ error: "Document type not found" });
      return;
    }

    res.json(updated);
  } catch (err) {
    console.error("Error updating document type:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.delete("/types/:id", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const id = parseInt(req.params.id as string);
    await db
      .delete(requiredDocumentTypesTable)
      .where(eq(requiredDocumentTypesTable.id, id));
    res.status(204).end();
  } catch (err) {
    console.error("Error deleting document type:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.get("/employee/:employeeId", async (req, res): Promise<void> => {
  try {
    const userId = await requireAuth(req, res);
    if (!userId) return;

    const employeeId = parseInt(req.params.employeeId as string);

    const types = await db
      .select()
      .from(requiredDocumentTypesTable)
      .orderBy(asc(requiredDocumentTypesTable.order));
    const docs = await db
      .select()
      .from(employeeDocumentsTable)
      .where(eq(employeeDocumentsTable.employeeId, employeeId));

    const result = types.map((type) => {
      const doc = docs.find((d) => d.documentTypeId === type.id);
      return {
        typeId: type.id,
        label: type.label,
        order: type.order,
        document: doc
          ? {
              id: doc.id,
              fileName: doc.fileName,
              filePath: doc.filePath,
              mimeType: doc.mimeType,
              uploadedAt: doc.uploadedAt,
            }
          : null,
      };
    });

    res.json(result);
  } catch (err) {
    console.error("Error fetching employee documents:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post(
  "/employee/:employeeId/upload/:typeId",
  upload.single("file"),
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const employeeId = parseInt(req.params.employeeId as string);
      const typeId = parseInt(req.params.typeId as string);
      const file = req.file;

      if (!file) {
        res.status(400).json({ error: "No file uploaded" });
        return;
      }

      const relativePath = path
        .join(employeeId.toString(), file.filename)
        .replace(/\\/g, "/");

      const existingDocs = await db
        .select()
        .from(employeeDocumentsTable)
        .where(eq(employeeDocumentsTable.employeeId, employeeId));

      const existingDoc = existingDocs.find((d) => d.documentTypeId === typeId);

      if (existingDoc && existingDoc.filePath) {
        const oldFilePath = path.join(UPLOADS_DIR, existingDoc.filePath);
        if (fs.existsSync(oldFilePath)) {
          fs.unlinkSync(oldFilePath);
        }
        await db
          .delete(employeeDocumentsTable)
          .where(eq(employeeDocumentsTable.id, existingDoc.id));
      }

      const [newDoc] = await db
        .insert(employeeDocumentsTable)
        .values({
          employeeId,
          documentTypeId: typeId,
          fileName: file.originalname,
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
  "/employee/:employeeId/document/:documentId",
  async (req, res): Promise<void> => {
    try {
      const userId = await requireAuth(req, res);
      if (!userId) return;

      const documentId = parseInt(req.params.documentId as string);

      const [doc] = await db
        .select()
        .from(employeeDocumentsTable)
        .where(eq(employeeDocumentsTable.id, documentId));
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
        .delete(employeeDocumentsTable)
        .where(eq(employeeDocumentsTable.id, documentId));
      res.status(204).end();
    } catch (err) {
      console.error("Error deleting document:", err);
      res.status(500).json({ error: "Internal server error" });
    }
  },
);

export default router;
