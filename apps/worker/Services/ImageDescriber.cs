using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Worker.Services;

public class ImageDescriber(HttpClient httpClient, string model)
{
    private record ChatMessage(
        [property: JsonPropertyName("role")] string Role,
        [property: JsonPropertyName("content")] JsonElement Content);

    private record ChatRequest(
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("messages")] ChatMessage[] Messages,
        [property: JsonPropertyName("max_tokens")] int MaxTokens);

    private record ChatChoice(
        [property: JsonPropertyName("message")] ChatChoiceMessage Message);

    private record ChatChoiceMessage(
        [property: JsonPropertyName("content")] string Content);

    private record ChatResponse(
        [property: JsonPropertyName("choices")] ChatChoice[] Choices);

    public async Task<string?> DescribeAsync(Stream imageStream, string contentType)
    {
        var imageBytes = new MemoryStream();
        await imageStream.CopyToAsync(imageBytes);
        var base64 = Convert.ToBase64String(imageBytes.ToArray());
        var dataUri = $"data:{contentType};base64,{base64}";

        var content = JsonSerializer.SerializeToElement(new object[]
        {
            new { type = "text", text = "Describe this image in one or two sentences. Be concise and factual." },
            new { type = "image_url", image_url = new { url = dataUri } }
        });

        var request = new ChatRequest(
            Model: model,
            Messages: [new ChatMessage("user", content)],
            MaxTokens: 150);

        var response = await httpClient.PostAsJsonAsync("v1/chat/completions", request);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<ChatResponse>();
        return result?.Choices.FirstOrDefault()?.Message.Content;
    }
}
