// Certificate engine: the design (JSON blocks) is drawn on a canvas so Arabic is shaped by the browser; the finished
// picture is sent to the server, which wraps it in a PDF and e-mails it. The Flutter app draws the same JSON.
import { authToken } from "@/lib/http";

export type Align = "left" | "center" | "right";
export type Block = {
  id: string;
  type: "text" | "image";
  x: number; y: number; w: number;            // % of the page (top-left corner, width)
  text?: string; size?: number;               // size = % of the page height
  color?: string; align?: Align; bold?: boolean; italic?: boolean;
  font?: "sans" | "serif" | "mono"; lh?: number;
  asset?: number; h?: number;                 // picture block: asset id and height in %
};
export type Frame = { style: "none" | "single" | "double"; color: string; width: number; inset: number };
export type Layout = { frame: Frame; blocks: Block[] };
export type Template = {
  id?: number; name: string; kind: string; lang: "ar" | "en";
  width: number; height: number; bgColor: string; bgAssetId: number | null; layout: Layout;
};

export const KINDS = ["experience", "end_of_service", "clearance", "custom"] as const;
export const PLACEHOLDERS: { key: string; en: string; ar: string }[] = [
  { key: "name", en: "Full name", ar: "الاسم الكامل" },
  { key: "position", en: "Job title", ar: "المسمى الوظيفي" },
  { key: "department", en: "Department", ar: "القسم" },
  { key: "company", en: "Company", ar: "الشركة" },
  { key: "start_date", en: "Start date", ar: "تاريخ البدء" },
  { key: "end_date", en: "Leaving date", ar: "تاريخ المغادرة" },
  { key: "duration", en: "Time worked", ar: "مدة العمل" },
  { key: "issue_date", en: "Issue date", ar: "تاريخ الإصدار" },
  { key: "serial", en: "Certificate no.", ar: "رقم الشهادة" },
  { key: "note", en: "Extra note", ar: "ملاحظة إضافية" },
];

const FONT = {
  sans: '"Segoe UI", Tahoma, "Noto Sans Arabic", Arial, sans-serif',
  serif: 'Georgia, "Times New Roman", "Traditional Arabic", "Noto Naskh Arabic", serif',
  mono: '"Courier New", monospace',
};

export const emptyLayout = (): Layout => ({ frame: { style: "none", color: "#b8975a", width: 6, inset: 24 }, blocks: [] });

export function parseTemplate(raw: any): Template {
  let layout: Layout = emptyLayout();
  try { const l = typeof raw.layout === "string" ? JSON.parse(raw.layout) : raw.layout; if (l && Array.isArray(l.blocks)) layout = { frame: l.frame ?? layout.frame, blocks: l.blocks }; } catch { /* keep empty */ }
  return {
    id: raw.id, name: raw.name ?? "", kind: raw.kind ?? "custom", lang: raw.lang === "ar" ? "ar" : "en",
    width: Number(raw.width) || 1123, height: Number(raw.height) || 794, bgColor: raw.bgColor ?? "#ffffff",
    bgAssetId: raw.bgAssetId ?? null, layout,
  };
}

/** The body the API wants when saving a design (layout travels as a JSON string). */
export const templatePayload = (t: Template) => ({
  name: t.name, kind: t.kind, lang: t.lang, width: Math.round(t.width), height: Math.round(t.height),
  bgColor: t.bgColor, bgAssetId: t.bgAssetId, layout: JSON.stringify(t.layout),
});

// ---------------------------------------------------------------- pictures (protected, fetched with the login token)

const imageCache = new Map<number, Promise<HTMLImageElement>>();
export function loadAsset(id: number): Promise<HTMLImageElement> {
  let p = imageCache.get(id);
  if (!p) {
    p = fetch(`/api/certificates/assets/${id}`, { headers: { Authorization: `Bearer ${authToken()}` } })
      .then((r) => { if (!r.ok) throw new Error("picture"); return r.blob(); })
      .then((b) => new Promise<HTMLImageElement>((res, rej) => {
        const img = new Image();
        img.onload = () => res(img);
        img.onerror = () => rej(new Error("picture"));
        img.src = URL.createObjectURL(b);
      }));
    imageCache.set(id, p);
    p.catch(() => imageCache.delete(id));
  }
  return p;
}

