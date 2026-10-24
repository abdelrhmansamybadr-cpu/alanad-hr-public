import { useState, useRef } from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  X,
  Upload,
  Eye,
  Download,
  Trash2,
  Plus,
  FileText,
  ChevronDown,
  ChevronRight,
} from "lucide-react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useLang } from "@/contexts/LanguageContext";
import { useAuth } from "@/contexts/AuthContext";

interface EmployeeDocumentsProps {
  employee: {
    id: number;
    firstName: string;
    lastName: string;
  };
  onClose: () => void;
}

interface DocType {
  typeId: number;
  label: string;
  order: number;
  document: {
    id: number;
    fileName: string;
    filePath: string;
    mimeType: string;
    uploadedAt: string;
  } | null;
}

export default function EmployeeDocuments({
  employee,
  onClose,
}: EmployeeDocumentsProps) {
  const { t, isRTL } = useLang();
  const { token } = useAuth();
  const queryClient = useQueryClient();
  const panelRef = useRef<HTMLDivElement>(null);
  const [showAdminSection, setShowAdminSection] = useState(false);
  const [previewFile, setPreviewFile] = useState<{
    url: string;
    mimeType: string;
    fileName: string;
  } | null>(null);
  const [newDocTypeLabel, setNewDocTypeLabel] = useState("");
  const [editingTypeId, setEditingTypeId] = useState<number | null>(null);
  const [editingLabel, setEditingLabel] = useState("");

  const { data: docTypes = [], isLoading } = useQuery<DocType[]>({
    queryKey: ["employeeDocuments", employee.id],
    queryFn: async () => {
      const res = await fetch(`/api/documents/employee/${employee.id}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error("Failed to fetch documents");
      return res.json();
    },
  });

  const uploadMutation = useMutation({
    mutationFn: async ({ typeId, file }: { typeId: number; file: File }) => {
      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch(
        `/api/documents/employee/${employee.id}/upload/${typeId}`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body: formData,
        },
      );
      if (!res.ok) throw new Error("Failed to upload");
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["employeeDocuments", employee.id],
      });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (documentId: number) => {
      const res = await fetch(
        `/api/documents/employee/${employee.id}/document/${documentId}`,
        {
          method: "DELETE",
          headers: { Authorization: `Bearer ${token}` },
        },
      );
      if (!res.ok) throw new Error("Failed to delete");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["employeeDocuments", employee.id],
      });
    },
  });

  const addDocTypeMutation = useMutation({
    mutationFn: async (label: string) => {
      const res = await fetch("/api/documents/types", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ label }),
      });
      if (!res.ok) throw new Error("Failed to add document type");
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["employeeDocuments"],
      });
      setNewDocTypeLabel("");
    },
  });

  const updateDocTypeMutation = useMutation({
    mutationFn: async ({ id, label }: { id: number; label: string }) => {
      const res = await fetch(`/api/documents/types/${id}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ label }),
      });
      if (!res.ok) throw new Error("Failed to update document type");
      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["employeeDocuments"],
      });
      setEditingTypeId(null);
      setEditingLabel("");
    },
  });

  const deleteDocTypeMutation = useMutation({
    mutationFn: async (id: number) => {
      const res = await fetch(`/api/documents/types/${id}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error("Failed to delete document type");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["employeeDocuments"],
      });
    },
  });

  const handleUpload = (typeId: number, file: File) => {
    uploadMutation.mutate({ typeId, file });
  };

  const handleDownload = (filePath: string, fileName: string) => {
    const link = document.createElement("a");
    link.href = `/uploads/${filePath}`;
    link.download = fileName;
    link.click();
  };

  const handlePreview = (
    filePath: string,
    mimeType: string,
    fileName: string,
  ) => {
    setPreviewFile({
      url: `/uploads/${filePath}`,
      mimeType,
      fileName,
    });
  };

  const handleAddDocType = () => {
    if (newDocTypeLabel.trim()) {
      addDocTypeMutation.mutate(newDocTypeLabel.trim());
    }
  };

  const handleUpdateDocType = (id: number) => {
    if (editingLabel.trim()) {
      updateDocTypeMutation.mutate({ id, label: editingLabel.trim() });
    }
  };

  const handleDeleteDocType = (id: number) => {
    if (confirm(t.deleteConfirm)) {
      deleteDocTypeMutation.mutate(id);
    }
  };

  return createPortal(
    <AnimatePresence>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
        <motion.div
          ref={panelRef}
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          className="bg-card w-full max-w-2xl rounded-2xl shadow-xl overflow-hidden border border-border flex flex-col max-h-[90vh]"
        >
          <div
            className={`p-6 border-b border-border bg-muted/10 shrink-0 flex items-center justify-between ${isRTL ? "flex-row-reverse" : ""}`}
          >
            <div className={isRTL ? "text-right" : ""}>
              <h2 className="text-xl font-bold">{t.requiredDocuments}</h2>
              <p className="text-sm text-muted-foreground mt-1">
                {employee.firstName} {employee.lastName}
              </p>
            </div>
            <button
              onClick={onClose}
              className="p-2 rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-4 space-y-3">
            {isLoading ? (
              <div className="text-center py-8 text-muted-foreground">
                {t.loading}
              </div>
            ) : (
              docTypes.map((doc) => (
                <div
                  key={doc.typeId}
                  className={`flex items-center gap-3 p-3 rounded-xl border border-border bg-background ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-foreground" dir="rtl">
                      {doc.label}
                    </p>
                    {doc.document && (
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {doc.document.fileName}
                      </p>
                    )}
                  </div>
                  <div
                    className={`flex items-center gap-2 ${isRTL ? "flex-row-reverse" : ""}`}
                  >
                    {doc.document ? (
                      <>
                        <span className="px-2 py-1 rounded-full text-xs font-medium bg-emerald-50 text-emerald-700 border border-emerald-200">
                          {t.uploaded}
                        </span>
                        <button
                          onClick={() =>
                            handlePreview(
                              doc.document!.filePath,
                              doc.document!.mimeType,
                              doc.document!.fileName,
                            )
                          }
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={t.preview}
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() =>
                            handleDownload(
                              doc.document!.filePath,
                              doc.document!.fileName,
                            )
                          }
                          className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                          title={t.download}
                        >
                          <Download className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() =>
                            deleteMutation.mutate(doc.document!.id)
                          }
                          className="p-1.5 text-muted-foreground hover:text-destructive rounded-md hover:bg-destructive/10 transition-colors"
                          title={t.delete}
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </>
                    ) : (
                      <span className="px-2 py-1 rounded-full text-xs font-medium bg-red-50 text-red-700 border border-red-200">
                        {t.missing}
                      </span>
                    )}
                    <input
                      type="file"
                      id={`file-input-${doc.typeId}`}
                      className="hidden"
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        if (file) handleUpload(doc.typeId, file);
                        e.target.value = "";
                      }}
                      accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
                    />
                    <button
                      onClick={() =>
                        document
                          .getElementById(`file-input-${doc.typeId}`)
                          ?.click()
                      }
                      className="p-1.5 text-muted-foreground hover:text-primary rounded-md hover:bg-primary/10 transition-colors"
                      title={t.uploadFile}
                    >
                      <Upload className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>

          <div className="border-t border-border p-4 shrink-0">
            <button
              onClick={() => setShowAdminSection(!showAdminSection)}
              className={`flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground ${isRTL ? "flex-row-reverse" : ""}`}
            >
              {showAdminSection ? (
                <ChevronDown className="w-4 h-4" />
              ) : (
                <ChevronRight className="w-4 h-4" />
              )}
              {t.manageDocTypes}
            </button>

            {showAdminSection && (
              <div className="mt-4 space-y-3">
                {docTypes.map((doc) => (
                  <div
                    key={doc.typeId}
                    className={`flex items-center gap-2 ${isRTL ? "flex-row-reverse" : ""}`}
                  >
                    {editingTypeId === doc.typeId ? (
                      <>
                        <input
                          type="text"
                          value={editingLabel}
                          onChange={(e) => setEditingLabel(e.target.value)}
                          className="flex-1 px-2 py-1 border border-border rounded text-sm"
                          dir="rtl"
                        />
                        <button
                          onClick={() => handleUpdateDocType(doc.typeId)}
                          className="px-2 py-1 text-sm bg-primary text-primary-foreground rounded"
                        >
                          {t.save}
                        </button>
                        <button
                          onClick={() => setEditingTypeId(null)}
                          className="px-2 py-1 text-sm text-muted-foreground"
                        >
                          {t.cancel}
                        </button>
                      </>
                    ) : (
                      <>
                        <span className="flex-1 text-sm" dir="rtl">
                          {doc.label}
                        </span>
                        <button
                          onClick={() => {
                            setEditingTypeId(doc.typeId);
                            setEditingLabel(doc.label);
                          }}
                          className="p-1 text-muted-foreground hover:text-primary"
                        >
                          <FileText className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleDeleteDocType(doc.typeId)}
                          className="p-1 text-muted-foreground hover:text-destructive"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </>
                    )}
                  </div>
                ))}
                <div
                  className={`flex items-center gap-2 ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <input
                    type="text"
                    value={newDocTypeLabel}
                    onChange={(e) => setNewDocTypeLabel(e.target.value)}
                    placeholder={t.addDocType}
                    className="flex-1 px-2 py-1 border border-border rounded text-sm"
                    dir="rtl"
                  />
                  <button
                    onClick={handleAddDocType}
                    disabled={
                      !newDocTypeLabel.trim() || addDocTypeMutation.isPending
                    }
                    className="p-1.5 bg-primary text-primary-foreground rounded hover:bg-primary/90 disabled:opacity-50"
                  >
                    <Plus className="w-4 h-4" />
                  </button>
                </div>
              </div>
            )}
          </div>
        </motion.div>

        <AnimatePresence>
          {previewFile && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 z-[60] flex items-center justify-center bg-black/80"
              onClick={() => setPreviewFile(null)}
            >
              <div className="relative bg-background rounded-lg shadow-xl max-w-4xl max-h-[90vh] w-full mx-4 overflow-hidden">
                <div
                  className={`flex items-center justify-between p-4 border-b border-border ${isRTL ? "flex-row-reverse" : ""}`}
                >
                  <p className="font-medium text-foreground truncate">
                    {previewFile.fileName}
                  </p>
                  <button
                    onClick={() => setPreviewFile(null)}
                    className="p-1 rounded hover:bg-muted"
                  >
                    <X className="w-5 h-5" />
                  </button>
                </div>
                <div className="p-4 overflow-auto max-h-[calc(90vh-80px)]">
                  {previewFile.mimeType.startsWith("image/") ? (
                    <img
                      src={previewFile.url}
                      alt={previewFile.fileName}
                      className="max-w-full h-auto mx-auto"
                    />
                  ) : previewFile.mimeType === "application/pdf" ? (
                    <iframe
                      src={previewFile.url}
                      className="w-full h-[70vh] border-0"
                      title={previewFile.fileName}
                    />
                  ) : (
                    <div className="text-center py-8">
                      <p className="text-muted-foreground mb-4">
                        {isRTL
                          ? "لا يمكن معاينة هذا الملف"
                          : "Cannot preview this file"}
                      </p>
                      <button
                        onClick={() =>
                          handleDownload(previewFile.url, previewFile.fileName)
                        }
                        className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg mx-auto"
                      >
                        <Download className="w-4 h-4" />
                        {t.download}
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </AnimatePresence>,
    document.body,
  );
}
