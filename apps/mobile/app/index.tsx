import { Link, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Image as RNImage,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { ImageStatus, imageDownloadUrl, listImages, type Image } from "@/api";

// Self-assessed by the vision model, not a calibrated probability — band it.
function certainty(confidence: number): string {
  if (confidence >= 0.8) return "high";
  if (confidence >= 0.5) return "medium";
  return "low";
}

function statusLine(item: Image): string {
  if (item.status === ImageStatus.Classified && item.classificationLabel) {
    const suffix = item.confidence != null ? ` (${certainty(item.confidence)} certainty)` : "";
    return `${item.classificationLabel}${suffix}`;
  }
  if (item.status === ImageStatus.Failed) return "classification failed";
  if (item.status === ImageStatus.Processing) return "classifying…";
  return "queued…";
}

export default function HomeScreen() {
  const [images, setImages] = useState<Image[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setError(null);
      const data = await listImages();
      setImages(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  return (
    <View style={styles.container}>
      {error ? (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
          <Text style={styles.errorHint}>
            Set EXPO_PUBLIC_API_URL in apps/mobile/.env to something the phone can reach.
          </Text>
        </View>
      ) : null}

      {loading && images.length === 0 ? (
        <ActivityIndicator style={{ marginTop: 32 }} />
      ) : (
        <FlatList
          data={images}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.list}
          refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
          renderItem={({ item }) => (
            <View style={styles.card}>
              <RNImage source={{ uri: imageDownloadUrl(item.id) }} style={styles.thumb} />
              <View style={styles.cardBody}>
                <Text style={styles.fileName} numberOfLines={1}>
                  {item.originalFileName}
                </Text>
                <Text style={styles.classification}>{statusLine(item)}</Text>
                {item.description ? (
                  <Text style={styles.description} numberOfLines={3}>
                    {item.description}
                  </Text>
                ) : null}
              </View>
            </View>
          )}
          ListEmptyComponent={
            !loading ? <Text style={styles.empty}>No images yet. Upload one!</Text> : null
          }
        />
      )}

      <Link href="/upload" asChild>
        <Pressable style={styles.fab}>
          <Text style={styles.fabText}>＋</Text>
        </Pressable>
      </Link>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f172a" },
  list: { padding: 16, gap: 12 },
  card: {
    flexDirection: "row",
    alignItems: "stretch",
    backgroundColor: "#1e293b",
    borderRadius: 12,
    overflow: "hidden",
    marginBottom: 12,
    minHeight: 96,
  },
  thumb: { width: 96, alignSelf: "stretch", backgroundColor: "#334155" },
  cardBody: { flex: 1, padding: 12, justifyContent: "center" },
  fileName: { color: "#f1f5f9", fontWeight: "600", fontSize: 15 },
  classification: { color: "#38bdf8", marginTop: 4, fontSize: 13, fontWeight: "500" },
  description: { color: "#cbd5e1", marginTop: 6, fontSize: 12, lineHeight: 16 },
  empty: { color: "#94a3b8", textAlign: "center", marginTop: 48 },
  errorBox: { backgroundColor: "#7f1d1d", padding: 12, margin: 16, borderRadius: 8 },
  errorText: { color: "#fecaca", fontWeight: "600" },
  errorHint: { color: "#fecaca", marginTop: 4, fontSize: 12 },
  fab: {
    position: "absolute",
    right: 24,
    bottom: 32,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: "#0ea5e9",
    alignItems: "center",
    justifyContent: "center",
    elevation: 4,
    shadowColor: "#000",
    shadowOpacity: 0.3,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
  },
  fabText: { color: "white", fontSize: 28, lineHeight: 32 },
});
