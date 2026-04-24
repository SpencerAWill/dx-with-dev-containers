using Worker.Services;

namespace Unit.Tests;

public class ImageClassifierTests
{
    private static readonly string ModelsPath = Path.Combine(
        FindRepoRoot(), "apps", "worker", "Models");

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        while (dir is not null && !File.Exists(Path.Combine(dir, "SnapSort.slnx")))
            dir = Directory.GetParent(dir)?.FullName;
        return dir ?? throw new InvalidOperationException("Could not find repo root");
    }

    private static bool ModelsExist =>
        File.Exists(Path.Combine(ModelsPath, "mobilenetv2-7.onnx")) &&
        File.Exists(Path.Combine(ModelsPath, "imagenet_classes.txt"));

    [Fact]
    public void Classify_returns_label_and_confidence()
    {
        Skip.IfNot(ModelsExist, "ONNX model not downloaded — run 'worker: download model' task");

        using var classifier = new ImageClassifier(
            Path.Combine(ModelsPath, "mobilenetv2-7.onnx"),
            Path.Combine(ModelsPath, "imagenet_classes.txt"));

        // Create a simple 224x224 red test image
        using var ms = new MemoryStream();
        using (var image = new SixLabors.ImageSharp.Image<SixLabors.ImageSharp.PixelFormats.Rgb24>(224, 224))
        {
            image.Save(ms, new SixLabors.ImageSharp.Formats.Png.PngEncoder());
        }
        ms.Position = 0;

        var result = classifier.Classify(ms);

        Assert.NotNull(result.Label);
        Assert.NotEmpty(result.Label);
        Assert.InRange(result.Confidence, 0.0, 1.0);
    }
}
