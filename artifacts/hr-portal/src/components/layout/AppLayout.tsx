import { Sidebar } from "./Sidebar";
import { Header } from "./Header";
import { ReactNode } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useLocation } from "wouter";
import { useLang } from "@/contexts/LanguageContext";

export function AppLayout({ children }: { children: ReactNode }) {
  const [location] = useLocation();
  const { isRTL } = useLang();

  return (
    <div className={`flex h-screen bg-muted/20 overflow-hidden font-sans`} dir={isRTL ? "rtl" : "ltr"}>
      <Sidebar />
      <div className="flex flex-col flex-1 overflow-hidden relative">
        <Header />
        <main className="flex-1 overflow-y-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={location}
              initial={{ opacity: 0, y: 10, filter: "blur(4px)" }}
              animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
              exit={{ opacity: 0, y: -10, filter: "blur(4px)" }}
              transition={{ duration: 0.25, ease: "easeOut" }}
              className="p-6 md:p-8 max-w-7xl mx-auto h-full"
            >
              {children}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>
    </div>
  );
}
