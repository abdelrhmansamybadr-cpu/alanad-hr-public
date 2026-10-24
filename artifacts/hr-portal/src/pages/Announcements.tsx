import { useListAnnouncements, useCreateAnnouncement, getListAnnouncementsQueryKey } from "@workspace/api-client-react";
import { useQueryClient } from "@tanstack/react-query";
import { format } from "date-fns";
import { Megaphone, Trash2, Plus } from "lucide-react";
import { useState } from "react";
import { motion } from "framer-motion";
import { useLang } from "@/contexts/LanguageContext";

export default function Announcements() {
  const { data: announcements = [], isLoading } = useListAnnouncements();
  const queryClient = useQueryClient();
  const [isAddOpen, setIsAddOpen] = useState(false);
  const { t, isRTL } = useLang();

  const createMutation = useCreateAnnouncement({
    mutation: {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: getListAnnouncementsQueryKey() });
        setIsAddOpen(false);
      }
    }
  });

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    createMutation.mutate({
      data: {
        title: formData.get("title") as string,
        content: formData.get("content") as string,
        authorName: formData.get("authorName") as string,
        priority: formData.get("priority") as string,
      }
    });
  };

  const priorityLabel = (p: string) => {
    if (p === 'urgent') return t.urgentPriority;
    if (p === 'high') return t.high;
    if (p === 'medium') return t.medium;
    return t.low;
  };

  return (
    <div className="space-y-6">
      <div className={`flex items-center justify-between gap-4 ${isRTL ? "flex-row-reverse" : ""}`}>
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">{t.announcementsTitle}</h1>
          <p className="text-muted-foreground mt-1">{t.manageAnnouncements}</p>
        </div>
        <button
          onClick={() => setIsAddOpen(true)}
          className="flex items-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all"
          data-testid="button-new-announcement"
        >
          <Plus className="w-4 h-4" /> {t.newAnnouncement}
        </button>
      </div>

      <div className="grid gap-6 max-w-4xl">
        {isLoading ? (
          <div className="p-8 text-center text-muted-foreground">{t.loading}</div>
        ) : announcements.length === 0 ? (
          <div className="p-8 text-center bg-card rounded-xl border border-border">{t.noAnnouncements}</div>
        ) : announcements.map((ann, i) => (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.05 }}
            key={ann.id}
            className="bg-card border border-border rounded-2xl p-6 shadow-sm relative overflow-hidden"
          >
            {ann.priority === 'urgent' && (
              <div className={`absolute top-0 ${isRTL ? "right-0" : "left-0"} w-1 h-full bg-red-500`}></div>
            )}
            <div className={`flex justify-between items-start mb-4 ${isRTL ? "flex-row-reverse" : ""}`}>
              <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                <div className={`p-2 rounded-xl ${ann.priority === 'urgent' ? 'bg-red-100 text-red-600' : 'bg-primary/10 text-primary'}`}>
                  <Megaphone className="w-5 h-5" />
                </div>
                <div className={isRTL ? "text-right" : ""}>
                  <h3 className="text-lg font-bold text-foreground">{ann.title}</h3>
                  <div className={`flex items-center text-xs text-muted-foreground mt-1 gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
                    <span className="font-medium text-foreground">{ann.authorName}</span>
                    <span>•</span>
                    <span>{format(new Date(ann.createdAt), 'MMM d, yyyy h:mm a')}</span>
                  </div>
                </div>
              </div>
              <div className={`flex items-center gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                <span className={`px-2 py-1 rounded text-xs font-bold uppercase tracking-wider ${
                  ann.priority === 'urgent' ? 'bg-red-100 text-red-700' :
                  ann.priority === 'high' ? 'bg-amber-100 text-amber-700' :
                  'bg-muted text-muted-foreground'
                }`}>
                  {priorityLabel(ann.priority)}
                </span>
                <button className="text-muted-foreground hover:text-destructive p-1 transition-colors">
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>
            <div className={`text-foreground/90 whitespace-pre-wrap leading-relaxed text-sm bg-muted/20 p-4 rounded-xl ${isRTL ? "text-right" : ""}`}>
              {ann.content}
            </div>
          </motion.div>
        ))}
      </div>

      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-card w-full max-w-lg rounded-2xl shadow-xl overflow-hidden border border-border"
          >
            <div className={`p-6 border-b border-border bg-muted/10 ${isRTL ? "text-right" : ""}`}>
              <h2 className="text-xl font-bold">{t.createAnnouncement}</h2>
            </div>
            <form onSubmit={handleSubmit} className="p-6 space-y-4">
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium">{t.announcementTitle}</label>
                <input required name="title" dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20" />
              </div>
              <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                <label className="text-sm font-medium">{t.content}</label>
                <textarea required name="content" rows={4} dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg resize-none outline-none focus:ring-2 focus:ring-primary/20" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.authorName}</label>
                  <input required name="authorName" dir={isRTL ? "rtl" : "ltr"} className="w-full px-3 py-2 border border-border rounded-lg outline-none focus:ring-2 focus:ring-primary/20" />
                </div>
                <div className={`space-y-2 ${isRTL ? "text-right" : ""}`}>
                  <label className="text-sm font-medium">{t.priority}</label>
                  <select required name="priority" defaultValue="medium" className="w-full px-3 py-2 border border-border rounded-lg bg-background outline-none">
                    <option value="low">{t.low}</option>
                    <option value="medium">{t.medium}</option>
                    <option value="high">{t.high}</option>
                    <option value="urgent">{t.urgentPriority}</option>
                  </select>
                </div>
              </div>
              <div className={`pt-4 flex ${isRTL ? "flex-row-reverse" : ""} justify-end gap-3`}>
                <button type="button" onClick={() => setIsAddOpen(false)} className="px-4 py-2 text-sm font-medium text-muted-foreground hover:bg-muted rounded-lg">{t.cancel}</button>
                <button type="submit" disabled={createMutation.isPending} className="px-4 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-lg shadow hover:bg-primary/90 disabled:opacity-50">
                  {createMutation.isPending ? t.saving : t.postAnnouncement}
                </button>
              </div>
            </form>
          </motion.div>
        </div>
      )}
    </div>
  );
}
