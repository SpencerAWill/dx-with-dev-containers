import * as ImageManipulator from "expo-image-manipulator";
import * as ImagePicker from "expo-image-picker";
import { useRouter } from "expo-router";
import { useState } from "react";
import {
  ActivityIndicator,
  Image as RNImage,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { uploadImage } from "@/api";

type Picked = {
  uri: string;
  fileName: string;
  mimeType: string;
};

export default function UploadScreen() {
  const router = useRouter();
  const [picked, setPicked] = useState<Picked | null>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function pick(source: "library" | "camera") {
    setError(null);
    const opts: ImagePicker.ImagePickerOptions = {
      mediaTypes: ["images"],
      quality: 0.8,
    };
    const result =
      source === "library"
        ? await ImagePicker.launchImageLibraryAsync(opts)
        : await ImagePicker.launchCameraAsync(opts);

    if (result.canceled || !result.assets.length) return;
    const asset = result.assets[0];

    // Transcode to JPEG so the backend (ImageSharp) and the web app can read it.
    // iPhone library picks are typically HEIC, which neither can handle.
    const jpeg = await ImageManipulator.manipulateAsync(asset.uri, [], {
      compress: 0.85,
      format: ImageManipulator.SaveFormat.JPEG,
    });

    const baseName = (asset.fileName ?? `photo-${Date.now()}`).replace(
      /\.[^.]+$/,
      "",
    );
    setPicked({
      uri: jpeg.uri,
      fileName: `${baseName}.jpg`,
      mimeType: "image/jpeg",
    });
  }

  async function submit() {
    if (!picked) return;
    setUploading(true);
    setError(null);
    try {
      await uploadImage(picked.uri, picked.fileName, picked.mimeType);
      router.back();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setUploading(false);
    }
  }

  return (
    <View style={styles.container}>
      {picked ? (
        <RNImage source={{ uri: picked.uri }} style={styles.preview} />
      ) : (
        <View style={styles.placeholder}>
          <Text style={styles.placeholderText}>No photo selected</Text>
        </View>
      )}

      <View style={styles.row}>
        <Pressable style={styles.secondary} onPress={() => pick("library")}>
          <Text style={styles.secondaryText}>Choose from library</Text>
        </Pressable>
        <Pressable style={styles.secondary} onPress={() => pick("camera")}>
          <Text style={styles.secondaryText}>Take photo</Text>
        </Pressable>
      </View>

      <Pressable
        style={[styles.primary, (!picked || uploading) && styles.disabled]}
        disabled={!picked || uploading}
        onPress={submit}
      >
        {uploading ? (
          <ActivityIndicator color="white" />
        ) : (
          <Text style={styles.primaryText}>Upload</Text>
        )}
      </Pressable>

      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f172a", padding: 16, gap: 16 },
  preview: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: 12,
    backgroundColor: "#1e293b",
  },
  placeholder: {
    width: "100%",
    aspectRatio: 1,
    borderRadius: 12,
    backgroundColor: "#1e293b",
    alignItems: "center",
    justifyContent: "center",
  },
  placeholderText: { color: "#64748b" },
  row: { flexDirection: "row", gap: 12 },
  secondary: {
    flex: 1,
    backgroundColor: "#1e293b",
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: "center",
  },
  secondaryText: { color: "#e2e8f0", fontWeight: "500" },
  primary: {
    backgroundColor: "#0ea5e9",
    paddingVertical: 16,
    borderRadius: 10,
    alignItems: "center",
  },
  primaryText: { color: "white", fontWeight: "600", fontSize: 16 },
  disabled: { opacity: 0.5 },
  error: { color: "#fca5a5", textAlign: "center" },
});
