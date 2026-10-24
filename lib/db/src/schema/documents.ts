import { pgTable, serial, text, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const requiredDocumentTypesTable = pgTable("required_document_types", {
  id: serial("id").primaryKey(),
  label: text("label").notNull(),
  order: integer("order_num").notNull().default(0),
  createdAt: text("created_at"),
});

export const insertRequiredDocumentTypeSchema = createInsertSchema(
  requiredDocumentTypesTable,
).omit({ id: true, createdAt: true });
export type InsertRequiredDocumentType = z.infer<
  typeof insertRequiredDocumentTypeSchema
>;
export type RequiredDocumentType =
  typeof requiredDocumentTypesTable.$inferSelect;

export const employeeDocumentsTable = pgTable("employee_documents", {
  id: serial("id").primaryKey(),
  employeeId: integer("employee_id").notNull(),
  documentTypeId: integer("document_type_id").notNull(),
  fileName: text("file_name"),
  filePath: text("file_path"),
  mimeType: text("mime_type"),
  uploadedAt: text("uploaded_at"),
});

export const insertEmployeeDocumentSchema = createInsertSchema(
  employeeDocumentsTable,
).omit({ id: true, uploadedAt: true });
export type InsertEmployeeDocument = z.infer<
  typeof insertEmployeeDocumentSchema
>;
export type EmployeeDocument = typeof employeeDocumentsTable.$inferSelect;