export async function loadImages(t: Template): Promise<Map<number, HTMLImageElement>> {
  const ids = new Set<number>();
  if (t.bgAssetId) ids.add(t.bgAssetId);
  t.layout.blocks.forEach((b) => { if (b.type === "image" && b.asset) ids.add(b.asset); });
  const map = new Map<number, HTMLImageElement>();
  await Promise.all([...ids].map(async (id) => { try { map.set(id, await loadAsset(id)); } catch { /* a missing picture is just not drawn */ } }));
  return map;
}

export function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(new Error("read")); r.readAsDataURL(file); });
}

export function imageSize(dataUrl: string): Promise<{ w: number; h: number }> {
  return new Promise((res, rej) => { const i = new Image(); i.onload = () => res({ w: i.naturalWidth, h: i.naturalHeight }); i.onerror = () => rej(new Error("image")); i.src = dataUrl; });
}

// ---------------------------------------------------------------- drawing

const RTL_CHARS = /[֐-ࣿיִ-﷿ﹰ-﻿]/;
const fill = (text: string, v: Record<string, string>) => text.replace(/\{(\w+)\}/g, (_, k) => v[k] ?? "");

function wrapLine(ctx: CanvasRenderingContext2D, line: string, maxW: number): string[] {
  if (!line) return [""];
  const words = line.split(/\s+/).filter(Boolean);
  const out: string[] = [];
  let cur = "";
  for (const w of words) {
    const test = cur ? `${cur} ${w}` : w;
    if (cur && ctx.measureText(test).width > maxW) { out.push(cur); cur = w; } else cur = test;
  }
  if (cur) out.push(cur);
  return out.length ? out : [""];
}

export type Boxes = Record<string, { x: number; y: number; w: number; h: number }>;

/** Draw the design. Returns the canvas and the box of every block (in design pixels) for the editor handles. */
export function renderCertificate(
  t: Template, values: Record<string, string>, images: Map<number, HTMLImageElement>, scale = 1,
): { canvas: HTMLCanvasElement; boxes: Boxes } {
  const W = t.width, H = t.height;
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(W * scale); canvas.height = Math.round(H * scale);
  const ctx = canvas.getContext("2d")!;
  ctx.scale(scale, scale);
  ctx.fillStyle = t.bgColor || "#ffffff";
  ctx.fillRect(0, 0, W, H);
  const bg = t.bgAssetId ? images.get(t.bgAssetId) : undefined;
  if (bg) ctx.drawImage(bg, 0, 0, W, H);

  const f = t.layout.frame;
  if (f && f.style !== "none") {
    ctx.strokeStyle = f.color; ctx.lineWidth = f.width;
    ctx.strokeRect(f.inset, f.inset, W - 2 * f.inset, H - 2 * f.inset);
    if (f.style === "double") {
      const g = f.inset + f.width * 2.4;
      ctx.lineWidth = Math.max(1, f.width / 3);
      ctx.strokeRect(g, g, W - 2 * g, H - 2 * g);
    }
  }

  const boxes: Boxes = {};
  for (const b of t.layout.blocks) {
    const bx = (b.x / 100) * W, by = (b.y / 100) * H, bw = (b.w / 100) * W;
    if (b.type === "image") {
      const bh = ((b.h ?? 10) / 100) * H;
      const img = b.asset ? images.get(b.asset) : undefined;
      if (img) {
        const r = Math.min(bw / img.naturalWidth, bh / img.naturalHeight);
        const dw = img.naturalWidth * r, dh = img.naturalHeight * r;
        ctx.drawImage(img, bx + (bw - dw) / 2, by + (bh - dh) / 2, dw, dh);
      } else { ctx.strokeStyle = "#9ca3af"; ctx.setLineDash([6, 4]); ctx.lineWidth = 1; ctx.strokeRect(bx, by, bw, bh); ctx.setLineDash([]); }
      boxes[b.id] = { x: bx, y: by, w: bw, h: bh };
      continue;
    }
    const px = ((b.size ?? 3) / 100) * H;
    const lineH = px * (b.lh ?? 1.5);
    ctx.font = `${b.italic ? "italic " : ""}${b.bold ? "bold " : ""}${px}px ${FONT[b.font ?? "sans"]}`;
    ctx.fillStyle = b.color || "#1f2937";
    ctx.textBaseline = "top";
    const align = b.align ?? "center";
    ctx.textAlign = align;
    const ax = align === "left" ? bx : align === "right" ? bx + bw : bx + bw / 2;
    let y = by;
    for (const para of fill(b.text ?? "", values).split("\n")) {
      ctx.direction = RTL_CHARS.test(para) ? "rtl" : "ltr";
      for (const line of wrapLine(ctx, para, bw)) { ctx.fillText(line, ax, y + (lineH - px) / 2); y += lineH; }
    }
    ctx.direction = "ltr";
    boxes[b.id] = { x: bx, y: by, w: bw, h: Math.max(lineH, y - by) };
  }
  return { canvas, boxes };
}

