import {
  createContext,
  useContext,
  useState,
  useEffect,
  ReactNode,
} from "react";

export type Language = "ar" | "en";

interface Translations {
  // Auth
  signIn: string;
  signInWithWindowsHello: string;
  signOut: string;
  signUp: string;
  loginTitle: string;
  loginSubtitle: string;
  registerTitle: string;
  registerSubtitle: string;
  fullName: string;
  emailAddress: string;
  password: string;
  confirmPassword: string;
  signingIn: string;
  signingInWithPasskey: string;
  registering: string;
  noAccount: string;
  hasAccount: string;
  loginError: string;
  passwordMismatch: string;
  myProfile: string;
  editProfile: string;
  changePassword: string;
  currentPassword: string;
  newPassword: string;
  confirmNewPassword: string;
  saveChanges: string;
  savingChanges: string;
  profileSaved: string;
  passwordChanged: string;
  wrongCurrentPassword: string;
  hrAdmin: string;
  myAccount: string;
  profileInfo: string;
  securitySettings: string;
  memberSince: string;

  // Notifications
  notifications: string;
  notifMarkAllRead: string;
  notifClearAll: string;
  notifEmpty: string;
  notifPermissionTitle: string;
  notifPermissionDesc: string;
  notifPermissionAllow: string;
  notifJustNow: string;
  notifMinAgo: string;
  notifHrAgo: string;
  notifDayAgo: string;

  // Nav
  dashboard: string;
  employees: string;
  departments: string;
  timeLeave: string;
  recruitment: string;
  reviews: string;
  payroll: string;
  attendance: string;
  announcements: string;
  needHelp: string;
  helpDesc: string;
  viewDocs: string;
  helpTitle: string;
  helpFaqTab: string;
  helpFeedbackTab: string;
  feedbackType: string;
  feedbackTypeFeedback: string;
  feedbackTypeBug: string;
  feedbackTypeFeature: string;
  feedbackMessage: string;
  feedbackPlaceholder: string;
  feedbackSend: string;
  feedbackSuccess: string;
  faq1Q: string;
  faq1A: string;
  faq2Q: string;
  faq2A: string;
  faq3Q: string;
  faq3A: string;
  faq4Q: string;
  faq4A: string;
  faq5Q: string;
  faq5A: string;
  faq6Q: string;
  faq6A: string;

  // Header
  searchPlaceholder: string;
  hrDirector: string;

  // Dashboard
  overview: string;
  welcomeBack: string;
  goodMorning: string;
  goodAfternoon: string;
  goodEvening: string;
  totalEmployees: string;
  activeEmployees: string;
  onLeaveToday: string;
  openPositions: string;
  pendingLeaves: string;
  newApplications: string;
  upcomingReviews: string;
  totalPayroll: string;
  vsLastMonth: string;
  recentActivity: string;
  viewAll: string;
  companyNews: string;
  noRecentActivity: string;
  totalDepartments: string;
  attendanceToday: string;
  talentPoolCount: string;
  justNow: string;
  minutesAgo: string;
  hoursAgo: string;
  daysAgo: string;
  newAppReceived: string;
  softwareEngineerRole: string;
  leaveApproved: string;
  michaelChenLeave: string;
  reviewSubmitted: string;
  sarahJenkinsReview: string;
  payrollProcessed: string;
  octoberPayroll: string;
  officeClosure: string;
  officeClosureDesc: string;
  townhallMeeting: string;
  townhallDesc: string;
  minsAgo: string;
  hoursAgo2: string;
  hoursAgo5: string;
  dayAgo: string;
  urgent: string;
  statusPending: string;
  statusApproved: string;
  statusRejected: string;
  statusNew: string;
  statusDraft: string;
  statusPaid: string;
  serverError: string;

  // Employees
  employeesTitle: string;
  manageTeam: string;
  addEmployee: string;
  searchEmployees: string;
  total: string;
  employee: string;
  contact: string;
  department: string;
  status: string;
  actions: string;
  loadingEmployees: string;
  noEmployeesFound: string;
  active: string;
  on_leave: string;
  inactive: string;
  unassigned: string;
  addNewEmployee: string;
  editEmployee: string;
  enterDetails: string;
  updateEmployeeDetails: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  position: string;
  selectDepartment: string;
  startDate: string;
  salary: string;
  cancel: string;
  save: string;
  saving: string;
  deleteConfirm: string;
  delete: string;
  papers: string;
  requiredDocuments: string;
  uploadFile: string;
  preview: string;
  download: string;
  uploaded: string;
  missing: string;
  manageDocTypes: string;
  addDocType: string;
  deleteDocType: string;

  // Departments
  departmentsTitle: string;
  manageDepts: string;
  addDepartment: string;
  deptName: string;
  manager: string;
  employeeCount: string;
  noDepts: string;
  addNewDept: string;
  deptDesc: string;
  description: string;
  managerId: string;
  employees2: string;
  noManager: string;

  // Leaves
  leaveManagement: string;
  reviewManage: string;
  requestLeave: string;
  all: string;
  pending: string;
  approved: string;
  rejected: string;
  leaveDetails: string;
  datesDuration: string;
  loading: string;
  noLeaves: string;
  daysRequested: string;
  processed: string;
  newLeaveRequest: string;
  selectEmployee: string;
  leaveType: string;
  annual: string;
  sick: string;
  unpaid: string;
  maternity: string;
  paternity: string;
  other: string;
  endDate: string;
  reason: string;
  reasonOptional: string;
  submitRequest: string;

  // Recruitment
  recruitmentTitle: string;
  manageRecruitment: string;
  postJob: string;
  jobPostings: string;
  applicants: string;
  applicantsCount: string;
  location: string;
  type: string;
  jobStatus: string;
  open: string;
  closed: string;
  on_hold: string;
  full_time: string;
  part_time: string;
  contract: string;
  internship: string;
  noJobs: string;
  newJobPosting: string;
  jobTitle: string;
  requirements: string;
  salaryRange: string;
  createJob: string;
  appStatus: string;
  new2: string;
  screening: string;
  interview: string;
  offer: string;
  hired: string;
  appliedOn: string;
  noApplicants: string;
  backToJobs: string;
  viewApplicants: string;
  updateStatus: string;
  jobDept: string;
  jobType: string;
  jobLocation: string;
  jobStatusLabel: string;
  postedOn: string;

  // Reviews
  reviewsTitle: string;
  manageReviews: string;
  addReview: string;
  reviewer: string;
  period: string;
  rating: string;
  reviewStatus: string;
  draft: string;
  submitted: string;
  acknowledged: string;
  noReviews: string;
  newReview: string;
  goals: string;
  achievements: string;
  feedback: string;
  createReview: string;
  selectReviewer: string;
  reviewPeriod: string;

