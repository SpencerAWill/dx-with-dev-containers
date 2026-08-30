import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";

interface ServiceStatus {
  name: string;
  healthy: boolean;
  error: string | null;
}

interface StatusResponse {
  healthy: boolean;
  services: ServiceStatus[];
}

export const Route = createFileRoute("/status")({
  component: Status,
});

function Status() {
  const { data, isLoading, error } = useQuery<StatusResponse>({
    queryKey: ["status"],
    queryFn: () => fetch("/api/status").then((r) => r.json()),
    refetchInterval: 10000,
  });

  return (
    <div className="status-page">
      <h2>Infrastructure Status</h2>

      {isLoading && <p className="loading">Checking services...</p>}

      {error && (
        <div className="status-error">
          <p>Could not reach the API. Is it running?</p>
        </div>
      )}

      {data && (
        <>
          <div
            className={`status-banner ${data.healthy ? "all-healthy" : "has-issues"}`}
          >
            {data.healthy
              ? "All services healthy"
              : "Some services have issues"}
          </div>
          <div className="status-grid">
            {data.services.map((svc) => (
              <div
                key={svc.name}
                className={`status-card ${svc.healthy ? "healthy" : "unhealthy"}`}
              >
                <span className="status-indicator">
                  {svc.healthy ? "\u2713" : "\u2717"}
                </span>
                <div>
                  <p className="status-name">{svc.name}</p>
                  {svc.error && (
                    <p className="status-error-text">{svc.error}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
