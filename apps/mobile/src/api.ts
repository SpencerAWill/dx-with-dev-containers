const BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? "http://localhost:5000";

// Matches Data.Models.ImageStatus enum ordering. .NET serializes enums as ints.
export const ImageStatus = {
  Uploaded: 0,
  Processing: 1,
  Classified: 2,
  Failed: 3,
} as const;

export type Image = {
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
};

export function imageDownloadUrl(id: string): string {
  return `${BASE_URL}/api/images/${id}/download`;
}

export async function listImages(): Promise<Image[]> {
  const res = await fetch(`${BASE_URL}/api/images`);
  if (!res.ok) throw new Error(`GET /api/images → ${res.status}`);
  return res.json();
}

export async function uploadImage(uri: string, fileName: string, mimeType: string): Promise<Image> {
  const form = new FormData();
  form.append("file", {
    uri,
    name: fileName,
    type: mimeType,
  } as unknown as Blob);

  const res = await fetch(`${BASE_URL}/api/images`, {
    method: "POST",
    body: form,
  });
  if (!res.ok) throw new Error(`POST /api/images → ${res.status}`);
  return res.json();
}
