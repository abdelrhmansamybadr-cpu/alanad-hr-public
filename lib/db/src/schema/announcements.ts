import { pgTable, serial, text, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const announcementsTable = pgTable("announcements", {
  id: serial("id").primaryKey(),
  title: text("title").notNull(),
  content: text("content").notNull(),
  authorId: integer("author_id"),
  authorName: text("author_name").notNull(),
  priority: text("priority").notNull().default("medium"),
  createdAt: text("created_at").notNull(),
});

export const insertAnnouncementSchema = createInsertSchema(announcementsTable).omit({ id: true });
export type InsertAnnouncement = z.infer<typeof insertAnnouncementSchema>;
export type Announcement = typeof announcementsTable.$inferSelect;
