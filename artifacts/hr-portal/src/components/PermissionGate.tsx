import { ReactNode } from "react";
import { useAuth } from "@/contexts/AuthContext";

interface PermissionGateProps {
  module: string;
  children: ReactNode;
  fallback?: ReactNode;
  showDenied?: boolean;
}

export function PermissionGate({
  module,
  children,
  fallback = null,
  showDenied = false,
}: PermissionGateProps) {
  const { isManager, hasPermission } = useAuth();

  if (isManager || hasPermission(module)) {
    return <>{children}</>;
  }

  if (showDenied) {
    return (
      <div className="flex items-center justify-center min-h-[200px]">
        <div className="text-center p-6 bg-muted/30 rounded-xl border border-border">
          <h3 className="text-lg font-semibold text-foreground mb-2">
            Access Denied
          </h3>
          <p className="text-sm text-muted-foreground">
            You don't have permission to access this module.
          </p>
        </div>
      </div>
    );
  }

  return <>{fallback}</>;
}
