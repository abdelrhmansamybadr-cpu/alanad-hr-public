export * from "./generated/api";
export * from "./generated/api.schemas";
export { setBaseUrl, setAuthTokenGetter, customFetch } from "./custom-fetch";
export type { AuthTokenGetter, CustomFetchOptions } from "./custom-fetch";

import { useQuery, useMutation } from "@tanstack/react-query";
import { customFetch } from "./custom-fetch";

export interface ActivityItem {
  type: string;
  title: string;
  desc: string;
  status: string;
  date: string;
}

export function useGetRecentActivity() {
  return useQuery({
    queryKey: ["/api/stats/activity"],
    queryFn: async () =>
      customFetch<ActivityItem[]>("/api/stats/activity", { method: "GET" }),
    refetchInterval: 60000,
  });
}

export interface DepartmentOverview {
  departmentId: number;
  departmentName: string;
  jobs: {
    jobId: number;
    jobTitle: string;
    counts: Record<string, number>;
  }[];
}

export interface CandidateWithDetails {
  id: number;
  applicantName: string;
  email: string;
  phone: string | null;
  resumeUrl: string | null;
  coverLetter: string | null;
  notes: string | null;
  status: string;
  appliedAt: string;
  jobId: number;
  jobTitle: string;
  departmentId: number;
  departmentName: string;
  documents: {
    id: number;
    fileName: string;
    filePath: string;
    mimeType: string;
    uploadedAt: string;
  }[];
}

export interface ListTalentPoolCandidatesParams {
  departmentId?: number;
  jobId?: number;
  status?: string;
  search?: string;
}

export const getTalentPoolOverviewUrl = () => `/api/talent-pool/overview`;

export const getTalentPoolOverviewQueryKey = () =>
  [`/api/talent-pool/overview`] as const;

export function useTalentPoolOverview() {
  return useQuery({
    queryKey: getTalentPoolOverviewQueryKey(),
    queryFn: async () => {
      return customFetch<DepartmentOverview[]>(getTalentPoolOverviewUrl(), {
        method: "GET",
      });
    },
  });
}

export const getTalentPoolCandidatesUrl = (
  params?: ListTalentPoolCandidatesParams,
) => {
  const searchParams = new URLSearchParams();
  if (params?.departmentId)
    searchParams.set("departmentId", params.departmentId.toString());
  if (params?.jobId) searchParams.set("jobId", params.jobId.toString());
  if (params?.status) searchParams.set("status", params.status);
  if (params?.search) searchParams.set("search", params.search);
  const qs = searchParams.toString();
  return `/api/talent-pool/candidates${qs ? "?" + qs : ""}`;
};

export const getTalentPoolCandidatesQueryKey = (
  params?: ListTalentPoolCandidatesParams,
) => [`/api/talent-pool/candidates`, params] as const;

export function useTalentPoolCandidates(
  params?: ListTalentPoolCandidatesParams,
) {
  return useQuery({
    queryKey: getTalentPoolCandidatesQueryKey(params),
    queryFn: async () => {
      return customFetch<CandidateWithDetails[]>(
        getTalentPoolCandidatesUrl(params),
        {
          method: "GET",
        },
      );
    },
  });
}

export interface UpdateCandidateParams {
  id: number;
  data: {
    status?: string;
    notes?: string;
  };
}

