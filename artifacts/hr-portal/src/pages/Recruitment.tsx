import { useState } from "react";
import {
  useListJobs,
  useListApplications,
  useCreateJob,
  getListJobsQueryKey,
  useListDepartments
} from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { Plus, Briefcase, MapPin, Users } from "lucide-react";
import { format } from "date-fns";
import { useLang } from "@/contexts/LanguageContext";

export default function Recruitment() {
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<'jobs' | 'apps'>('jobs');
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [filterJobId, setFilterJobId] = useState<number | null>(null);
  const { t, isRTL } = useLang();

  const { data: jobs = [], isLoading: loadingJobs } = useListJobs();
  const { data: apps = [], isLoading: loadingApps } = useListApplications();
  const { data: departments = [] } = useListDepartments();

  const createJob = useCreateJob({
    mutation: {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: getListJobsQueryKey() });
        setIsAddOpen(false);
      }
    }
  });

  const handleJobSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    createJob.mutate({
      data: {
        title: formData.get("title") as string,
        departmentId: Number(formData.get("departmentId")),
        location: formData.get("location") as string,
        type: formData.get("type") as string,
        description: formData.get("description") as string,
        salary: formData.get("salary") as string,
        status: "open",
      }
    });
  };

  const jobStatusLabel = (s: string) => {
    if (s === 'open') return t.open;
    if (s === 'closed') return t.closed;
    return t.on_hold;
  };

  return (
    <div className="space-y-6">
      <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}>
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">{t.recruitmentTitle}</h1>
          <p className="text-muted-foreground mt-1">{t.manageRecruitment}</p>
        </div>
        {activeTab === 'jobs' && (
          <button onClick={() => setIsAddOpen(true)} className="flex items-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all">
            <Plus className="w-4 h-4" /> {t.postJob}
          </button>
        )}
      </div>

      <div className={`flex gap-6 border-b border-border ${isRTL ? "flex-row-reverse" : ""}`}>
        <button
          onClick={() => setActiveTab('jobs')}
          className={`pb-3 text-sm font-medium border-b-2 transition-colors ${activeTab === 'jobs' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
        >
          {t.jobPostings}
        </button>
        <button
          onClick={() => { setActiveTab('apps'); setFilterJobId(null); }}
          className={`pb-3 text-sm font-medium border-b-2 transition-colors ${activeTab === 'apps' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
        >
          {t.applicants}
        </button>
      </div>

      {activeTab === 'jobs' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {loadingJobs ? (
            <div className="col-span-full py-12 text-center text-muted-foreground">{t.loading}</div>
          ) : jobs.length === 0 ? (
            <div className="col-span-full py-12 text-center text-muted-foreground bg-card border border-border rounded-xl">{t.noJobs}</div>
          ) : (
            jobs.map(job => (
              <div key={job.id} className="bg-card rounded-2xl border border-border shadow-sm p-6 flex flex-col hover:shadow-md transition-all group">
                <div className={`flex justify-between items-start mb-4 ${isRTL ? "flex-row-reverse" : ""}`}>
                  <div className="p-2.5 bg-primary/10 text-primary rounded-xl group-hover:scale-110 transition-transform">
                    <Briefcase className="w-5 h-5" />
                  </div>
                  <span className={`px-2 py-1 text-xs font-semibold rounded-md uppercase tracking-wider ${
                    job.status === 'open' ? 'bg-emerald-100 text-emerald-700' : 'bg-muted text-muted-foreground'
                  }`}>
                    {jobStatusLabel(job.status)}
                  </span>
                </div>
                <h3 className={`text-lg font-bold text-foreground ${isRTL ? "text-right" : ""}`}>{job.title}</h3>
                <p className={`text-sm text-primary font-medium mt-1 ${isRTL ? "text-right" : ""}`}>{job.departmentName}</p>

                <div className={`mt-4 space-y-2 flex-1 ${isRTL ? "text-right" : ""}`}>
                  <div className={`flex items-center text-sm text-muted-foreground ${isRTL ? "flex-row-reverse" : ""}`}>
                    <MapPin className={`w-4 h-4 ${isRTL ? "ml-2" : "mr-2"}`} /> {job.location}
                  </div>
                  <div className={`flex items-center text-sm text-muted-foreground ${isRTL ? "flex-row-reverse" : ""}`}>
                    <div className={`w-4 h-4 ${isRTL ? "ml-2" : "mr-2"} flex justify-center items-center text-xs`}>⏱</div>
                    {job.type === 'full_time' ? t.full_time : job.type === 'part_time' ? t.part_time : job.type === 'contract' ? t.contract : t.internship}
                  </div>
                </div>

                <div className={`mt-6 pt-4 border-t border-border flex items-center justify-between ${isRTL ? "flex-row-reverse" : ""}`}>
                  <div className={`flex items-center text-sm font-medium text-foreground ${isRTL ? "flex-row-reverse" : ""}`}>
                    <Users className={`w-4 h-4 ${isRTL ? "ml-2" : "mr-2"} text-muted-foreground`} /> {job.applicantCount} {t.applicantsCount}
                  </div>
                  <button
                    onClick={() => { setFilterJobId(job.id); setActiveTab('apps'); }}
                    className="text-sm font-medium text-primary hover:underline"
                  >{t.viewApplicants}</button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {activeTab === 'apps' && (
        <div className="space-y-3">
          {filterJobId !== null && (
            <div className={`flex items-center gap-3 px-4 py-2 bg-primary/10 rounded-lg text-sm ${isRTL ? "flex-row-reverse" : ""}`}>
              <span className="text-primary font-medium">
                {isRTL ? "عرض المتقدمين لـ: " : "Showing applicants for: "}
                <span className="font-bold">{jobs.find(j => j.id === filterJobId)?.title}</span>
              </span>
              <button onClick={() => setFilterJobId(null)} className="text-muted-foreground hover:text-foreground text-xs underline">
                {isRTL ? "عرض الكل" : "Show all"}
              </button>
            </div>
          )}
        <div className="bg-card rounded-2xl border border-border shadow-sm overflow-hidden">
          <table className="w-full text-left">
            <thead>
              <tr className={`bg-muted/30 border-b border-border ${isRTL ? "text-right" : ""}`}>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">{t.employee}</th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">{t.jobTitle}</th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">{t.appliedOn}</th>
                <th className="px-6 py-4 text-xs font-semibold text-muted-foreground uppercase tracking-wider">{t.appStatus}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {loadingApps ? (
                <tr><td colSpan={4} className="p-8 text-center text-muted-foreground">{t.loading}</td></tr>
              ) : apps.filter(a => filterJobId === null || a.jobId === filterJobId).length === 0 ? (
                <tr><td colSpan={4} className="p-8 text-center text-muted-foreground">{t.noApplicants}</td></tr>
              ) : apps.filter(a => filterJobId === null || a.jobId === filterJobId).map(app => (
                <tr key={app.id} className={`hover:bg-muted/20 ${isRTL ? "text-right" : ""}`}>
                  <td className="px-6 py-4">
                    <p className="font-semibold text-foreground">{app.applicantName}</p>
                    <p className="text-sm text-muted-foreground">{app.email}</p>
                  </td>
                  <td className="px-6 py-4 text-sm font-medium text-foreground">{app.jobTitle}</td>
                  <td className="px-6 py-4 text-sm text-muted-foreground">{format(new Date(app.appliedAt), 'MMM d, yyyy')}</td>
                  <td className="px-6 py-4">
                    <select
                      className="text-sm font-medium bg-secondary text-secondary-foreground border border-border rounded-md px-2 py-1 outline-none"
                      defaultValue={app.status}
                    >
                      <option value="new">{t.new2}</option>
                      <option value="screening">{t.screening}</option>
                      <option value="interview">{t.interview}</option>
                      <option value="offer">{t.offer}</option>
                      <option value="hired">{t.hired}</option>
                      <option value="rejected">{t.rejected}</option>
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        </div>
      )}

      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <div className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border">
            <div className={`p-6 border-b border-border bg-muted/10 ${isRTL ? "text-right" : ""}`}>
              <h2 className="text-xl font-bold">{t.newJobPosting}</h2>
            </div>
            <form onSubmit={handleJobSubmit} className="p-6 space-y-4">
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium">{t.jobTitle}</label>
                <input required name="title" dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.department}</label>
                  <select required name="departmentId" className="w-full px-3 py-2 border border-border rounded-lg bg-background">
                    <option value="">{t.selectDepartment}</option>
                    {departments.map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.type}</label>
                  <select required name="type" className="w-full px-3 py-2 border border-border rounded-lg bg-background">
                    <option value="full_time">{t.full_time}</option>
                    <option value="part_time">{t.part_time}</option>
                    <option value="contract">{t.contract}</option>
                    <option value="internship">{t.internship}</option>
                  </select>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.location}</label>
                  <input required name="location" dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg outline-none" />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.salaryRange}</label>
                  <input name="salary" dir="ltr" className="w-full px-3 py-2 border border-border rounded-lg outline-none" placeholder="e.g. $80k - $100k" />
                </div>
              </div>
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium">{t.description}</label>
                <textarea required name="description" rows={4} dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg resize-none outline-none" />
              </div>
              <div className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3`}>
                <button type="button" onClick={() => setIsAddOpen(false)} className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg">{t.cancel}</button>
                <button type="submit" disabled={createJob.isPending} className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 disabled:opacity-50">
                  {createJob.isPending ? t.saving : t.createJob}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
