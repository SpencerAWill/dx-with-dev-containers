using System.Net;
using System.Text;
using Worker.Services;

namespace Unit.Tests;

public class ImageAnalyzerTests
{
    // Captures the outgoing request and replays a canned chat-completion body,
    // so these tests exercise the analyzer without a running vision model.
    private sealed class StubHandler(string responseBody) : HttpMessageHandler
    {
        public string? CapturedRequest { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CapturedRequest = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json")
            };
        }
    }

    private static string ChatResponse(string content) =>
        """{"choices":[{"message":{"role":"assistant","content":"""
        + System.Text.Json.JsonSerializer.Serialize(content)
        + "}}]}";

    private static (ImageAnalyzer Analyzer, StubHandler Handler) CreateAnalyzer(string content)
    {
        var handler = new StubHandler(ChatResponse(content));
        var httpClient = new HttpClient(handler) { BaseAddress = new Uri("http://vision-model.test") };
        return (new ImageAnalyzer(httpClient, "test-model"), handler);
    }

    private static MemoryStream FakeImage() => new([1, 2, 3, 4]);

    [Fact]
    public async Task Analyze_returns_label_confidence_and_description()
    {
        var (analyzer, _) = CreateAnalyzer(
            """{"label":"golden retriever","confidence":0.92,"description":"A dog on a lawn."}""");

        var result = await analyzer.AnalyzeAsync(FakeImage(), "image/png");

        Assert.Equal("golden retriever", result.Label);
        Assert.Equal(0.92, result.Confidence);
        Assert.Equal("A dog on a lawn.", result.Description);
    }

    [Fact]
    public async Task Analyze_sends_the_image_as_a_data_uri_with_the_content_type()
    {
        var (analyzer, handler) = CreateAnalyzer(
            """{"label":"cat","confidence":0.5,"description":"A cat."}""");

        await analyzer.AnalyzeAsync(FakeImage(), "image/jpeg");

        Assert.Contains("data:image/jpeg;base64,AQIDBA==", handler.CapturedRequest);
        Assert.Contains("json_schema", handler.CapturedRequest);
    }

    [Fact]
    public async Task Analyze_tolerates_a_fenced_json_response()
    {
        var (analyzer, _) = CreateAnalyzer(
            "```json\n{\"label\":\"bicycle\",\"confidence\":0.7,\"description\":\"A bike.\"}\n```");

        var result = await analyzer.AnalyzeAsync(FakeImage(), "image/png");

        Assert.Equal("bicycle", result.Label);
    }

    [Theory]
    [InlineData(1.7, 1.0)]
    [InlineData(-0.5, 0.0)]
    public async Task Analyze_clamps_confidence_to_a_valid_range(double reported, double expected)
    {
        var (analyzer, _) = CreateAnalyzer(
            $$"""{"label":"tree","confidence":{{reported}},"description":"A tree."}""");

        var result = await analyzer.AnalyzeAsync(FakeImage(), "image/png");

        Assert.Equal(expected, result.Confidence);
    }

    [Fact]
    public async Task Analyze_treats_a_blank_description_as_absent()
    {
        var (analyzer, _) = CreateAnalyzer("""{"label":"tree","confidence":0.6,"description":"   "}""");

        var result = await analyzer.AnalyzeAsync(FakeImage(), "image/png");

        Assert.Null(result.Description);
    }

    [Fact]
    public async Task Analyze_throws_when_the_model_returns_no_label()
    {
        var (analyzer, _) = CreateAnalyzer("""{"label":"","confidence":0.6,"description":"A tree."}""");

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => analyzer.AnalyzeAsync(FakeImage(), "image/png"));
    }
}
