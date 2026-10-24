import {
  pgTable,
  serial,
  text,
  boolean,
  integer,
  uniqueIndex,
} from "drizzle-orm/pg-core";

export const userPermissionsTable = pgTable(
  "user_permissions",
  {
    id: serial("id").primaryKey(),
    userId: integer("user_id").notNull(),
    module: text("module").notNull(),
    enabled: boolean("enabled").notNull().default(true),
  },
  (table) => ({
    uniqueUserModule: uniqueIndex("user_permissions_user_module_unique").on(
      table.userId,
      table.module,
    ),
  }),
);

export type UserPermission = typeof userPermissionsTable.$inferSelect;
