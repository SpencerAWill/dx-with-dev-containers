using System.Net;
using System.Net.Http.Json;
using Data.Models;

namespace Integration.Tests;

public class ImageEndpointTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private readonly HttpClient _client = fixture.CreateClient();

    [Fact]
    public async Task Get_images_returns_ok_with_empty_list()
    {
        var response = await _client.GetAsync("/api/images");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var images = await response.Content.ReadFromJsonAsync<List<Image>>();
        Assert.NotNull(images);
        Assert.Empty(images);
    }

    [Fact]
    public async Task Get_image_by_id_returns_not_found_for_missing_id()
    {
        var response = await _client.GetAsync($"/api/images/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Health_endpoint_returns_ok()
    {
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Post_image_uploads_file_and_returns_created()
    {
        using var content = new MultipartFormDataContent();
        var fileBytes = "fake image content"u8.ToArray();
        content.Add(new ByteArrayContent(fileBytes), "file", "cat.jpg");

        var response = await _client.PostAsync("/api/images", content);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var image = await response.Content.ReadFromJsonAsync<Image>();
        Assert.NotNull(image);
        Assert.Equal("cat.jpg", image.OriginalFileName);
        Assert.Equal(ImageStatus.Uploaded, image.Status);
        Assert.NotEqual(Guid.Empty, image.Id);
        Assert.Contains("azurite", image.BlobUri);
    }

    [Fact]
    public async Task Post_image_then_get_by_id_returns_same_image()
    {
        using var content = new MultipartFormDataContent();
        content.Add(new ByteArrayContent("test"u8.ToArray()), "file", "dog.png");

        var postResponse = await _client.PostAsync("/api/images", content);
        var created = await postResponse.Content.ReadFromJsonAsync<Image>();

        var getResponse = await _client.GetAsync($"/api/images/{created!.Id}");

        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);
        var fetched = await getResponse.Content.ReadFromJsonAsync<Image>();
        Assert.Equal(created.Id, fetched!.Id);
        Assert.Equal("dog.png", fetched.OriginalFileName);
    }

    [Fact]
    public async Task Post_image_then_download_returns_same_content()
    {
        var original = "download test content"u8.ToArray();
        using var content = new MultipartFormDataContent();
        content.Add(new ByteArrayContent(original), "file", "test.bin");

        var postResponse = await _client.PostAsync("/api/images", content);
        var created = await postResponse.Content.ReadFromJsonAsync<Image>();

        var downloadResponse = await _client.GetAsync($"/api/images/{created!.Id}/download");

        Assert.Equal(HttpStatusCode.OK, downloadResponse.StatusCode);
        var downloaded = await downloadResponse.Content.ReadAsByteArrayAsync();
        Assert.Equal(original, downloaded);
    }

    [Fact]
    public async Task Download_returns_not_found_for_missing_id()
    {
        var response = await _client.GetAsync($"/api/images/{Guid.NewGuid()}/download");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