  // Shifts
  shifts: string;
  shiftsTitle: string;
  manageShifts: string;
  addShift: string;
  shiftName: string;
  shiftStartTime: string;
  shiftEndTime: string;
  workingDays: string;
  shiftColor: string;
  shiftDescField: string;
  createShift: string;
  editShift: string;
  deleteShift: string;
  manageShiftEmps: string;
  noShifts: string;
  unassignedEmps: string;
  assignToShift: string;
  removeFromShift: string;
  totalShifts: string;
  assignedEmps: string;
  shiftDuration: string;
  dayMon: string;
  dayTue: string;
  dayWed: string;
  dayThu: string;
  dayFri: string;
  daySat: string;
  daySun: string;
  colorBlue: string;
  colorPurple: string;
  colorEmerald: string;
  colorOrange: string;
  colorRose: string;
  colorAmber: string;
  colorTeal: string;
  colorIndigo: string;
  empCountInShift: string;
  noEmpsInShift: string;
  shiftAssigned: string;
  shiftUnassigned: string;
  shiftDeleted: string;
  shiftSaved: string;

  // Payroll
  payrollTitle: string;
  managePayroll: string;
  addPayroll: string;
  month: string;
  baseSalary: string;
  bonus: string;
  deductions: string;
  netPay: string;
  payStatus: string;
  pendingPay: string;
  paid: string;
  processedPay: string;
  noPayroll: string;
  newPayrollRecord: string;
  selectMonth: string;
  createPayroll: string;
  markAsPaid: string;
  markAsPending: string;
  paySlip: string;
  exportCsv: string;
  selectEmployeePayroll: string;
  netPayAuto: string;
  deleteRecord: string;

  // Attendance
  attendanceTitle: string;
  manageAttendance: string;
  logAttendance: string;
  date: string;
  checkIn: string;
  checkOut: string;
  hoursWorked: string;
  attStatus: string;
  present: string;
  absent: string;
  late: string;
  half_day: string;
  noAttendance: string;
  newAttendance: string;
  createAttendance: string;
  selectDate: string;
  editAttRecord: string;
  hoursAutoCalc: string;
  filterByDate: string;
  allEmployees: string;

  // Announcements
  announcementsTitle: string;
  manageAnnouncements: string;
  newAnnouncement: string;
  author: string;
  priority: string;
  low: string;
  medium: string;
  high: string;
  urgentPriority: string;
  noAnnouncements: string;
  createAnnouncement: string;
  announcementTitle: string;
  content: string;
  authorName: string;
  postAnnouncement: string;
  deleteAnnouncement: string;

  // Talent Pool
  talentPool: string;
  talentPoolDesc: string;
  archiveCandidate: string;
  restoreCandidate: string;
  candidateNotes: string;
  candidateDocuments: string;
  markHired: string;
  allDepartments: string;
  noCandidates: string;
  talentPoolStatus: string;
  newStatus: string;
  rejectedStatus: string;
  talentPoolStatusBadge: string;
  viewCandidate: string;
  editCandidate: string;
  deleteCandidate: string;
  uploadDoc: string;
  restoreToScreening: string;
  confirmArchive: string;
  confirmRestore: string;
  confirmHire: string;
  confirmDelete: string;

  leaveAnalytics: string;
  employeeLeaveOverview: string;
  leaveAnalyticsDesc: string;
  takenThisWeek: string;
  takenThisMonth: string;
  takenThisYear: string;
  remainingThisMonth: string;
  remainingThisYear: string;
  pendingRequests: string;
  leaveHistory: string;
  leavePolicy: string;
  daysPerMonth: string;
  daysPerYear: string;
  savePolicy: string;
  policyUpdated: string;
  exportCsvBtn: string;
  printReport: string;
  leaveReport: string;
  searchEmployees2: string;
  noEmployeesFound2: string;
  allDepartments2: string;
  leaveDetails2: string;
  thisWeek: string;
  thisMonth: string;
  thisYear: string;
  remaining: string;
  totalLeaves: string;
  monthlyLimitExceeded: string;
  yearlyLimitExceeded: string;
  limitInfo: string;
  backToLeaves: string;
  leaveType_annual: string;
  leaveType_sick: string;
  leaveType_unpaid: string;
  leaveType_maternity: string;
  leaveType_paternity: string;
  leaveType_other: string;

  // Talent Bank (Bank Al-Talabeed)
  talentBank: string;
  talentBankDesc: string;
  waitingPersons: string;
  personsWaiting: string;
  addPerson: string;
  addPersonTitle: string;
  personName: string;
  personJobTitle: string;
  selectJob: string;
  personSelectDepartment: string;
  additionalNotes: string;
  savePerson: string;
  savingPerson: string;
  personSaved: string;
  personDeleted: string;
  editPerson: string;
  deletePerson: string;
  confirmDeletePerson: string;
  personDetails: string;
  deptWaitingPersons: string;
  noPersonsInDept: string;
  personsCount: string;
  backToTalentBank: string;
  jobPosition: string;
  addedOn: string;
  personDepartment: string;
}

