import { useState, useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import { X, HelpCircle, MessageSquare } from "lucide-react";
import { toast } from "sonner";
import { useLang } from "@/contexts/LanguageContext";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";

interface HelpPanelProps {
  open: boolean;
  onClose: () => void;
}

export function HelpPanel({ open, onClose }: HelpPanelProps) {
  const { t, isRTL } = useLang();
  const [activeTab, setActiveTab] = useState<"faq" | "feedback">("faq");
  const [feedbackType, setFeedbackType] = useState("feedback");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open, onClose]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [open, onClose]);

  const faqs = [
    { q: t.faq1Q, a: t.faq1A },
    { q: t.faq2Q, a: t.faq2A },
    { q: t.faq3Q, a: t.faq3A },
    { q: t.faq4Q, a: t.faq4A },
    { q: t.faq5Q, a: t.faq5A },
    { q: t.faq6Q, a: t.faq6A },
  ];

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!message.trim()) return;
    setSending(true);
    setTimeout(() => {
      setSending(false);
      setMessage("");
      setFeedbackType("feedback");
      toast.success(t.feedbackSuccess);
      onClose();
    }, 800);
  }

  const positionClass = isRTL ? "left-6" : "right-6";

  const panel = (
    <AnimatePresence>
      {open && (
        <motion.div
          ref={panelRef}
          initial={{ opacity: 0, y: 20, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 20, scale: 0.95 }}
          transition={{ duration: 0.2, ease: "easeOut" }}
          className={`fixed bottom-6 ${positionClass} z-50 w-96 max-w-[calc(100vw-3rem)] bg-background border border-border rounded-2xl shadow-2xl flex flex-col overflow-hidden`}
          dir={isRTL ? "rtl" : "ltr"}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-border bg-primary/5">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center text-primary">
                <HelpCircle className="w-4 h-4" />
              </div>
              <span className="font-semibold text-sm text-foreground">{t.helpTitle}</span>
            </div>
            <button
              onClick={onClose}
              className="w-7 h-7 flex items-center justify-center rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          {/* Tabs */}
          <div className="flex border-b border-border">
            <button
              onClick={() => setActiveTab("faq")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 text-xs font-medium transition-colors ${
                activeTab === "faq"
                  ? "text-primary border-b-2 border-primary bg-primary/5"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <HelpCircle className="w-3.5 h-3.5" />
              {t.helpFaqTab}
            </button>
            <button
              onClick={() => setActiveTab("feedback")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 text-xs font-medium transition-colors ${
                activeTab === "feedback"
                  ? "text-primary border-b-2 border-primary bg-primary/5"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <MessageSquare className="w-3.5 h-3.5" />
              {t.helpFeedbackTab}
            </button>
          </div>

          {/* Content */}
          <div className="overflow-y-auto max-h-[380px]">
            {activeTab === "faq" ? (
              <div className="px-3 py-2">
                <Accordion type="single" collapsible className="w-full">
                  {faqs.map((faq, i) => (
                    <AccordionItem key={i} value={`faq-${i}`} className="border-border">
                      <AccordionTrigger className={`text-xs font-medium py-3 hover:no-underline text-foreground ${isRTL ? "text-right flex-row-reverse" : "text-left"}`}>
                        {faq.q}
                      </AccordionTrigger>
                      <AccordionContent className={`text-xs text-muted-foreground leading-relaxed pb-3 ${isRTL ? "text-right" : "text-left"}`}>
                        {faq.a}
                      </AccordionContent>
                    </AccordionItem>
                  ))}
                </Accordion>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="p-4 space-y-4">
                <div>
                  <label className={`block text-xs font-medium text-foreground mb-1.5 ${isRTL ? "text-right" : "text-left"}`}>
                    {t.feedbackType}
                  </label>
                  <select
                    value={feedbackType}
                    onChange={(e) => setFeedbackType(e.target.value)}
                    className={`w-full text-xs rounded-lg border border-border bg-background px-3 py-2 text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 ${isRTL ? "text-right" : "text-left"}`}
                  >
                    <option value="feedback">{t.feedbackTypeFeedback}</option>
                    <option value="bug">{t.feedbackTypeBug}</option>
                    <option value="feature">{t.feedbackTypeFeature}</option>
                  </select>
                </div>

                <div>
                  <label className={`block text-xs font-medium text-foreground mb-1.5 ${isRTL ? "text-right" : "text-left"}`}>
                    {t.feedbackMessage}
                  </label>
                  <textarea
                    value={message}
                    onChange={(e) => setMessage(e.target.value)}
                    placeholder={t.feedbackPlaceholder}
                    rows={4}
                    className={`w-full text-xs rounded-lg border border-border bg-background px-3 py-2 text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 resize-none ${isRTL ? "text-right" : "text-left"}`}
                  />
                </div>

                <button
                  type="submit"
                  disabled={!message.trim() || sending}
                  className="w-full bg-primary text-primary-foreground text-xs font-medium rounded-lg px-4 py-2.5 hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                >
                  {sending ? "..." : t.feedbackSend}
                </button>
              </form>
            )}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );

  return createPortal(panel, document.body);
}
