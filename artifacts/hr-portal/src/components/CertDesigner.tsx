import { useEffect, useMemo, useRef, useState } from "react";
import { ImagePlus, Type, Trash2, Copy, ChevronUp, ChevronDown, AlignLeft, AlignCenter, AlignRight, Bold, Italic, X } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/http";
import { inputCls, btnGhost, useTr } from "@/components/kit";
import {
  type Block, type Template, type Boxes, PLACEHOLDERS, KINDS, loadImages, renderCertificate, readFileAsDataUrl, imageSize,
} from "@/lib/certRender";

/** Upload a picture for a certificate (background, logo, signature, stamp). */
export async function uploadPicture(file: File): Promise<{ id: number; width: number; height: number }> {
  if (!/^image\/(png|jpe?g|webp)$/.test(file.type)) throw new Error("Use a PNG, JPG or WEBP picture");
  if (file.size > 8 * 1024 * 1024) throw new Error("The picture is larger than 8 MB");
  const dataUrl = await readFileAsDataUrl(file);
  const d = await api<{ id: number; width: number; height: number }>("/certificates/assets", "POST", { dataUrl, name: file.name.slice(0, 120) });
  return d;
}

const uid = () => "b" + Math.random().toString(36).slice(2, 8);
const label = "block text-xs font-medium text-muted-foreground mb-1";

