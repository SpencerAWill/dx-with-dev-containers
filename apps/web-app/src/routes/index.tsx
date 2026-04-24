import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

interface Image {
  id: string;
  originalFileName: string;
  contentType: string;
  blobUri: string;
  status: number;
  classificationLabel: string | null;
  confidence: number | null;
  description: string | null;
  uploadedAt: string;
  classifiedAt: string | null;
}

const statusLabels: Record<number, string> = {
  0: "Uploaded",
  1: "Processing",
  2: "Classified",
  3: "Failed",
};

const statusColors: Record<number, string> = {
  0: "#6b7280",
  1: "#f59e0b",
  2: "#10b981",
  3: "#ef4444",
};

export const Route = createFileRoute("/")({
  component: Gallery,
});

function Gallery() {
  const queryClient = useQueryClient();

  const { data: images, isLoading } = useQuery<Image[]>({
    queryKey: ["images"],
    queryFn: () => fetch("/api/images").then((r) => r.json()),
    refetchInterval: 3000,
  });

  const deleteImage = useMutation({
    mutationFn: (id: string) =>
      fetch(`/api/images/${id}`, { method: "DELETE" }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["images"] }),
  });

  if (isLoading) return <p className="loading">Loading images...</p>;

  if (!images?.length) {
    return (
      <div className="empty">
        <p>No images yet.</p>
        <a href="/upload">Upload your first image</a>
      </div>
    );
  }

  return (
    <div className="gallery">
      {images.map((img) => (
        <div key={img.id} className="card">
          <div className="card-image">
            <img
              src={`/api/images/${img.id}/download`}
              alt={img.originalFileName}
              loading="lazy"
            />
          </div>
          <div className="card-body">
            <span
              className="badge"
              style={{ backgroundColor: statusColors[img.status] }}
            >
              {statusLabels[img.status]}
            </span>
            <p className="filename">{img.originalFileName}</p>
            {img.classificationLabel && (
              <p className="label">{img.classificationLabel}</p>
            )}
            {img.confidence != null && (
              <p className="confidence">
                {(img.confidence * 100).toFixed(1)}% confidence
              </p>
            )}
            {img.description && (
              <p className="description">{img.description}</p>
            )}
            <button
              className="delete-btn"
              onClick={() => deleteImage.mutate(img.id)}
              disabled={deleteImage.isPending}
            >
              Remove
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
