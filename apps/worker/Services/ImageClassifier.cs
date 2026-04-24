using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace Worker.Services;

public record ClassificationResult(string Label, double Confidence);

public class ImageClassifier : IDisposable
{
    private const int ImageSize = 224;

    // ImageNet normalization values
    private static readonly float[] Mean = [0.485f, 0.456f, 0.406f];
    private static readonly float[] StdDev = [0.229f, 0.224f, 0.225f];

    private readonly InferenceSession _session;
    private readonly string[] _labels;

    public ImageClassifier(string modelPath, string labelsPath)
    {
        _session = new InferenceSession(modelPath);
        _labels = File.ReadAllLines(labelsPath);
    }

    public ClassificationResult Classify(Stream imageStream)
    {
        var input = PreprocessImage(imageStream);

        using var results = _session.Run(
        [
            NamedOnnxValue.CreateFromTensor(_session.InputNames[0], input)
        ]);

        var output = results[0].AsEnumerable<float>().ToArray();
        var probabilities = Softmax(output);

        var maxIndex = 0;
        for (var i = 1; i < probabilities.Length; i++)
        {
            if (probabilities[i] > probabilities[maxIndex])
                maxIndex = i;
        }

        var label = maxIndex < _labels.Length ? _labels[maxIndex] : $"class_{maxIndex}";
        return new ClassificationResult(label, Math.Round(probabilities[maxIndex], 4));
    }

    private static DenseTensor<float> PreprocessImage(Stream imageStream)
    {
        using var image = Image.Load<Rgb24>(imageStream);
        image.Mutate(x => x.Resize(ImageSize, ImageSize));

        var tensor = new DenseTensor<float>([1, 3, ImageSize, ImageSize]);

        for (var y = 0; y < ImageSize; y++)
        {
            for (var x = 0; x < ImageSize; x++)
            {
                var pixel = image[x, y];
                tensor[0, 0, y, x] = ((pixel.R / 255f) - Mean[0]) / StdDev[0];
                tensor[0, 1, y, x] = ((pixel.G / 255f) - Mean[1]) / StdDev[1];
                tensor[0, 2, y, x] = ((pixel.B / 255f) - Mean[2]) / StdDev[2];
            }
        }

        return tensor;
    }

    private static float[] Softmax(float[] logits)
    {
        var max = logits.Max();
        var exps = logits.Select(l => MathF.Exp(l - max)).ToArray();
        var sum = exps.Sum();
        return exps.Select(e => e / sum).ToArray();
    }

    public void Dispose()
    {
        _session.Dispose();
        GC.SuppressFinalize(this);
    }
}