export function useUpdateCandidate() {
  return useMutation({
    mutationFn: async ({ id, data }: UpdateCandidateParams) => {
      return customFetch(`/api/talent-pool/candidates/${id}`, {
        method: "PUT",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

export function useDeleteCandidate() {
  return useMutation({
    mutationFn: async (id: number) => {
      return customFetch(`/api/talent-pool/candidates/${id}`, {
        method: "DELETE",
      });
    },
  });
}

export function useUploadCandidateDocument() {
  return useMutation({
    mutationFn: async ({ id, file }: { id: number; file: File }) => {
      const formData = new FormData();
      formData.append("file", file);
      return customFetch(`/api/talent-pool/candidates/${id}/documents`, {
        method: "POST",
        body: formData,
      });
    },
  });
}

export function useHireAsEmployee() {
  return useMutation({
    mutationFn: async (candidateId: number) => {
      return customFetch<{ id: number }>(
        `/api/talent-pool/candidates/${candidateId}/hire-as-employee`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
        },
      );
    },
  });
}

export function useDeleteCandidateDocument() {
  return useMutation({
    mutationFn: async ({
      candidateId,
      docId,
    }: {
      candidateId: number;
      docId: number;
    }) => {
      return customFetch(
        `/api/talent-pool/candidates/${candidateId}/documents/${docId}`,
        {
          method: "DELETE",
        },
      );
    },
  });
}

export interface EmployeeLeaveAnalytics {
  employeeId: number;
  firstName: string;
  lastName: string;
  position: string;
  departmentId: number;
  status: string;
  takenThisWeek: number;
  takenThisMonth: number;
  takenThisYear: number;
  remainingThisMonth: number;
  remainingThisYear: number;
  pendingRequests: number;
}

export interface EmployeeLeaveDetail {
  employee: {
    id: number;
    firstName: string;
    lastName: string;
    position: string;
    departmentId: number;
    status: string;
  };
  policy: { daysPerMonth: number; daysPerYear: number };
  summary: {
    takenThisWeek: number;
    takenThisMonth: number;
    takenThisYear: number;
    remainingThisMonth: number;
    remainingThisYear: number;
    pendingRequests: number;
    totalAll: number;
  };
  history: {
    id: number;
    type: string;
    startDate: string;
    endDate: string;
    days: number;
    reason?: string | null;
    status: string;
    createdAt: string;
  }[];
}

export interface LeavePolicy {
  id: number;
  daysPerMonth: number;
  daysPerYear: number;
  updatedAt: string;
}

export function useLeaveAnalytics() {
  return useQuery({
    queryKey: ["/api/leaves/analytics"],
    queryFn: () =>
      customFetch<EmployeeLeaveAnalytics[]>("/api/leaves/analytics", {
        method: "GET",
      }),
  });
}

export function useEmployeeLeaveDetail(employeeId: number | null) {
  return useQuery({
    queryKey: ["/api/leaves/analytics", employeeId],
    queryFn: () =>
      customFetch<EmployeeLeaveDetail>(`/api/leaves/analytics/${employeeId}`, {
        method: "GET",
      }),
    enabled: employeeId != null,
  });
}

export function useLeavePolicy() {
  return useQuery({
    queryKey: ["/api/leaves/policy"],
    queryFn: () =>
      customFetch<LeavePolicy>("/api/leaves/policy", { method: "GET" }),
  });
}

export function useUpdateLeavePolicy() {
  return useMutation({
    mutationFn: (data: { daysPerMonth: number; daysPerYear: number }) =>
      customFetch<LeavePolicy>("/api/leaves/policy", {
        method: "PUT",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      }),
  });
}

export interface HRStaffMember {
  id: number;
  name: string;
  email: string;
  role: string;
  avatar: string | null;
  title: string | null;
  phone: string | null;
  status: string;
  createdAt: string;
  permissions: { module: string; enabled: boolean }[];
}

export interface CreateHRStaffParams {
  name: string;
  email: string;
  password: string;
  title?: string;
  phone?: string;
}

export interface UpdateHRStaffParams {
  name?: string;
  title?: string;
  phone?: string;
}

export function useGetHRStaff() {
  return useQuery<HRStaffMember[]>({
    queryKey: ["/api/hr-staff"],
    queryFn: async () =>
      customFetch<HRStaffMember[]>("/api/hr-staff", { method: "GET" }),
  });
}

export function useCreateHRStaff() {
  return useMutation({
    mutationFn: async (data: CreateHRStaffParams) => {
      return customFetch<HRStaffMember>("/api/hr-staff", {
        method: "POST",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

export function useUpdateHRStaff() {
  return useMutation({
    mutationFn: async ({
      id,
      data,
    }: {
      id: number;
      data: UpdateHRStaffParams;
    }) => {
      return customFetch<HRStaffMember>(`/api/hr-staff/${id}`, {
        method: "PUT",
        body: JSON.stringify(data),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

export function useUpdateHRStaffStatus() {
  return useMutation({
    mutationFn: async ({ id, status }: { id: number; status: string }) => {
      return customFetch<HRStaffMember>(`/api/hr-staff/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status }),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

export function useResetHRStaffPassword() {
  return useMutation({
    mutationFn: async ({ id, password }: { id: number; password: string }) => {
      return customFetch<{ success: boolean }>(`/api/hr-staff/${id}/password`, {
        method: "PATCH",
        body: JSON.stringify({ password }),
        headers: { "Content-Type": "application/json" },
      });
    },
  });
}

export function useGetHRStaffPermissions(staffId: number) {
  return useQuery<{ module: string; enabled: boolean }[]>({
    queryKey: ["/api/hr-staff", staffId, "permissions"],
    queryFn: async () =>
      customFetch<{ module: string; enabled: boolean }[]>(
        `/api/hr-staff/${staffId}/permissions`,
        { method: "GET" },
      ),
    enabled: staffId > 0,
  });
}

export function useUpdateHRStaffPermissions() {
  return useMutation({
    mutationFn: async ({
      id,
      permissions,
    }: {
      id: number;
      permissions: { module: string; enabled: boolean }[];
    }) => {
      return customFetch<{ module: string; enabled: boolean }[]>(
        `/api/hr-staff/${id}/permissions`,
        {
          method: "PUT",
          body: JSON.stringify({ permissions }),
          headers: { "Content-Type": "application/json" },
        },
      );
    },
  });
}

export function useDeleteHRStaff() {
  return useMutation({
    mutationFn: async (id: number) => {
      return customFetch(`/api/hr-staff/${id}`, {
        method: "DELETE",
      });
    },
  });
}