const ar: Translations = {
  // Auth
  signIn: "تسجيل الدخول",
  signInWithWindowsHello: "تسجيل الدخول بـ Windows Hello",
  signOut: "تسجيل الخروج",
  signUp: "إنشاء حساب",
  loginTitle: "مرحباً بك مجدداً",
  loginSubtitle: "سجّل دخولك للوصول إلى لوحة الموارد البشرية",
  registerTitle: "إنشاء حساب جديد",
  registerSubtitle: "انضم إلى نظام إدارة الموارد البشرية",
  fullName: "الاسم الكامل",
  emailAddress: "البريد الإلكتروني",
  password: "كلمة المرور",
  confirmPassword: "تأكيد كلمة المرور",
  signingIn: "جاري الدخول...",
  signingInWithPasskey: "جاري الدخول بالمفتاح...",
  registering: "جاري التسجيل...",
  noAccount: "ليس لديك حساب؟",
  hasAccount: "لديك حساب بالفعل؟",
  loginError: "البريد الإلكتروني أو كلمة المرور غير صحيحة",
  passwordMismatch: "كلمتا المرور غير متطابقتين",
  myProfile: "ملفي الشخصي",
  editProfile: "تعديل الملف الشخصي",
  changePassword: "تغيير كلمة المرور",
  currentPassword: "كلمة المرور الحالية",
  newPassword: "كلمة المرور الجديدة",
  confirmNewPassword: "تأكيد كلمة المرور الجديدة",
  saveChanges: "حفظ التغييرات",
  savingChanges: "جاري الحفظ...",
  profileSaved: "تم تحديث الملف الشخصي بنجاح",
  passwordChanged: "تم تغيير كلمة المرور بنجاح",
  wrongCurrentPassword: "كلمة المرور الحالية غير صحيحة",
  hrAdmin: "مدير الموارد البشرية",
  myAccount: "حسابي",
  profileInfo: "المعلومات الشخصية",
  securitySettings: "الأمان",
  memberSince: "عضو منذ",

  // Notifications
  notifications: "الإشعارات",
  notifMarkAllRead: "تحديد الكل كمقروء",
  notifClearAll: "مسح الكل",
  notifEmpty: "لا توجد إشعارات",
  notifPermissionTitle: "تفعيل إشعارات النظام",
  notifPermissionDesc: "اسمح بالإشعارات لتلقي تنبيهات فورية على سطح المكتب.",
  notifPermissionAllow: "السماح بالإشعارات",
  notifJustNow: "الآن",
  notifMinAgo: "د",
  notifHrAgo: "س",
  notifDayAgo: "ي",
  // Nav
  dashboard: "لوحة التحكم",
  employees: "الموظفون",
  departments: "الأقسام",
  timeLeave: "الوقت والإجازات",
  recruitment: "التوظيف",
  reviews: "التقييمات",
  payroll: "الرواتب",
  attendance: "الحضور",
  announcements: "الإعلانات",
  needHelp: "هل تحتاج مساعدة؟",
  helpDesc: "راجع الوثائق أو تواصل مع الدعم.",
  viewDocs: "عرض الوثائق",
  helpTitle: "مركز المساعدة",
  helpFaqTab: "الأسئلة الشائعة",
  helpFeedbackTab: "إرسال ملاحظة",
  feedbackType: "نوع الملاحظة",
  feedbackTypeFeedback: "ملاحظة عامة",
  feedbackTypeBug: "الإبلاغ عن خطأ",
  feedbackTypeFeature: "طلب ميزة",
  feedbackMessage: "الرسالة",
  feedbackPlaceholder: "اكتب ملاحظتك أو وصف المشكلة هنا...",
  feedbackSend: "إرسال",
  feedbackSuccess: "تم إرسال ملاحظتك بنجاح! شكراً لك.",
  faq1Q: "كيف أضيف موظفًا جديدًا؟",
  faq1A:
    'انتقل إلى صفحة الموظفون من القائمة الجانبية، ثم انقر على زر "إضافة موظف" في الأعلى. أدخل بيانات الموظف وانقر حفظ.',
  faq2Q: "كيف أوافق على طلب إجازة؟",
  faq2A:
    "اذهب إلى صفحة الوقت والإجازات، ابحث عن الطلب المعلق وانقر على زر الموافقة. سيتم إشعار الموظف تلقائيًا.",
  faq3Q: "كيف أعالج كشف الرواتب؟",
  faq3A:
    'افتح صفحة الرواتب، اختر الشهر المطلوب وانقر على "معالجة الرواتب". يمكنك مراجعة التفاصيل قبل التأكيد.',
  faq4Q: "كيف أنشر وظيفة شاغرة؟",
  faq4A:
    'انتقل إلى صفحة التوظيف وانقر على "نشر وظيفة". أدخل عنوان الوظيفة والمتطلبات والقسم ثم احفظ.',
  faq5Q: "كيف أسجل الحضور؟",
  faq5A:
    "اذهب إلى صفحة الحضور، اختر التاريخ والموظف ثم أدخل وقت الدخول والخروج وانقر حفظ.",
  faq6Q: "كيف أكتب تقييم أداء؟",
  faq6A:
    'افتح صفحة التقييمات وانقر على "إضافة تقييم". اختر الموظف والفترة الزمنية وأدخل الأهداف والملاحظات.',

  // Header
  searchPlaceholder: "ابحث عن موظفين، أقسام، وظائف...",
  hrDirector: "مدير الموارد البشرية",

  // Dashboard
  overview: "نظرة عامة",
  welcomeBack: "مرحباً بعودتك، إليك ما يحدث اليوم.",
  goodMorning: "صباح الخير",
  goodAfternoon: "مساء الخير",
  goodEvening: "مساء الخير",
  totalEmployees: "إجمالي الموظفين",
  activeEmployees: "الموظفون النشطون",
  onLeaveToday: "في إجازة اليوم",
  openPositions: "الوظائف الشاغرة",
  pendingLeaves: "طلبات الإجازة المعلقة",
  newApplications: "طلبات جديدة",
  upcomingReviews: "تقييمات قادمة",
  totalPayroll: "إجمالي الرواتب",
  vsLastMonth: "مقارنةً بالشهر الماضي",
  recentActivity: "النشاط الأخير",
  viewAll: "عرض الكل",
  companyNews: "أخبار الشركة",
  noRecentActivity: "لا يوجد نشاط حديث",
  totalDepartments: "الأقسام",
  attendanceToday: "الحضور اليوم",
  talentPoolCount: "بنك المواهب",
  justNow: "الآن",
  minutesAgo: "دقائق مضت",
  hoursAgo: "ساعات مضت",
  daysAgo: "أيام مضت",
  newAppReceived: "تم استلام طلب توظيف جديد",
  softwareEngineerRole: "وظيفة مهندس برمجيات",
  leaveApproved: "تمت الموافقة على الإجازة",
  michaelChenLeave: "مايكل تشن - إجازة سنوية",
  reviewSubmitted: "تم تقديم تقييم الأداء",
  sarahJenkinsReview: "مراجعة سارة جنكينز Q3",
  payrollProcessed: "تمت معالجة الرواتب",
  octoberPayroll: "رواتب أكتوبر 2023",
  officeClosure: "إغلاق المكتب غداً",
  officeClosureDesc:
    "بسبب تحذيرات الطقس الشديد، سيكون المكتب الرئيسي مغلقاً غداً. يرجى العمل عن بُعد.",
  townhallMeeting: "اجتماع Q3 العام",
  townhallDesc: "انضم إلينا يوم الجمعة الساعة 2 مساءً للتحديث الفصلي.",
  minsAgo: "منذ 10 دقائق",
  hoursAgo2: "منذ ساعتين",
  hoursAgo5: "منذ 5 ساعات",
  dayAgo: "منذ يوم",
  urgent: "عاجل",
  statusPending: "قيد الانتظار",
  statusApproved: "معتمد",
  statusRejected: "مرفوض",
  statusNew: "جديد",
  statusDraft: "مسودة",
  statusPaid: "مدفوع",
  serverError: "خطأ في الخادم",

  // Employees
  employeesTitle: "الموظفون",
  manageTeam: "إدارة أعضاء الفريق وملفاتهم الشخصية.",
  addEmployee: "إضافة موظف",
  searchEmployees: "البحث عن موظفين...",
  total: "إجمالي",
  employee: "الموظف",
  contact: "التواصل",
  department: "القسم",
  status: "الحالة",
  actions: "الإجراءات",
  loadingEmployees: "جاري تحميل الموظفين...",
  noEmployeesFound: "لم يتم العثور على موظفين.",
  active: "نشط",
  on_leave: "في إجازة",
  inactive: "غير نشط",
  unassigned: "غير مخصص",
  addNewEmployee: "إضافة موظف جديد",
  editEmployee: "تعديل بيانات الموظف",
  enterDetails: "أدخل بيانات العضو الجديد في الفريق.",
  updateEmployeeDetails: "تحديث بيانات الموظف.",
  firstName: "الاسم الأول",
  lastName: "اسم العائلة",
  email: "البريد الإلكتروني",
  phone: "الهاتف",
  position: "المنصب",
  selectDepartment: "اختر قسماً",
  startDate: "تاريخ البدء",
  salary: "الراتب",
  cancel: "إلغاء",
  save: "حفظ الموظف",
  saving: "جاري الحفظ...",
  deleteConfirm: "هل أنت متأكد من حذف هذا الموظف؟",
  delete: "حذف",
  papers: "الأوراق",
  requiredDocuments: "المستندات المطلوبة",
  uploadFile: "رفع ملف",
  preview: "معاينة",
  download: "تحميل",
  uploaded: "مرفوع",
  missing: "مفقود",
  manageDocTypes: "إدارة أنواع المستندات",
  addDocType: "إضافة نوع",
  deleteDocType: "حذف",

  // Departments
  departmentsTitle: "الأقسام",
  manageDepts: "إدارة هيكل الأقسام وفرق الشركة.",
  addDepartment: "إضافة قسم",
  deptName: "اسم القسم",
  manager: "المدير",
  employeeCount: "عدد الموظفين",
  noDepts: "لم يتم العثور على أقسام.",
  addNewDept: "إضافة قسم جديد",
  deptDesc: "أنشئ قسماً جديداً في الشركة.",
  description: "الوصف",
  managerId: "معرّف المدير (اختياري)",
  employees2: "موظفون",
  noManager: "لا يوجد مدير",

  // Leaves
  leaveManagement: "إدارة الإجازات",
  reviewManage: "مراجعة وإدارة طلبات الإجازة.",
  requestLeave: "طلب إجازة",
  all: "الكل",
  pending: "معلق",
  approved: "موافق عليه",
  rejected: "مرفوض",
  leaveDetails: "تفاصيل الإجازة",
  datesDuration: "التواريخ والمدة",
  loading: "جاري التحميل...",
  noLeaves: "لم يتم العثور على طلبات إجازة.",
  daysRequested: "أيام مطلوبة",
  processed: "تمت المعالجة",
  newLeaveRequest: "طلب إجازة جديد",
  selectEmployee: "اختر موظفاً",
  leaveType: "نوع الإجازة",
  annual: "سنوية",
  sick: "مرضية",
  unpaid: "بدون راتب",
  maternity: "أمومة",
  paternity: "أبوة",
  other: "أخرى",
  endDate: "تاريخ الانتهاء",
  reason: "السبب",
  reasonOptional: "السبب (اختياري)",
  submitRequest: "تقديم الطلب",

  // Recruitment
  recruitmentTitle: "التوظيف",
  manageRecruitment: "إدارة الوظائف الشاغرة والمتقدمين.",
  postJob: "نشر وظيفة",
  jobPostings: "الوظائف المنشورة",
  applicants: "المتقدمون",
  applicantsCount: "متقدم",
  location: "الموقع",
  type: "النوع",
  jobStatus: "الحالة",
  open: "مفتوح",
  closed: "مغلق",
  on_hold: "معلق",
  full_time: "دوام كامل",
  part_time: "دوام جزئي",
  contract: "عقد",
  internship: "تدريب",
  noJobs: "لم يتم العثور على وظائف.",
  newJobPosting: "نشر وظيفة جديدة",
  jobTitle: "المسمى الوظيفي",
  requirements: "المتطلبات",
  salaryRange: "نطاق الراتب",
  createJob: "نشر الوظيفة",
  appStatus: "حالة الطلب",
  new2: "جديد",
  screening: "فرز",
  interview: "مقابلة",
  offer: "عرض",
  hired: "تم التوظيف",
  appliedOn: "تاريخ التقديم",
  noApplicants: "لا يوجد متقدمون لهذه الوظيفة.",
  backToJobs: "العودة للوظائف",
  viewApplicants: "عرض المتقدمين",
  updateStatus: "تحديث الحالة",
  jobDept: "القسم",
  jobType: "نوع الوظيفة",
  jobLocation: "الموقع",
  jobStatusLabel: "حالة الوظيفة",
  postedOn: "تاريخ النشر",

  // Reviews
  reviewsTitle: "تقييمات الأداء",
  manageReviews: "تتبع وإدارة مراجعات أداء الموظفين.",
  addReview: "إضافة تقييم",
  reviewer: "المُقيِّم",
  period: "الفترة",
  rating: "التقييم",
  reviewStatus: "الحالة",
  draft: "مسودة",
  submitted: "مقدم",
  acknowledged: "مُقر به",
  noReviews: "لم يتم العثور على تقييمات.",
  newReview: "تقييم جديد",
  goals: "الأهداف",
  achievements: "الإنجازات",
  feedback: "الملاحظات",
  createReview: "إنشاء التقييم",
  selectReviewer: "اختر المُقيِّم",
  reviewPeriod: "فترة التقييم",

  // Shifts
  shifts: "الورديات",
  shiftsTitle: "ورديات العمل",
  manageShifts: "إدارة جداول عمل الموظفين وتنظيم الورديات.",
  addShift: "إضافة وردية",
  shiftName: "اسم الوردية",
  shiftStartTime: "وقت البدء",
  shiftEndTime: "وقت الانتهاء",
  workingDays: "أيام العمل",
  shiftColor: "اللون",
  shiftDescField: "الوصف (اختياري)",
  createShift: "إنشاء الوردية",
  editShift: "تعديل الوردية",
  deleteShift: "حذف الوردية",
  manageShiftEmps: "إدارة الموظفين",
  noShifts: "لا توجد ورديات بعد.",
  unassignedEmps: "موظفون غير محددة وردياتهم",
  assignToShift: "تعيين لوردية",
  removeFromShift: "إزالة من الوردية",
  totalShifts: "إجمالي الورديات",
  assignedEmps: "الموظفون المعينون",
  shiftDuration: "مدة الوردية",
  dayMon: "إث",
  dayTue: "ثل",
  dayWed: "أر",
  dayThu: "خم",
  dayFri: "جم",
  daySat: "سب",
  daySun: "أح",
  colorBlue: "أزرق",
  colorPurple: "بنفسجي",
  colorEmerald: "زمردي",
  colorOrange: "برتقالي",
  colorRose: "وردي",
  colorAmber: "كهرماني",
  colorTeal: "أزرق مخضر",
  colorIndigo: "نيلي",
  empCountInShift: "موظف في هذه الوردية",
  noEmpsInShift: "لا يوجد موظفون في هذه الوردية",
  shiftAssigned: "تم تعيين الموظف للوردية",
  shiftUnassigned: "تم إزالة الموظف من الوردية",
  shiftDeleted: "تم حذف الوردية",
  shiftSaved: "تم حفظ الوردية",

  // Payroll
  payrollTitle: "الرواتب",
  managePayroll: "إدارة كشوف رواتب الموظفين.",
  addPayroll: "إضافة راتب",
  month: "الشهر",
  baseSalary: "الراتب الأساسي",
  bonus: "المكافأة",
  deductions: "الخصومات",
  netPay: "صافي الراتب",
  payStatus: "الحالة",
  pendingPay: "معلق",
  paid: "مدفوع",
  processedPay: "تمت المعالجة",
  noPayroll: "لم يتم العثور على سجلات رواتب.",
  newPayrollRecord: "سجل راتب جديد",
  selectMonth: "اختر الشهر",
  createPayroll: "إنشاء السجل",
  markAsPaid: "تعيين كمدفوع",
  markAsPending: "تعيين كمعلق",
  paySlip: "قسيمة الراتب",
  exportCsv: "تصدير CSV",
  selectEmployeePayroll: "اختر الموظف",
  netPayAuto: "صافي الراتب (محسوب تلقائياً)",
  deleteRecord: "حذف السجل",

  // Attendance
  attendanceTitle: "سجل الحضور",
  manageAttendance: "تتبع حضور وغياب الموظفين.",
  logAttendance: "تسجيل الحضور",
  date: "التاريخ",
  checkIn: "وقت الدخول",
  checkOut: "وقت الخروج",
  hoursWorked: "ساعات العمل",
  attStatus: "الحالة",
  present: "حاضر",
  absent: "غائب",
  late: "متأخر",
  half_day: "نصف يوم",
  noAttendance: "لم يتم العثور على سجلات حضور.",
  newAttendance: "تسجيل حضور جديد",
  createAttendance: "تسجيل",
  selectDate: "اختر التاريخ",
  editAttRecord: "تعديل سجل الحضور",
  hoursAutoCalc: "ساعات العمل (محسوبة تلقائياً)",
  filterByDate: "تصفية حسب التاريخ",
  allEmployees: "جميع الموظفين",

  // Announcements
  announcementsTitle: "الإعلانات",
  manageAnnouncements: "نشر وإدارة إعلانات الشركة.",
  newAnnouncement: "إعلان جديد",
  author: "الكاتب",
  priority: "الأولوية",
  low: "منخفضة",
  medium: "متوسطة",
  high: "عالية",
  urgentPriority: "عاجل",
  noAnnouncements: "لا توجد إعلانات",
  createAnnouncement: "إنشاء إعلان",
  announcementTitle: "عنوان الإعلان",
  content: "المحتوى",
  authorName: "اسم الكاتب",
  postAnnouncement: "نشر الإعلان",
  deleteAnnouncement: "هل أنت متأكد من حذف هذا الإعلان؟",

  // Talent Pool
  talentPool: "بنك المواهب",
  talentPoolDesc: "أرشيف المرشحين حسب الأقسام",
  archiveCandidate: "أرشفة المرشح",
  restoreCandidate: "استعادة المرشح",
  candidateNotes: "ملاحظات المرشح",
  candidateDocuments: "مستندات المرشح",
  markHired: "تعيين كموظف",
  allDepartments: "جميع الأقسام",
  noCandidates: "لا يوجد مرشحون",
  talentPoolStatus: "بنك المواهب",
  newStatus: "جديد",
  rejectedStatus: "مرفوض",
  talentPoolStatusBadge: "في بنك المواهب",
  viewCandidate: "عرض المرشح",
  editCandidate: "تعديل المرشح",
  deleteCandidate: "حذف المرشح",
  uploadDoc: "رفع مستند",
  restoreToScreening: "إعادة للفرز",
  confirmArchive: "هل تريد أرشفة هذا المرشح؟",
  confirmRestore: "هل تريد استعادة هذا المرشح؟",
  confirmHire: "هل تريد تعيين هذا المرشح كموظف؟",
  confirmDelete: "هل أنت متأكد من حذف هذا المرشح؟",

  leaveAnalytics: "تحليلات الإجازات",
  employeeLeaveOverview: "نظرة عامة على إجازات الموظفين",
  leaveAnalyticsDesc: "عرض وتحليل إجازات جميع الموظفين",
  takenThisWeek: "مأخوذة هذا الأسبوع",
  takenThisMonth: "مأخوذة هذا الشهر",
  takenThisYear: "مأخوذة هذا العام",
  remainingThisMonth: "المتبقي هذا الشهر",
  remainingThisYear: "المتبقي هذا العام",
  pendingRequests: "طلبات معلقة",
  leaveHistory: "سجل الإجازات",
  leavePolicy: "سياسة الإجازات",
  daysPerMonth: "أيام في الشهر",
  daysPerYear: "أيام في السنة",
  savePolicy: "حفظ السياسة",
  policyUpdated: "تم تحديث السياسة",
  exportCsvBtn: "تصدير CSV",
  printReport: "طباعة التقرير",
  leaveReport: "تقرير الإجازات",
  searchEmployees2: "بحث عن موظف...",
  noEmployeesFound2: "لم يتم العثور على موظفين",
  allDepartments2: "جميع الأقسام",
  leaveDetails2: "تفاصيل الإجازة",
  thisWeek: "هذا الأسبوع",
  thisMonth: "هذا الشهر",
  thisYear: "هذا العام",
  remaining: "المتبقي",
  totalLeaves: "إجمالي الإجازات",
  monthlyLimitExceeded: "تجاوز الحد الشهري للإجازات",
  yearlyLimitExceeded: "تجاوز الحد السنوي للإجازات",
  limitInfo: "حد الإجازة",
  backToLeaves: "العودة إلى الإجازات",
  leaveType_annual: "سنوية",
  leaveType_sick: "مرضية",
  leaveType_unpaid: "بدون راتب",
  leaveType_maternity: "أمومة",
  leaveType_paternity: "أبوة",
  leaveType_other: "أخرى",

  // Talent Bank
  talentBank: "بنك المواهب",
  talentBankDesc: "إدارة المرشحين حسب الأقسام",
  waitingPersons: "الأشخاص في الانتظار",
  personsWaiting: "شخص في الانتظار",
  addPerson: "إضافة شخص",
  addPersonTitle: "إضافة شخص جديد",
  personName: "الاسم",
  personJobTitle: "المسمى الوظيفي",
  selectJob: "اختر الوظيفة",
  personSelectDepartment: "اختر القسم",
  additionalNotes: "ملاحظات إضافية",
  savePerson: "حفظ",
  savingPerson: "جاري الحفظ...",
  personSaved: "تم حفظ الشخص بنجاح",
  personDeleted: "تم حذف الشخص بنجاح",
  editPerson: "تعديل البيانات",
  deletePerson: "حذف الشخص",
  confirmDeletePerson: "هل أنت متأكد من حذف هذا الشخص؟",
  personDetails: "بيانات الشخص",
  deptWaitingPersons: "الأشخاص في الانتظار بهذا القسم",
  noPersonsInDept: "لا يوجد أشخاص في الانتظار بهذا القسم",
  personsCount: "عدد الأشخاص",
  backToTalentBank: "العودة لبنك المواهب",
  jobPosition: "الوظيفة",
  addedOn: "تاريخ الإضافة",
  personDepartment: "القسم",
};