export function CertDesigner({ value, onChange, values }: { value: Template; onChange: (t: Template) => void; values: Record<string, string> }) {
  const tr = useTr();
  const [images, setImages] = useState<Map<number, HTMLImageElement>>(new Map());
  const [boxes, setBoxes] = useState<Boxes>({});
  const [sel, setSel] = useState<string | null>(value.layout.blocks[0]?.id ?? null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const bgFile = useRef<HTMLInputElement>(null);
  const imgFile = useRef<HTMLInputElement>(null);
  const textRef = useRef<HTMLTextAreaElement>(null);
  const drag = useRef<null | { id: string; mode: "move" | "size"; sx: number; sy: number; x: number; y: number; w: number }>(null);

  const assetKey = useMemo(() => [value.bgAssetId, ...value.layout.blocks.map((b) => (b.type === "image" ? b.asset : 0))].join(","), [value]);
  useEffect(() => { let on = true; loadImages(value).then((m) => on && setImages(m)); return () => { on = false; }; /* eslint-disable-next-line */ }, [assetKey]);

  useEffect(() => {
    const { canvas, boxes: bx } = renderCertificate(value, values, images, 1);
    const c = canvasRef.current;
    if (c) { c.width = canvas.width; c.height = canvas.height; c.getContext("2d")!.drawImage(canvas, 0, 0); }
    setBoxes(bx);
  }, [value, values, images]);

  const blocks = value.layout.blocks;
  const cur = blocks.find((b) => b.id === sel) ?? null;
  const setBlock = (id: string, patch: Partial<Block>) => onChange({ ...value, layout: { ...value.layout, blocks: blocks.map((b) => (b.id === id ? { ...b, ...patch } : b)) } });
  const setBlocks = (bl: Block[]) => onChange({ ...value, layout: { ...value.layout, blocks: bl } });
  const set = (patch: Partial<Template>) => onChange({ ...value, ...patch });
  const setFrame = (patch: Partial<Template["layout"]["frame"]>) => onChange({ ...value, layout: { ...value.layout, frame: { ...value.layout.frame, ...patch } } });

  function addText() {
    const b: Block = { id: uid(), type: "text", text: value.lang === "ar" ? "نص جديد" : "New text", x: 20, y: 30, w: 60, size: 3.6, color: "#1f2937", align: "center", font: "sans", lh: 1.5 };
    setBlocks([...blocks, b]); setSel(b.id);
  }
  async function addImage(f: File) {
    try {
      const a = await uploadPicture(f);
      const ratio = a.height / a.width;
      const w = 16, h = Math.min(40, w * ratio * (value.width / value.height));
      const b: Block = { id: uid(), type: "image", asset: a.id, x: 42, y: 70, w, h };
      setBlocks([...blocks, b]); setSel(b.id);
    } catch (e: any) { toast.error(e.message); }
  }
  async function setBackground(f: File) {
    try {
      const dataUrl = await readFileAsDataUrl(f);
      const size = await imageSize(dataUrl);
      const a = await uploadPicture(f);
      const w = 1123, h = Math.min(4000, Math.max(300, Math.round((w * size.h) / size.w)));
      set({ bgAssetId: a.id, width: w, height: h });
      toast.success(tr("Background added — now place the name where it belongs.", "تمت إضافة الخلفية — ضع الاسم في مكانه."));
    } catch (e: any) { toast.error(e.message); }
  }
  function insertPlaceholder(k: string) {
    if (!cur || cur.type !== "text") return;
    const ta = textRef.current;
    const text = cur.text ?? "";
    const s = ta?.selectionStart ?? text.length, e = ta?.selectionEnd ?? text.length;
    setBlock(cur.id, { text: text.slice(0, s) + `{${k}}` + text.slice(e) });
  }
  const move = (dir: -1 | 1) => {
    const i = blocks.findIndex((b) => b.id === sel); const j = i + dir;
    if (i < 0 || j < 0 || j >= blocks.length) return;
    const a = [...blocks]; [a[i], a[j]] = [a[j], a[i]]; setBlocks(a);
  };

  // ------------------------------------------------ dragging on the page
  function down(e: React.PointerEvent, b: Block, mode: "move" | "size") {
    e.preventDefault(); e.stopPropagation();
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    setSel(b.id);
    drag.current = { id: b.id, mode, sx: e.clientX, sy: e.clientY, x: b.x, y: b.y, w: b.w };
  }
  function moveP(e: React.PointerEvent) {
    const d = drag.current, r = stageRef.current?.getBoundingClientRect();
    if (!d || !r) return;
    const dx = ((e.clientX - d.sx) / r.width) * 100, dy = ((e.clientY - d.sy) / r.height) * 100;
    if (d.mode === "move") setBlock(d.id, { x: Math.round((d.x + dx) * 10) / 10, y: Math.round((d.y + dy) * 10) / 10 });
    else setBlock(d.id, { w: Math.max(3, Math.round((d.w + dx) * 10) / 10) });
  }
  const up = () => { drag.current = null; };

  const num = (v: number | undefined, f: (n: number) => void, step = 1) => (
    <input type="number" step={step} className={inputCls} value={Number.isFinite(v as number) ? v : 0} onChange={(e) => f(Number(e.target.value))} />
  );

  return (
    <div className="grid lg:grid-cols-[minmax(0,1fr)_340px] gap-5">
      {/* ---------------- the page */}
      <div>
        <div
          ref={stageRef}
          className="relative w-full bg-muted/30 border border-border rounded-xl shadow-inner overflow-hidden select-none touch-none"
          style={{ aspectRatio: `${value.width} / ${value.height}` }}
          onPointerMove={moveP} onPointerUp={up} onPointerCancel={up}
          onPointerDown={() => setSel(null)}
        >
          <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" />
          {blocks.map((b) => {
            const bx = boxes[b.id]; if (!bx) return null;
            const on = b.id === sel;
            return (
              <div
                key={b.id}
                onPointerDown={(e) => down(e, b, "move")}
                className={`absolute cursor-move ${on ? "outline outline-2 outline-primary bg-primary/5" : "hover:outline hover:outline-1 hover:outline-primary/50"}`}
                style={{ left: `${(bx.x / value.width) * 100}%`, top: `${(bx.y / value.height) * 100}%`, width: `${(bx.w / value.width) * 100}%`, height: `${(bx.h / value.height) * 100}%` }}
              >
                {on && <span onPointerDown={(e) => down(e, b, "size")} className="absolute -right-1.5 -bottom-1.5 h-3.5 w-3.5 rounded-sm bg-primary cursor-ew-resize" title={tr("Drag to change the width", "اسحب لتغيير العرض")} />}
              </div>
            );
          })}
        </div>
        <p className="text-xs text-muted-foreground mt-2">{tr("Drag a box to place it. Drag its corner to change the width. The preview uses sample data.", "اسحب الصندوق لوضعه في مكانه، واسحب زاويته لتغيير العرض. المعاينة ببيانات تجريبية.")}</p>
      </div>

      {/* ---------------- tools */}
      <div className="space-y-4 text-sm">
        <section className="border border-border rounded-xl p-3 space-y-3">
          <div>
            <label className={label}>{tr("Design name", "اسم التصميم")}</label>
            <input className={inputCls} value={value.name} onChange={(e) => set({ name: e.target.value })} />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className={label}>{tr("Type", "النوع")}</label>
              <select className={inputCls} value={value.kind} onChange={(e) => set({ kind: e.target.value })}>
                {KINDS.map((k) => <option key={k} value={k}>{{ experience: tr("Experience", "خبرة"), end_of_service: tr("End of service", "إنهاء خدمة"), clearance: tr("Clearance", "إخلاء طرف"), custom: tr("Other", "أخرى") }[k]}</option>)}
              </select>
            </div>
            <div>
              <label className={label}>{tr("Language", "اللغة")}</label>
              <select className={inputCls} value={value.lang} onChange={(e) => set({ lang: e.target.value as "ar" | "en" })}>
                <option value="ar">العربية</option><option value="en">English</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className={label}>{tr("Page", "الصفحة")}</label>
              <select className={inputCls} value={value.height < value.width ? "land" : "port"} onChange={(e) => set(e.target.value === "land" ? { width: 1123, height: 794 } : { width: 794, height: 1123 })}>
                <option value="land">{tr("A4 landscape", "A4 عرضي")}</option><option value="port">{tr("A4 portrait", "A4 طولي")}</option>
              </select>
            </div>
            <div>
              <label className={label}>{tr("Background colour", "لون الخلفية")}</label>
              <input type="color" className="h-9 w-full rounded-lg border border-border" value={value.bgColor} onChange={(e) => set({ bgColor: e.target.value })} />
            </div>
          </div>
          <div>
            <label className={label}>{tr("Your own design (picture with an empty place for the name)", "تصميمك الخاص (صورة بها مكان فارغ للاسم)")}</label>
            <div className="flex gap-2">
              <button type="button" className={btnGhost + " flex-1"} onClick={() => bgFile.current?.click()}><ImagePlus className="h-4 w-4" />{value.bgAssetId ? tr("Change picture", "تغيير الصورة") : tr("Upload picture", "رفع صورة")}</button>
              {value.bgAssetId && <button type="button" className={btnGhost} onClick={() => set({ bgAssetId: null })} title={tr("Remove the picture", "إزالة الصورة")}><X className="h-4 w-4" /></button>}
            </div>
            <input ref={bgFile} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) setBackground(f); e.target.value = ""; }} />
          </div>
          <div className="grid grid-cols-[1fr_72px_72px] gap-2 items-end">
            <div>
              <label className={label}>{tr("Frame", "الإطار")}</label>
              <select className={inputCls} value={value.layout.frame.style} onChange={(e) => setFrame({ style: e.target.value as any })}>
                <option value="none">{tr("None", "بدون")}</option><option value="single">{tr("Single line", "خط واحد")}</option><option value="double">{tr("Double line", "خطان")}</option>
              </select>
            </div>
            <input type="color" className="h-9 w-full rounded-lg border border-border" value={value.layout.frame.color} onChange={(e) => setFrame({ color: e.target.value })} />
            {num(value.layout.frame.width, (n) => setFrame({ width: Math.max(1, n) }))}
          </div>
        </section>

        <section className="border border-border rounded-xl p-3 space-y-3">
          <div className="flex gap-2">
            <button type="button" className={btnGhost + " flex-1"} onClick={addText}><Type className="h-4 w-4" />{tr("Add text", "إضافة نص")}</button>
            <button type="button" className={btnGhost + " flex-1"} onClick={() => imgFile.current?.click()}><ImagePlus className="h-4 w-4" />{tr("Logo / signature", "شعار / توقيع")}</button>
            <input ref={imgFile} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) addImage(f); e.target.value = ""; }} />
          </div>
          <div className="max-h-36 overflow-auto divide-y divide-border border border-border rounded-lg">
            {blocks.length === 0 && <p className="p-3 text-muted-foreground">{tr("No boxes yet.", "لا توجد صناديق بعد.")}</p>}
            {blocks.map((b) => (
              <button key={b.id} type="button" onClick={() => setSel(b.id)} className={`w-full text-start px-3 py-1.5 truncate ${b.id === sel ? "bg-primary/10 text-primary font-medium" : "hover:bg-muted/50"}`}>
                {b.type === "image" ? "🖼 " + tr("Picture", "صورة") : (b.text || "…").split("\n")[0].slice(0, 40)}
              </button>
            ))}
          </div>
        </section>

        {cur && (
          <section className="border border-primary/30 rounded-xl p-3 space-y-3">
            <div className="flex items-center justify-between">
              <b>{cur.type === "image" ? tr("Picture", "صورة") : tr("Text box", "صندوق نص")}</b>
              <div className="flex gap-1">
                <button type="button" className="p-1.5 rounded-md hover:bg-muted" onClick={() => move(-1)} title={tr("Move back", "للخلف")}><ChevronUp className="h-4 w-4" /></button>
                <button type="button" className="p-1.5 rounded-md hover:bg-muted" onClick={() => move(1)} title={tr("Bring forward", "للأمام")}><ChevronDown className="h-4 w-4" /></button>
                <button type="button" className="p-1.5 rounded-md hover:bg-muted" onClick={() => { const c = { ...cur, id: uid(), x: cur.x + 2, y: cur.y + 3 }; setBlocks([...blocks, c]); setSel(c.id); }} title={tr("Duplicate", "نسخ")}><Copy className="h-4 w-4" /></button>
                <button type="button" className="p-1.5 rounded-md hover:bg-destructive/10 text-destructive" onClick={() => { setBlocks(blocks.filter((b) => b.id !== cur.id)); setSel(null); }} title={tr("Delete", "حذف")}><Trash2 className="h-4 w-4" /></button>
              </div>
            </div>
            {cur.type === "text" && (
              <>
                <textarea ref={textRef} rows={4} className={inputCls} dir="auto" value={cur.text ?? ""} onChange={(e) => setBlock(cur.id, { text: e.target.value })} />
                <div>
                  <label className={label}>{tr("Insert the employee's data", "إدراج بيانات الموظف")}</label>
                  <div className="flex flex-wrap gap-1">
                    {PLACEHOLDERS.map((p) => (
                      <button key={p.key} type="button" onClick={() => insertPlaceholder(p.key)} className="px-2 py-1 text-xs rounded-full border border-border hover:bg-primary/10 hover:border-primary">{tr(p.en, p.ar)}</button>
                    ))}
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div><label className={label}>{tr("Size", "الحجم")}</label>{num(cur.size, (n) => setBlock(cur.id, { size: Math.max(0.8, n) }), 0.2)}</div>
                  <div><label className={label}>{tr("Colour", "اللون")}</label><input type="color" className="h-9 w-full rounded-lg border border-border" value={cur.color ?? "#1f2937"} onChange={(e) => setBlock(cur.id, { color: e.target.value })} /></div>
                </div>
                <div className="flex items-center gap-1">
                  {([["left", AlignLeft], ["center", AlignCenter], ["right", AlignRight]] as const).map(([a, Icon]) => (
                    <button key={a} type="button" onClick={() => setBlock(cur.id, { align: a })} className={`p-2 rounded-lg border ${cur.align === a ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}><Icon className="h-4 w-4" /></button>
                  ))}
                  <button type="button" onClick={() => setBlock(cur.id, { bold: !cur.bold })} className={`p-2 rounded-lg border ${cur.bold ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}><Bold className="h-4 w-4" /></button>
                  <button type="button" onClick={() => setBlock(cur.id, { italic: !cur.italic })} className={`p-2 rounded-lg border ${cur.italic ? "bg-primary text-primary-foreground border-primary" : "border-border hover:bg-muted"}`}><Italic className="h-4 w-4" /></button>
                  <select className={inputCls + " flex-1"} value={cur.font ?? "sans"} onChange={(e) => setBlock(cur.id, { font: e.target.value as any })}>
                    <option value="sans">{tr("Clean", "عادي")}</option><option value="serif">{tr("Formal", "رسمي")}</option><option value="mono">{tr("Typewriter", "آلة كاتبة")}</option>
                  </select>
                </div>
                <div><label className={label}>{tr("Line spacing", "تباعد الأسطر")}</label>{num(cur.lh, (n) => setBlock(cur.id, { lh: Math.min(3, Math.max(1, n)) }), 0.1)}</div>
              </>
            )}
            <div className="grid grid-cols-3 gap-2">
              <div><label className={label}>{tr("Left %", "يسار %")}</label>{num(cur.x, (n) => setBlock(cur.id, { x: n }), 0.5)}</div>
              <div><label className={label}>{tr("Top %", "أعلى %")}</label>{num(cur.y, (n) => setBlock(cur.id, { y: n }), 0.5)}</div>
              <div><label className={label}>{tr("Width %", "العرض %")}</label>{num(cur.w, (n) => setBlock(cur.id, { w: Math.max(3, n) }), 0.5)}</div>
            </div>
            {cur.type === "image" && <div><label className={label}>{tr("Height %", "الارتفاع %")}</label>{num(cur.h, (n) => setBlock(cur.id, { h: Math.max(3, n) }), 0.5)}</div>}
          </section>
        )}
      </div>
    </div>
  );
}
