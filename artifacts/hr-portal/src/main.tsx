import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";

// Every /api call also carries the edition id (X-App-Id).
// The API requires a login token on every request. Several pages call plain fetch()
// without one, so attach the saved token to same-origin /api/ requests here.
const nativeFetch = window.fetch.bind(window);
window.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
  try {
    const url =
      typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const isApi = url.startsWith("/api/") || url.startsWith(`${window.location.origin}/api/`);
    const token = localStorage.getItem("hr-token");
    if (isApi) {
      const headers = new Headers(
        init?.headers ?? (typeof input === "object" && "headers" in input ? input.headers : undefined),
      );
      // Al Anad edition: tell the server which edition is calling, so it only accepts Al Anad's people.
      headers.set("X-App-Id", "alanad");
      if (token && !headers.has("Authorization")) headers.set("Authorization", `Bearer ${token}`);
      return nativeFetch(input, { ...init, headers });
    }
  } catch {
    // fall through to the untouched request
  }
  return nativeFetch(input, init);
};

createRoot(document.getElementById("root")!).render(<App />);
