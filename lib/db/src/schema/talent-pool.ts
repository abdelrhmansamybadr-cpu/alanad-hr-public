import { pgTable, serial, text, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const candidateDocumentsTable = pgTable("candidate_documents", {
  id: serial("id").primaryKey(),
  applicationId: integer("application_id").notNull(),
  fileName: text("file_name"),
  filePath: text("file_path"),
  mimeType: text("mime_type"),
  uploadedAt: text("uploaded_at"),
});

export const insertCandidateDocumentSchema = createInsertSchema(
  candidateDocumentsTable,
).omit({ id: true });
export type InsertCandidateDocument = z.infer<
  typeof insertCandidateDocumentSchema
>;
export type CandidateDocument = typeof candidateDocumentsTable.$inferSelect;