export const toJpeg = (c: HTMLCanvasElement, q = 0.92) => c.toDataURL("image/jpeg", q);

// ---------------------------------------------------------------- values for the placeholders

export function fmtDate(iso: string | null | undefined, lang: "ar" | "en"): string {
  if (!iso) return "";
  const d = new Date(iso.slice(0, 10) + "T12:00:00");
  if (isNaN(+d)) return iso;
  return new Intl.DateTimeFormat(lang === "ar" ? "ar-EG-u-nu-latn" : "en-GB", { day: "numeric", month: "long", year: "numeric" }).format(d);
}

const arCount = (n: number, one: string, two: string, few: string, many: string) =>
  n === 1 ? one : n === 2 ? two : n >= 3 && n <= 10 ? `${n} ${few}` : `${n} ${many}`;

/** "2 years and 3 months" / "سنتان و3 أشهر" between two dates (at least the days when shorter than a month). */
export function duration(start: string | null | undefined, end: string | null | undefined, lang: "ar" | "en"): string {
  if (!start || !end) return "";
  const a = new Date(start.slice(0, 10) + "T12:00:00"), b = new Date(end.slice(0, 10) + "T12:00:00");
  if (isNaN(+a) || isNaN(+b) || b < a) return "";
  let y = b.getFullYear() - a.getFullYear(), m = b.getMonth() - a.getMonth(), d = b.getDate() - a.getDate() + 1;
  if (d < 0) { m -= 1; d += new Date(b.getFullYear(), b.getMonth(), 0).getDate(); }
  if (m < 0) { y -= 1; m += 12; }
  const parts: string[] = [];
  if (lang === "ar") {
    if (y) parts.push(arCount(y, "سنة", "سنتان", "سنوات", "سنة"));
    if (m) parts.push(arCount(m, "شهر", "شهران", "أشهر", "شهرًا"));
    if (!y && !m) parts.push(arCount(Math.max(1, d), "يوم", "يومان", "أيام", "يومًا"));
    return parts.join(" و");
  }
  if (y) parts.push(`${y} year${y === 1 ? "" : "s"}`);
  if (m) parts.push(`${m} month${m === 1 ? "" : "s"}`);
  if (!y && !m) parts.push(`${Math.max(1, d)} day${d === 1 ? "" : "s"}`);
  return parts.join(" and ");
}

/** Keep a code such as CERT-2026-0001 in its own left-to-right run inside Arabic text (otherwise the parts swap places). */
const ltr = (v: string, lang: "ar" | "en") => (lang === "ar" ? `\u2066${v}\u2069` : v);

export type EmployeeLite = { firstName: string; lastName: string; position?: string | null; departmentName?: string | null; startDate?: string | null };

export function buildValues(e: EmployeeLite, o: { company: string; serial: string; issueDate: string; startDate: string; endDate: string; lang: "ar" | "en"; note?: string }): Record<string, string> {
  return {
    name: `${e.firstName} ${e.lastName}`.trim(), first_name: e.firstName, last_name: e.lastName,
    position: e.position ?? "", department: e.departmentName ?? "", company: o.company,
    start_date: fmtDate(o.startDate, o.lang), end_date: fmtDate(o.endDate, o.lang), issue_date: fmtDate(o.issueDate, o.lang),
    duration: duration(o.startDate, o.endDate, o.lang), serial: ltr(o.serial, o.lang), note: o.note ?? "",
  };
}

export const sampleValues = (lang: "ar" | "en"): Record<string, string> =>
  lang === "ar"
    ? { name: "محمد أحمد علي", position: "محاسب أول", department: "المالية", company: "اسم الشركة", start_date: fmtDate("2022-03-01", "ar"), end_date: fmtDate("2026-03-01", "ar"), duration: "4 سنوات", issue_date: fmtDate("2026-03-05", "ar"), serial: "\u2066CERT-2026-0001\u2069", note: "" }
    : { name: "Mohamed Ahmed Ali", position: "Senior Accountant", department: "Finance", company: "Company name", start_date: fmtDate("2022-03-01", "en"), end_date: fmtDate("2026-03-01", "en"), duration: "4 years", issue_date: fmtDate("2026-03-05", "en"), serial: "CERT-2026-0001", note: "" };