const en: Translations = {
  // Auth
  signIn: "Sign In",
  signInWithWindowsHello: "Sign in with Windows Hello",
  signOut: "Sign Out",
  signUp: "Create Account",
  loginTitle: "Welcome back",
  loginSubtitle: "Sign in to access your HR dashboard",
  registerTitle: "Create an account",
  registerSubtitle: "Join the HR management system",
  fullName: "Full Name",
  emailAddress: "Email Address",
  password: "Password",
  confirmPassword: "Confirm Password",
  signingIn: "Signing in...",
  signingInWithPasskey: "Signing in with passkey...",
  registering: "Creating account...",
  noAccount: "Don't have an account?",
  hasAccount: "Already have an account?",
  loginError: "Invalid email or password",
  passwordMismatch: "Passwords do not match",
  myProfile: "My Profile",
  editProfile: "Edit Profile",
  changePassword: "Change Password",
  currentPassword: "Current Password",
  newPassword: "New Password",
  confirmNewPassword: "Confirm New Password",
  saveChanges: "Save Changes",
  savingChanges: "Saving...",
  profileSaved: "Profile updated successfully",
  passwordChanged: "Password changed successfully",
  wrongCurrentPassword: "Current password is incorrect",
  hrAdmin: "HR Administrator",
  myAccount: "My Account",
  profileInfo: "Profile Information",
  securitySettings: "Security",
  memberSince: "Member since",

  // Notifications
  notifications: "Notifications",
  notifMarkAllRead: "Mark all as read",
  notifClearAll: "Clear all",
  notifEmpty: "No notifications",
  notifPermissionTitle: "Enable Desktop Notifications",
  notifPermissionDesc:
    "Allow notifications to receive instant alerts on your desktop.",
  notifPermissionAllow: "Allow Notifications",
  notifJustNow: "just now",
  notifMinAgo: "m ago",
  notifHrAgo: "h ago",
  notifDayAgo: "d ago",
  // Nav
  dashboard: "Dashboard",
  employees: "Employees",
  departments: "Departments",
  timeLeave: "Time & Leave",
  recruitment: "Recruitment",
  reviews: "Reviews",
  payroll: "Payroll",
  attendance: "Attendance",
  announcements: "Announcements",
  needHelp: "Need help?",
  helpDesc: "Check out our documentation or contact support.",
  viewDocs: "View Docs",
  helpTitle: "Help Center",
  helpFaqTab: "FAQ",
  helpFeedbackTab: "Send Feedback",
  feedbackType: "Type",
  feedbackTypeFeedback: "General Feedback",
  feedbackTypeBug: "Report a Bug",
  feedbackTypeFeature: "Feature Request",
  feedbackMessage: "Message",
  feedbackPlaceholder:
    "Describe your feedback or the issue you're experiencing...",
  feedbackSend: "Send",
  feedbackSuccess: "Your feedback was sent successfully! Thank you.",
  faq1Q: "How do I add a new employee?",
  faq1A:
    'Go to the Employees page from the sidebar, then click the "Add Employee" button at the top. Fill in the employee details and click Save.',
  faq2Q: "How do I approve a leave request?",
  faq2A:
    "Navigate to the Time & Leaves page, find the pending request and click the Approve button. The employee will be notified automatically.",
  faq3Q: "How do I process payroll?",
  faq3A:
    'Open the Payroll page, select the desired month and click "Process Payroll". You can review the details before confirming.',
  faq4Q: "How do I post a job opening?",
  faq4A:
    'Go to the Recruitment page and click "Post a Job". Enter the job title, requirements and department, then save.',
  faq5Q: "How do I record attendance?",
  faq5A:
    "Navigate to the Attendance page, select the date and employee, then enter check-in and check-out times and save.",
  faq6Q: "How do I write a performance review?",
  faq6A:
    'Open the Reviews page and click "Add Review". Select the employee and time period, then enter goals and feedback.',

  // Header
  searchPlaceholder: "Search employees, departments, jobs...",
  hrDirector: "HR Director",

  // Dashboard
  overview: "Overview",
  welcomeBack: "Welcome back, here's what's happening today.",
  goodMorning: "Good morning",
  goodAfternoon: "Good afternoon",
  goodEvening: "Good evening",
  totalEmployees: "Total Employees",
  activeEmployees: "Active Employees",
  onLeaveToday: "On Leave Today",
  openPositions: "Open Positions",
  pendingLeaves: "Pending Leaves",
  newApplications: "New Applications",
  upcomingReviews: "Upcoming Reviews",
  totalPayroll: "Total Payroll",
  vsLastMonth: "vs last month",
  recentActivity: "Recent Activity",
  viewAll: "View all",
  companyNews: "Company News",
  noRecentActivity: "No recent activity",
  totalDepartments: "Departments",
  attendanceToday: "Attendance Today",
  talentPoolCount: "Talent Pool",
  justNow: "Just now",
  minutesAgo: "minutes ago",
  hoursAgo: "hours ago",
  daysAgo: "days ago",
  newAppReceived: "New application received",
  softwareEngineerRole: "Software Engineer role",
  leaveApproved: "Leave approved",
  michaelChenLeave: "Michael Chen - Annual Leave",
  reviewSubmitted: "Performance review submitted",
  sarahJenkinsReview: "Sarah Jenkins Q3 Review",
  payrollProcessed: "Payroll processed",
  octoberPayroll: "October 2023 Payroll",
  officeClosure: "Office Closure Tomorrow",
  officeClosureDesc:
    "Due to severe weather warnings, the main office will be closed tomorrow. Please work remotely.",
  townhallMeeting: "Q3 Townhall Meeting",
  townhallDesc: "Join us this Friday at 2 PM EST for the quarterly update.",
  minsAgo: "10 mins ago",
  hoursAgo2: "2 hours ago",
  hoursAgo5: "5 hours ago",
  dayAgo: "1 day ago",
  urgent: "Urgent",
  statusPending: "Pending",
  statusApproved: "Approved",
  statusRejected: "Rejected",
  statusNew: "New",
  statusDraft: "Draft",
  statusPaid: "Paid",
  serverError: "Server error",

  // Employees
  employeesTitle: "Employees",
  manageTeam: "Manage your team members and their profiles.",
  addEmployee: "Add Employee",
  searchEmployees: "Search employees...",
  total: "total",
  employee: "Employee",
  contact: "Contact",
  department: "Department",
  status: "Status",
  actions: "Actions",
  loadingEmployees: "Loading employees...",
  noEmployeesFound: "No employees found.",
  active: "Active",
  on_leave: "On Leave",
  inactive: "Inactive",
  unassigned: "Unassigned",
  addNewEmployee: "Add New Employee",
  editEmployee: "Edit Employee",
  enterDetails: "Enter the details of the new team member.",
  updateEmployeeDetails: "Update the employee's information.",
  firstName: "First Name",
  lastName: "Last Name",
  email: "Email",
  phone: "Phone",
  position: "Position",
  selectDepartment: "Select a department",
  startDate: "Start Date",
  salary: "Salary",
  cancel: "Cancel",
  save: "Save Employee",
  saving: "Saving...",
  deleteConfirm: "Are you sure you want to delete this employee?",
  delete: "Delete",
  papers: "Papers",
  requiredDocuments: "Required Documents",
  uploadFile: "Upload File",
  preview: "Preview",
  download: "Download",
  uploaded: "Uploaded",
  missing: "Missing",
  manageDocTypes: "Manage Document Types",
  addDocType: "Add Type",
  deleteDocType: "Delete",

  // Departments
  departmentsTitle: "Departments",
  manageDepts: "Manage your company's department structure and teams.",
  addDepartment: "Add Department",
  deptName: "Department Name",
  manager: "Manager",
  employeeCount: "Employees",
  noDepts: "No departments found.",
  addNewDept: "Add New Department",
  deptDesc: "Create a new department in your organization.",
  description: "Description",
  managerId: "Manager ID (optional)",
  employees2: "employees",
  noManager: "No manager assigned",

  // Leaves
  leaveManagement: "Leave Management",
  reviewManage: "Review and manage employee time off requests.",
  requestLeave: "Request Leave",
  all: "All",
  pending: "Pending",
  approved: "Approved",
  rejected: "Rejected",
  leaveDetails: "Leave Details",
  datesDuration: "Dates & Duration",
  loading: "Loading...",
  noLeaves: "No leave requests found.",
  daysRequested: "days requested",
  processed: "Processed",
  newLeaveRequest: "New Leave Request",
  selectEmployee: "Select Employee",
  leaveType: "Leave Type",
  annual: "Annual",
  sick: "Sick",
  unpaid: "Unpaid",
  maternity: "Maternity",
  paternity: "Paternity",
  other: "Other",
  endDate: "End Date",
  reason: "Reason",
  reasonOptional: "Reason (Optional)",
  submitRequest: "Submit Request",

  // Recruitment
  recruitmentTitle: "Recruitment",
  manageRecruitment: "Manage open positions and track candidates.",
  postJob: "Post a Job",
  jobPostings: "Job Postings",
  applicants: "Applicants",
  applicantsCount: "applicants",
  location: "Location",
  type: "Type",
  jobStatus: "Status",
  open: "Open",
  closed: "Closed",
  on_hold: "On Hold",
  full_time: "Full Time",
  part_time: "Part Time",
  contract: "Contract",
  internship: "Internship",
  noJobs: "No job postings found.",
  newJobPosting: "New Job Posting",
  jobTitle: "Job Title",
  requirements: "Requirements",
  salaryRange: "Salary Range",
  createJob: "Post Job",
  appStatus: "Application Status",
  new2: "New",
  screening: "Screening",
  interview: "Interview",
  offer: "Offer",
  hired: "Hired",
  appliedOn: "Applied On",
  noApplicants: "No applicants for this job yet.",
  backToJobs: "Back to Jobs",
  viewApplicants: "View Applicants",
  updateStatus: "Update Status",
  jobDept: "Department",
  jobType: "Job Type",
  jobLocation: "Location",
  jobStatusLabel: "Job Status",
  postedOn: "Posted On",

  // Reviews
  reviewsTitle: "Performance Reviews",
  manageReviews: "Track and manage employee performance evaluations.",
  addReview: "Add Review",
  reviewer: "Reviewer",
  period: "Period",
  rating: "Rating",
  reviewStatus: "Status",
  draft: "Draft",
  submitted: "Submitted",
  acknowledged: "Acknowledged",
  noReviews: "No reviews found.",
  newReview: "New Performance Review",
  goals: "Goals",
  achievements: "Achievements",
  feedback: "Feedback",
  createReview: "Create Review",
  selectReviewer: "Select Reviewer",
  reviewPeriod: "Review Period",

  // Shifts
  shifts: "Shifts",
  shiftsTitle: "Work Shifts",
  manageShifts: "Manage employee work schedules and shift assignments.",
  addShift: "Add Shift",
  shiftName: "Shift Name",
  shiftStartTime: "Start Time",
  shiftEndTime: "End Time",
  workingDays: "Working Days",
  shiftColor: "Color",
  shiftDescField: "Description (optional)",
  createShift: "Create Shift",
  editShift: "Edit Shift",
  deleteShift: "Delete Shift",
  manageShiftEmps: "Manage Employees",
  noShifts: "No shifts created yet.",
  unassignedEmps: "Unassigned Employees",
  assignToShift: "Assign to Shift",
  removeFromShift: "Remove",
  totalShifts: "Total Shifts",
  assignedEmps: "Assigned Employees",
  shiftDuration: "Duration",
  dayMon: "Mon",
  dayTue: "Tue",
  dayWed: "Wed",
  dayThu: "Thu",
  dayFri: "Fri",
  daySat: "Sat",
  daySun: "Sun",
  colorBlue: "Blue",
  colorPurple: "Purple",
  colorEmerald: "Emerald",
  colorOrange: "Orange",
  colorRose: "Rose",
  colorAmber: "Amber",
  colorTeal: "Teal",
  colorIndigo: "Indigo",
  empCountInShift: "employees",
  noEmpsInShift: "No employees assigned",
  shiftAssigned: "Employee assigned to shift",
  shiftUnassigned: "Employee removed from shift",
  shiftDeleted: "Shift deleted",
  shiftSaved: "Shift saved",

  // Payroll
  payrollTitle: "Payroll",
  managePayroll: "Manage employee compensation records.",
  addPayroll: "Add Record",
  month: "Month",
  baseSalary: "Base Salary",
  bonus: "Bonus",
  deductions: "Deductions",
  netPay: "Net Pay",
  payStatus: "Status",
  pendingPay: "Pending",
  paid: "Paid",
  processedPay: "Processed",
  noPayroll: "No payroll records found.",
  newPayrollRecord: "New Payroll Record",
  selectMonth: "Select Month",
  createPayroll: "Create Record",
  markAsPaid: "Mark as Paid",
  markAsPending: "Mark as Pending",
  paySlip: "Pay Slip",
  exportCsv: "Export CSV",
  selectEmployeePayroll: "Select Employee",
  netPayAuto: "Net Pay (auto-calculated)",
  deleteRecord: "Delete Record",

  // Attendance
  attendanceTitle: "Attendance",
  manageAttendance: "Track employee check-in and check-out records.",
  logAttendance: "Log Attendance",
  date: "Date",
  checkIn: "Check In",
  checkOut: "Check Out",
  hoursWorked: "Hours Worked",
  attStatus: "Status",
  present: "Present",
  absent: "Absent",
  late: "Late",
  half_day: "Half Day",
  noAttendance: "No attendance records found.",
  newAttendance: "Log Attendance",
  createAttendance: "Log Record",
  selectDate: "Select Date",
  editAttRecord: "Edit Attendance Record",
  hoursAutoCalc: "Hours Worked (auto-calculated)",
  filterByDate: "Filter by Date",
  allEmployees: "All Employees",

  // Announcements
  announcementsTitle: "Announcements",
  manageAnnouncements: "Publish and manage company-wide announcements.",
  newAnnouncement: "New Announcement",
  author: "Author",
  priority: "Priority",
  low: "Low",
  medium: "Medium",
  high: "High",
  urgentPriority: "Urgent",
  noAnnouncements: "No announcements",
  createAnnouncement: "Create Announcement",
  announcementTitle: "Announcement Title",
  content: "Content",
  authorName: "Author Name",
  postAnnouncement: "Post Announcement",
  deleteAnnouncement: "Are you sure you want to delete this announcement?",

  // Talent Pool
  talentPool: "Talent Pool",
  talentPoolDesc: "Candidate archive by department",
  archiveCandidate: "Archive Candidate",
  restoreCandidate: "Restore Candidate",
  candidateNotes: "Candidate Notes",
  candidateDocuments: "Candidate Documents",
  markHired: "Mark as Hired",
  allDepartments: "All Departments",
  noCandidates: "No candidates found",
  talentPoolStatus: "Talent Pool",
  newStatus: "New",
  rejectedStatus: "Rejected",
  talentPoolStatusBadge: "In Talent Pool",
  viewCandidate: "View Candidate",
  editCandidate: "Edit Candidate",
  deleteCandidate: "Delete Candidate",
  uploadDoc: "Upload Document",
  restoreToScreening: "Restore to Screening",
  confirmArchive: "Archive this candidate?",
  confirmRestore: "Restore this candidate?",
  confirmHire: "Mark this candidate as hired?",
  confirmDelete: "Are you sure you want to delete this candidate?",

  leaveAnalytics: "Leave Analytics",
  employeeLeaveOverview: "Employee Leave Overview",
  leaveAnalyticsDesc: "View and analyze leave data for all employees",
  takenThisWeek: "Taken This Week",
  takenThisMonth: "Taken This Month",
  takenThisYear: "Taken This Year",
  remainingThisMonth: "Remaining This Month",
  remainingThisYear: "Remaining This Year",
  pendingRequests: "Pending Requests",
  leaveHistory: "Leave History",
  leavePolicy: "Leave Policy",
  daysPerMonth: "Days Per Month",
  daysPerYear: "Days Per Year",
  savePolicy: "Save Policy",
  policyUpdated: "Policy updated successfully",
  exportCsvBtn: "Export CSV",
  printReport: "Print Report",
  leaveReport: "Leave Report",
  searchEmployees2: "Search employees...",
  noEmployeesFound2: "No employees found",
  allDepartments2: "All Departments",
  leaveDetails2: "Leave Details",
  thisWeek: "This Week",
  thisMonth: "This Month",
  thisYear: "This Year",
  remaining: "Remaining",
  totalLeaves: "Total Leaves",
  monthlyLimitExceeded: "Monthly leave limit exceeded",
  yearlyLimitExceeded: "Yearly leave limit exceeded",
  limitInfo: "Leave Limit",
  backToLeaves: "Back to Leaves",
  leaveType_annual: "Annual",
  leaveType_sick: "Sick",
  leaveType_unpaid: "Unpaid",
  leaveType_maternity: "Maternity",
  leaveType_paternity: "Paternity",
  leaveType_other: "Other",

  // Talent Bank
  talentBank: "Talent Bank",
  talentBankDesc: "Manage candidates by department",
  waitingPersons: "Waiting Persons",
  personsWaiting: "person waiting",
  addPerson: "Add Person",
  addPersonTitle: "Add New Person",
  personName: "Name",
  personJobTitle: "Job Title",
  selectJob: "Select Job",
  personSelectDepartment: "Select Department",
  additionalNotes: "Additional Notes",
  savePerson: "Save",
  savingPerson: "Saving...",
  personSaved: "Person saved successfully",
  personDeleted: "Person deleted successfully",
  editPerson: "Edit Details",
  deletePerson: "Delete Person",
  confirmDeletePerson: "Are you sure you want to delete this person?",
  personDetails: "Person Details",
  deptWaitingPersons: "Waiting persons in this department",
  noPersonsInDept: "No waiting persons in this department",
  personsCount: "Number of persons",
  backToTalentBank: "Back to Talent Bank",
  jobPosition: "Position",
  addedOn: "Added On",
  personDepartment: "Department",
};

interface LanguageContextType {
  lang: Language;
  setLang: (lang: Language) => void;
  t: Translations;
  isRTL: boolean;
}

const LanguageContext = createContext<LanguageContextType | null>(null);

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Language>(() => {
    const stored = localStorage.getItem("hr-lang") as Language | null;
    return stored || "ar";
  });

  const setLang = (newLang: Language) => {
    setLangState(newLang);
    localStorage.setItem("hr-lang", newLang);
  };

  const isRTL = lang === "ar";
  const t = lang === "ar" ? ar : en;

  useEffect(() => {
    document.documentElement.setAttribute("dir", isRTL ? "rtl" : "ltr");
    document.documentElement.setAttribute("lang", lang);
  }, [isRTL, lang]);

  return (
    <LanguageContext.Provider value={{ lang, setLang, t, isRTL }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLang() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLang must be used within LanguageProvider");
  return ctx;
}
