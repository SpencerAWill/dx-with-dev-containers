using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Worker.Services;

public record ImageAnalysis(string Label, double Confidence, string? Description);

/// <summary>
/// Classifies and describes an image in a single call to the vision model
/// (Docker Model Runner, OpenAI-compatible chat completions).
/// </summary>
public class ImageAnalyzer(HttpClient httpClient, string model)
{
    private const string Prompt = """
        Identify the main subject of this image and describe it. Respond with JSON:
          label       - the primary subject as a lowercase noun phrase of one to three words
          confidence  - how certain you are of the label, from 0.0 to 1.0
          description - one or two concise, factual sentences about the image
        """;

    // The model is constrained to this schema server-side, so the content of a
    // successful response is always parseable JSON in this shape.
    private static readonly object ResponseFormat = new
    {
        type = "json_schema",
        json_schema = new
        {
            name = "image_analysis",
            strict = true,
            schema = new
            {
                type = "object",
                properties = new
                {
                    label = new { type = "string" },
                    confidence = new { type = "number" },
                    description = new { type = "string" }
                },
                required = new[] { "label", "confidence", "description" },
                additionalProperties = false
            }
        }
    };

    private record ChatMessage(
        [property: JsonPropertyName("role")] string Role,
        [property: JsonPropertyName("content")] JsonElement Content);

    private record ChatRequest(
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("messages")] ChatMessage[] Messages,
        [property: JsonPropertyName("max_tokens")] int MaxTokens,
        [property: JsonPropertyName("response_format")] object ResponseFormat);

    private record ChatChoice(
        [property: JsonPropertyName("message")] ChatChoiceMessage Message);

    private record ChatChoiceMessage(
        [property: JsonPropertyName("content")] string Content);

    private record ChatResponse(
        [property: JsonPropertyName("choices")] ChatChoice[] Choices);

    private record AnalysisPayload(
        [property: JsonPropertyName("label")] string? Label,
        [property: JsonPropertyName("confidence")] double? Confidence,
        [property: JsonPropertyName("description")] string? Description);

    public async Task<ImageAnalysis> AnalyzeAsync(
        Stream imageStream,
        string contentType,
        CancellationToken cancellationToken = default)
    {
        var imageBytes = new MemoryStream();
        await imageStream.CopyToAsync(imageBytes, cancellationToken);
        var base64 = Convert.ToBase64String(imageBytes.ToArray());
        var dataUri = $"data:{contentType};base64,{base64}";

        var content = JsonSerializer.SerializeToElement(new object[]
        {
            new { type = "text", text = Prompt },
            new { type = "image_url", image_url = new { url = dataUri } }
        });

        var request = new ChatRequest(
            Model: model,
            Messages: [new ChatMessage("user", content)],
            MaxTokens: 300,
            ResponseFormat: ResponseFormat);

        var response = await httpClient.PostAsJsonAsync("v1/chat/completions", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<ChatResponse>(cancellationToken);
        var raw = result?.Choices.FirstOrDefault()?.Message.Content
            ?? throw new InvalidOperationException("Vision model returned no completion.");

        var payload = JsonSerializer.Deserialize<AnalysisPayload>(StripCodeFence(raw))
            ?? throw new InvalidOperationException($"Vision model returned unparseable JSON: {raw}");

        if (string.IsNullOrWhiteSpace(payload.Label))
            throw new InvalidOperationException($"Vision model returned no label: {raw}");

        return new ImageAnalysis(
            Label: Truncate(payload.Label.Trim(), 256),
            Confidence: Math.Round(Math.Clamp(payload.Confidence ?? 0, 0, 1), 4),
            Description: string.IsNullOrWhiteSpace(payload.Description) ? null : payload.Description.Trim());
    }

    // Belt and braces: strict schema mode should never fence the response, but a
    // model that ignores it would otherwise fail deserialization outright.
    private static string StripCodeFence(string content)
    {
        var trimmed = content.Trim();
        if (!trimmed.StartsWith("```"))
            return trimmed;

        var start = trimmed.IndexOf('\n');
        var end = trimmed.LastIndexOf("```", StringComparison.Ordinal);
        return start < 0 || end <= start ? trimmed : trimmed[(start + 1)..end].Trim();
    }

    private static string Truncate(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength];
}
