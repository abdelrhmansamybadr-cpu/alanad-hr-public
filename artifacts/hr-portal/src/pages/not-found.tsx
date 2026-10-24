import { useLocation } from "wouter";
import { useLang } from "@/contexts/LanguageContext";

export default function NotFound() {
  const [, navigate] = useLocation();
  const { isRTL } = useLang();

  return (
    <div
      className={`min-h-screen flex flex-col items-center justify-center bg-background text-foreground px-4 ${isRTL ? "text-right" : "text-center"}`}
      dir={isRTL ? "rtl" : "ltr"}
    >
      <div className="relative mb-8 select-none">
        <span className="text-[160px] font-black leading-none text-primary/10">
          404
        </span>
        <span className="absolute inset-0 flex items-center justify-center text-7xl font-black text-primary">
          404
        </span>
      </div>

      <h2 className="text-2xl font-bold text-foreground mb-3">
        {isRTL ? "الصفحة غير موجودة" : "Page Not Found"}
      </h2>
      <p className="text-muted-foreground mb-10 max-w-sm text-sm leading-relaxed">
        {isRTL
          ? "الصفحة التي تبحث عنها غير موجودة أو ربما تم نقلها."
          : "The page you're looking for doesn't exist or may have been moved."}
      </p>

      <div className={`flex gap-3 ${isRTL ? "flex-row-reverse" : ""}`}>
        <button
          onClick={() => window.history.back()}
          className="px-5 py-2.5 text-sm font-medium border border-border rounded-xl text-muted-foreground hover:bg-muted transition-colors"
        >
          {isRTL ? "رجوع" : "Go Back"}
        </button>
        <button
          onClick={() => navigate("/")}
          className="px-5 py-2.5 text-sm font-medium bg-primary text-primary-foreground rounded-xl shadow-sm shadow-primary/20 hover:-translate-y-0.5 hover:shadow-md transition-all"
        >
          {isRTL ? "الرئيسية" : "Dashboard"}
        </button>
      </div>
    </div>
  );
}
