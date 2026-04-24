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
}
