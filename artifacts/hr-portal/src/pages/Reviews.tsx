import { useListReviews } from "@workspace/api-client-react";
import { Star, FileText } from "lucide-react";
import { format } from "date-fns";
import { useLang } from "@/contexts/LanguageContext";

export default function Reviews() {
  const { data: reviews = [], isLoading } = useListReviews();
  const { t, isRTL } = useLang();

  const statusLabel = (s: string) => {
    if (s === 'acknowledged') return t.acknowledged;
    if (s === 'submitted') return t.submitted;
    return t.draft;
  };

  return (
    <div className="space-y-6">
      <div className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 ${isRTL ? "sm:flex-row-reverse" : ""}`}>
        <div className={isRTL ? "text-right" : ""}>
          <h1 className="text-3xl font-bold text-foreground tracking-tight">{t.reviewsTitle}</h1>
          <p className="text-muted-foreground mt-1">{t.manageReviews}</p>
        </div>
        <button className="px-4 py-2.5 bg-primary text-primary-foreground rounded-xl font-medium shadow-sm hover:-translate-y-0.5 transition-all">
          {t.addReview}
        </button>
      </div>

      <div className="grid grid-cols-1 gap-4">
        {isLoading ? (
          <div className="p-12 text-center text-muted-foreground">{t.loading}</div>
        ) : reviews.length === 0 ? (
          <div className="p-12 text-center bg-card rounded-xl border border-border text-muted-foreground">{t.noReviews}</div>
        ) : (
          reviews.map(review => (
            <div key={review.id} className="bg-card rounded-2xl border border-border shadow-sm p-6 flex flex-col md:flex-row md:items-center gap-6 hover:shadow-md transition-shadow">
              <div className={`flex-1 ${isRTL ? "text-right" : ""}`}>
                <div className={`flex items-center gap-3 mb-2 flex-wrap ${isRTL ? "flex-row-reverse" : ""}`}>
                  <h3 className="text-lg font-bold text-foreground">{review.employeeName}</h3>
                  <span className="text-xs px-2 py-1 bg-muted text-muted-foreground rounded-md uppercase font-semibold tracking-wider">
                    {review.period}
                  </span>
                  <span className={`text-xs px-2 py-1 rounded-md uppercase font-semibold tracking-wider ${
                    review.status === 'acknowledged' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'
                  }`}>
                    {statusLabel(review.status)}
                  </span>
                </div>
                <div className={`flex items-center gap-1 text-amber-500 mb-3 ${isRTL ? "flex-row-reverse" : ""}`}>
                  {[...Array(5)].map((_, i) => (
                    <Star key={i} className={`w-5 h-5 ${i < review.rating ? 'fill-current' : 'text-muted/30 fill-transparent'}`} />
                  ))}
                  <span className={`${isRTL ? "mr-2" : "ml-2"} text-sm font-medium text-muted-foreground`}>({review.rating}/5)</span>
                </div>
                <div className={`text-sm text-muted-foreground flex items-start gap-2 ${isRTL ? "flex-row-reverse" : ""}`}>
                  <FileText className="w-4 h-4 shrink-0 mt-0.5" />
                  <p className="line-clamp-2">{review.feedback || "—"}</p>
                </div>
              </div>
              <div className={`md:border-${isRTL ? "r" : "l"} md:border-border md:${isRTL ? "pr-6" : "pl-6"} md:w-48 shrink-0 flex flex-col justify-center ${isRTL ? "text-right" : ""}`}>
                <p className="text-xs text-muted-foreground mb-1">{t.reviewer}</p>
                <p className="text-sm font-semibold text-foreground">{review.reviewerName || "—"}</p>
                <p className="text-xs text-muted-foreground mt-4 mb-1">{t.date}</p>
                <p className="text-sm font-medium text-foreground">{format(new Date(review.reviewedAt), 'MMM d, yyyy')}</p>
                <button className="mt-4 w-full text-xs font-medium border border-border rounded-lg py-2 hover:bg-muted transition-colors">
                  {t.viewAll}
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
