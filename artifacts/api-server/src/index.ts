import app from "./app";
import { logger } from "./lib/logger";
import { initDb } from "@workspace/db";
import { seedAdminUser } from "./seed-users";

const port = Number(process.env["PORT"] || "3001");

if (Number.isNaN(port) || port <= 0) {
  throw new Error(`Invalid PORT value: "${process.env["PORT"]}"`);
}

initDb()
  .then(() => seedAdminUser())
  .then(() => {
    app.listen(port, (err) => {
      if (err) {
        logger.error({ err }, "Error listening on port");
        process.exit(1);
      }
      logger.info({ port }, "Server listening");
    });
  })
  .catch((err) => {
    logger.error({ err }, "Failed to initialize database");
    process.exit(1);
  });
