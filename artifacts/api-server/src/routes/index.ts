import { Router, type IRouter } from "express";
import healthRouter from "./health";
import employees from "./employees";
import departments from "./departments";
import leaves from "./leaves";
import recruitment from "./recruitment";
import reviews from "./reviews";
import payroll from "./payroll";
import announcements from "./announcements";
import attendance from "./attendance";
import stats from "./stats";
import auth from "./auth";
import shifts from "./shifts";
import documents from "./documents";
import talentPool from "./talent-pool";
import hrStaff from "./hr-staff";
import attendanceRules from "./attendance-rules";

const router: IRouter = Router();

router.use(healthRouter);
router.use("/auth", auth);
router.use("/employees", employees);
router.use("/departments", departments);
router.use("/leaves", leaves);
router.use("/", recruitment);
router.use("/reviews", reviews);
router.use("/payroll", payroll);
router.use("/announcements", announcements);
router.use("/attendance", attendance);
router.use("/stats", stats);
router.use("/shifts", shifts);
router.use("/documents", documents);
router.use("/talent-pool", talentPool);
router.use("/hr-staff", hrStaff);
router.use("/attendance-rules", attendanceRules);

export default router;
